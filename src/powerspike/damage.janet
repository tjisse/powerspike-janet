(import ./validation :as v)

(defn resistance-multiplier [resistance]
  (v/finite-number resistance "resistance")
  (if (>= resistance 0)
    (/ 100 (+ 100 resistance))
    (- 2 (/ 100 (- 100 resistance)))))

(defn effective-resistance [resistance modifiers]
  (v/finite-number resistance "resistance")
  (def flat-reduction (v/nonnegative (get modifiers :reduction-flat 0) "flat reduction"))
  (def percent-reduction (v/fraction (get modifiers :reduction-percent 0) "percent reduction"))
  (def percent-pen (v/fraction (get modifiers :penetration-percent 0) "percent penetration"))
  (def flat-pen (v/nonnegative (get modifiers :penetration-flat 0) "flat penetration"))
  (def reduced (- resistance flat-reduction))
  # Reductions can create negative resistance. Penetration cannot.
  (if (<= reduced 0) reduced
    (max 0 (- (* reduced (- 1 percent-reduction) (- 1 percent-pen)) flat-pen))))

(defn resolve-hit [raw type stats target]
  (v/nonnegative raw "raw damage")
  (assert (some (fn [x] (= x type)) [:physical :magic :true]) "explicit damage type required")
  (if (= type :true)
    {:raw raw :type type :effective-resistance nil :damage raw}
    (do
      (def armor? (= type :physical))
      (def resistance-key (if armor? :armor :mr))
      (assert (has-key? target resistance-key) (string "target requires " resistance-key))
      (def effective
        (effective-resistance (target resistance-key)
                              {:reduction-flat (get target (if armor? :armor-reduction-flat :mr-reduction-flat) 0)
                               :reduction-percent (get target (if armor? :armor-reduction-percent :mr-reduction-percent) 0)
                               :penetration-percent (get stats (if armor? :armor-pen-percent :magic-pen-percent) 0)
                               :penetration-flat (get stats (if armor? :armor-pen-flat :magic-pen-flat) 0)}))
      {:raw raw :type type :effective-resistance effective
       :damage (* raw (resistance-multiplier effective))})))

(defn expected-attack-damage [stats]
  (v/nonnegative (stats :ad) "attack damage")
  (v/fraction (get stats :crit-chance 0) "critical chance")
  (v/nonnegative (get stats :crit-damage 2) "critical multiplier")
  (* (stats :ad) (+ 1 (* (get stats :crit-chance 0) (- (get stats :crit-damage 2) 1)))))

(defn cooldown [base ability-haste]
  (v/nonnegative base "cooldown")
  (v/nonnegative ability-haste "ability haste")
  (* base (/ 100 (+ 100 ability-haste))))

(defn spell-damage [spell rank stats]
  (v/integer-between rank 1 (length (spell :base-damage)) "spell rank")
  (assert (some (fn [x] (= x (spell :damage-type))) [:physical :magic :true])
          "spell requires an explicit damage type")
  (var raw ((spell :base-damage) (- rank 1)))
  (v/nonnegative raw "spell base damage")
  (eachp [key ratio] (get spell :scalings {})
    (v/finite-number ratio "spell ratio")
    (assert (has-key? stats key) (string "missing scaling stat: " key))
    (+= raw (* ratio (stats key))))
  (v/nonnegative raw "resolved spell damage")
  raw)
