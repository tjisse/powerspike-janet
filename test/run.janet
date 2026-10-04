(import ../src/powerspike/stats :as stats)
(import ../src/powerspike/damage :as damage)
(import ../src/powerspike/builds :as builds)
(import ../src/powerspike/skills :as skills)
(import ../src/powerspike/combat :as combat)
(import ../src/powerspike/optimization :as opt)
(import ../src/powerspike/core :as core)
(import ../data/16.19.1/snapshot :as snapshot)

(import ../src/powerspike/rotation :as rotation)
(import ../src/powerspike/observations :as observations)
(import ../data/16.19.1/annie :as annie-model)

(var passed 0)
(var failed 0)
(defn near [actual expected]
  (assert (< (math/abs (- actual expected)) 1e-7)
          (string "expected " expected ", got " actual)))
(defn rejects [f]
  (assert (try (do (f) false) ([err] true)) "expected rejection"))
(defn test [name f]
  (try
    (do (f) (++ passed) (print "ok " name))
    ([err] (++ failed) (eprint "FAIL " name ": " err))))

(def garen (snapshot/champions "Garen"))
(def annie (snapshot/champions "Annie"))
(def ie (snapshot/items "3031"))
(def dagger (snapshot/items "1042"))
(def sword (snapshot/items "1036"))
(def boots (snapshot/items "3006"))
(def target {:armor 80 :mr 80})
(def scenario {:duration 5 :windup-fraction 0.3})
(def generic {:ad 100 :ap 200 :bonus-ad 40 :attack-speed 1 :mp 100
              :ability-haste 0 :crit-chance 0 :crit-damage 2})
# Synthetic spell for engine tests, not a claim about a champion ability.
(def spell {:id :test-q :damage-type :magic :base-damage [100]
            :scalings {:ap 0.5} :cost [50] :cooldown [2]
            :cast-time 0.5 :cooldown-start :start})

(test "growth starts at zero and reaches 17 at level 18"
      (fn [] (near (stats/growth-factor 1) 0) (near (stats/growth-factor 18) 17)))
(test "first level-up gives 72 percent of growth"
      (fn [] (near (stats/growth-factor 2) 0.72)))
(test "fractional and out-of-range levels are rejected"
      (fn [] (each level [0 19 2.5 math/inf]
               (rejects (fn [] (stats/growth-factor level))))))
(test "Garen AD uses the matching game-file growth rather than DDragon zero"
      (fn [] (near ((stats/base-stats garen 18) :ad) 145.5)))
(test "Annie's attack speed ratio differs from base attack speed"
      (fn [] (near ((stats/total-stats annie 1 [boots]) :attack-speed) 0.7975)))
(test "attack speed is capped"
      (fn [] (near ((stats/total-stats garen 18 (map (fn [_] dagger) (range 100))) :attack-speed) 2.5)))
(test "stat aggregation does not mutate champion data"
      (fn [] (stats/total-stats garen 18 [ie]) (near ((garen :base) :ad) 69)))
(test "critical chance uses fractions consistently"
      (fn [] (near ((stats/total-stats garen 1 [(snapshot/items "1018")]) :crit-chance) 0.15)))
(test "base critical damage comes from this patch's character record"
      (fn [] (near ((stats/total-stats garen 1 []) :crit-damage) 2)))
(test "Infinity Edge adds 30 percentage points to critical multiplier"
      (fn [] (near ((stats/total-stats garen 1 [ie]) :crit-damage) 2.3)))
(test "expected critical attack damage"
      (fn [] (near (damage/expected-attack-damage {:ad 100 :crit-chance 0.25 :crit-damage 2.3}) 132.5)))
(test "Deathcap applies its patch-specific AP multiplier after flat AP"
      (fn [] (near ((stats/total-stats annie 1 [(snapshot/items "3089") (snapshot/items "1052")]) :ap) 195)))
(test "percentage penetration sources compose multiplicatively"
      (fn [] (def fake {:id "test" :supported true :stats {:magic-pen-percent 0.4}})
        (near ((stats/total-stats annie 1 [fake fake]) :magic-pen-percent) 0.64)))
(test "movement speed bonuses add before soft caps"
      (fn [] (near ((stats/total-stats garen 1 [(snapshot/items "3086") (snapshot/items "3086")]) :move-speed) 367.2)))
(test "unrecognized item stats are rejected"
      (fn [] (rejects (fn [] (stats/total-stats annie 1 [{:id "test" :supported true :stats {:guess 5}}])))))
(test "80 resistance mitigates 180 raw damage to 100"
      (fn [] (near ((damage/resolve-hit 180 :physical {} target) :damage) 100)))
(test "physical and magical hits use different target resistance"
      (fn [] (near ((damage/resolve-hit 200 :physical {} {:armor 100 :mr 0}) :damage) 100)
        (near ((damage/resolve-hit 200 :magic {} {:armor 100 :mr 0}) :damage) 200)))
(test "true damage bypasses resistance"
      (fn [] (near ((damage/resolve-hit 200 :true {} {:armor 1000 :mr 1000}) :damage) 200)))
(test "negative resistance amplifies damage"
      (fn [] (near (* 100 (damage/resistance-multiplier -50)) (/ 400 3))))
(test "penetration cannot create negative resistance"
      (fn [] (near (damage/effective-resistance 20 {:penetration-flat 80}) 0)))
(test "penetration does not erase pre-existing negative resistance"
      (fn [] (near (damage/effective-resistance -50 {:penetration-flat 80 :penetration-percent 0.4}) -50)))
(test "flat reduction precedes percentage reduction and penetration"
      (fn [] (near (damage/effective-resistance 100 {:reduction-flat 20 :reduction-percent 0.3
                                                     :penetration-percent 0.4 :penetration-flat 18}) 15.6)))
(test "flat reduction can create negative resistance"
      (fn [] (near (damage/effective-resistance 20 {:reduction-flat 50 :penetration-flat 10}) -30)))
(test "damage types and target fields cannot be guessed"
      (fn [] (rejects (fn [] (damage/resolve-hit 100 :unknown {} target)))
        (rejects (fn [] (damage/resolve-hit 100 :magic {} {:armor 0})))))
(test "non-finite damage and invalid penetration are rejected"
      (fn [] (rejects (fn [] (damage/resolve-hit math/inf :true {} {})))
        (rejects (fn [] (damage/effective-resistance 80 {:penetration-percent 40})))))
(test "ability haste halves a ten-second cooldown at 100 haste"
      (fn [] (near (damage/cooldown 10 100) 5)))
(test "spell scaling stat does not dictate its damage type"
      (fn [] (near (damage/spell-damage {:damage-type :physical :base-damage [100] :scalings {:ap 0.5}} 1 generic) 200)))
(test "unknown spell scaling stats fail rather than defaulting"
      (fn [] (rejects (fn [] (damage/spell-damage {:damage-type :magic :base-damage [100] :scalings {:guess 1}} 1 generic)))))
(test "early skill ranks respect level gates"
      (fn [] (rejects (fn [] (skills/validate-ranks {:q 2} 2)))
        (rejects (fn [] (skills/validate-ranks {:r 1} 5)))))
(test "skill points cannot exceed champion level"
      (fn [] (rejects (fn [] (skills/validate-ranks {:q 1 :w 1} 1)))))
(test "skill order is checked at each historical level"
      (fn [] (rejects (fn [] (skills/ranks-from-order [:q :q :w] 3)))))
(test "a legal 18-level skill order produces five-five-five-three"
      (fn [] (assert (= {:q 5 :w 5 :e 5 :r 3}
                        (table/to-struct (skills/ranks-from-order
                                           [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e] 18))))))
(test "boots are optional"
      (fn [] (assert ((builds/inspect-build [sword] {:slots 1}) :legal))))
(test "multiple boots and unique legendary duplicates are rejected"
      (fn [] (assert (not ((builds/inspect-build [boots (snapshot/items "3020")] {}) :legal)))
        (assert (not ((builds/inspect-build [ie ie] {}) :legal)))))
(test "components can be repeated"
      (fn [] (assert ((builds/inspect-build [sword sword] {}) :legal))))
(test "budget and slot count are respected"
      (fn [] (assert (not ((builds/inspect-build [ie] {:budget 3000}) :legal)))
        (assert (not ((builds/inspect-build [sword dagger] {:slots 1}) :legal)))))
(test "unsupported and map-incompatible items are rejected"
      (fn [] (assert (not ((builds/inspect-build [{:id "x" :gold 0 :maps [12] :supported false :purchasable true}] {:map 11}) :legal)))))
(test "no-purchase builds work with zero slots"
      (fn [] (assert ((builds/inspect-build [] {:slots 0 :budget 0}) :legal))))
(test "five attacks land in five seconds at one attack per second"
      (fn [] (def result (combat/auto-attacks generic {:armor 0 :mr 0} {:duration 5 :windup-fraction 0.3}))
        (near (result :damage) 500) (assert (= 5 (length (result :events))))
        (near (((result :events) 0) :at) 0.3)))
(test "a hit at the exact window endpoint is excluded"
      (fn [] (near ((combat/auto-attacks generic {:armor 0 :mr 0} {:duration 0.3 :windup-fraction 0.3}) :damage) 0)))
(test "travel time can move a hit outside the window"
      (fn [] (near ((combat/auto-attacks generic {:armor 0 :mr 0} {:duration 1 :windup-fraction 0.3 :travel-time 0.8}) :damage) 0)))
(test "spells land after their cast time and consume resource"
      (fn [] (def result (combat/simulate generic {:armor 0 :mr 100}
                                          {:duration 2 :actions [{:at 0 :kind :spell :spell spell :rank 1}]}))
        (near (result :damage) 100) (near (result :resource-left) 50)
        (near (((result :events) 0) :at) 0.5)))
(test "a spell cannot overlap an attack windup"
      (fn [] (rejects (fn [] (combat/simulate generic target
                                              {:duration 3 :actions [{:at 0 :kind :attack :windup 0.3}
                                                                     {:at 0.1 :kind :spell :spell spell :rank 1}]})))))
(test "an attack cannot overlap a spell cast"
      (fn [] (rejects (fn [] (combat/simulate generic target
                                              {:duration 3 :actions [{:at 0 :kind :spell :spell spell :rank 1}
                                                                     {:at 0.25 :kind :attack :windup 0.3}]})))))
(test "repeat spells obey their cooldown"
      (fn [] (rejects (fn [] (combat/simulate generic target
                                              {:duration 3 :actions [{:at 0 :kind :spell :spell spell :rank 1}
                                                                     {:at 1 :kind :spell :spell spell :rank 1}]})))))
(test "insufficient resource rejects a rotation"
      (fn [] (rejects (fn [] (combat/simulate generic target
                                              {:duration 5 :resource 50 :actions [{:at 0 :kind :spell :spell spell :rank 1}
                                                                                  {:at 2 :kind :spell :spell spell :rank 1}]})))))
(test "a mixed rotation has one shared action timeline"
      (fn [] (def result (combat/simulate generic {:armor 0 :mr 0}
                                          {:duration 3 :actions [{:at 0 :kind :spell :spell spell :rank 1}
                                                                 {:at 0.5 :kind :attack :windup 0.3}
                                                                 {:at 1.5 :kind :attack :windup 0.3}
                                                                 {:at 2 :kind :spell :spell spell :rank 1}]}))
        (near (result :damage) 600) (near (result :resource-left) 0)))
(test "attacks cannot bypass their timer"
      (fn [] (rejects (fn [] (combat/simulate generic target
                                              {:duration 3 :actions [{:at 0 :kind :attack :windup 0.3}
                                                                     {:at 0.5 :kind :attack :windup 0.3}]})))))
(test "exact search finds a known bounded optimum including repeats"
      (fn [] (def result (opt/exact-search [sword dagger] {:slots 2 :budget 700}
                                           (fn [items] (reduce + 0 (map (fn [item] (get (item :stats) :ad 0)) items)))))
        (assert (result :complete)) (near ((result :best) :score) 20)
        (assert (= ["1036" "1036"] (tuple ;(map (fn [item] (item :id)) ((result :best) :items)))))))
(test "exact search can choose no purchase"
      (fn [] (def result (opt/exact-search [sword] {:budget 0} (fn [items] (length items))))
        (assert (empty? ((result :best) :items))) (assert (result :complete))))
(test "evaluation limits report best-found rather than optimal"
      (fn [] (def result (opt/exact-search [sword dagger] {:slots 2 :max-evaluations 1} (fn [items] (length items))))
        (assert (not (result :complete))) (assert (= :best-found (result :guarantee)))))
(test "duplicate candidate IDs are rejected"
      (fn [] (rejects (fn [] (opt/exact-search [sword sword] {} (fn [items] 0))))))
(test "same-item fitness changes with target instead of reusing global cache"
      (fn [] (def low (core/evaluate-build garen 18 [ie] {:armor 0 :mr 0} scenario {}))
        (def high (core/evaluate-build garen 18 [ie] {:armor 100 :mr 0} scenario {}))
        (near ((low :combat) :dps) (* 2 ((high :combat) :dps)))))
(test "snapshot-based demo regression, with declared timing assumptions"
      (fn [] (def result (core/evaluate-build garen 18 [ie boots] target scenario {}))
        (near ((result :stats) :ad) 220.5)
        (near ((result :combat) :damage) 973.875)
        (near ((result :combat) :dps) 194.775)))
(test "all snapshot items can be aggregated without unhandled stats"
      (fn [] (each item (values snapshot/items) (stats/total-stats annie 18 [item]))))

(test "Annie Q/W damage uses explicit per-field rank indexing"
      (fn [] (near (((annie-model/spells 0) :base-damage) 0) 80)
        (near (((annie-model/spells 0) :cost) 0) 60)
        (near (((annie-model/spells 0) :base-damage) 4) 260)
        (near (((annie-model/spells 1) :base-damage) 4) 230)
        (near (((annie-model/spells 1) :cost) 4) 90)
        (near (((annie-model/spells 1) :cooldown) 4) 7)
        (near (((annie-model/spells 1) :scalings) :ap) 0.8)))
(test "Annie penetration comes from learned R even without casting R"
      (fn [] (def totals (stats/total-stats annie 18 []))
        (near ((stats/apply-rank-penetration annie totals {:r 0}) :magic-pen-percent) 0)
        (near ((stats/apply-rank-penetration annie totals {:r 1}) :magic-pen-percent) 0.1)
        (near ((stats/apply-rank-penetration annie totals {:r 2}) :magic-pen-percent) 0.15)
        (near ((stats/apply-rank-penetration annie totals {:r 3}) :magic-pen-percent) 0.2)
        (near (totals :magic-pen-percent) 0)))
(test "learned R penetration combines multiplicatively with Void Staff"
      (fn [] (def totals (stats/total-stats annie 18 [(snapshot/items "3135")]))
        (near ((stats/apply-rank-penetration annie totals {:r 3}) :magic-pen-percent) 0.52)))
(test "Annie Q uses its explicit projectile speed"
      (fn [] (def result (rotation/evaluate generic {:armor 0 :mr 0}
                                            {:duration 2 :distance 350 :include-attacks false} [(annie-model/spells 0)] {:q 1}))
        (near (((result :events) 0) :at) 0.5)))
(test "rank-zero spells are excluded from automatic rotation"
      (fn [] (def result (rotation/evaluate generic target {:duration 2 :include-attacks false}
                                            annie-model/spells {:q 0 :w 0}))
        (near (result :damage) 0)))
(test "automatic rotation honors a cooldown that starts on cast completion"
      (fn [] (def end-spell (table ;(kvs spell)))
        (put end-spell :slot :q) (put end-spell :cooldown-start :end)
        (def result (rotation/evaluate generic {:armor 0 :mr 0}
                                       {:duration 4 :include-attacks false} [end-spell] {:q 1}))
        (near (((result :actions) 1) :at) 2.5)))
(test "automatic rotation stops casting when resource runs out"
      (fn [] (def single (table ;(kvs spell))) (put single :slot :q)
        (def result (rotation/evaluate generic target
                                       {:duration 10 :resource 50 :include-attacks false} [single] {:q 1}))
        (assert (= 1 (length (result :actions)))) (near (result :resource-left) 0)))
(test "combined rotation scores the evaluated timeline"
      (fn [] (def ranks (skills/ranks-from-order annie-model/skill-order 18))
        (def items [(snapshot/items "3089") (snapshot/items "3135") (snapshot/items "3020")])
        (def result (core/evaluate-rotation annie 18 items target
                                            {:duration 5 :distance 300 :include-attacks true :windup-fraction 0.3}
                                            {} annie-model/spells ranks))
        (near ((result :combat) :dps) (+ ((result :combat) :attack-dps) ((result :combat) :ability-dps)))
        # Q,W,Q: 1452 raw magic / 1.264; four attacks: 380.2 / 1.8.
        (near ((result :combat) :damage) 1359.956399437412)
        (near ((result :combat) :resource-left) 593)))
(test "ability-only rotation generates no attacks"
      (fn [] (def result (rotation/evaluate (stats/total-stats annie 18 []) target
                                            {:duration 5 :distance 300 :include-attacks false} annie-model/spells {:q 5 :w 5}))
        (assert (all (fn [action] (= :spell (action :kind))) (result :actions)))
        (near (result :attack-dps) 0)))
(test "rotation validates learned ranks before scoring a build"
      (fn [] (rejects (fn [] (core/evaluate-rotation annie 2 [] target
                                                     {:duration 5 :include-attacks false} {} annie-model/spells {:q 2})))))

(test "mixed item patches are rejected by the core API"
      (fn [] (def other (table ;(kvs sword))) (put other :patch "15.1.1")
        (rejects (fn [] (core/evaluate-build garen 18 [other] target scenario {})))))
(test "mixed spell patches are rejected by the core API"
      (fn [] (def other (table ;(kvs (annie-model/spells 0)))) (put other :patch "15.1.1")
        (rejects (fn [] (core/evaluate-rotation annie 18 [] target
                                                {:duration 5 :include-attacks false} {} [other] {:q 5})))))

(def observed-stats {:ad 50 :ap 0 :hp 560 :armor 23 :mr 30 :attack-speed 0.61
                     :move-speed 335 :ability-haste 0})
(def observation {:schema-version 1 :source "synthetic-test" :patch "16.19.1"
                  :champion "Annie" :level 1 :ranks {:q 1 :w 0 :e 0 :r 0}
                  :map-id 11 :game-mode "CLASSIC" :is-dead false
                  :context-reviewed true :buffs [] :role-quest-state "inactive"
                  :excluded-stats [] :observed observed-stats
                  :tolerances {:default {:absolute 0.001 :relative 0.00001}}})
(test "stat observations compare against independently supplied baseline values"
      (fn [] (def result (observations/compare-stats annie [] observation))
        (assert (= :consistent (result :status)))
        (assert (= 8 (result :checked)))))
(test "a matching observation without reviewed context is not validation"
      (fn [] (def record (merge @{} observation {:context-reviewed false}))
        (assert (= :needs-context ((observations/compare-stats annie [] record) :status)))))
(test "a stat discrepancy is reported with its observed difference"
      (fn [] (def record (merge @{} observation {:observed (merge @{} observed-stats {:ap 18})}))
        (def result (observations/compare-stats annie [] record))
        (assert (= :mismatch (result :status)))
        (assert (= 1 (result :mismatches)))))
(test "explicit exclusions do not count as checked stats"
      (fn [] (def record (merge @{} observation {:excluded-stats [:ap]
                                                 :observed (merge @{} observed-stats {:ap 18})}))
        (def result (observations/compare-stats annie [] record))
        (assert (= :consistent (result :status)))
        (assert (= 7 (result :checked)))))
(test "missing measured stats make a comparison incomplete"
      (fn [] (def record (merge @{} observation {:observed {:ad 50}}))
        (def result (observations/compare-stats annie [] record))
        (assert (= :incomplete (result :status)))
        (assert (= 7 (result :missing)))))
(test "observations reject mismatched patches, maps, and unknown stats"
      (fn [] (each overrides [{:patch "16.18.1"} {:map-id 12} {:observed {:invented 0}}]
               (rejects (fn [] (observations/compare-stats annie [] (merge @{} observation overrides)))))))
(test "non-finite observations and invalid tolerances fail"
      (fn [] (each overrides [{:observed {:ad math/inf}}
                              {:tolerances {:default {:absolute -1 :relative 0}}}]
               (rejects (fn [] (observations/compare-stats annie [] (merge @{} observation overrides)))))))
(test "observed learned R penetration uses rank context"
      (fn [] (def record (merge @{} observation {:level 6 :ranks {:r 1}
                                                 :observed {:magic-pen-percent 0.1} :excluded-stats observations/required-stats}))
        (assert (= :consistent ((observations/compare-stats annie [] record) :status)))))
(test "the API's Practice Tool mode is accepted without allowing other modes"
      (fn [] (def record (merge @{} observation {:game-mode "PRACTICETOOL"}))
        (assert (= :consistent ((observations/compare-stats annie [] record) :status)))
        (rejects (fn [] (observations/compare-stats annie []
                                                    (merge @{} observation {:game-mode "ARAM"}))))))
(test "recorded stat shards are applied before caps and percent multipliers"
      (fn [] (def totals (stats/total-stats annie 1 [(snapshot/items "3089")]
                                            [{:ap 20 :attack-speed-bonus 0.1 :hp 65}]))
        (near (totals :ap) 195)
        (near (totals :attack-speed) 0.6725)
        (near (totals :hp) 625)))
(test "unmodeled stat shards are rejected instead of disappearing"
      (fn [] (rejects (fn [] (observations/compare-stats annie []
                                                         (merge @{} observation {:shard-ids [5008]}) snapshot/stat-shards)))))
(test "measured Annie level-one capture agrees for ten checked stats"
      (fn [] (def record (parse (slurp "observations/16.19.1/annie-level1-no-items.jdn")))
        (def result (observations/compare-stats annie [] record snapshot/stat-shards))
        (assert (= :consistent (result :status)))
        (assert (= (record :expected-checked-stats) (result :checked)))
        (assert (= 0 (result :mismatches)))
        (def speed-row (find (fn [row] (= :move-speed (row :stat))) (result :rows)))
        (assert (= :excluded (speed-row :status)))))
(test "measured Cloak capture confirms fractional crit chance and eleven stats"
      (fn [] (def record (parse (slurp "observations/16.19.1/annie-level1-cloak.jdn")))
        (def result (observations/compare-stats annie [(snapshot/items "1018")]
                                                record snapshot/stat-shards))
        (assert (= :consistent (result :status)))
        (assert (= (record :expected-checked-stats) (result :checked)))
        (assert (= 0 (result :mismatches)))
        (def crit-row (find (fn [row] (= :crit-chance (row :stat))) (result :rows)))
        (near (crit-row :expected) 0.15)
        (near (crit-row :observed) 0.15000000596046448)))
(test "measured Void Staff capture confirms AP and remaining-resistance penetration"
      (fn [] (def record (parse (slurp "observations/16.19.1/annie-level1-void-staff.jdn")))
        (def result (observations/compare-stats annie [(snapshot/items "3135")]
                                                record snapshot/stat-shards))
        (assert (= :consistent (result :status)))
        (assert (= (record :expected-checked-stats) (result :checked)))
        (assert (= 0 (result :mismatches)))
        (def pen-row (find (fn [row] (= :magic-pen-percent (row :stat))) (result :rows)))
        (near (pen-row :expected) 0.4)
        (near (pen-row :observed) (- 1 0.6000000238418579))))

(each sample [["annie-level6-void-staff.jdn" 0.4]
              ["annie-level6-void-staff-r1.jdn" 0.46]]
  (test (string "measured level-six Annie: " (sample 0))
        (fn [] (def record (parse (slurp (string "observations/16.19.1/" (sample 0)))))
          (def result (observations/compare-stats annie [(snapshot/items "3135")]
                                                  record snapshot/stat-shards))
          (assert (= :consistent (result :status)))
          (assert (= 12 (result :checked)))
          (assert (= 0 (result :mismatches)))
          (each pair [[:hp 1004.2] [:ad 60.4675] [:armor 38.8] [:mr 35.135]
                      [:mp 516.75] [:attack-speed 0.706075]
                      [:magic-pen-percent (sample 1)]]
            (def row (find (fn [row] (= (pair 0) (row :stat))) (result :rows)))
            (near (row :expected) (pair 1))))))

(print passed " passed; " failed " failed")
(when (> failed 0) (os/exit 1))
