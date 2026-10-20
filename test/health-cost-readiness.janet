(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(defn constant [n] {:op :constant :value n})
(def health {:op :stat :stat :health :formula 0})
(defn affine [a b] {:op :sum :children [{:op :multiply :children [(constant a) health]} (constant b)]})
(def spell {:id "fixture-health" :slot :q :cost-resource :health :cost (affine 0.5 0) :cooldown 99 :range 500 :cast-time 0.04 :missile-speed 0
            :effects [{:kind :damage :damage-type :true :amount 1 :target :enemy :status :estimated}]})
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :base {:hp 100 :ad 10 :ap 0}
          :stats {:hp 100 :mp 100 :ad 10 :ap 0.5 :armor 0 :mr 0 :attack-speed 1 :hp-regen 5 :mp-regen 5}
          :health 1.663 :resource 100 :abilities [spell] :ranks {:q 1 :w 1} :position 0 :attack-range 500
          :strategy {:attacks false :abilities true :movement :hold}} (or fields {})))
(def dummy (unit "dummy" {:health 100 :abilities [] :strategy {:attacks false :abilities false :movement :hold}}))
(defn input [&opt fields events duration side other]
  {:duration (or duration 0.7) :initial-events (or events []) :event-limit 2000
   :actors (if (= side 1) [(or other dummy) (unit "active" fields)] [(unit "active" fields) (or other dummy)])})
(defn run [&opt fields events duration side other] (engine/simulate (input fields events duration side other)))
(defn casts [result] (filter |(and (= :cast ($ :kind)) (= "active" ($ :actor)) (= "fixture-health" ($ :source))) (result :trace)))
(defn first-at [result] ((first (casts result)) :at))
(defn none [result] (assert (empty? (casts result))))
(defn effect [time side data]
  {:at time :kind :effect :actor (- 1 side) :target side :source "fixture-health-state" :origin (string "fixture/" time) :effect data})
(defn bonus [time side stat amount &opt duration]
  (effect time side {:kind :stat-buff :stat stat :amount amount :duration (or duration 1)}))

# Solve h - (a*h+b) >= 1 independently, with both participant orders and
# different positive regeneration rates. Payment still evaluates the real AST.
(each side [0 1]
  (each rate [0.7 1 3.7]
    (each a [-0.5 0.04 0.08 0.5 0.9]
      (def required (/ 4 (- 1 a)))
      (def fields {:health (- required (* rate 0.337)) :stats (merge (dummy :stats) {:hp-regen (* 5 rate)})
                   :abilities [(merge spell {:cost (affine a 3)})]})
      (def definition (input fields nil 0.39 side))
      (def result (engine/simulate definition))
      (assert (= 1 (length (casts result))))
      (close 0.337 (first-at result))
      (close (+ (* a required) 3) ((first (casts result)) :cost))
      (assert (>= (get-in result [:actors side :health]) 1))
      (assert (= (result :metrics) ((engine/simulate (merge definition {:trace false})) :metrics))))))

# Fractions/missing health, zero-cost clamping and rank overrides are affine.
(each [cost required] [[{:op :multiply :children [(constant 5) {:op :stat :stat :health-percent :formula 0}]} 2]
                       [{:op :multiply :children [(constant 0.5) {:op :stat :stat :missing-health :formula 0}]} 4]
                       [{:op :multiply :children [(constant 5) {:op :stat :stat :missing-health-percent :formula 0}]} 4]
                       [(affine -0.5 0.2) 1]
                       [{:op :with-rank :rank 2 :children [{:op :multiply :children [{:op :rank :values [0.25 0.5] :offset -1} health]}]} 2]
                       [{:op :with-rank :rank nil :children [(affine 0.5 0)]} 2]]
  (close 0.337 (first-at (run {:health (- required 0.337) :stats (merge (dummy :stats) {:hp 10})
                               :abilities [(merge spell {:cost cost})]}))))
(def free (run {:health 0.663 :abilities [(merge spell {:cost (affine -0.5 0.2)})]}))
(close 0 ((first (casts free)) :cost))

# Rate, cap, coefficient and buff changes replace the forecast; healing can
# enable it immediately. Damage at a deadline invalidates it before selection.
(each side [0 1]
  (close 0.1354 (first-at (run nil [(bonus 0.113 side :hp-regen 45)] nil side)))
  (close 0.22 (first-at (run nil [(bonus 0 side :hp-regen 45 0.013)] nil side)))
  (close 0.45 (first-at (run {:stats (merge (dummy :stats) {:hp-regen 0})}
                             [(bonus 0.113 side :hp-regen 5)] nil side)))
  (close 0.337 (first-at (run {:stats (merge (dummy :stats) {:hp 1.9})}
                              [(bonus 0.113 side :hp 1)] nil side)))
  (close 0.113 (first-at (run nil [(effect 0.113 side {:kind :heal :amount 0.337})] nil side)))
  (close 0.437 (first-at (run nil [(effect 0.337 side {:kind :damage :damage-type :true :amount 0.1})] nil side)))
  (close 0.537 (first-at (run nil [(effect 0.337 side {:kind :control :control :silence :duration 0.2})] nil side))))
(def stat-cost {:op :multiply :children [health {:op :stat :stat :ap :formula 0}]})
(close 0.113 (first-at (run {:abilities [(merge spell {:cost stat-cost})]} [(bonus 0.113 0 :ap -0.1)])))
(close 0.837 (first-at (run {:abilities [(merge spell {:cost stat-cost})]} [(bonus 0.113 0 :ap 0.1)] 0.9)))
(def target-cost {:op :multiply :children [health {:op :target-stat :stat :ap}]})
(close 0.113 (first-at (run {:abilities [(merge spell {:cost target-cost})]} [(bonus 0.113 1 :ap -0.1)])))
(def conditional {:op :conditional :buff "health-discount" :invert false :children [(affine 0.25 0) (affine 0.5 0)]})
(close 0.137 (first-at (run {:abilities [(merge spell {:cost conditional})]}
                            [(effect 0.137 0 {:kind :buff :buff "health-discount" :duration 1})])))
(close 0.337 (first-at (run {:health 1.663 :abilities [(merge spell {:cost conditional})]
                             :strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.2}}}}
                            [(effect 0 0 {:kind :buff :buff "health-discount" :duration 0.137})])))

# Priority, current action locks, recast/charge gates and repeated spending.
(def locked (run {:abilities [spell (merge spell {:id "fixture-w" :slot :w :cost 0.1 :cast-lock 0.4})]}))
(close 0.437 (first-at locked))
(def recast (run {:abilities [(merge spell {:cost 0 :recast {:count 1 :window 1 :delay 0.1 :cost (affine 0.5 0)}})]}))
(assert (= 2 (length (casts recast))))
(close 0.337 (((casts recast) 1) :at))
(def charged (run {:health 2 :abilities [(merge spell {:max-charges 2 :charge-delay 0.1 :recharge-time 99})]} nil 1.1))
(assert (= 2 (length (casts charged))))
(close 1 (((casts charged) 1) :at))
(close 0.437 (first-at (run {:strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.437}}}})))
(each fields [{:stats (merge (dummy :stats) {:hp-regen 0})} {:stats (merge (dummy :stats) {:hp 1.9})}
              {:strategy {:attacks false :abilities false :movement :hold}} {:ranks {:q 0}}]
  (none (run fields)))
(each victim [0 1]
  (none (run nil [(effect 0.337 victim {:kind :damage :damage-type :true :amount 100})])))
(none (run {:health 1.75} nil 0.25))
(close 0.25 (first-at (run {:health 1.75} nil 0.25001)))

# Coefficients do not change merely because health regenerates. Unrelated
# stat events must not wake another ability still using fallback polling.
(def unchanged {:health 10 :resource 9.98 :stats (merge (dummy :stats) {:hp-regen 0})
                :abilities [(merge spell {:cost-resource :resource :cost health})
                            (merge spell {:id "fixture-w" :slot :w :cost (affine 0.5 100)})]})
(close 0.05 (first-at (run unchanged [(bonus 0.037 0 :armor 1)])))

# Nonlinear, target-current-health and nonmonotone costs keep polling. This
# prevents freezing them or guessing a derivative from sample values.
(def quadratic {:op :multiply :children [(constant 0.1) health health]})
(close 0.35 (first-at (run {:health 0.8 :abilities [(merge spell {:cost quadratic})]})))
(close 0.35 (first-at (run {:health 0.663 :abilities [(merge spell {:cost (affine 1 -2)})]})))
(none (run {:abilities [(merge spell {:cost (affine 1 2)})]}))
(def huge {:op :sum :children [{:op :multiply :children [(constant 1e308) health]}
                               {:op :multiply :children [(constant 1e308) health]}
                               {:op :multiply :children [(constant -1e308) health]}]})
(def overflow (run {:health 0.1 :abilities [(merge spell {:cost huge})]} nil 0.2))
(none overflow)
(assert (empty? (overflow :unsupported)))
(close 0.35 (first-at (run {:abilities [(merge spell {:cost {:op :target-stat :stat :health}})]}
                           nil nil nil (merge dummy {:health 1 :stats (merge (dummy :stats) {:hp-regen 0})}))))

# Retained 16.18.1 costs: exact source ASTs, evaluated at configured low health.
(def fixtures "data/parser-fixtures/16.18.1/")
(def fonts (util/read-json (slurp (string fixtures "strings.json"))))
(defn kit [id]
  (normalize/kit id (util/read-json (slurp (string fixtures id "-characters.json")))
                 (util/read-json (slurp (string fixtures id "-abilities.json"))) fonts "16.18.1"))
(each [id slot coefficient] [["DrMundo" :w 0.079999998211860657] ["Zac" :q 0.079999998211860657]
                             ["Zac" :w 0.039999999105930328] ["Zac" :e 0.039999999105930328]]
  (def source (find |(= slot ($ :slot)) ((kit id) :abilities)))
  (def required (/ 1 (- 1 coefficient)))
  (def result (run {:health (- required 0.337) :abilities [(merge spell {:cost (source :cost)})]}))
  (close 0.337 (first-at result))
  (close (* coefficient required) ((first (casts result)) :cost)))

# An explicitly synthetic carrier keeps the retained Mundo W cost on its own
# patch. Its 10 HP, configured regeneration and true damage are test inputs.
(def root (string "build/health-cost-tests/" (hash/sha256 (os/cryptorand 8))))
(packages/initialize root "build/seed")
(def source-cost ((find |(= :w ($ :slot)) ((kit "DrMundo") :abilities)) :cost))
(def coefficient 0.079999998211860657)
(def required (/ 1 (- 1 coefficient)))
(def rate (/ (- required 1) 0.337))
(def carrier (merge spell {:cost source-cost :cast-time 0.25 :name "Synthetic health-cost carrier"
                           :max-rank 5 :available true :checked false :icon "AnnieQ.png" :icon-group "spell"
                           :tooltip "Synthetic carrier using retained 16.18.1 Mundo W cost; not Annie mechanics."
                           :variables [] :record {} :unresolved ["Synthetic carrier stats/effect; not champion mechanics."]}))
(def champions (map (fn [id]
                      (def objects (util/read-json (slurp (string fixtures id "-characters.json"))))
                      (def detail (get-in (util/read-json (slurp (string fixtures id "-abilities.json"))) ["data" id]))
                      (def champion (normalize/champion "16.18.1" detail objects))
                      (if (= id "Annie")
                        (merge champion {:base (merge (champion :base) {:hp 10 :hp-regen (* rate 5)}) :abilities [carrier]})
                        champion)) ["Annie" "Garen"]))
(def bytes (util/encode-data (util/canonical {:schema 1 :parser "6" :patch "16.18.1" :champions champions :items []})))
(def snapshot (hash/sha256 bytes))
(def directory (string root "/patches/16.18.1/" snapshot))
(util/write (string directory "/package.jdn") bytes)
(util/write (string directory "/manifest.json") (util/encode-json {"initial" false "synthetic_health_cost" true "package_sha256" snapshot}))
(util/write (string root "/patches/16.18.1/current") snapshot)
(packages/initialize root nil)
(def caster {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items []} :health-fraction 0.1
             :strategy {:attacks false :abilities true :priority [:q] :movement :hold}})
(def idle (merge caster {:kind :champion :health-fraction 1 :strategy {:attacks false :abilities false :movement :hold}}))
(def definition {:schema 1 :patch "16.18.1" :snapshot snapshot :duration 0.592 :distance 0 :seed 1 :player caster :target idle})
(each [input side] [[definition 0] [(merge definition {:player idle :target (merge caster {:kind :champion})}) 1]]
  (def result (scenario/simulate input))
  (def starts (filter |(= :cast ($ :kind)) (result :trace)))
  (def hits (filter |(= :damage ($ :kind)) (result :trace)))
  (assert (= 1 (length starts) (length hits)))
  (close 0.337 ((first starts) :at))
  (close 0.587 ((first hits) :at))
  (close (* coefficient required) ((first starts) :cost))
  (close 1 (get-in result [:actors side :damage-dealt]))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= snapshot (hash/sha256 (slurp (string directory "/package.jdn")))))
(when-let [export (os/getenv "PS_HEALTH_COST_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(util/remove-tree root)
(print "Affine health-cost thresholds, exact payment/reserve, changing coefficients/rates, action gates, retained current-health formulas and compiled fitness parity passed.")
