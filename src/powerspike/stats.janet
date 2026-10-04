(import ./validation :as v)

(def flat-stats [:hp :mp :ad :ap :armor :mr :hp-regen :mp-regen :move-speed])
(def percent-stats [:armor-pen-percent :magic-pen-percent])

(defn growth-factor [level]
  (v/integer-between level 1 18 "level")
  (def n (- level 1))
  (* n (+ 0.7025 (* 0.0175 n))))

(defn base-stats [champion level]
  (def factor (growth-factor level))
  (def result @{})
  (each key flat-stats
    (put result key (+ (get (champion :base) key 0)
                       (* factor (get (champion :growth) key 0)))))
  result)

(defn apply-rank-penetration [champion totals ranks]
  # Declared permanent penetration passives only; rank zero is explicitly zero.
  # This hook does not infer arbitrary spell/buff effects from game records.
  (def result (merge @{} totals))
  (eachp [slot bonuses] (get champion :rank-penetration {})
    (eachp [key values] bonuses
      (assert (some (fn [x] (= key x)) percent-stats) "unsupported rank penetration stat")
      (def rank (get ranks slot 0))
      (v/integer-between rank 0 (- (length values) 1) "penetration passive rank")
      (def value (values rank))
      (v/fraction value "rank penetration")
      (put result key (- 1 (* (- 1 (get result key 0)) (- 1 value))))))
  result)

(defn total-stats [champion level items &opt external-modifiers]
  (def result (base-stats champion level))
  (def base-ad (result :ad))
  (var bonus-as (* (growth-factor level) (champion :attack-speed-growth)))
  (var crit 0)
  (var crit-damage (champion :crit-damage))
  (var ap-multiplier 1)
  (var move-bonus 0)
  (put result :ability-haste 0)
  (put result :armor-pen-flat 0)
  (put result :magic-pen-flat 0)
  (each key percent-stats (put result key 0))
  (def modifiers @[])
  (each item items
    (assert (item :supported) (string "unsupported item: " (item :id)))
    (array/push modifiers (item :stats)))
  (each modifier (or external-modifiers []) (array/push modifiers modifier))
  (each modifier modifiers
    (eachp [key value] modifier
      (v/finite-number value (string "stat modifier " key))
      (cond
        (= key :attack-speed-bonus) (+= bonus-as value)
        (= key :crit-chance) (+= crit value)
        (= key :crit-damage-bonus) (+= crit-damage value)
        (= key :ap-multiplier) (do (assert (>= value 1) "AP multiplier must be >= 1")
                                 (*= ap-multiplier value))
        (= key :move-speed-percent) (+= move-bonus value)
        (some (fn [x] (= key x)) percent-stats)
        (do (v/fraction value (string key))
          (put result key (- 1 (* (- 1 (result key)) (- 1 value)))))
        (some (fn [x] (= key x)) [;flat-stats :ability-haste :armor-pen-flat :magic-pen-flat])
        (put result key (+ (get result key 0) value))
        (error (string "unhandled item stat: " key)))))
  (put result :base-ad base-ad)
  (put result :bonus-ad (- (result :ad) base-ad))
  (put result :ap (* (result :ap) ap-multiplier))
  (put result :crit-chance (max 0 (min 1 crit)))
  (put result :crit-damage crit-damage)
  (v/nonnegative (result :ability-haste) "ability haste")
  (v/nonnegative (result :armor-pen-flat) "flat armor penetration")
  (v/nonnegative (result :magic-pen-flat) "flat magic penetration")
  (def raw-as (+ (champion :attack-speed-base)
                 (* (champion :attack-speed-ratio) bonus-as)))
  (put result :attack-speed (max 0 (min raw-as (champion :attack-speed-cap))))
  (put result :attack-speed-uncapped raw-as)
  (def raw-ms (* (result :move-speed) (+ 1 move-bonus)))
  (put result :move-speed
       (cond (> raw-ms 490) (+ 475 (* 0.5 (- raw-ms 490)))
         (> raw-ms 415) (+ 415 (* 0.8 (- raw-ms 415)))
         (< raw-ms 220) (+ 110 (* raw-ms 0.5))
         raw-ms))
  result)
