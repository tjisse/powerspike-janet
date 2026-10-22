(import ./expressions :as expr)

# Handwritten combat semantics, using numerical values from the selected raw
# spell record. This is not another parser or a rewrite of saved packages.
(defn sum-of [& children] {:op :sum :children children})
(defn product-of [& children] {:op :multiply :children children})
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
