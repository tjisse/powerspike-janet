(import ./expressions :as expr)
(import ./remaining-abilities :as remaining)
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
           :zilean-w {:self-cast true :missile-speed 0 :audit-context {:kind :needs-basic-cooldown :only-if-no-effect true :reason "The isolated probe supplies no Q/E cooldown to refund. Paired E/W regressions verify its actual readiness change."}}
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

(defn attack-defense [ability handler forms]
  (def spell (ability :record))
  (defn term [name] (expr/variable name spell))
  (defn pct [name] (product-of (literal 0.01) (term name)))
  (defn neg [node] (product-of (literal -1) node))
  (defn one-plus [node] (sum-of (literal 1) node))
  (defn self-stat [key] {:op :stat :stat key :formula 0})
  (defn target-stat [key] {:op :target-stat :stat key})
  (defn dmg [type amount &opt fields] (merge {:kind :damage :target :enemy :damage-type type :amount amount} (or fields {})))
  (defn stat [key amount duration &opt mode fields]
    (merge {:kind :stat-buff :target :self :stat key :amount amount :duration duration :mode (or mode :add)} (or fields {})))
  (defn haste [amount duration &opt fields] (stat :move-speed (one-plus amount) duration :multiply fields))
  (defn buff [name bonuses duration] {:kind :buff :target :self :buff name :stat-bonuses bonuses :duration duration :refresh true})
  (defn empower [count duration effects &opt fields]
    (merge {:kind :empower :target :self :count count :duration duration :effects effects} (or fields {})))
  (defn aux [suffix]
    (get (find |(string/has-suffix? (string/ascii-lower suffix) (string/ascii-lower ($ :path))) (or forms [])) :record))
  (def janna-passive (when (= handler :janna-w) (aux "/TailwindSelf")))
  (def cait-missile (when (= handler :caitlyn-r) (aux "/CaitlynRMissile")))
  (def all-cc [:stun :root :charm :fear :airborne :suppression :silence :slow :grounded :polymorph])
  (def note (case handler
              :chogath-e "Vorpal Spikes resets the attack timer and empowers three attacks with magic damage, decaying slows and range. Cooldown begins after consumption/expiry. Feast stacks start at zero; width, secondary targets and monsters remain excluded."
              :kayle-e "Starfire Spellblade grants passive attack damage and a ranged, resetting next attack with live missing-health magic damage. Its ordinary modeled attack delivers the hit; explosion geometry and exceptional on-hit ordering remain excluded."
              :fizz-w "Seastone Trident adds refreshing bleed pulses. Its next attack gains bonus damage; a surviving target enables five seconds of extra on-hit damage, while a killing attack refunds mana and sets a short cooldown. Monster rules and Q application remain excluded."
              :sett-q "Knuckle Down resets attacks, empowers the next two with maximum-health damage and grants movement only while approaching the sole champion. Sett's alternating-hand passive timing and other kit effects remain excluded."
              :volibear-q "Thundering Smash resets attacks, grants conditional chase speed/range and replaces the next attack's damage with its base/AD result plus stun. Immobilization before consumption cancels the buff and resets cooldown. Terrain, unit collision and exceptional attack effects remain excluded."
              :xayah-w "Deadly Plumage grants attack speed and a secondary physical blade sharing the attack's rolled raw damage; a successful blade grants movement speed. Rakan sharing, feather geometry and secondary projectile timing remain excluded."
              :sona-e "Song of Celerity grants self movement for at least three seconds, up to seven while unharmed. Damage after the minimum ends it. Allied aura, Power Chord and passive stacks remain excluded."
              :teemo-w "Move Quick grants passive movement while out of champion/turret combat, recovering after the source delay. The active replaces it with doubled movement that persists through damage. The fight assumes no recent pre-fight damage; camouflage and other passive effects remain excluded."
              :miss-fortune-w "Strut grants learned-rank out-of-combat movement in two stages. Activation restores full movement and grants attack speed; new damage removes the movement bonus and restarts recovery. The fight begins fully recovered. Love Tap and its cooldown refunds remain excluded."
              :nasus-w "Wither ramps movement and attack-speed reduction together in source-strength, one-second steps scaled by tenacity. Tenacity shortens the control window, cleanse removes both, and slow immunity blocks both. The source maximum persists through the final step interval."
              :shen-w "Spirit's Refuge blocks ordinary attacks and their procs for its duration, assuming Shen and his spirit blade are together and he remains in the zone. Blade placement, allies and delayed entry remain excluded."
              :tryndamere-r "Undying Rage prevents damage from reducing health below its source floor without healing a caster already below it. It casts while disabled and restores Fury in the configured resource pool. Fury-derived crits, exceptional death effects and other passives remain excluded."
              :olaf-r "Ragnarok grants permanent resistances, cleanses and prevents controls, grants AD and brief chase movement. Distinct champion attacks or E hits refresh its remaining duration to at least the source extension. Exceptional displacement, E cast-only refresh and other passive effects remain excluded."
              :malphite-w "Thunderclap grants permanent armor, resets and empowers an attack, then adds aftershocks on later attacks. Granite Shield's tripled armor, cone geometry and monsters remain excluded."
              :taric-w "Bastion grants its learned-rank armor multiplier and self maximum-health shield. Linked allies and duplicate spell origins remain excluded."
              :evelynn-e "Base Whiplash deals base plus maximum-health damage, applies supported on-hit effects and grants movement when it hits. Demon Shade empowerment, its dash and reset remain excluded."
              :kogmaw-r "Living Artillery scales with live missing health, doubles below the source tooltip's 40% threshold, and stacks mana costs with a cap and eight-second expiry. Ground impact delay and vision remain excluded; impact uses modeled cast completion."
              :caitlyn-r "Ace in the Hole uses its source critical-stat scaling, a one-second channel after the raw cast time and the selected missile. Control or target death interrupts it, setting a five-second cooldown without refunding mana. Interception, vision and exceptional untargetability remain excluded."
              :pyke-w "Ghostwater Dive grants lethality-scaled decaying movement, ending on a subsequent attack/cast. Camouflage, detection and grey-health healing remain excluded."
              :pyke-r "Death From Below checks live health: below threshold it deals shield-bypassing true damage; otherwise reduced physical damage. It blinks on an unblocked champion hit. Undying protection still prevents death. X geometry, kill-gold/recasts and other targets remain excluded."
              :gwen-w "Hallowed Mist grants resistances and blocks enemy damage/control from outside its fixed zone. The zone follows automatically once when Gwen exits, then ends on a second exit. Manual repositioning, terrain, edge hitboxes and exceptional targeting remain excluded."
              :janna-w "Zephyr grants learned-rank movement at combat start, then deals base/AP plus selected Tailwind bonus-movement damage and a slow. Temporary AP changes to its passive movement, ghosted collision and other allies remain excluded."
              :diana-r "Moonfall pulls the sole nearby champion to the caster in one dimension, slows, and checks range again for its delayed base explosion. Multi-champion amplification, flight/airborne timing and geometry remain excluded."
              :milio-w "Self-following Cozy Campfire grants attack range and twelve half-second healing pulses over its duration. Ally retargeting, Fired Up and measured healing tick phase remain excluded."
              :hecarim-w "Spirit of Dread deals source-rate nearby pulses, grants resistances and heals from Hecarim's damage to nearby champions after resistance, including shield absorption. Allies, monsters, geometry and exceptional damage interactions remain excluded."))
  (assert note "Unknown attack/defense handler.")
  (def specs
    (case handler
      :chogath-e [(empower (term "MaximumAttacks") (term "BuffDuration")
                           [(dmg :magic (sum-of (term "FlatDamageCalc") (product-of (term "MaxHealthPercentCalc") (target-stat :hp))))
                            {:kind :control :control :slow :target :enemy :strength (pct "SlowAmountPercentage") :duration (term "SlowDuration") :decay-steps (literal 16)}]
                           {:reset true :range-bonus (term "AttackRangeIncrease") :cooldown-after true})]
      :kayle-e [(dmg :magic (term "EPassiveTotalDamage") {:trigger :passive :on [:attack] :allow-same-time true})
                (empower (literal 1) (term "BuffDuration") [(dmg :magic (product-of (term "ActiveTotalExecuteDamage") (target-stat :missing-health)))]
                         {:reset true :range-floor (ability :range)})]
      :fizz-w [{:kind :periodic :target :enemy :trigger :passive :on [:attack] :allow-same-time true :damage-type :magic :amount (term "DoTDamage")
                :duration (term "BleedDuration") :pulse-count (product-of (term "BleedDuration") (term "DoTTicksPerSecond"))
                :pulse-interval (quotient (literal 1) (term "DoTTicksPerSecond")) :first-delay (quotient (literal 1) (term "DoTTicksPerSecond")) :preserve-pulse-phase true :buff "Seastone bleed"}
               (empower (literal 1) (term "ActiveDuration") [(dmg :magic (term "ActiveDamage"))]
                        {:reset true :after-first [(empower :all (term "OnHitBuffDuration") [(dmg :magic (term "OnHitBuffDamage"))])]
                         :on-kill [{:kind :resource :target :self :amount (term "OnKillManaRefund")}
                                   {:kind :set-cooldown :target :self :amount (term "OnKillNewCooldown")}]})]
      :sett-q [(empower (literal 2) (term "Duration") [(dmg :physical (sum-of (term "BaseDamage") (product-of (term "MaxHealthDamageCalc") (target-stat :hp))))] {:reset true})
               (haste (term "MSAmount") (term "MSDuration") {:chase-only true})]
      :volibear-q [(empower (literal 1) (term "Duration")
                            [(dmg :physical (sum-of (term "CalculatedDamage") (neg (self-stat :ad))))
                             {:kind :control :control :stun :target :enemy :duration (term "StunDuration")}]
                            {:reset true :range-bonus (term "BonusRange") :reset-on-controls [:stun :root :charm :fear :airborne :suppression :polymorph]})
                   (haste (term "MinSpeed") (term "Duration") {:requires-empowerment (ability :id) :chase-amount (one-plus (term "MaxSpeed"))})]
      :xayah-w [(buff "Deadly Plumage" {:attack-speed-bonus (pct "WAttackSpeedAmount")} (term "WAttackSpeedDuration"))
                (empower :all (term "WAttackSpeedDuration")
                         [(dmg :physical (literal 0) {:attack-raw-ratio (pct "BonusDamagePercent") :suppress-procs true})
                          (haste (pct "WMoveSpeedAmount") (term "WMoveSpeedDuration"))])]
      :sona-e [{:kind :combat-move :target :self :policy :sona :amount (term "TotalSelfMovementSpeed")
                :minimum (term "SelfMovementSpeedDurationMin") :maximum (term "SelfMovementSpeedDurationMax")}]
      :teemo-w [{:kind :combat-move :target :self :trigger :combat-start :policy :teemo :amount (term "PassiveMoveSpeedBonus") :recovery (term "PassiveCooldownOnDamageTaken")}
                {:kind :combat-move :target :self :policy :activate :amount (term "ActiveMoveSpeedBonus") :duration (term "ActiveMoveSpeedBuffDuration")}]
      :miss-fortune-w [{:kind :combat-move :target :self :trigger :combat-start :policy :strut :amount (term "PassiveBaseMS") :maximum-amount (term "PassiveMaxMS")
                        :recovery (term "PassiveBaseMSOOC") :second-recovery (term "PassiveMaxMSExtraOOC")}
                       (buff "Strut attack speed" {:attack-speed-bonus (term "ActiveAS")} (term "ActiveDuration"))
                       {:kind :combat-move :target :self :policy :restore}]
      :nasus-w [{:kind :withering :target :enemy :strength (pct "SlowBase") :maximum (pct "MaxSlowTooltipOnly") :increment (pct "SlowPerTick") :attack-ratio (term "AttackSpeedSlowMult") :duration (term "Duration")}]
      :shen-w [{:kind :protection :target :self :buff "Spirit's Refuge" :block-attacks true :duration (term "ZoneDuration")}]
      :tryndamere-r [{:kind :protection :target :self :buff "Undying Rage" :duration (term "TryndRDuration") :health-floor (term "TryndRMinHealth")}
                     {:kind :resource :target :self :amount (term "TryndRFuryGain")}]
      :olaf-r [{:kind :cleanse :target :self :controls all-cc :attack-speed-slows true}
               {:kind :protection :target :self :buff "Ragnarok" :duration (term "Duration") :controls all-cc :attack-speed-slows true
                :extend-on [:attack :spell-hit] :extend-slots [:e] :extension (term "DurationExtension")}
               (stat :ad (term "AD") (literal 100000) :add {:requires-protection (ability :id)})
               (haste (term "Haste") (term "HasteDuration") {:chase-only true})]
      :malphite-w [(empower (literal 1) (term "ThunderclapBuffDuration") [(dmg :physical (term "TotalBonusDamage")) (dmg :physical (term "ThunderclapSplash"))]
                            {:reset true :after-first [(empower :all (term "ThunderclapBuffDuration") [(dmg :physical (term "ThunderclapSplash"))])]})]
      :taric-w [{:kind :shield :target :self :amount (product-of (pct "ShieldHPRatio") (self-stat :hp)) :duration (term "ShieldDuration")}]
      :evelynn-e [{:kind :sequence :target :enemy :effects
                   [(dmg :magic (sum-of (term "BaseDamage") (product-of (term "PercentHealthBaseTOOLTIP") (target-stat :hp))) {:applies-on-hit true})
                    (haste (term "SpeedAmount") (term "SpeedDuration"))]}]
      :kogmaw-r [{:kind :health-threshold-damage :target :enemy :amount (term "BaseDamageCalc") :amplification (term "TooltipMissingHealthDamageAmp")
                  :threshold (literal 0.4) :maximum (term "FinalDamageMult") :damage-type :magic}]
      :caitlyn-r [(dmg :physical (term "RTotalDamage"))]
      :pyke-w [(merge (haste (pct "MoveSpeed") (term "CamoDuration") {:end-on-action true}) {:decay-steps (literal 16)})]
      :pyke-r [{:kind :threshold-strike :target :enemy :amount (term "RDamage") :ratio (term "ReducedDamage")}]
      :gwen-w [{:kind :protection :target :self :buff "Hallowed Mist" :duration (term "ZoneDuration") :zone-radius (term "ZoneRadius") :zone-relocations 1 :outside-untargetable true}
               (stat :armor (term "TotalResists") (term "ZoneDuration") :add {:requires-protection (ability :id)})
               (stat :mr (term "TotalResists") (term "ZoneDuration") :add {:requires-protection (ability :id)})]
      :janna-w [(merge (haste (term "TotalMS") (literal 100000)) {:trigger :combat-start})
                (dmg :magic (sum-of (term "TotalDamage") (expr/variable "BonusDamage" (merge (or janna-passive {}) {"__powerspike_patch" "16.21.1" "__powerspike_stat_scope" [[7 2]]}))))
                {:kind :control :target :enemy :control :slow :strength (term "TotalSlow") :duration (term "SlowDuration")}]
      :diana-r [{:kind :moonfall :target :enemy :amount (term "RExplosionDamage") :delay-duration (term "Delay")
                 :strength (neg (term "SlowPotency")) :duration (term "SlowDuration") :radius (ability :range)}]
      :milio-w [(stat :attack-range (product-of (term "RangePctIncrease") (self-stat :attack-range)) (term "ZoneDuration"))
                {:kind :heal :target :self :amount (quotient (term "HealingOverTime") (literal 12)) :hits 12 :interval (quotient (term "ZoneDuration") (literal 12))
                 :delay (quotient (term "ZoneDuration") (literal 12)) :requires-caster-alive true}]
      :hecarim-w [(stat :armor (term "ResistAmount") (term "BuffDuration")) (stat :mr (term "ResistAmount") (term "BuffDuration"))
                  {:kind :damage-vamp :target :self :duration (term "BuffDuration") :radius (ability :range) :amount (pct "LeechAmount")}
                  (dmg :magic (quotient (term "TotalDamage") (quotient (term "BuffDuration") (term "TickTime")))
                       {:hits (quotient (term "BuffDuration") (term "TickTime")) :interval (term "TickTime") :delay (term "TickTime")
                        :range-at-impact (ability :range) :requires-caster-alive true :heal-dealt-ratio (pct "LeechAmount") :vamp-accounted true})]))
  (def extra
    (case handler
      :chogath-e {:self-cast true :cast-time 0 :missile-speed 0}
      :kayle-e {:self-cast true :cast-time 0 :missile-speed 0}
      :fizz-w {:self-cast true :cast-time 0 :missile-speed 0}
      :sett-q {:self-cast true :cast-time 0 :missile-speed 0}
      :volibear-q {:self-cast true :cast-time 0 :missile-speed 0}
      :xayah-w {:self-cast true :cast-time 0 :missile-speed 0}
      :sona-e {:self-cast true :cast-time 0 :missile-speed 0}
      :teemo-w {:self-cast true :cast-time 0 :missile-speed 0}
      :miss-fortune-w {:self-cast true :cast-time 0 :missile-speed 0}
      :nasus-w {:missile-speed 0}
      :shen-w {:self-cast true :cast-time 0 :missile-speed 0}
      :tryndamere-r {:self-cast true :cast-time 0 :missile-speed 0 :usable-controls all-cc}
      :olaf-r {:self-cast true :cast-time 0 :missile-speed 0 :usable-controls all-cc :rank-bonuses {:armor (term "Resists") :mr (term "Resists")}}
      :malphite-w {:self-cast true :cast-time 0 :missile-speed 0 :rank-bonuses {:armor-multiplier (one-plus (term "BonusArmorPassive"))}}
      :taric-w {:self-cast true :missile-speed 0 :rank-bonuses {:armor-multiplier (one-plus (term "ArmorBonusPercentage"))}}
      :evelynn-e {:missile-speed 0}
      :kogmaw-r {:missile-speed 0 :stacking-cost {:base (term "BaseCost") :cap (term "ManaCostCap") :window (term "ManaCostDuration")}}
      :caitlyn-r {:missile-speed (get-in cait-missile ["mMissileSpec" "movementComponent" "mSpeed"])
                  :cast-time (+ (get spell "mCastTime" (get spell "spellCastTime" 0.25)) 1) :channel true :interruptible-channel true :finish-channel-on-release true :cancel-cooldown 5 :cancel-on-target-death true}
      :pyke-w {:self-cast true :cast-time 0 :missile-speed 0}
      :pyke-r {:missile-speed 0}
      :gwen-w {:self-cast true :cast-time 0 :missile-speed 0}
      :diana-r {:self-cast true :missile-speed 0}
      :milio-w {:self-cast true :missile-speed 0}
      :hecarim-w {:self-cast true :cast-time 0 :missile-speed 0}
      {}))
  (defn problems [node]
    (cond (and (dictionary? node) (node :op)) (expr/problems node)
      (dictionary? node) (mapcat problems (values node))
      (indexed? node) (mapcat problems node) []))
  (def missing [;(if (and (= handler :janna-w) (not janna-passive)) ["Zephyr requires selected Tailwind source."] [])
                ;(if (and (= handler :caitlyn-r) (not cait-missile)) ["Ace in the Hole requires selected missile source."] [])])
  (def unresolved [;(problems specs) ;(problems extra) ;missing])
  (merge ability extra {:effects (map |(merge {:trigger :cast :condition :always :target-kinds [:champion :practice]
                                               :status (if (empty? unresolved) :estimated :unresolved) :evidence {:tooltip note :override true}} $) specs)
                        :unresolved [;unresolved note]}))

(defn areas-impact [ability handler forms]
  (def spell (ability :record))
  (defn term [name] (expr/variable name spell))
  (defn pct [name] (product-of (literal 0.01) (term name)))
  (defn self-stat [key] {:op :stat :stat key :formula 0})
  (defn enemy-stat [key] {:op :target-stat :stat key})
  (defn dmg [amount &opt type] {:kind :damage :target :enemy :damage-type (or type :magic) :amount amount})
  (defn slow [strength duration] {:kind :control :target :enemy :control :slow :strength strength :duration duration})
  (defn speed [amount duration] {:kind :stat-buff :target :self :stat :move-speed :mode :multiply :amount (sum-of (literal 1) amount) :duration duration})
  (defn field [duration interval radius effects &opt extra]
    (merge {:kind :field :target :self :duration duration :interval interval :radius radius :effects effects} (or extra {})))
  (defn aux [suffix] (get (find |(string/has-suffix? (string/ascii-lower suffix) (string/ascii-lower ($ :path))) (or forms [])) :record))
  (def ez-missile (when (= handler :ezreal-w) (aux "/EzrealW")))
  (def naut-missile (when (= handler :nautilus-q) (aux "/NautilusAnchorDragMissile")))
  (def lucian-p (when (= handler :lucian-e) (aux "/LucianPassive")))
  (def gangplank-missile (when (= handler :gangplank-q) (aux "/GangplankQProceed")))
  (def twitch-missile (when (= handler :twitch-w) (aux "/TwitchVenomCaskMissile")))
  (def note (case handler
              :aatrox-e "Umbral Dash heals for the selected champion-damage vamp and moves toward the opponent up to its source range at cast completion. Continuous dash travel, casting during another windup and World Ender amplification remain excluded."
              :alistar-e "Trample checks radius every half second, gains stacks on champion hits, and grants one stunning empowered attack on five hits. Its aura ends on consumption. Ghosted collision and exact initial tick phase remain excluded."
              :amumu-w "Despair toggles on automatically, pays mana for each half-second interval, checks radius and deals source percentage-health damage. It stops when unaffordable. Manual toggle-off and Curse refresh remain excluded."
              :anivia-r "Glacial Storm persists at the opponent's cast position, drains mana, grows to its source damage and slow strengths, and ends on disabling control, range leash or resource depletion. Circular growth uses source minimum/maximum radii with linear model growth; Frostbite synergy and manual recasting remain excluded."
              :braum-e "Unbreakable grants source movement and absorbs the first non-true damaging hit, then reduces non-true damage while facing the sole opponent. This duel assumes continued facing; missile interception geometry and allies remain excluded."
              :ezreal-w "Essence Flux marks its hit target, detonates on a subsequent ordinary attack or ability damage, and refunds the detonating ability's paid mana plus the source return. Item procs do not detonate it independently. Collision and structures remain excluded."
              :gangplank-q "Parrrley deals source physical damage, rolls critical damage using the selected calculation and applies supported attack on-hits once. Barrel interaction, gold and Silver Serpents remain excluded."
              :ivern-w "Brushmaker places brush at the caster's cast position and grants its source on-hit while inside, lingering after exit. Three charges and source recovery are modeled; allies, vision and natural map brush remain excluded."
              :kled-w "Violent Tendencies starts on an ordinary attack, grants four attacks of source attack speed and adds source maximum-health damage on the fourth release. Cooldown begins on consumption or expiry; champion hits refund source cooldown. Dismounting, structures and special hit interactions remain excluded."
              :lucian-e "Relentless Pursuit moves toward the opponent up to source range at cast completion and resets the attack timer. Its next Lightslinger adds the selected passive second shot and refunds E on both hits. Simultaneous movement, other abilities' Lightslinger activations and Vigilance remain excluded."
              :malzahar-r "Nether Grasp immediately suppresses and channels ten source beam ticks, with a fixed-position percentage-health pool lasting independently. Interrupting the caster ends the beam and its suppression. Geometry, voidlings and manual cancel remain excluded."
              :milio-q "Ultra Mega Fire Kick knocks the sole target away, applies source damage/slow at modeled projectile impact and refunds half the paid mana on a champion hit. Bounce flight and minion geometry remain excluded."
              :nautilus-q "Dredge Line uses the selected missile, deals source damage, stuns and draws both actors to their midpoint on hit. Pull travel and terrain refunds remain excluded."
              :ornn-e "Searing Charge advances toward the opponent and deals source bonus-resistance damage at cast completion within dash range. Terrain collision and its conditional knockup are excluded because this duel has no terrain input."
              :rumble-q "Flamespitter checks radius every source quarter-second, deals base/AP and maximum-health damage, and scales with tracked Danger Zone heat. Heat gain from these reviewed Q/W casts, delayed decay and overheat ability lock are modeled; E/R heat interactions remain excluded. Overheated attacks, cone facing and post-exit burn remain excluded."
              :rumble-w "Scrap Shield grants the source shield and movement, with tracked Danger Zone heat amplification. Heat gain from these reviewed Q/W casts, delayed decay and overheat ability lock are modeled; E/R heat interactions remain excluded. Overheated attacks remain excluded."
              :taliyah-w "Seismic Shove displaces the target toward the caster after its source delay. Direction is fixed to pull; airborne flight, terrain and Unraveled Earth interaction remain excluded."
              :thresh-e "Flay applies source magic damage and slow and pushes the target away. Its passive starts fully charged, scales with time since the previous attack and retains configured soul counts. Airborne flight, chosen swing direction and soul collection remain excluded."
              :trundle-e "Pillar of Ice pushes the target away and maintains a source slow within the fixed-position area. Terrain path blocking and airborne flight remain excluded."
              :twitch-w "Venom Cask maintains its source slow in a fixed-position cloud. Deadly Venom stack damage and Contaminate coupling remain excluded; this slot currently models the cloud's movement effect only."
              :warwick-r "Infinite Duress reaches the sole target at modeled cast completion, suppresses and channels three source magic hits with supported on-hits and healing for post-resistance damage. It ends on caster control or target death. Leap travel, collision and passive heal amplification remain excluded."
              :fizz-r "Chum the Waters attaches a fish, applies a distance-tier slow, then source tier damage and a one-second knockup after the detonation delay. Distance is sampled at release. Missile collision and extra targets remain excluded."
              :senna-e "Curse of the Black Mist grants the source AP-scaled movement boost for its source duration. Camouflage, target visibility, ally sharing and the rest of Senna's kit remain excluded."
              :tryndamere-q "Bloodlust consumes the configured Fury pool and heals base/AP plus source healing per Fury, capped at 100 Fury. Fury generation, Fury-derived critical chance and passive missing-health attack damage remain excluded."
              :velkoz-r "Life Form Disintegration Ray channels ten evenly spaced magic-damage model ticks with its source slow and range checks, interrupted by disabling control. Research, Deconstruction stack/true-damage conversion, cursor geometry and manual cancel remain excluded."))
  (assert note "Unknown area/impact handler.")
  (def specs (case handler
               :aatrox-e [{:kind :damage-vamp :target :self :trigger :combat-start :duration (literal 180) :radius (literal 1e6) :amount (term "TotalEVamp") :buff "Umbral Dash"}
                          {:kind :advance :target :self :distance (term "EMaxRange")}]
               :alistar-e [(field (term "Duration") (literal 0.5) (term "Radius")
                                  [(dmg (quotient (term "TotalDamage") (literal 10)))]
                                  {:stacks (term "MaxStacks") :empower {:kind :empower :count (literal 1) :duration (literal 6) :range-bonus (term "BonusAARange")
                                                                        :end-field true :spell-shield-sensitive true :consume-on-miss false :effects [(dmg (term "AttackBonusDamage")) {:kind :control :control :stun :target :enemy :duration (term "StunDuration")}]}})]
               :amumu-w [(field (literal 180) (literal 0.5) (ability :range)
                                [(dmg (product-of (literal 0.5) (sum-of (term "BaseDamage") (product-of (pct "TotalHealthDamage") (enemy-stat :hp)))))]
                                {:mana-per-second (expr/ranked (get spell "mana") -1 "Despair mana per second") :toggle true})]
               :anivia-r [(field (literal 180) (term "TickRate") (literal 400)
                                 [(dmg (product-of (term "TickRate") (term "TotalDamagePerSecond")))
                                  (slow (pct "SlowAmount") (term "ChillDuration"))]
                                 {:fixed true :toggle true :leash (term "LeashBreak") :interrupt-controls [:stun :charm :fear :airborne :suppression :silence :polymorph]
                                  :mana-per-second (term "ManaCostPerSecond") :growth (term "GrowthTime") :initial-radius (literal 200) :growth-damage (pct "BonusMultiplier") :growth-slow (term "EnhancedSlow") :growth-slow-duration (product-of (term "ChillDuration") (term "SlowDurationAtMaxMultiplier"))})]
               :braum-e [{:kind :protection :target :self :buff "Unbreakable" :duration (term "ShieldHoldDuration") :first-hit-immune true :damage-types [:physical :magic] :reduction (pct "ShieldFacingDRAmount")}
                         (speed (pct "MoveSpeedPercent") (term "ShieldHoldDuration"))]
               :ezreal-w [{:kind :attach :target :enemy :amount (term "Damage") :duration (term "DetonationTimeout") :mana-return (term "ManaReturn")}]
               :gangplank-q [(merge (dmg (term "ShotDamage") :physical) {:critical-amount (term "ShotCrit") :applies-on-hit true})]
               :ivern-w [{:kind :brush :target :self :duration (term "MaxBrushDuration") :radius (term "BrushRadius") :linger (term "BuffDuration") :amount (term "TotalDamage")}]
               :kled-w [{:kind :attack-cycle :target :self :trigger :combat-start :count (literal 4) :duration (term "ActiveDuration") :attack-speed (term "AttackSpeed")
                         :refund (term "ChampCooldownRefund")
                         :effects [(dmg (sum-of (term "BaseFlatDamage") (product-of (term "PercentDamage") (enemy-stat :hp))) :physical)]}]
               :lucian-e [{:kind :advance :target :self :distance (term "MaxDistance")}
                          {:kind :reset :target :self}
                          {:kind :empower :target :self :count (literal 1) :duration (expr/variable "PassiveDuration" lucian-p)
                           :effects [(merge (dmg (expr/variable "TotalDamage" lucian-p) :physical) {:applies-on-hit true :separate-origin true :attack-hit true :inherit-critical true :critical-amount (product-of (expr/variable "TotalDamage" lucian-p) (self-stat :crit-damage))})
                                     {:kind :cooldown-refund :target :self :slots [:e] :amount (product-of (literal 2) (term "CDRefundChampion"))}]}]
               :malzahar-r [{:kind :beam :target :enemy :duration (term "CCDuration") :pulses (term "BeamDamageTicks") :amount (term "TotalDamageTooltip") :radius (term "BeamTetherRange") :break-on-range true :control :suppression}
                            (field (term "PoolDuration") (literal 0.5) (literal 250)
                                   [(dmg (product-of (quotient (term "ZoneDamageTooltip") (literal 10)) (enemy-stat :hp)))] {:fixed true :persists-after-death true})]
               :milio-q [{:kind :sequence :target :enemy :effects
                          [(dmg (term "Damage")) (slow (term "SlowAmountPercent") (term "SlowDuration"))
                           {:kind :displace :mode :away :distance (term "KnockbackDistance")}
                           {:kind :paid-mana-refund :target :self :amount (term "RefundRatio")}]}]
               :nautilus-q [{:kind :sequence :target :enemy :effects
                             [(dmg (term "QDamageCalc")) {:kind :control :control :stun :duration (literal 1)} {:kind :meet :target :enemy}]}]
               :ornn-e [(dmg (term "TotalDamage") :physical) {:kind :advance :target :self :distance (term "DashRange")}]
               :rumble-q [(field (term "FlamespitterDuration") (term "TickRate") (ability :range)
                                 [(dmg (quotient (sum-of (term "FlatDamage") (product-of (term "HealthDamage") (enemy-stat :hp))) (term "TotalTicks")))] {:heat-scaled true})]
               :rumble-w [{:kind :shield :target :self :amount (term "TotalShield") :duration (term "ShieldDuration") :heat-scaled true}
                          (merge (speed (term "MoveSpeed") (term "MoveSpeedDuration")) {:heat-scaled true})]
               :taliyah-w [{:kind :displace :target :enemy :mode :toward :distance (term "ThrowDistance") :delay (term "KnockupDelay")}]
               :thresh-e [(dmg (term "TotalDamage")) (slow (pct "ActiveSlowPercentage") (term "SlowDuration"))
                          {:kind :displace :target :enemy :mode :away :distance (literal 200)}
                          {:kind :charged-attack :target :enemy :trigger :passive :on [:attack] :allow-same-time true :amount (term "PAttackDamageMin") :maximum (term "PAttackDamageMax") :duration (term "FullChargeDuration")}]
               :trundle-e [{:kind :displace :target :enemy :mode :away :distance (term "EnemyDisplacementRange")}
                           (field (term "PillarDuration") (literal 0.25) (term "SlowRadius") [(slow (pct "SlowAmount") (literal 0.25))] {:fixed true :immediate true :persists-after-death true})]
               :twitch-w [(field (term "Duration") (literal 0.25) (term "AoERadius") [(slow (pct "TotalSlowAmount") (literal 0.25))] {:fixed true :immediate true :persists-after-death true})]
               :warwick-r [{:kind :beam :target :enemy :duration (term "RDuration") :pulses (literal 3) :amount (term "DamageCumulative") :radius (literal 2500) :break-on-range true :control :suppression :applies-on-hit true :heal-ratio (literal 1)}]
               :fizz-r [{:kind :shark :target :enemy :amount (term "SmallSharkDamage") :medium (term "MidDamageMulti") :large (term "LargeDamageMulti") :duration (term "DetonationTime")}]
               :senna-e [(speed (term "TotalMS") (term "BuffDuration"))]
               :tryndamere-q [{:kind :fury-heal :target :self :amount (term "BaseHeal") :per-fury (term "HealPerFury")}]
               :velkoz-r [{:kind :beam :target :enemy :duration (literal 2.5) :pulses (literal 10) :amount (term "TotalDamage") :radius (ability :range) :slow (pct "Effect3Amount")}]))
  (def extra (case handler
               :aatrox-e {:self-cast true :missile-speed 0 :disabled-controls [:grounded :root]}
               :alistar-e {:self-cast true :missile-speed 0 :cast-time 0}
               :amumu-w {:cost-resource :resource :minimum-resource (product-of (literal 0.5) (expr/ranked (get spell "mana") -1 "Despair minimum mana")) :self-cast true :missile-speed 0 :cast-time 0 :cost (literal 0)}
               :anivia-r {:cast-range-required true :cost (expr/ranked (get spell "mana") -1 "Glacial Storm initial mana") :cost-resource :resource :range (literal 750) :missile-speed 0 :cast-time 0}
               :braum-e {:self-cast true :missile-speed 0 :cast-time 0}
               :ezreal-w {:missile-speed (get-in ez-missile ["mMissileSpec" "movementComponent" "mSpeed"])}
               :gangplank-q {:missile-speed (get-in gangplank-missile ["mMissileSpec" "movementComponent" "mSpeed"]) :cast-time 0.25}
               :ivern-w {:self-cast true :missile-speed 0 :max-charges (literal 3) :recharge-time (expr/ranked (get spell "mAmmoRechargeTime") 0 "Brushmaker charge recovery") :charge-delay (literal 0.5)}
               :kled-w {:passive true :self-cast true :missile-speed 0 :cooldown (term "WCooldown")}
               :lucian-e {:self-cast true :missile-speed 0 :disabled-controls [:grounded :root]}
               :malzahar-r {:missile-speed 0 :channel true :interruptible-channel true :cast-lock (term "CCDuration") :cancel-on-target-death true}
               :milio-q {:missile-speed (get-in spell ["mMissileSpec" "movementComponent" "mSpeed"])}
               :nautilus-q {:missile-speed (get-in naut-missile ["mMissileSpec" "movementComponent" "mSpeed"]) :range (ability :range)}
               :ornn-e {:missile-speed 0 :range (term "DashRange") :disabled-controls [:grounded :root]}
               :rumble-q {:cost-resource :mana :self-cast true :missile-speed 0 :cast-time 0 :heat-gain (term "InitialHeatCost") :cost (literal 0)}
               :rumble-w {:cost-resource :mana :self-cast true :missile-speed 0 :cast-time 0 :heat-gain (term "HeatCost") :cost (literal 0)}
               :taliyah-w {:missile-speed 0}
               :thresh-e {:missile-speed 0 :range (literal 500)}
               :trundle-e {:missile-speed 0}
               :twitch-w {:cast-range-required true :missile-speed (get-in twitch-missile ["mMissileSpec" "movementComponent" "mSpeed"])}
               :warwick-r {:missile-speed 0 :range (product-of (self-stat :move-speed) (literal 2.5)) :blink-to-target true :channel true :interruptible-channel true :cast-lock (sum-of (literal 0.1) (term "RDuration")) :cancel-on-target-death true :disabled-controls [:grounded :root]}
               :fizz-r {:missile-speed (get spell "missileSpeed") :range (term "MaxDistance")}
               :senna-e {:self-cast true :missile-speed 0}
               :tryndamere-q {:cost-resource :mana :self-cast true :missile-speed 0 :cast-time 0 :cost (literal 0)}
               :velkoz-r {:missile-speed 0 :channel true :interruptible-channel true :cast-lock (literal 2.75)} {}))
  (defn problems [node] (cond (and (dictionary? node) (node :op)) (expr/problems node)
                          (dictionary? node) (mapcat problems (values node))
                          (indexed? node) (mapcat problems node) []))
  (def missing (seq [[key record] :in [[:lucian-e lucian-p] [:ezreal-w ez-missile] [:nautilus-q naut-missile]]
                     :when (and (= handler key) (not record))] "Selected auxiliary spell source is missing."))
  (def invalid-missile (and (some |(= handler $) [:ezreal-w :gangplank-q :milio-q :nautilus-q :twitch-w :fizz-r])
                            (or (not (util/finite? (extra :missile-speed))) (<= (extra :missile-speed) 0))))
  (def unresolved [;(problems specs) ;(problems extra) ;missing ;(if invalid-missile ["Selected projectile speed is missing or invalid."] [])])
  (merge ability extra {:effects (map |(merge {:trigger :cast :condition :always :target-kinds [:champion :practice]
                                               :status (if (empty? unresolved) :estimated :unresolved) :evidence {:tooltip note :override true}} $) specs)
                        :unresolved [;unresolved note]}))

(defn sustain-charge [ability handler forms]
  (def spell (ability :record))
  (defn term [name] (expr/variable name spell))
  (defn pct [name] (product-of (literal 0.01) (term name)))
  (defn one [node] (sum-of (literal 1) node))
  (defn neg [node] (product-of (literal -1) node))
  (defn self-stat [key] {:op :stat :stat key :formula 0})
  (defn enemy-stat [key] {:op :target-stat :stat key})
  (defn dmg [amount &opt type] {:kind :damage :target :enemy :damage-type (or type :magic) :amount amount})
  (defn slow [strength duration] {:kind :control :target :enemy :control :slow :strength strength :duration duration})
  (defn stat [key amount duration &opt mode] {:kind :stat-buff :target :self :stat key :amount amount :duration duration :mode (or mode :add)})
  (defn speed [amount duration] (stat :move-speed (one amount) duration :multiply))
  (defn field [duration interval radius effects &opt extra] (merge {:kind :field :target :self :duration duration :interval interval :radius radius :effects effects} (or extra {})))
  (defn guard [name duration &opt fields] (merge {:kind :protection :target :self :buff name :duration duration} (or fields {})))
  (defn aux [suffix] (get (find |(string/has-suffix? (string/ascii-lower suffix) (string/ascii-lower ($ :path))) (or forms [])) :record))
  (def briar-p (when (some |(= handler $) [:briar-q :briar-e :briar-r]) (aux "/BriarP")))
  (def lee-two (when (= handler :leesin-w) (aux "/LeeSinWTwo")))
  (def all-cc [:stun :charm :fear :airborne :suppression :silence :root :slow :grounded :polymorph])
  (def kaisa-bonus-as {:op :stat :stat :attack-speed-bonus :formula 0})
  (def kaisa-time {:op :maximum :children [(term "Effect8Amount") (sum-of (term "Effect3Amount") (product-of (neg (sum-of (term "Effect3Amount") (neg (term "Effect8Amount")))) {:op :minimum :children [(literal 1) kaisa-bonus-as]}))]})
  (def kaisa-speed (product-of (term "Effect1Amount") {:op :minimum :children [(literal 2) (one kaisa-bonus-as)]}))
  (def note (case handler
              :braum-w "Stand Behind Me self-casts its source bonus-resistance shield stance. Ally dash and sharing are excluded."
              :briar-q "Head Rush pays the selected passive's current-health cost, lands on the sole opponent, deals source physical damage, stuns and shreds both resistances. Dash flight, bleed, passive healing amplification and Blood Frenzy target selection are excluded."
              :briar-e "Chilling Scream pays its selected current-health cost, charges fully for one second without control interruption, reduces damage and heals during charge, then damages, slows and pushes. Walls, early manual release, bleed, passive healing amplification and Frenzy cancellation are excluded."
              :briar-r "Certain Death pays the selected current-health cost, lands its source magic damage and grants resists, lifesteal and chase movement against the sole prey. The prey is not feared. Missile/leap flight, forced pursuit, bleed, passive healing amplification and Blood Frenzy attack-speed/cleave are excluded."
              :karthus-e "Defile maintains a radius-checked quarter-second damage aura, pays source continuous mana and restores source mana on a kill. Death Defied and manual toggle-off remain excluded."
              :singed-q "Poison Trail emits fixed-position model clouds every quarter second, paying continuous mana; clouds last their source duration and refresh phase-preserving poison. Cloud occupancy is sampled in one dimension; manual toggle and ultimate grievous wounds are excluded."
              :drmundo-r "Maximum Dosage grants temporary base health from missing health, source movement and dynamic maximum-health healing pulses. Rank-three amplification counts the sole nearby enemy. Takedown extensions and resurrection are excluded; expiry clamps current health to the restored maximum."
              :nasus-r "Fury of the Sands grants source maximum/current health, resists, attack range and a moving percentage-health aura; subsequent Q cooldowns are halved. Existing Q timers, size/collision and Siphoning Strike stacks remain excluded."
              :masteryi-w "Meditate channels source healing with live missing-health amplification, initial/ongoing damage reduction and continuous maximum-mana drain. Disabling control or unaffordable drain ends it; damage reduction lingers afterwards. Tower variants, passive stacks and manual attack cancel remain excluded."
              :nunu-r "Absolute Zero fully channels by default, with a source shield and ramping nearby slow. Interruption detonates at a linear charge fraction; surviving shield decays afterwards. Early manual release, brush visibility and measured charge/decay curves remain excluded."
              :ornn-w "Bellows Breath applies five source maximum-health/minimum-damage pulses, resists displacement during the breath, and marks the final hit Brittle. An attack or immobilization consumes Brittle for source damage and amplifies that control. Cone geometry, forward march and terrain interaction remain excluded."
              :pantheon-e "Base Aegis Assault faces the sole opponent, blocks its non-turret damage, applies six source-rate physical pulses and the final close-range shield slam. Movement is allowed during its action lock. Mortal Will, facing changes and manual early recast remain excluded."
              :sett-w "Haymaker stores unshielded post-mitigation damage as Grit, consumes it for a decaying shield at cast start and source center-line true damage at release. Stored instances decay separately after their source delay. The sole target is assumed centered; side damage and hitbox geometry remain excluded."
              :sett-r "The Show Stopper suppresses and carries the sole target, then deals source base/bonus-AD plus target bonus-health physical damage and slows. Travel is a fixed one-dimensional carry; terrain, other enemies and edge falloff remain excluded."
              :kaisa-e "Unevolved Supercharge locks attacks/casts during its bonus-AS-scaled charge, grants scaled movement while charging, then source attack speed. Ordinary hits refund its cooldown. Evolution invisibility and manual charge behavior remain excluded."
              :leesin-w "Safeguard self-casts its source shield with the champion cooldown refund. One automatic Iron Will recast pays the selected second-cast energy and grants source omnivamp. Ally/ward dashes, Flurry and non-champion vamp variants remain excluded."
              :kindred-e "Mounting Dread slows and marks the sole opponent. Three landed attacks with a refreshed source window consume it for source critical-stat-scaled base plus live missing-health damage. Marks default to their configured buff count; Wolf flight and non-champion caps remain excluded."
              :kindred-r "Lamb's Respite creates a fixed zone protecting both champions from death below ten percent maximum health and blocking healing at that floor. Exiting removes protection; occupants heal at expiry. Other units and exceptional death/health-cost interactions remain excluded."
              :mordekaiser-w "Indestructible stores source outgoing post-mitigation and incoming pre-mitigation champion damage, converts it to a decaying shield and can automatically recast to heal from the remaining shield. The shield uses a reviewed four-second lifetime and an explicit quadratic model decay; non-champions and measured decay curves remain excluded."
              :viego-r "Base Heartbreaker lands on the sole opponent, applies source critical-stat-scaled physical damage plus live missing-health damage, supported on-hits and a brief slow. Possessions, displacement of other enemies and flight geometry remain excluded."
              :vi-q "Vault Breaker charges to its source maximum, slows Vi during charge, then lands source damage and knockback control and applies Denting Blows. Interruption cancels it with source cooldown/mana refund. Early manual release, terrain, dash flight and passive shield remain excluded."
              :vladimir-w "Sanguine Pool pays source current health, prevents new enemy hits/controls, grants decaying movement and applies nearby source damage, slow and pre-mitigation healing. Already established tagged poison continues. Special ongoing effects, collision and casting during the pool remain excluded."
              :vladimir-e "Tides of Blood charges to maximum over the source ramp time, pays health in quarter-second installments and releases source damage/slow. Control or insufficient health releases the accumulated charge. Projectile collision, early manual release and blood-resource interactions remain excluded."
              :jinx-r "Super Mega Death Rocket uses its retained initial missile speed and ramps source direct damage over one modeled second of travel; live missing-health damage is not ramped. Acceleration, collision, launch-position drift and other targets remain excluded."
              :zoe-r "Portal Jump advances toward the opponent up to the reviewed range, resets the attack timer, locks movement for one second and returns to the original position. Attacks/casts remain possible during the visit. Vision, flight windows and exceptional displacement/return interactions remain excluded."))
  (assert note "Unknown sustain/charge handler.")
  (def specs (case handler
               :braum-w [(stat :armor (term "GrantedBraumArmor") (term "Duration")) (stat :mr (term "GrantedBraumMR") (term "Duration"))]
               :briar-q [{:kind :sequence :target :enemy :effects [(dmg (term "TotalDamage") :physical)
                                                                   {:kind :control :control :stun :duration (term "StunDuration")}
                                                                   {:kind :stat-buff :stat :armor :mode :multiply :amount (sum-of (literal 1) (neg (term "ShredPercent"))) :duration (term "ShredDuration")}
                                                                   {:kind :stat-buff :stat :mr :mode :multiply :amount (sum-of (literal 1) (neg (term "ShredPercent"))) :duration (term "ShredDuration")}]}]
               :briar-e [(merge (guard "Chilling Scream" (literal 1) {:damage-types [:physical :magic] :reduction (pct "DRPercent")}) {:trigger :cast-start})
                         (merge (field (literal 1) (literal 0.25) (literal 1e6) [{:kind :heal :target :self :amount (quotient (term "PercentMaxHPHeal") (literal 4))}] {:requires-channel true}) {:trigger :cast-start})
                         (merge (dmg (term "Damage")) {:range-at-impact (term "MaxMissileRange")}) (merge (slow (term "SlowPercent") (term "SlowDuration")) {:range-at-impact (term "MaxMissileRange")}) {:kind :displace :target :enemy :mode :away :distance (term "KnockbackDistance") :range-at-impact (term "MaxMissileRange")}]
               :briar-r [(dmg (term "Damage")) (stat :armor (term "TotalResists") (literal 180)) (stat :mr (term "TotalResists") (literal 180))
                         {:kind :damage-vamp :target :self :duration (literal 180) :radius (literal 1e6) :amount (term "LifestealPercent") :attacks-only true :buff "Certain Death"} (merge (speed (term "ExtraMoveSpeedPercent") (literal 180)) {:chase-only true})]
               :karthus-e [(field (literal 180) (literal 0.25) (ability :range) [(dmg (product-of (literal 0.25) (term "TotalDPS")))]
                                  {:toggle true :mana-per-second (expr/ranked (get spell "mana") -1 "Defile mana per second")})
                           {:kind :resource :target :self :trigger :passive :on [:kill] :amount (term "ManaRestoreOnKill")}]
               :singed-q [(field (literal 180) (quotient (literal 1) (term "TicksPerSecond")) (literal 180) []
                                 {:toggle true :trail true :cloud-duration (term "CloudDuration") :poison-duration (term "PoisonDuration") :dps (term "DamagePerSecond")
                                  :mana-per-second (expr/ranked (get spell "mana") -1 "Poison Trail mana per second")})]
               :drmundo-r [{:kind :dosage :target :self :amount (term "MissingHealthHeal") :duration (term "Duration") :regeneration (term "MaxHealthHoT") :nearby-bonus (term "BonusPerNearbyChampion")}
                           (speed (term "SpeedBoostAmount") (term "Duration"))]
               :nasus-r [{:kind :health-buff :target :self :amount (term "BonusHealth") :duration (term "Duration")}
                         (stat :armor (term "InitialResistGain") (term "Duration")) (stat :mr (term "InitialResistGain") (term "Duration"))
                         (stat :attack-range (term "AttackRangeIncrease") (term "Duration"))
                         {:kind :cooldown-scale :target :self :slots [:q] :amount (sum-of (literal 1) (neg (term "QCDR"))) :duration (term "Duration")}
                         (field (term "Duration") (term "TickRate") (term "MinAoERadius") [(dmg (product-of (term "TickRate") (term "DamageCalc") (enemy-stat :hp)))])]
               :masteryi-w [(merge (guard "Meditate" (sum-of (term "HealDuration") (term "DRLinger")) {:damage-types [:physical :magic] :reduction (term "DamageReduction") :initial-reduction (term "InitialDR") :initial-duration (term "InitialExtraDRDuration") :channel-bound true :linger (term "DRLinger")}) {:trigger :cast-start})
                            (merge (field (term "HealDuration") (term "TickFrequency") (literal 1e6)
                                          [{:kind :heal :target :self :amount (product-of (quotient (term "TickFrequency") (term "HealDuration")) (term "TotalHeal")
                                                                                          (one (product-of (term "MaxMissingHealthPercent") (self-stat :missing-health-percent))))}]
                                          {:requires-channel true :end-channel-on-empty true :mana-per-second (product-of (term "PercentManaCostPerSecond") (self-stat :mp))}) {:trigger :cast-start})
                            {:kind :reset :target :self :trigger :cast-start}]
               :nunu-r [(merge {:kind :shield :target :self :amount (term "TotalShieldAmount") :duration (term "MaxShieldDuration") :shield-key "Absolute Zero" :channel-shield true :decay-after-channel (term "ShieldDecayDuration")} {:trigger :cast-start})
                        (merge (field (term "ChannelDuration") (literal 0.25) (ability :range)
                                      [(slow (neg (term "SlowStartAmount")) (literal 0.25))]
                                      {:requires-channel true :immediate true :ramp-slow (neg (term "MaxSlowAmount")) :ramp-duration (term "ChannelDuration")}) {:trigger :cast-start})
                        {:kind :charge-damage :target :enemy :damage-type :magic :amount (term "MaximumDamage") :minimum-factor (literal 0) :range-at-impact (ability :range)}
                        {:kind :charged-slow :target :enemy :initial (neg (term "SlowStartAmount")) :strength (neg (term "MaxSlowAmount")) :duration (term "SlowDuration") :range-at-impact (ability :range)}]
               :ornn-w [(guard "Bellows Breath" (term "BreathDuration") {:controls [:airborne] :direct-displacement-immune true})
                        (field (term "BreathDuration") (quotient (term "BreathDuration") (term "NumberOfTicks")) (term "RectangleLength")
                               [(dmg {:op :maximum :children [(term "MinimumDamagePerTick") (product-of (term "PercentHPPerTick") (enemy-stat :hp))]})]
                               {:brittle-on-final {:duration (term "BrittleDuration") :amount (term "BrittlePercentMaxHPCalc") :amplification (literal 0.3)}})]
               :pantheon-e [(merge (guard "Aegis Assault" (term "ShieldDuration") {:damage-immune true :exclude-turrets true}) {:trigger :cast-start})
                            (merge (field (term "ShieldDuration") (quotient (literal 1) (term "AttacksPerSecond")) (term "SpearStrikesRadius")
                                          [(dmg (quotient (term "DamageCalc") (product-of (term "ShieldDuration") (term "AttacksPerSecond"))) :physical)]) {:trigger :cast-start})
                            (merge (dmg (term "ShieldDamageCalc") :physical) {:range-at-impact (term "ShieldSwipeRadius")})]
               :sett-w [{:kind :damage-store :target :self :trigger :combat-start :taken (term "DamageStored") :cap (term "StoredHealth") :delay (term "AdrenalineStorageWindow") :decay-fraction (term "ResourceDecayRate") :per-instance true}
                        {:kind :store-shield :target :self :trigger :cast-start :duration (term "ShieldMaxDuration") :amount (term "ShieldConversion") :shield-key "Haymaker" :decay-delay (term "ShieldDecayDelay") :lock (term "LockTime")}
                        {:kind :stored-strike :target :enemy :damage-type :true :amount (term "DamageCalc") :ratio (term "DamageConversion")}]
               :sett-r [{:kind :carry :target :enemy :amount (term "DamageCalc") :ratio (term "MaxHealthDamage") :duration (term "GrabDuration") :distance (term "DistancePastFirstHit") :slow (term "SlowAmount") :slow-duration (term "SlowDuration")}]
               :kaisa-e [(merge (speed kaisa-speed kaisa-time) {:trigger :cast-start :channel-bound true})
                         {:kind :buff :target :self :buff "Supercharge" :refresh true :stat-bonuses {:attack-speed-bonus (term "Effect5Amount")} :duration (term "Effect2Amount")}
                         {:kind :attack-profile :target :self :duration (term "Effect2Amount") :windup 0.0644 :missile-speed 2500}
                         {:kind :cooldown-refund :target :self :trigger :passive :on [:attack] :slots [:e] :allow-same-time true :amount (term "Effect4Amount")}]
               :leesin-w [{:kind :shield :target :self :amount (term "ShieldAmount") :duration (term "ShieldDuration") :cast-phase :initial}
                          {:kind :damage-vamp :target :self :duration (term "LifestealAndSpellVampTime") :amount (pct "LifestealAndSpellVamp") :radius (literal 1e6) :buff "Iron Will" :cast-phase :recast}]
               :kindred-e [(slow (pct "TotalSlow") (term "SlowDuration"))
                           {:kind :attack-mark :target :enemy :count (sum-of (term "StacksToProc") (literal -1)) :duration (term "TotalDuration") :amount (term "BaseBiteDamage") :ratio (term "PercentBiteDamage")}]
               :kindred-r [{:kind :shared-sanctuary :target :self :duration (term "BuffDuration") :radius (term "AoERadius") :amount (term "HealFlat")}]
               :mordekaiser-w [{:kind :damage-store :target :self :trigger :combat-start :taken (term "DamageTakenConversion") :taken-pre-mitigation true :dealt (term "DamageConversion")
                                :cap (term "MaxHealthCap") :minimum (term "BaseShield") :delay (term "TimeBeforeDecay") :decay (term "HealthDecay") :shield-key "Indestructible"}
                               {:kind :store-shield :target :self :duration (literal 4) :amount (literal 1) :shield-key "Indestructible" :decay-delay (literal 0) :quadratic true :cast-phase :initial}
                               {:kind :consume-shield :target :self :shield-key "Indestructible" :amount (term "HealingPercent") :cast-phase :recast}]
               :viego-r [(merge (dmg (sum-of (term "TotalDamage") (product-of (pct "TotalPercentHealth") (enemy-stat :missing-health))) :physical) {:applies-on-hit true})
                         (slow (term "SlowPercent") (term "SlowDuration"))]
               :vi-q [(merge (slow (pct "SelfSlow") (expr/ranked (get spell "mChannelDuration") 0 "Vault Breaker charge")) {:target :self :trigger :cast-start :channel-bound true})
                      (dmg (term "MaxDamageTooltip") :physical)
                      {:kind :control :target :enemy :control :airborne :duration (term "KnockbackDuration")}]
               :vladimir-w [(guard "Sanguine Pool" (literal 2) {:untargetable true})
                            (merge (speed (term "HasteBoost") (term "HasteDuration")) {:decay-steps (literal 16)})
                            (field (literal 2) (literal 0.5) (literal 350) [(merge (dmg (quotient (term "TotalDamage") (literal 4))) {:heal-owner-ratio (term "VampPercent")})
                                                                            (slow (neg (term "MoveSpeedMod")) (literal 0.5))])]
               :vladimir-e [{:kind :charge-damage :target :enemy :damage-type :magic :amount (term "MaxDamageTooltip") :minimum-amount (term "MinDamageTooltip") :range-at-impact (ability :range)}
                            (merge (slow (pct "SlowPercent") (literal 0.5)) {:requires-full-charge true})]
               :jinx-r [{:kind :travel-damage :target :enemy :damage-type :physical :amount (term "DamageFloor") :maximum (term "DamageMax") :missing-ratio (pct "PercentDamage")}]
               :zoe-r [{:kind :portal :target :self :distance (literal 575) :duration (literal 1)} {:kind :reset :target :self}]))
  (def extra (case handler
               :braum-w {:self-cast true :cast-time 0 :missile-speed 0}
               :briar-q {:missile-speed 0 :blink-to-target true :disabled-controls [:grounded :root]}
               :briar-e {:uninterruptible true :self-cast true :missile-speed 0 :range (term "MaxMissileRange") :cast-time 1 :channel true :interruptible-channel true :channel-interrupts [] :finish-channel-on-release true}
               :briar-r {:missile-speed 0 :blink-to-target true}
               :karthus-e {:self-cast true :cast-time 0 :missile-speed 0 :cost-resource :resource :cost (literal 0) :minimum-resource (product-of (literal 0.25) (expr/ranked (get spell "mana") -1 "Defile minimum mana"))}
               :singed-q {:self-cast true :cast-time 0 :missile-speed 0 :cost-resource :resource :cost (literal 0) :cooldown (term "ToggleCooldown") :minimum-resource (product-of (literal 0.25) (expr/ranked (get spell "mana") -1 "Poison Trail minimum mana"))}
               :drmundo-r {:self-cast true :cast-time 0 :missile-speed 0}
               :nasus-r {:self-cast true :cast-time 0 :missile-speed 0}
               :masteryi-w {:self-cast true :cast-time 0 :cast-lock (term "HealDuration") :channel true :interruptible-channel true :cost-resource :resource :cost (term "BaseManaCost") :missile-speed 0}
               :nunu-r {:self-cast true :cast-time 3 :channel true :interruptible-channel true :finish-channel-on-release true :early-detonation true :missile-speed 0}
               :ornn-w {:self-cast true :cast-time 0 :cast-lock (term "BreathDuration") :missile-speed 0}
               :pantheon-e {:can-move true :self-cast true :cast-time 1.5 :missile-speed 0}
               :sett-w {:range (literal 720) :missile-speed 0}
               :sett-r {:missile-speed 0 :cast-lock (sum-of (term "GrabDuration") (literal 0.25))}
               :kaisa-e {:uninterruptible true :self-cast true :cast-time-expression kaisa-time :missile-speed 0 :channel true :interruptible-channel true :channel-can-move true :channel-interrupts [] :finish-channel-on-release true}
               :leesin-w {:self-cast true :cast-time 0 :missile-speed 0 :self-cooldown-factor (sum-of (literal 1) (neg (term "W1CooldownRecovered")))
                          :recast {:count (literal 1) :window (term "W1ReactivateTime") :delay (literal 0.5) :cost (expr/ranked (get lee-two "mana") -1 "Iron Will energy")}}
               :kindred-e {:missile-speed 0}
               :kindred-r {:self-cast true :missile-speed 0}
               :mordekaiser-w {:self-cast true :cast-time 0 :missile-speed 0 :recast {:count (literal 1) :window (literal 4) :delay (literal 0.5) :cost (literal 0)}}
               :viego-r {:missile-speed 0 :blink-to-target true :disabled-controls [:grounded :root]}
               :vi-q {:cast-time-expression (expr/ranked (get spell "mChannelDuration") 0 "Vault Breaker charge") :channel true :interruptible-channel true :cancel-cooldown (term "CanceledRefundTime") :cancel-refund (term "ManaRefundPercent")
                      :finish-channel-on-release true :missile-speed 0 :range (sum-of (term "MinDashRange") (term "ExtraDashRangeAtMaxCharge")) :blink-to-target true :disabled-controls [:grounded :root]}
               :vladimir-w {:can-move true :self-cast true :cast-time 0 :cast-lock 2 :missile-speed 0 :cost-resource :health :cost (product-of (term "HealthCost") (self-stat :health))}
               :vladimir-e {:cast-time-expression (term "TimetoRampMaxDamage") :channel true :interruptible-channel true :finish-channel-on-release true :early-detonation true
                            :health-drain (quotient (term "ChargeHealthTooltip") (term "TimetoRampMaxDamage")) :cost-resource :health :cost (literal 0) :missile-speed 0}
               :jinx-r {:missile-speed (get spell "missileSpeed")}
               :zoe-r {:self-cast true :missile-speed 0 :disabled-controls [:grounded :root]} {}))
  (def health-cost (when (some |(= handler $) [:briar-q :briar-e :briar-r])
                     {:cost-resource :health :cost (product-of (expr/variable "CurrentHealthPercentCost" briar-p) (self-stat :health))}))
  (defn problems [node] (cond (and (dictionary? node) (node :op)) (expr/problems node) (dictionary? node) (mapcat problems (values node)) (indexed? node) (mapcat problems node) []))
  (def missing [;(if (and (some |(= handler $) [:briar-q :briar-e :briar-r]) (not briar-p)) ["Selected Crimson Curse cost source missing."] [])
                ;(if (and (= handler :leesin-w) (not lee-two)) ["Selected Iron Will cost source missing."] [])])
  (def unresolved [;(problems specs) ;(problems extra) ;(problems health-cost) ;missing])
  (merge ability extra (or health-cost {}) {:effects (map |(merge {:trigger :cast :condition :always :target-kinds [:champion :practice]
                                                                   :status (if (empty? unresolved) :estimated :unresolved) :evidence {:tooltip note :override true}} $) specs)
                                            :unresolved [;unresolved note]}))

(defn review [ability handler &opt forms]
  (case handler
    :monkeyking-w (remaining/review ability handler forms)
    :fiora-r (remaining/review ability handler forms)
    :locke-w (remaining/review ability handler forms)
    :naafiri-q (remaining/review ability handler forms)
    :mel-r (remaining/review ability handler forms)
    :tahmkench-e (remaining/review ability handler forms)
    :tahmkench-r (remaining/review ability handler forms)
    :varus-w (remaining/review ability handler forms)
    :zeri-e (remaining/review ability handler forms)
    :zeri-q (remaining/review ability handler forms)
    :warwick-w (remaining/review ability handler forms)
    :quinn-w (remaining/review ability handler forms)
    :yasuo-w (remaining/review ability handler forms)
    :xayah-e (remaining/review ability handler forms)
    :zed-w (remaining/review ability handler forms)
    :ryze-r (remaining/review ability handler forms)
    :taliyah-r (remaining/review ability handler forms)
    :reksai-w (remaining/review ability handler forms)
    :renata-w (remaining/review ability handler forms)
    :renata-r (remaining/review ability handler forms)
    :ally-only (remaining/review ability handler forms)
    :vision-only (remaining/review ability handler forms)
    :terrain-only (remaining/review ability handler forms)
    :informational-slot (remaining/review ability handler forms)
    :anivia-w (remaining/review ability handler forms)
    :yunara-r (remaining/review ability handler forms)
    :akshan-w (remaining/review ability handler forms)
    :twitch-q (remaining/review ability handler forms)
    :jinx-q (remaining/review ability handler forms)
    :urgot-w (remaining/review ability handler forms)
    :aurelionsol-w (remaining/review ability handler forms)
    :ksante-q (remaining/review ability handler forms)
    :hwei-q (remaining/review ability handler forms)
    :rell-w (remaining/review ability handler forms)
    :kayn-r (remaining/review ability handler forms)
    :reksai-r (remaining/review ability handler forms)
    :yone-e (remaining/review ability handler forms)
    :twistedfate-r (remaining/review ability handler forms)
    :graves-e (remaining/review ability handler forms)
    :ashe-q (remaining/review ability handler forms)
    :kalista-e (remaining/review ability handler forms)
    :yunara-q (remaining/review ability handler forms)
    :viego-q (remaining/review ability handler forms)
    :smolder-q (remaining/review ability handler forms)
    :gnar-q (remaining/review ability handler forms)
    :gnar-w (remaining/review ability handler forms)
    :gnar-e (remaining/review ability handler forms)
    :jayce-q (remaining/review ability handler forms)
    :jayce-w (remaining/review ability handler forms)
    :jayce-e (remaining/review ability handler forms)
    :akshan-r (remaining/review ability handler forms)
    :aurelionsol-q (remaining/review ability handler forms)
    :briar-w (remaining/review ability handler forms)
    :corki-w (remaining/review ability handler forms)
    :rammus-w (remaining/review ability handler forms)
    :nilah-r (remaining/review ability handler forms)
    :mordekaiser-r (remaining/review ability handler forms)
    :bard-r (remaining/review ability handler forms)
    :teemo-r (remaining/review ability handler forms)
    :akali-w (remaining/review ability handler forms)
    :aurora-w (remaining/review ability handler forms)
    :ambessa-q (remaining/review ability handler forms)
    :fiora-q (remaining/review ability handler forms)
    :elise-q (remaining/review ability handler forms)
    :elise-w (remaining/review ability handler forms)
    :illaoi-q (remaining/review ability handler forms)
    :shyvana-e (remaining/review ability handler forms)
    :zaahen-r (remaining/review ability handler forms)
    :reksai-e (remaining/review ability handler forms)
    :kayn-e (remaining/review ability handler forms)
    :khazix-r (remaining/review ability handler forms)
    :hwei-r (remaining/review ability handler forms)
    :sion-q (remaining/review ability handler forms)
    :ksante-w (remaining/review ability handler forms)
    :yunara-e (remaining/review ability handler forms)
    :yunara-w (remaining/review ability handler forms)
    :vex-r (remaining/review ability handler forms)
    :shaco-q (remaining/review ability handler forms)
    :zoe-q (remaining/review ability handler forms)
    :braum-w (sustain-charge ability handler forms)
    :briar-q (sustain-charge ability handler forms)
    :briar-e (sustain-charge ability handler forms)
    :briar-r (sustain-charge ability handler forms)
    :karthus-e (sustain-charge ability handler forms)
    :singed-q (sustain-charge ability handler forms)
    :drmundo-r (sustain-charge ability handler forms)
    :nasus-r (sustain-charge ability handler forms)
    :masteryi-w (sustain-charge ability handler forms)
    :nunu-r (sustain-charge ability handler forms)
    :ornn-w (sustain-charge ability handler forms)
    :pantheon-e (sustain-charge ability handler forms)
    :sett-w (sustain-charge ability handler forms)
    :sett-r (sustain-charge ability handler forms)
    :kaisa-e (sustain-charge ability handler forms)
    :leesin-w (sustain-charge ability handler forms)
    :kindred-e (sustain-charge ability handler forms)
    :kindred-r (sustain-charge ability handler forms)
    :mordekaiser-w (sustain-charge ability handler forms)
    :viego-r (sustain-charge ability handler forms)
    :vi-q (sustain-charge ability handler forms)
    :vladimir-w (sustain-charge ability handler forms)
    :vladimir-e (sustain-charge ability handler forms)
    :jinx-r (sustain-charge ability handler forms)
    :zoe-r (sustain-charge ability handler forms)

    :aatrox-e (areas-impact ability handler forms)
    :alistar-e (areas-impact ability handler forms)
    :amumu-w (areas-impact ability handler forms)
    :anivia-r (areas-impact ability handler forms)
    :braum-e (areas-impact ability handler forms)
    :ezreal-w (areas-impact ability handler forms)
    :gangplank-q (areas-impact ability handler forms)
    :ivern-w (areas-impact ability handler forms)
    :kled-w (areas-impact ability handler forms)
    :lucian-e (areas-impact ability handler forms)
    :malzahar-r (areas-impact ability handler forms)
    :milio-q (areas-impact ability handler forms)
    :nautilus-q (areas-impact ability handler forms)
    :ornn-e (areas-impact ability handler forms)
    :rumble-q (areas-impact ability handler forms)
    :rumble-w (areas-impact ability handler forms)
    :taliyah-w (areas-impact ability handler forms)
    :thresh-e (areas-impact ability handler forms)
    :trundle-e (areas-impact ability handler forms)
    :twitch-w (areas-impact ability handler forms)
    :warwick-r (areas-impact ability handler forms)
    :fizz-r (areas-impact ability handler forms)
    :senna-e (areas-impact ability handler forms)
    :tryndamere-q (areas-impact ability handler forms)
    :velkoz-r (areas-impact ability handler forms)

    :chogath-e (attack-defense ability handler forms)
    :kayle-e (attack-defense ability handler forms)
    :fizz-w (attack-defense ability handler forms)
    :sett-q (attack-defense ability handler forms)
    :volibear-q (attack-defense ability handler forms)
    :xayah-w (attack-defense ability handler forms)
    :sona-e (attack-defense ability handler forms)
    :teemo-w (attack-defense ability handler forms)
    :miss-fortune-w (attack-defense ability handler forms)
    :nasus-w (attack-defense ability handler forms)
    :shen-w (attack-defense ability handler forms)
    :tryndamere-r (attack-defense ability handler forms)
    :olaf-r (attack-defense ability handler forms)
    :malphite-w (attack-defense ability handler forms)
    :taric-w (attack-defense ability handler forms)
    :evelynn-e (attack-defense ability handler forms)
    :kogmaw-r (attack-defense ability handler forms)
    :caitlyn-r (attack-defense ability handler forms)
    :pyke-w (attack-defense ability handler forms)
    :pyke-r (attack-defense ability handler forms)
    :gwen-w (attack-defense ability handler forms)
    :janna-w (attack-defense ability handler forms)
    :diana-r (attack-defense ability handler forms)
    :milio-w (attack-defense ability handler forms)
    :hecarim-w (attack-defense ability handler forms)

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
