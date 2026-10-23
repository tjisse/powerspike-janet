(import ./expressions :as expr)
(import ./data-util :as util)
(import pshash :as hash)

# Reviewed auxiliary spells are embedded at build time, just like fixed-form
# profiles. Never pair them with a changed primary record or another patch.
(def supplement-root "data/ability-fixtures/16.21.1/twenty/")
(def supplement-manifest (util/read-json (slurp (string supplement-root "manifest.json"))))
(def supplement-records
  (tabseq [id :in ["Katarina" "Velkoz"]]
    id (do
         (def file (string id "-characters.json"))
         (def bytes (slurp (string supplement-root file)))
         (assert (= (hash/sha256 bytes) (get-in supplement-manifest ["fixture_sha256" file])))
         (util/read-json bytes))))
(defn supplement [ability id primary auxiliary]
  (def records (supplement-records id))
  (defn spell [name] (get-in (find |(and (dictionary? $) (= name (get $ "mScriptName"))) (values records)) ["mSpell"]))
  (def selected (merge @{} (ability :record)))
  (put selected "__powerspike_patch" nil) (put selected "__powerspike_stat_scope" nil)
  (when (= (util/canonical selected) (util/canonical (spell primary))) (spell auxiliary)))

# Handwritten combat semantics, using numerical values from the selected raw
# spell record. This is not another parser or a rewrite of saved packages.
(defn sum-of [& children] {:op :sum :children children})
(defn product-of [& children] {:op :multiply :children children})
(defn quotient [a b] {:op :divide :children [a b]})
(defn literal [value] {:op :constant :value value})
(defn percent-display [ability names]
  (map |(if (some (fn [name] (= name (string/ascii-lower ($ :name)))) names)
          (merge $ {:display-scale 100 :suffix "%"}) $) (ability :variables)))
(defn garen [ability handler]
  (def spell (ability :record))
  (defn term [name] (expr/variable name spell))
  (def spins (sum-of (term "NumTicks")
                     {:op :floor :children [{:op :divide :children [{:op :stat :stat :attack-speed-item-growth :formula 0}
                                                                    (term "ASPerTick")]}]}))
  (def note
    (case handler
      :garen-r "Demacian Justice deals base plus a fraction of the opponent's missing health, evaluated at impact. Vision is excluded."
      :garen-e "Judgment uses item/level attack speed, separate spins, critical hits and champion armor reduction. This duel assumes the opponent is the nearest enemy. Spins are spaced evenly across the source duration, with the first at the end of one spin. Automatic strategy completes the spin before E/R; early cancellation is excluded."))
  (def effect
    (case handler
      :garen-r {:kind :damage :damage-type :true :amount (sum-of (term "BaseDamage")
                                                                 (product-of (term "ExecuteDamage") {:op :target-stat :stat :missing-health}))}
      :garen-e {:kind :judgment :damage-type :physical :amount (term "TotalDamage")
                :radius (ability :range)
                :duration (term "Duration") :base-spins (term "NumTicks") :attack-speed-per-spin (term "ASPerTick")
                :spins spins
                :nearest-bonus (term "NearestEnemyBonus") :crit-mod (term "CritMod")
                :shred-hits (term "StacksToShred") :shred-amount (term "ShredAmount") :shred-duration (term "ShredDuration")}))
  (def problems (mapcat |(if (and (dictionary? $) ($ :op)) (expr/problems $) []) (values effect)))
  (def compiled (merge effect {:id (string (ability :id) "/reviewed") :target :enemy
                               :target-kinds [:champion :practice] :trigger :cast :condition :always
                               :status (if (empty? problems) :estimated :unresolved)
                               :evidence {:override true :tooltip note}}
                       (if (= handler :garen-e) {:state-on-miss true} {})))
  # These targeted handlers replace the generic tooltip's incomplete effects.
  # Keep unrelated source/input failures; remove only the superseded effect notes.
  (def notes (filter |(not (or (= $ note) (= $ "Judgment uses reviewed spin semantics.")
                               (= $ "Demacian Justice uses reviewed missing-health semantics.")
                               (and (= handler :garen-e) (= $ "Unresolved tooltip variable: f1"))
                               (string/has-prefix? "Periodic damage needs" $)
                               (string/has-prefix? "Conditional/maximum effect needs" $)
                               (= $ "Recasts/charges need explicit semantics.")
                               (= $ "Stack state requires explicit triggers."))) (ability :unresolved)))
  (merge ability {:effects [compiled] :missile-speed 0
                  :variables (if (= handler :garen-e)
                               (map |(if (= "f1" ($ :name)) (merge $ {:expression spins}) $) (ability :variables))
                               (ability :variables))
                  :cast-time (if (= handler :garen-e) 0 (ability :cast-time))
                  :unresolved [;notes ;problems note]}
         (if (= handler :garen-e) {:always-release-self true} {})))

(defn seraphine [ability handler]
  (defn term [name] (expr/variable name (ability :record)))
  (def note (case handler
              :seraphine-q "High Note increases its damage with the opponent's missing health, capped at the source's execute threshold. Geometry and minion damage remain excluded."
              :seraphine-w "Surround Sound shields immediately. If already shielded at cast start, it heals missing health after the source delay; repeat pulses refresh the delay. Other allies and decaying movement speed remain excluded."
              :seraphine-e "Beat Drop slows, upgrades to root on an already slowed enemy, or stun on an immobilized/grounded enemy, checked at impact. Projectile collision remains excluded."
              :seraphine-p "Every third basic ability echoes once, without another resource cost or cooldown. Echo starts with zero stacks. Notes and their attack damage/range remain excluded."))
  (def specs
    (case handler
      :seraphine-q
      [{:kind :damage :target :enemy :damage-type :magic
        :amount (product-of (term "ExplosionDamage")
                            (sum-of (literal 1)
                                    (product-of (term "DamageAmp") (literal 0.01)
                                                {:op :minimum :children [(literal 1)
                                                                         (quotient {:op :target-stat :stat :missing-health-percent}
                                                                                   (sum-of (literal 1) (product-of (literal -1) (term "ExecuteThreshold"))))]})))}]
      :seraphine-w
      [{:kind :heal :target :self :trigger :cast-start :requires-shield-at-cast true :refresh-pulse true
        :amount (product-of (term "WMissingHPHeal") (literal 0.01) {:op :stat :stat :missing-health :formula 0})
        :delay (term "WHealSplitDelay")}
       {:kind :shield :target :self :amount (term "ShieldValueSeraphine") :duration (term "ShieldDuration")}]
      :seraphine-e
      [{:kind :damage :target :enemy :damage-type :magic :amount (term "FinalDamage")}
       {:kind :control :target :enemy :control :slow :upgrade-on-control true
        :amount (term "SlowDuration") :duration (term "SlowDuration") :strength (product-of (literal 0.01) (term "SlowValue"))}]
      :seraphine-p []))
  (def effects
    (map (fn [effect]
           (def problems (mapcat |(if (and (dictionary? $) ($ :op)) (expr/problems $) []) (values effect)))
           (merge {:trigger :cast :condition :always :target-kinds [:champion :practice]
                   :status (if (empty? problems) :estimated :unresolved) :evidence {:tooltip note :override true}}
                  effect)) specs))
  (def notes (filter |(not (or (= $ note) (string/has-prefix? "Seraphine uses reviewed" $)
                               (string/has-prefix? "Conditional/maximum effect needs" $)
                               (string/has-prefix? "Control trigger/duration unresolved:" $)
                               (= $ "Passive activation requires an explicit trigger handler.")
                               (= $ "Stack state requires explicit triggers.")
                               (= $ "No recognized executable effect; this does not imply zero damage."))) (ability :unresolved)))
  (def echo-delay (when (= handler :seraphine-p) (term "EchoCastDelay")))
  (def echo-problems (when echo-delay (expr/problems echo-delay)))
  (merge ability {:effects effects :unresolved [;notes ;(or echo-problems []) note]}
         (if (= handler :seraphine-p)
           {:echo (when (empty? echo-problems) {:every 3 :delay echo-delay})} {})))

(defn fiddlesticks [ability handler]
  (def spell (ability :record))
  (defn term [name] (expr/variable name spell))
  (def tick (expr/compile-part (get-in spell ["mSpellCalculations" "DamageDone" "mMultiplier"]) spell))
  (def note (case handler
              :fiddlesticks-q "Terrify deals a percentage of current health with a minimum, fears on a ready target and doubles damage during its own recent-fear timer. Unseen/effigy passive fears and fear-driven fleeing remain excluded."
              :fiddlesticks-w "Bountiful Harvest channels, deals separate drain ticks and a final missing-health hit, heals from pre-mitigation damage and refunds 60% of remaining cooldown on completion or target death. Control and an escaped tether end the channel without a refund. Monster/minion variants remain excluded."
              :fiddlesticks-e "Reap deals its source-defined magic damage and slow. The ground slash is assumed to apply at cast completion; center-hit silence, unseen fear and geometry remain excluded."
              :fiddlesticks-r "Crowstorm channels before blinking to the opponent's position selected at cast start, then deals separate area ticks while alive and in range. Unseen fear, terrain, vision and multi-target behavior remain excluded."))
  (def specs (case handler
               :fiddlesticks-q [{:kind :terrify :target :enemy :amount (term "TotalPercentHealthDamage")
                                 :minimum (term "MinimumDamage") :duration (term "FearDuration") :fear-cooldown (ability :cooldown)}]
               :fiddlesticks-w [{:kind :drain :target :enemy :amount (quotient (term "DrainDamageCalc") (term "TicksPerSecond"))
                                 :interval (quotient (literal 1) (term "TicksPerSecond")) :duration (term "DrainDuration")
                                 :leash (term "DrainLeashRange") :finisher-ratio (term "PercentMultiplier")
                                 :heal-ratio (product-of (literal 0.01) (term "VampPercentage"))
                                 :refund (if (string/find "60%" (ability :tooltip)) (literal 0.6)
                                           (expr/unresolved "Drain completion refund is not established by this tooltip."))}]
               :fiddlesticks-e [{:kind :damage :target :enemy :damage-type :magic :amount (term "Damage")}
                                {:kind :control :target :enemy :control :slow :duration (term "SilenceDuration")
                                 :strength (product-of (literal -1) (term "SlowAmount"))}]
               :fiddlesticks-r [{:kind :damage :target :enemy :damage-type :magic :amount (term "DamageDone")
                                 :delay tick :interval tick :hits (quotient (term "Duration") tick)
                                 :range-at-impact (expr/ranked (get spell "castRadius") 0 "Crowstorm radius") :requires-caster-alive true}
                                {:kind :buff :target :self :amount (literal 0) :buff "Crowstorm" :refresh true :duration (term "Duration")}]))
  (def effects (map (fn [effect]
                      (def problems (mapcat |(if (and (dictionary? $) ($ :op)) (expr/problems $) []) (values effect)))
                      (merge {:trigger :cast :condition :always :target-kinds [:champion :practice]
                              :status (if (empty? problems) :estimated :unresolved) :evidence {:tooltip note :override true}} effect)) specs))
  (defn fixed [expression]
    (def checked (protect (expr/evaluate expression {:rank 1})))
    (if (first checked) (checked 1) :unresolved))
  (def notes (filter |(not (or (= $ note) (string/has-prefix? "Fiddlesticks uses reviewed" $)
                               (string/find "require an explicit handler;" $)
                               (and (= handler :fiddlesticks-e) (string/has-prefix? "Control trigger/duration unresolved:" $))
                               (string/has-prefix? "Periodic damage needs" $)
                               (string/has-prefix? "Conditional/maximum effect needs" $))) (ability :unresolved)))
  (merge ability {:effects effects :unresolved [;notes note] :missile-speed 0
                  :variables (if (= handler :fiddlesticks-q)
                               (percent-display ability ["totalpercenthealthdamage" "totalpercenthealthdamagefeared"])
                               (ability :variables))}
         (case handler
           :fiddlesticks-w {:interruptible-channel true :cast-lock (fixed (sum-of (literal (ability :cast-time)) (term "DrainDuration")))}
           :fiddlesticks-r {:interruptible-channel true :channel true :blink-to-target true :finish-channel-on-release true :always-release-self true
                            :disabled-controls [:grounded] :channel-interrupts [:stun :charm :fear :airborne :suppression :silence :grounded]
                            :cast-time (fixed (term "ChannelTime"))}
           {})))

(defn vayne [ability]
  (defn term [name] (expr/variable name (ability :record)))
  (def note "Silver Bolts deals true damage on the third consecutive hit against the sole opponent, with a source-defined health ratio, damage floor and refreshed mark duration. It is passive and costs no cast or resource. Monster variants and target switching remain excluded.")
  (def amount {:op :maximum :children [(term "DamageFloor")
                                       (product-of (term "MaxHealthRatio") {:op :target-stat :stat :hp})]})
  (def problems [;(expr/problems amount) ;(expr/problems (term "DebuffDuration"))])
  (merge ability {:passive true :variables (percent-display ability ["totaldamage"])
                  :effects [{:kind :damage :damage-type :true :target :enemy :target-kinds [:champion :practice]
                             :amount amount :trigger :passive :on [:attack :spell-hit] :every 3 :window (term "DebuffDuration")
                             :refresh-window true :allow-same-time true :counter-buff "Silver Bolts"
                             :condition :always :status (if (empty? problems) :estimated :unresolved)
                             :evidence {:tooltip note :override true}}]
                  :unresolved [;problems note]}))

(defn completeness [ability handler]
  (defn term [name] (expr/variable name (ability :record)))
  (defn percent [name] (product-of (literal 0.01) (term name)))
  (defn buff [name bonuses duration]
    {:kind :buff :target :self :buff name :stat-bonuses bonuses :refresh true :duration duration})
  (def note
    (case handler
      :vi-w "Denting Blows triggers on three distinct attacks or modeled Q/E hits, with refreshed marks, maximum-health damage, armor reduction and bonus attack speed. Proc damage precedes its new armor reduction in this simulation. Blast Shield cooldown reduction, pre-fight marks and monster variants remain excluded."
      :twisted-fate-e "Stacked Deck grants learned-rank bonus attack speed and magic damage on every fourth distinct attack, starting without pre-fight stacks. Other targets and structures remain excluded."
      :tristana-q "Rapid Fire grants source-defined bonus attack speed for its duration, at cast start and independently of enemy range. Other champion mechanics remain excluded."
      :singed-r "Insanity Potion grants temporary ability power, armor, magic resist, movement speed, health regeneration and mana regeneration. Poison Trail's Grievous Wounds and other kit effects remain excluded."
      :gangplank-w "Remove Scurvy heals base/AP plus live missing health and cleanses modeled stun, charm, fear, suppression, silence, root, slow, grounding and polymorph. Its source permits casting while disabled. Airborne displacement, stasis and non-control debuffs remain excluded."
      :veigar-r "Primordial Burst scales with live missing health up to twice its minimum damage at two-thirds missing health. The source's accelerating projectile uses distance at cast release; continued target movement during flight remains excluded."
      :zac-w "Unstable Matter deals source-defined base plus target maximum-health damage, with its current-health cost. Blob pickup healing and cooldown refunds, monsters and minions remain excluded."
      :zilean-e "Time Warp uses its offensive enemy slow and source duration. Allied/self haste targeting remains excluded. It has no modeled projectile travel."
      :malzahar-e "Malefic Visions applies sixteen quarter-second damage pulses over four seconds; recasting replaces remaining pulses. The first pulse is one interval after application. Q/R refresh, spreading, mana restoration and minion rules remain excluded."
      :cassiopeia-q "Noxious Blast applies seven poison pulses across three seconds, starting at modeled cast completion. Reapplication replaces remaining pulses. Ground detonation delay, decaying movement speed, Twin Fang synergy and geometry remain excluded."))
  (def specs
    (case handler
      :vi-w
      [{:kind :sequence :target :enemy :trigger :passive :on [:attack :spell-hit] :spell-slots [:q :e]
        :every (sum-of (term "StacksBeforeEffect") (literal 1)) :window (term "MarkerBuffDuration")
        :refresh-window true :allow-same-time true :counter-buff "Denting Blows"
        :effects [{:kind :damage :target :enemy :damage-type :physical
                   :amount (product-of (term "TotalDamageTooltip") {:op :target-stat :stat :hp})}
                  {:kind :stat-buff :target :enemy :stat :armor :mode :multiply
                   :amount (sum-of (literal 1) (product-of (literal -1) (percent "ShredAmount"))) :duration (term "SharedBuffsDuration")}
                  (buff "Denting Blows attack speed" {:attack-speed-bonus (percent "AttackSpeed")} (term "SharedBuffsDuration"))]}]
      :twisted-fate-e
      [{:kind :damage :target :enemy :damage-type :magic :amount (term "BonusDamage")
        :trigger :passive :on [:attack] :every (term "Effect4Amount") :allow-same-time true
        :counter-buff "Stacked Deck" :counter-target :self}]
      :tristana-q [(merge (buff "Rapid Fire" {:attack-speed-bonus (term "AttackSpeedMod")} (term "BuffDuration")) {:trigger :cast-start})]
      :singed-r (map |{:kind :stat-buff :target :self :stat $ :amount (term "StatAmount") :duration (term "Duration")}
                     [:ap :armor :mr :move-speed :hp-regen :mp-regen])
      :gangplank-w
      [{:kind :cleanse :target :self :controls [:stun :charm :fear :suppression :silence :root :slow :grounded :polymorph]}
       {:kind :heal :target :self :amount (sum-of (term "BaseHealth")
                                                  (product-of (percent "PercentHeal") {:op :stat :stat :missing-health :formula 0}))}]
      :veigar-r
      [{:kind :damage :target :enemy :damage-type :magic
        :amount (product-of (term "MinDamage")
                            (sum-of (literal 1) {:op :minimum :children [(sum-of (term "MaxExecuteMult") (literal -1))
                                                                         (product-of (literal 1.5) {:op :target-stat :stat :missing-health-percent})]}))}]
      :zac-w
      [{:kind :damage :target :enemy :damage-type :magic
        :amount (sum-of (term "BaseDamage") (product-of (term "DisplayPercentDamage") {:op :target-stat :stat :hp}))}]
      :zilean-e [{:kind :control :target :enemy :control :slow :strength (percent "SpeedAmount") :duration (term "Duration")}]
      :malzahar-e [{:kind :periodic :target :enemy :damage-type :magic :amount (term "TotalDamage")
                    :pulse-count (quotient (term "Duration") (term "SecondsPerTick")) :pulse-interval (term "SecondsPerTick")
                    :first-delay (term "SecondsPerTick") :duration (term "Duration") :buff "Malefic Visions"}]
      :cassiopeia-q [{:kind :periodic :target :enemy :damage-type :magic :amount (term "TooltipTotalDamage")
                      :pulse-count (term "NumDamageTicks") :pulse-interval (quotient (term "PoisonDuration") (sum-of (term "NumDamageTicks") (literal -1)))
                      :first-delay (literal 0) :duration (term "PoisonDuration") :buff "Noxious Blast poison"}]))
  (defn problems [value]
    (cond (and (dictionary? value) (value :op)) (expr/problems value)
      (dictionary? value) (mapcat problems (values value))
      (indexed? value) (mapcat problems value) []))
  (assert (string? note) "Unknown reviewed champion handler.")
  (def motion (get-in ability [:record "mMissileSpec" "movementComponent"]))
  (def valid-motion (and (dictionary? motion) (= "AcceleratingMovement" (get motion "__type"))
                         (util/finite? (get motion "mInitialSpeed")) (> (motion "mInitialSpeed") 0)
                         (util/finite? (get motion "mAcceleration")) (> (motion "mAcceleration") 0)
                         (util/finite? (get motion "mMaxSpeed")) (>= (motion "mMaxSpeed") (motion "mInitialSpeed"))))
  (def unresolved [;(problems specs)
                   ;(if (and (= handler :veigar-r) (not valid-motion)) ["Primordial Burst's accelerating projectile source is unavailable."] [])
                   ;(if (= handler :twisted-fate-e) (problems (percent "AttackSpeedBonus")) [])])
  (def effects (map |(merge {:target-kinds [:champion :practice] :condition :always :trigger :cast
                             :status (if (empty? unresolved) :estimated :unresolved)
                             :evidence {:tooltip note :override true}} $) specs))
  (merge ability {:effects effects :unresolved [;unresolved note]}
         (case handler
           :vi-w {:passive true :variables (percent-display ability ["totaldamagetooltip"])}
           :twisted-fate-e {:passive true :rank-bonuses (if (empty? unresolved) {:attack-speed-bonus (percent "AttackSpeedBonus")} {})}
           :tristana-q {:cast-time 0 :self-cast true :missile-speed 0}
           :singed-r {:self-cast true :missile-speed 0}
           :gangplank-w {:self-cast true :missile-speed 0
                         :usable-controls (if (and (get (ability :record) "canCastWhileDisabled")
                                                   (get (ability :record) "cannotBeSuppressed"))
                                            [:stun :charm :fear :suppression :silence :polymorph] [])}
           :veigar-r {:projectile-motion motion}
           :zac-w {:missile-speed 0 :variables (percent-display ability ["displaypercentdamage"])}
           :zilean-e {:missile-speed 0}
           :malzahar-e {:missile-speed 0}
           :cassiopeia-q {:missile-speed 0})))

(defn twenty [ability handler]
  (defn term [name] (expr/variable name (ability :record)))
  (defn percent [name] (product-of (literal 0.01) (term name)))
  (defn steroid [name bonuses duration] {:kind :buff :target :self :buff name :stat-bonuses bonuses :duration duration :refresh true})
  (defn stat [name amount duration &opt mode] {:kind :stat-buff :target :self :stat name :amount amount :duration duration :mode (or mode :add)})
  (defn slow [strength duration steps] {:kind :control :target :enemy :control :slow :strength strength :duration duration :decay-steps steps})
  (def bonus-as {:op :stat :stat :attack-speed-bonus :formula 0})
  (def kata (when (= handler :katarina-e) (supplement ability "Katarina" "KatarinaEWrapper" "KatarinaE")))
  (def velkoz (when (= handler :velkoz-q) (supplement ability "Velkoz" "VelkozQ" "VelkozQMissile")))
  (def note
    (case handler
      :warwick-q "Jaws of the Beast uses its tap damage and heals from damage after resistance, including damage absorbed by shields. Held following, attachment, monsters and minions remain excluded."
      :singed-w "Mega Adhesive applies its delayed grounding and slow to the sole opponent. This duel assumes they remain in the aimed area; leaving the field and Fling's landing root remain excluded."
      :singed-e "Fling deals base/AP plus maximum-health damage and flips the opponent over the caster in one dimension. Movement is applied at impact; airborne flight timing and Mega Adhesive's landing root remain excluded."
      :katarina-e "Shunpo uses the reviewed enemy-target blink, damage, attack reset and auxiliary cast time. Ally/dagger targeting, dagger pickups and their cooldown refunds remain excluded."
      :xin-r "Crescent Guard deals base/scaling plus current-health damage and prevents champion damage from beyond its defense radius. Challenge-dependent knockback and other kit effects remain excluded."
      :yone-w "Spirit Cleave deals equal physical/magic health-scaled halves and grants the sole-champion shield only when the strike lands. Bonus attack speed reduces cast time and cooldown using the selected caps; ability haste does not. Geometry, monsters, minions and other passive effects remain excluded."
      :lulu-q "Glitterlance uses a primary bolt and its decaying slow. Pix's separate position, additional bolt damage, collision and other targets remain excluded."
      :lulu-w "Whimsy uses its enemy polymorph, disabling attacks/casts while reducing movement speed. Self/ally attack-speed and movement buffs remain excluded."
      :velkoz-q "Plasma Fission uses the reviewed primary bolt travel, damage and decaying slow. Split/recast geometry, mana-on-kill and passive stacks remain excluded."
      :trundle-w "Frozen Domain grants its attack-speed, movement and healing bonuses. This duel assumes Trundle remains inside his placed area; field exits and other allies remain excluded."
      :draven-w "Blood Rush grants attack speed and decaying movement speed. Axe catches, their cooldown resets and unit collision remain excluded."
      :twitch-r "Spray and Pray grants attack damage and attack range. This duel uses the ordinary modeled attack delivery; piercing projectile travel, dodging and additional targets remain excluded."
      :sivir-r "On the Hunt grants movement speed and reduces basic cooldowns on distinct champion attacks while active. Other allies and takedown duration refresh remain excluded."
      :zilean-w "Rewind subtracts the source duration from Q/E cooldowns and wakes newly ready actions. It does not affect W, R, charges or recast timers."
      :teemo-e "Toxic Shot adds impact damage and a refreshed poison. Further attacks preserve the next poison tick instead of repeatedly delaying it. Monster variants and other kit effects remain excluded."
      :karthus-w "Wall of Pain applies its magic-resist reduction and decaying slow. This duel assumes the opponent crosses the placed wall; wall placement and repeated crossings remain excluded."
      :nocturne-w "Shroud of Darkness grants passive attack speed and blocks the next eligible enemy spell impact. A successful block adds the passive bonus again for its duration. Existing poison, attacks and item procs do not consume this shield; exceptional spell interactions remain excluded."
      :sivir-e "Spell Shield blocks the next eligible enemy spell impact and heals on a successful block. Existing poison, attacks and item procs do not consume it. Fleet of Foot and exceptional spell interactions remain excluded."
      :kassadin-w "Nether Blade adds passive on-hit damage, empowers the next attack and restores missing mana against the sole champion opponent. The empowerment remains until consumed; its expiry, monsters and minions remain excluded."
      :olaf-w "Tough It Out resets the attack timer, grants attack speed and shields using live missing health, capped at the selected low-health threshold. Other passive and kit effects remain excluded."))
  (assert (string? note) "Unknown twenty-slot handler.")
  (def specs
    (case handler
      :warwick-q [{:kind :damage :target :enemy :damage-type :magic
                   :amount (sum-of (term "BaseBiteDamage") (product-of (percent "TargetPercentHPDamage") {:op :target-stat :stat :hp}))
                   :heal-dealt-ratio (percent "LifestealPercent")}]
      :singed-w [(merge (slow (percent "SlowPercent") (term "WDuration") nil) {:delay (term "DelayExecute")})
                 {:kind :control :target :enemy :control :grounded :duration (term "WDuration") :delay (term "DelayExecute")}]
      :singed-e [{:kind :sequence :target :enemy
                  :effects [{:kind :damage :damage-type :magic :amount (sum-of (term "BaseDamage") (product-of (percent "MaxHPDamage") {:op :target-stat :stat :hp}))}
                            {:kind :displace :distance (term "FlingDistance") :mode :over-caster}]}]
      :katarina-e [{:kind :damage :target :enemy :damage-type :magic :amount (term "TotalDamage")}
                   {:kind :reset :target :self :trigger :cast-start}]
      :xin-r [{:kind :damage :target :enemy :damage-type :physical
               :range-at-impact (ability :range)
               :amount (sum-of (term "TotalDamage") (product-of (term "PercentCurrentHealthDamage") {:op :target-stat :stat :health}))}
              {:kind :range-guard :target :self :radius (term "MissileDefenseRadius") :duration (term "MissileDefenseBaseDuration")}]
      :yone-w
      (let [half (product-of (literal 0.5) (sum-of (term "BaseDamage") (product-of (term "MaxHealthDamage") {:op :target-stat :stat :hp})))
            shield (product-of (term "WShield") (sum-of (literal 1) (term "FirstChampShieldMultiplier")))]
        [{:kind :sequence :target :enemy
          :effects [{:kind :damage :damage-type :physical :amount half}
                    {:kind :damage :damage-type :magic :amount half}
                    {:kind :shield :target :self :amount shield :duration (term "ShieldDuration")}]}])
      :lulu-q [{:kind :damage :target :enemy :damage-type :magic :amount (term "TotalDamage")}
               (slow (product-of (literal -1) (term "SlowAmount")) (term "SlowDuration") (term "SlowDecayTicks"))]
      :lulu-w [{:kind :control :target :enemy :control :polymorph :duration (term "CCDuration") :movement-penalty (term "SlowAmount")}]
      :velkoz-q [{:kind :damage :target :enemy :damage-type :magic :amount (term "TotalDamage")}
                 (slow (term "SlowAmount") (term "SlowDuration") (literal 16))]
      :trundle-w [(steroid "Frozen Domain" {:attack-speed-bonus (term "ASBonus")} (term "Duration"))
                  (stat :healing-multiplier (sum-of (literal 1) (term "HealingBonus")) (term "Duration") :multiply)
                  (stat :move-speed (sum-of (literal 1) (term "MSBonus")) (term "Duration") :multiply)]
      :draven-w [(steroid "Blood Rush" {:attack-speed-bonus (percent "Temp_AS")} (term "Temp_ASDuration"))
                 (merge (stat :move-speed (sum-of (literal 1) (percent "Temp_MSMod")) (term "Temp_MSDuration") :multiply)
                        {:decay-steps {:op :floor :children [(sum-of (literal 0.5) (quotient (percent "Temp_MSMod") (product-of (literal -1) (term "Temp_MSDecay"))))]}})]
      :twitch-r [(steroid "Spray and Pray" {:ad (term "BonusAD")} (term "Duration"))
                 (stat :attack-range (term "BonusRange") (term "Duration"))]
      :sivir-r [(steroid "On the Hunt" {} (term "UltDuration"))
                (stat :move-speed (sum-of (literal 1) (term "MaxMS")) (term "UltDuration") :multiply)
                {:kind :cooldown-refund :target :self :trigger :passive :on [:attack] :allow-same-time true
                 :requires-buff "On the Hunt" :slots [:q :w :e] :amount (term "AttackCooldownRefund")}]
      :zilean-w [{:kind :cooldown-refund :target :self :slots [:q :e] :amount (term "CooldownReduction")}]
      :teemo-e [{:kind :sequence :target :enemy :trigger :passive :on [:attack] :allow-same-time true
                 :effects [{:kind :damage :damage-type :magic :amount (term "ImpactCalculatedDamage")}
                           {:kind :periodic :damage-type :magic :amount (term "TotalDotDamage") :preserve-pulse-phase true
                            :duration (term "PoisonDuration") :pulse-count (quotient (term "PoisonDuration") (term "TickFrequency"))
                            :pulse-interval (term "TickFrequency") :first-delay (term "TickFrequency") :buff "Toxic Shot poison"}]}]
      :karthus-w [{:kind :stat-buff :target :enemy :stat :mr :mode :multiply :amount (sum-of (literal 1) (product-of (literal -1) (percent "MagicResistShred"))) :duration (term "DebuffDuration")}
                  (slow (percent "SlowPercent") (term "DebuffDuration") (literal 16))]
      :nocturne-w [{:kind :spell-shield :target :self :duration (term "ShieldDuration") :trigger :cast-start
                    :on-block [(steroid "Shroud attack speed" {:attack-speed-bonus (percent "ActiveAS")} (term "DoubleASDuration"))]}]
      :sivir-e [{:kind :spell-shield :target :self :duration (term "SpellShieldDuration") :trigger :cast-start
                 :on-block [{:kind :heal :target :self :amount (term "TotalHeal")}]}]
      :kassadin-w [{:kind :damage :target :enemy :damage-type :magic :amount (term "OnHitDamage") :trigger :passive :on [:attack] :allow-same-time true}
                   {:kind :sequence :target :enemy :trigger :attack :attack-count 1 :reset true
                    :effects [{:kind :damage :damage-type :magic :amount (term "ActiveDamage")}
                              {:kind :resource :target :self :amount (product-of (percent "ChampionMissingManaRatio") {:op :stat :stat :missing-mana :formula 0})}]}]
      :olaf-w [{:kind :reset :target :self :trigger :cast-start}
               (merge (steroid "Tough It Out" {:attack-speed-bonus (term "Attackspeed")} (term "Duration")) {:trigger :cast-start})
               {:kind :shield :target :self :trigger :cast-start :duration (term "ShieldDuration")
                :amount (sum-of (term "BaseShield")
                                (product-of (term "ShieldPercMissingHP") {:op :minimum :children [{:op :stat :stat :missing-health :formula 0}
                                                                                                  (product-of {:op :stat :stat :hp :formula 0} (sum-of (literal 1) (product-of (literal -1) (term "ThresholdForMax"))))]}))}]))
  (defn problems [value]
    (cond (and (dictionary? value) (value :op)) (expr/problems value)
      (dictionary? value) (mapcat problems (values value))
      (indexed? value) (mapcat problems value) []))
  (def unresolved [;(problems specs)
                   ;(if (and (= handler :katarina-e) (not kata)) ["Shunpo auxiliary record does not match the selected source."] [])
                   ;(if (and (= handler :velkoz-q) (not velkoz)) ["Plasma Fission missile record does not match the selected source."] [])])
  (def effects (map |(merge {:target-kinds [:champion :practice] :condition :always :trigger :cast
                             :status (if (empty? unresolved) :estimated :unresolved) :evidence {:tooltip note :override true}} $) specs))
  (merge ability {:effects effects :unresolved [;unresolved note]}
         (case handler
           :warwick-q {:missile-speed 0 :cast-time 0}
           :singed-w {:missile-speed 0}
           :singed-e {:missile-speed 0}
           :katarina-e {:missile-speed 0 :cast-time (if kata (get kata "mCastTime") 0.15) :blink-to-target true :always-release-self true :disabled-controls [:grounded]}
           :xin-r {:self-cast true :missile-speed 0 :always-release-self true}
           :yone-w {:missile-speed 0 :unhasted true
                    :cooldown (product-of (expr/ranked (get-in ability [:record "cooldownTime"]) 0 "Yone W base cooldown")
                                          (sum-of (literal 1) (product-of (literal -1) {:op :minimum :children [(term "WAttackSpeedCDMax") (product-of bonus-as (term "WAttackSpeedCDPercent"))]})))
                    :cast-time-expression (product-of (term "WBaseCastTime") (sum-of (literal 1) (product-of (literal -1) {:op :minimum :children [(term "WAttackSpeedCastReductionMax") (product-of bonus-as (term "WAttackSpeedCastReductionPercent"))]})))}
           :lulu-q {}
           :lulu-w {:missile-speed 0}
           :velkoz-q {:missile-speed (get-in velkoz ["mMissileSpec" "movementComponent" "mSpeed"] 0) :recast nil}
           :trundle-w {:self-cast true :missile-speed 0}
           :draven-w {:self-cast true :missile-speed 0}
           :twitch-r {:self-cast true :missile-speed 0 :cast-time 0}
           :sivir-r {:self-cast true :missile-speed 0}
           :zilean-w {:self-cast true :missile-speed 0}
           :teemo-e {:passive true}
           :karthus-w {:missile-speed 0}
           :nocturne-w {:self-cast true :cast-time 0 :rank-bonuses {:attack-speed-bonus (percent "ActiveAS")}}
           :sivir-e {:self-cast true :cast-time 0}
           :kassadin-w {:self-cast true :cast-time 0}
           :olaf-w {:self-cast true :cast-time 0})))

(defn twenty-five [ability handler forms]
  (def spell (ability :record))
  (defn term [name] (expr/variable name spell))
  (defn neg [node] (product-of (literal -1) node))
  (defn plus-one [node] (sum-of (literal 1) node))
  (defn percent [name] (product-of (literal 0.01) (term name)))
  (defn damage [type amount] {:kind :damage :target :enemy :damage-type type :amount amount})
  (defn slow [strength duration] {:kind :control :target :enemy :control :slow :strength strength :duration duration})
  (defn stat [key amount duration &opt mode target]
    {:kind :stat-buff :target (or target :self) :stat key :amount amount :duration duration :mode (or mode :add)})
  (defn speed [amount duration] (stat :move-speed (plus-one amount) duration :multiply))
  (defn buff [name bonuses duration] {:kind :buff :target :self :buff name :stat-bonuses bonuses :duration duration :refresh true})
  (defn protection [name duration fields] (merge {:kind :protection :target :self :buff name :duration duration} fields))
  (defn aux [suffix]
    (get (find |(string/has-suffix? (string/ascii-lower suffix) (string/ascii-lower ($ :path))) (or forms [])) :record))
  (def karma-missile (when (= handler :karma-q) (aux "/KarmaQMissile")))
  (def khazix-missile (when (= handler :khazix-w) (aux "/KhazixWMissile")))
  (def sivir-missile (when (= handler :sivir-q) (aux "/SivirQMissile")))
  (def bonus-as {:op :stat :stat :attack-speed-bonus :formula 0})
  (def note (case handler
              :blitzcrank-w "Overdrive grants attack speed and movement speed decaying to its source floor, followed by a self slow. Decay uses sixteen model steps; collision and other kit effects remain excluded."
              :katarina-w "Preparation grants its decaying movement speed using sixteen model steps. Dagger placement, pickups, damage and Shunpo refunds remain excluded."
              :viego-e "Harrowed Path grants attack speed and movement speed, assuming Viego stays inside established mist. Terrain propagation, arrival, camouflage and field exits remain excluded."
              :tryndamere-w "Mocking Shout reduces enemy attack damage in range. The facing-dependent slow is excluded because the duel has no facing input."
              :yuumi-e "Unattached Zoomies shields Yuumi and grants attack speed. Movement speed persists only while this shield remains. Attachment, ally mana restoration and sharing remain excluded."
              :master-yi-r "Highlander grants attack/movement speed, removes modeled movement and attack-speed slows and prevents new slows during its duration. Takedown extensions/refunds and duration pauses remain excluded."
              :taric-r "Cosmic Radiance grants damage immunity after its source delay without blocking crowd control. Only the caster is modeled; allied copies and exceptional interactions remain excluded."
              :alistar-r "Unbreakable Will cleanses modeled disabling controls and reduces physical/magic damage. True damage is unaffected. Airborne displacement cleanup and exceptional debuffs remain excluded."
              :karma-q "Base Inner Flame deals damage and slows with the selected auxiliary missile speed. Mantra, collision geometry and other targets remain excluded."
              :karma-w "Base Focused Resolve damages at application and tether completion, then roots if continuously in leash range. Escape or either participant's death breaks the tether. Mantra, vision and other targets remain excluded."
              :karma-e "Base Inspire shields the caster and grants movement speed. Mantra and other allies remain excluded."
              :khazix-q "Unevolved Taste Their Fear uses isolated damage in this sole-opponent duel, which assumes no nearby enemy allies or minions. Evolution refunds/range and nonisolated targets remain excluded."
              :khazix-w "Unevolved Void Spike deals damage and heals only if the caster is within the reviewed 275-unit explosion radius. The missile comes from the selected snapshot. Evolution, collision and extra targets remain excluded."
              :khazix-e "Unevolved Leap deals landing damage at modeled cast completion. Dash movement, flight time, evolution and resets remain excluded."
              :kayn-q "Base Reaping Slash applies separate dash/slash damage hits at modeled cast completion. Dash movement, flight/slash separation, transformation and monster variants remain excluded."
              :kayn-w "Base Blade's Reach deals damage and applies its decaying slow in sixteen model steps. Shadow Assassin, Rhaast and geometry remain excluded."
              :syndra-q "Base Dark Sphere deals its selected source damage at modeled cast completion. Detonation delay, splinter upgrades/charges and sphere interaction with other spells remain excluded."
              :veigar-w "Dark Matter deals damage after its source impact delay and uses the explicit zero-stack base cooldown. Phenomenal Evil stacks and their cooldown reduction remain excluded."
              :volibear-e "Sky Splitter deals base/AP plus maximum-health damage and slows at modeled cast completion. It shields only when the caster is within the blast radius of the opponent. Ground detonation delay, placement and other targets remain excluded."
              :nocturne-e "Unspeakable Horror deals eight evenly spaced model pulses across its tether duration and fears on completion if continuously in range. Escape or either participant's death breaks it. Fear chase speed, fleeing and measured server tick timing remain excluded."
              :sivir-q "Boomerang Blade applies two full champion hits, critical-stat scaling and bonus-AS cast scaling. Both phases are assumed to hit; return travel uses twice the release distance. Turning, continued movement and other targets remain excluded."
              :corki-e "Gatling Gun deals separate source-rate pulses with capped stacking armor/MR reduction lingering after the last hit. Each pulse checks range; damage precedes its new shred stack. Cone facing, other targets and measured tick phase remain excluded."
              :rell-r "Magnet Storm deals eight evenly spaced model pulses, each checking radius and caster life. Initial pull and continuous dragging/geometry remain excluded."
              :nilah-w "Jubilant Veil dodges ordinary attacks, reduces magic damage and grants movement speed. Successful dodges suppress ordinary attack procs. Ally sharing, ghosted collision and exceptional empowered attacks remain excluded."
              :maokai-q "Bramble Smash deals base/AP plus maximum-health damage and briefly slows. Knockback movement/airborne timing and geometry remain excluded."))
  (assert note "Unknown twenty-five-slot handler.")
  (def specs
    (case handler
      :blitzcrank-w [(buff "Overdrive" {:attack-speed-bonus (term "AttackSpeedMod")} (term "Duration"))
                     (merge (speed (term "MoveSpeedMod") (term "Duration"))
                            {:decay-steps (literal 16) :decay-duration (term "MoveSpeedModMinTime") :decay-floor (plus-one (term "MoveSpeedModMin"))})
                     (merge (slow (term "MoveSpeedModReduction") (term "SlowDuration")) {:target :self :delay (term "Duration")})]
      :katarina-w [(merge (speed (percent "MovespeedAmount") (term "MovespeedDuration")) {:decay-steps (literal 16)})]
      :viego-e [(buff "Harrowed Path" {:attack-speed-bonus (term "AttackSpeed")} (term "MistDuration"))
                (speed (term "TotalMovespeed") (term "MistDuration"))]
      :tryndamere-w [(stat :ad (term "ADReduction") (term "ReductionDuration") :add :enemy)]
      :yuumi-e [{:kind :shield :target :self :amount (term "TotalShielding") :duration (term "MSDuration") :shield-key "Zoomies"}
                (buff "Zoomies" {:attack-speed-bonus (percent "TotalAttackSpeed")} (term "MSDuration"))
                (merge (speed (percent "MSAmount") (term "MSDuration")) {:requires-shield "Zoomies"})]
      :master-yi-r [(buff "Highlander" {:attack-speed-bonus (percent "RASBonus")} (term "RDuration"))
                    (speed (percent "RMSBonus") (term "RDuration"))
                    {:kind :cleanse :target :self :controls [:slow] :attack-speed-slows true}
                    (protection "Highlander slow immunity" (term "RDuration") {:controls [:slow] :attack-speed-slows true})]
      :taric-r [(merge (protection "Cosmic Radiance" (term "InvulnDuration") {:damage-immune true})
                       {:delay (term "InitialDelay") :requires-caster-alive true})]
      :alistar-r [{:kind :cleanse :target :self :controls [:stun :charm :fear :suppression :silence :root :slow :grounded :polymorph]}
                  (protection "Unbreakable Will" (term "RDuration") {:damage-types [:physical :magic] :reduction (percent "RDamageReduction")})]
      :karma-q [(damage :magic (term "TotalDamage")) (slow (neg (term "SlowAmount")) (term "SlowDuration"))]
      :karma-w [{:kind :tether :target :enemy :damage-type :magic :amount (product-of (literal 2) (term "InitialDamage"))
                 :duration (term "TetherDuration") :leash (term "LeashBreakRange") :pulses (literal 2) :first-immediate true
                 :control :root :control-duration (term "RootDuration") :buff "Focused Resolve tether"}]
      :karma-e [{:kind :shield :target :self :amount (term "TotalShield") :duration (term "ShieldDuration")}
                (speed (term "MoveSpeed") (term "MoveSpeedDuration"))]
      :khazix-q [(damage :physical (term "IsoDamage"))]
      :khazix-w [{:kind :sequence :target :enemy
                  :effects [(damage :physical (term "BaseDamage"))
                            {:kind :heal :target :self :amount (term "HealAmount") :nearby-required
                             (literal 275)}]}]
      :khazix-e [(damage :physical (term "TotalDamage"))]
      :kayn-q [(merge (damage :physical (term "TotalDamage")) {:hits 2})]
      :kayn-w [(damage :physical (term "TotalDamage"))
               (merge (slow (neg (term "SlowIntensity")) (term "SlowDuration")) {:decay-steps (literal 16)})]
      :syndra-q [(damage :magic (term "TotalDamage"))]
      :veigar-w [(merge (damage :magic (term "TotalDamage")) {:delay (term "ImpactDelay")})]
      :volibear-e [(damage :magic (sum-of (term "CalculatedDamage") (product-of (term "PercentDamage") {:op :target-stat :stat :hp})))
                   (slow (term "SlowAmount") (term "SlowDuration"))
                   {:kind :shield :target :self :amount (term "ShieldValue") :duration (term "ShieldDuration")
                    :nearby-required (expr/ranked (get spell "castRadius") 0 "Sky Splitter blast radius")}]
      :nocturne-e [{:kind :tether :target :enemy :damage-type :magic :amount (term "TotalDamage")
                    :duration (term "LeashDuration") :leash (term "LeashBreakRange") :pulses (literal 8)
                    :control :fear :control-duration (term "CCDuration") :buff "Unspeakable Horror tether"}]
      :sivir-q [(merge (damage :physical (term "TotalDamage")) {:travel-multiplier 1})
                (merge (damage :physical (term "TotalDamage")) {:travel-multiplier 2})]
      :corki-e [{:kind :spray :target :enemy :damage-type :physical :amount (term "TotalDamage")
                 :duration (term "SprayDuration") :rate (term "TicksPerSecond") :radius (ability :range)
                 :shred (neg (term "ShredMax")) :shred-cap (term "ShredCap") :shred-duration (term "ShredDuration")}]
      :rell-r [(merge (damage :magic (quotient (term "TotalDamage") (literal 8)))
                      {:hits 8 :interval (quotient (term "Duration") (literal 8)) :delay (quotient (term "Duration") (literal 8))
                       :range-at-impact (term "GravityRadius") :requires-caster-alive true})
               (buff "Magnet Storm" {} (term "Duration"))]
      :nilah-w [(protection "Jubilant Veil" (term "BaseDuration") {:dodge-attacks true :damage-types [:magic] :reduction (term "MagicDamageReduction")})
                (speed (term "MoveSpeedPercent") (term "BaseDuration"))]
      :maokai-q [(damage :magic (sum-of (term "TotalDamage") (product-of (term "BasePercentHealth") {:op :target-stat :stat :hp})))
                 (slow (term "SlowAmount") (term "SlowDuration"))]))
  (defn problems [value]
    (cond (and (dictionary? value) (value :op)) (expr/problems value)
      (dictionary? value) (mapcat problems (values value))
      (indexed? value) (mapcat problems value) []))
  (def extra
    (case handler
      :blitzcrank-w {:self-cast true :missile-speed 0}
      :katarina-w {:self-cast true :missile-speed 0 :cast-time 0}
      :viego-e {:self-cast true :missile-speed 0}
      :tryndamere-w {:missile-speed 0}
      :yuumi-e {:self-cast true :missile-speed 0}
      :master-yi-r {:self-cast true :missile-speed 0 :cast-time 0}
      :taric-r {:self-cast true :missile-speed 0}
      :alistar-r {:self-cast true :missile-speed 0 :cast-time 0 :usable-controls [:stun :charm :fear :suppression :silence :root :slow :grounded :polymorph]}
      :karma-q {:range (expr/ranked (get karma-missile "castRange") 0 "Inner Flame missile range")
                :missile-speed (get-in karma-missile ["mMissileSpec" "movementComponent" "mSpeed"])}
      :karma-w {:missile-speed 0}
      :karma-e {:self-cast true :missile-speed 0}
      :khazix-w {:range (expr/ranked (get khazix-missile "castRange") 0 "Void Spike missile range")
                 :missile-speed (get-in khazix-missile ["mMissileSpec" "movementComponent" "mSpeed"])}
      :khazix-e {:missile-speed 0 :disabled-controls [:grounded :root]}
      :kayn-q {:missile-speed 0 :disabled-controls [:grounded :root]}
      :kayn-w {:missile-speed 0}
      :syndra-q {:missile-speed 0}
      :veigar-w {:missile-speed 0 :cooldown (term "BaseCooldown")}
      :volibear-e {:missile-speed 0 :always-release-self true}
      :nocturne-e {:missile-speed 0}
      :sivir-q {:missile-speed (get-in sivir-missile ["mMissileSpec" "movementComponent" "mSpeed"])
                :cast-time-expression (product-of (term "QBaseCastTime")
                                                  (sum-of (literal 1) (neg {:op :minimum :children [(term "QAttackSpeedCastReductionMax")
                                                                                                    (product-of bonus-as (term "QAttackSpeedCastReductionPercent"))]})))}
      :corki-e {:self-cast true :missile-speed 0}
      :rell-r {:self-cast true :missile-speed 0}
      :nilah-w {:self-cast true :missile-speed 0}
      :maokai-q {:missile-speed 0}
      {}))
  (def missing (seq [[name record] :in [["Inner Flame" karma-missile] ["Void Spike" khazix-missile] ["Boomerang Blade" sivir-missile]]
                     :when (and (or (and (= name "Inner Flame") (= handler :karma-q))
                                    (and (= name "Void Spike") (= handler :khazix-w))
                                    (and (= name "Boomerang Blade") (= handler :sivir-q))) (not record))]
                 (string name " requires its matching selected auxiliary spell.")))
  (def unresolved [;(problems specs) ;(problems extra) ;missing])
  (merge ability extra
         {:effects (map |(merge {:target-kinds [:champion :practice] :condition :always :trigger :cast
                                 :status (if (empty? unresolved) :estimated :unresolved) :evidence {:tooltip note :override true}} $) specs)
          :unresolved [;unresolved note]}))

(defn review [ability handler &opt forms]
  (case handler
    :blitzcrank-w (twenty-five ability handler forms)
    :katarina-w (twenty-five ability handler forms)
    :viego-e (twenty-five ability handler forms)
    :tryndamere-w (twenty-five ability handler forms)
    :yuumi-e (twenty-five ability handler forms)
    :master-yi-r (twenty-five ability handler forms)
    :taric-r (twenty-five ability handler forms)
    :alistar-r (twenty-five ability handler forms)
    :karma-q (twenty-five ability handler forms)
    :karma-w (twenty-five ability handler forms)
    :karma-e (twenty-five ability handler forms)
    :khazix-q (twenty-five ability handler forms)
    :khazix-w (twenty-five ability handler forms)
    :khazix-e (twenty-five ability handler forms)
    :kayn-q (twenty-five ability handler forms)
    :kayn-w (twenty-five ability handler forms)
    :syndra-q (twenty-five ability handler forms)
    :veigar-w (twenty-five ability handler forms)
    :volibear-e (twenty-five ability handler forms)
    :nocturne-e (twenty-five ability handler forms)
    :sivir-q (twenty-five ability handler forms)
    :corki-e (twenty-five ability handler forms)
    :rell-r (twenty-five ability handler forms)
    :nilah-w (twenty-five ability handler forms)
    :maokai-q (twenty-five ability handler forms)
    :garen-e (garen ability handler)
    :garen-r (garen ability handler)
    :fiddlesticks-q (fiddlesticks ability handler)
    :fiddlesticks-w (fiddlesticks ability handler)
    :fiddlesticks-e (fiddlesticks ability handler)
    :fiddlesticks-r (fiddlesticks ability handler)
    :vayne-w (vayne ability)
    :seraphine-q (seraphine ability handler)
    :seraphine-w (seraphine ability handler)
    :seraphine-e (seraphine ability handler)
    :seraphine-p (seraphine ability handler)
    :vi-w (completeness ability handler)
    :twisted-fate-e (completeness ability handler)
    :tristana-q (completeness ability handler)
    :singed-r (completeness ability handler)
    :gangplank-w (completeness ability handler)
    :veigar-r (completeness ability handler)
    :zac-w (completeness ability handler)
    :zilean-e (completeness ability handler)
    :malzahar-e (completeness ability handler)
    :cassiopeia-q (completeness ability handler)
    (twenty ability handler)))
