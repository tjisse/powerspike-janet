(import ./expressions :as expr)

# Handwritten combat semantics, using numerical values from the selected raw
# spell record. This is not another parser or a rewrite of saved packages.
(defn sum-of [& children] {:op :sum :children children})
(defn product-of [& children] {:op :multiply :children children})
(defn quotient [a b] {:op :divide :children [a b]})
(defn literal [value] {:op :constant :value value})
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
                               :evidence {:override true :tooltip note}}))
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
                  :unresolved [;notes ;problems note]}))

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
  (merge ability {:effects effects :unresolved [;notes note] :missile-speed 0}
         (case handler
           :fiddlesticks-w {:interruptible-channel true :cast-lock (fixed (sum-of (literal (ability :cast-time)) (term "DrainDuration")))}
           :fiddlesticks-r {:interruptible-channel true :channel true :blink-to-target true :finish-channel-on-release true
                            :disabled-controls [:grounded] :channel-interrupts [:stun :charm :fear :airborne :suppression :silence :grounded]
                            :cast-time (fixed (term "ChannelTime"))}
           {})))

(defn review [ability handler]
  (case handler
    :garen-e (garen ability handler)
    :garen-r (garen ability handler)
    :fiddlesticks-q (fiddlesticks ability handler)
    :fiddlesticks-w (fiddlesticks ability handler)
    :fiddlesticks-e (fiddlesticks ability handler)
    :fiddlesticks-r (fiddlesticks ability handler)
    (seraphine ability handler)))
