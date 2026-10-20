(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(defn stat [name &opt target? formula]
  (if target? {:op :target-stat :stat name} {:op :stat :stat name :formula (or formula 0)}))
(defn constant [value] {:op :constant :value value})
(defn branch [yes no &opt invert]
  {:op :conditional :buff "fixture-mark" :invert (or invert false) :children [yes no]})
(def spell {:id "fixture-q" :slot :q :cost {:op :stat :stat :ad :formula 0} :cooldown 99 :cast-time 0.04 :missile-speed 0 :range 500
            :effects [{:kind :damage :damage-type :true :amount 10 :target :enemy :status :estimated}]})
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :base {:hp 1000 :mp 1000 :ad 5 :ap 0}
          :stats {:hp 1000 :mp 1000 :ad 10 :ap 100 :armor 0 :mr 0 :attack-speed 1 :mp-regen 5 :move-speed 100}
          :abilities [spell] :ranks {:q 1 :w 1} :resource 9.663 :position 0 :attack-range 100
          :strategy {:attacks false :abilities true :movement :hold}} (or fields {})))
(def dummy (unit "dummy" {:position 133.7 :abilities [] :strategy {:attacks false :abilities false :movement :hold}}))
(defn input [&opt fields events side other duration]
  {:duration (or duration 0.7) :initial-events (or events [])
   :actors (if (= side 1) [(or other dummy) (unit "active" fields)] [(unit "active" fields) (or other dummy)])})
(defn run [&opt fields events side other duration] (engine/simulate (input fields events side other duration)))
(defn casts [result] (filter |(and (= :cast ($ :kind)) (= "active" ($ :actor))) (result :trace)))
(defn first-at [result] ((first (casts result)) :at))
(defn none [result] (assert (empty? (casts result))))
(defn effect [time target data]
  {:at time :kind :effect :actor (- 1 target) :target target :source "fixture-state" :origin (string "fixture/" time) :effect data})
(defn bonus [time target name amount &opt duration]
  (effect time target {:kind :stat-buff :stat name :amount amount :duration (or duration 1)}))
(defn mark [time target duration &opt extra]
  (effect time target (merge {:kind :buff :buff "fixture-mark" :stacks 1 :duration duration} (or extra {}))))

# Independent affordability arithmetic, own/bonus/base/target stats, both roles,
# and between-poll changes that replace or invalidate an old forecast.
(each side [0 1]
  (def definition (input nil nil side))
  (def result (engine/simulate definition))
  (close (/ (- 10 9.663) 1) (first-at result))
  (assert (= (result :metrics) ((engine/simulate (merge definition {:trace false})) :metrics)))
  (close 0.137 (first-at (run nil [(bonus 0.113 side :ad -0.2)] side)))
  (close 0.113 (first-at (run nil [(bonus 0.113 side :ad -1)] side)))
  (close 0.537 (first-at (run nil [(bonus 0.113 side :ad 0.2)] side)))
  (close 0.237 (first-at (run {:resource 10 :stats (merge (dummy :stats) {:mp-regen 0})}
                              [(bonus 0 side :ad 1 0.237)] side)))
  (close 0.137 (first-at (run {:abilities [(merge spell {:cost (stat :ad true)})]}
                              [(bonus 0.113 (- 1 side) :ad -0.2)] side)))
  (close 0.337 (first-at (run {:resource 4.663 :abilities [(merge spell {:cost (stat :ad false 2)})]} nil side)))
  (close 0.337 (first-at (run {:resource 4.663 :abilities [(merge spell {:cost (stat :ad false 1)})]}
                              [(bonus 0.113 side :ad 99)] side))))

# Buff counters and conditional branches change at application, consumption,
# refresh and expiry. Unchanged expression values do not add extra decisions.
(def conditional-cost (branch (constant 9) (constant 10)))
(each side [0 1]
  (close 0.137 (first-at (run {:abilities [(merge spell {:cost conditional-cost})]} [(mark 0.137 side 1)] side)))
  (close 0.237 (first-at (run {:resource 10 :abilities [(merge spell {:cost (branch (constant 11) (constant 10))})]}
                              [(mark 0 side 0.237)] side)))
  (close 0.137 (first-at (run {:abilities [(merge spell {:cost (branch (constant 10) (constant 9) true)})]}
                              [(mark 0.137 side 1)] side))))
(def counter-cost {:op :sum :children [(constant 10) {:op :multiply :children [(constant -1) {:op :buff-count :name "fixture-mark"}]}]})
(close 0.137 (first-at (run {:abilities [(merge spell {:cost counter-cost})]} [(mark 0.137 0 1)])))
(close 0.437 (first-at (run {:abilities [(merge spell {:cost (branch (constant 11) (constant 10))})] :resource 10}
                            [(mark 0 0 0.237 {:refresh true}) (mark 0.1 0 0.337 {:refresh true})])))
(def consumed (run {:resource 10 :abilities [(merge spell {:cost (branch (constant 11) (constant 10))})]
                    :triggers [{:id "fixture-consume" :on [:damage-taken] :cooldown 99 :consume-buff "fixture-mark"
                                :kind :heal :amount 0 :target :self}]}
                   [(mark 0 0 1) (effect 0.137 0 {:kind :damage :damage-type :true :amount 1})]))
(close 0.137 (first-at consumed))

# Recast costs are evaluated expressions, not raw dictionaries. A forecast must
# use the active phase and preserve the recast delay and its remaining count.
(def recast (run {:resource 0 :abilities [(merge spell {:cost 0 :recast {:count 1 :window 1 :delay 0.1 :cost (stat :ad)}})]}
                 [(bonus 0 0 :ad -9.663)]))
(assert (= 2 (length (casts recast))))
(close 0.337 (((casts recast) 1) :at))
(def health-cost (run {:health 10.663 :stats (merge (dummy :stats) {:hp-regen 5})
                       :abilities [(merge spell {:cost-resource :health})]}))
(close 0.337 (first-at health-cost))
(def cooldown (run {:resource 10 :abilities [(merge spell {:cooldown 0.337})]} [(bonus 0.137 0 :ad -10)]))
(assert (= 3 (length (casts cooldown))))
(each [expected event] (map tuple [0 0.337 0.674] (casts cooldown)) (close expected (event :at)))
(def charged (run {:resource 10 :abilities [(merge spell {:max-charges 1 :recharge-time 0.437 :charge-delay 0.01})]}
                  [(bonus 0.137 0 :ad -10)]))
(assert (= 2 (length (casts charged))))
(close 0.437 (((casts charged) 1) :at))

# Range expansion wakes a stationary actor, and relative movement forecasts use
# the updated range. Range contraction cannot retain an obsolete permission.
(def ranged {:resource 100 :abilities [(merge spell {:cost 0 :range (stat :ap)})]
             :strategy {:attacks false :abilities true :movement :approach}})
(each side [0 1]
  (close 0.337 (first-at (run ranged nil side)))
  (close 0.137 (first-at (run ranged [(bonus 0.113 side :ap 20)] side)))
  (close 0.113 (first-at (run (merge ranged {:strategy {:attacks false :abilities true :movement :hold}})
                              [(bonus 0.113 side :ap 40)] side)))
  (close 0.437 (first-at (run (merge ranged {:attack-range 0}) [(bonus 0.113 side :ap -10)] side)))
  (close 0.137 (first-at (run (merge ranged {:abilities [(merge spell {:cost 0 :range (stat :ap true)})]})
                              [(bonus 0.113 (- 1 side) :ap 20)] side)))
  (close 0.137 (first-at (run (merge ranged {:strategy {:attacks false :abilities true :movement :hold}
                                             :abilities [(merge spell {:cost 0 :range (branch (constant 200) (constant 100))})]})
                              [(mark 0.137 side 1)] side))))
(none (run (merge ranged {:strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.137}}}})
           [(bonus 0 0 :ap 40 0.137)]))

# Ordinary action gates still bind after input changes, including same-time
# reversal/control/death and locks established by a triggering cast.
(close 0.237 (first-at (run {:strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.237}}}}
                            [(bonus 0.137 0 :ad -1)])))
(close 0.337 (first-at (run nil [(bonus 0.137 0 :ad -1) (effect 0.137 0 {:kind :control :control :silence :duration 0.2})])))
(close 0.337 (first-at (run nil [(bonus 0.137 0 :ad -1) (bonus 0.137 0 :ad 0)])))
(each victim [0 1]
  (none (run nil [(bonus 0.137 0 :ad -1) (effect 0.137 victim {:kind :damage :damage-type :true :amount 1000})])))
(none (run {:strategy {:attacks false :abilities false :movement :hold}} [(bonus 0.137 0 :ad -1)]))
(none (run {:ranks {:q 0}} [(bonus 0.137 0 :ad -1)]))
(none (run nil [(bonus 0.137 0 :ad -1)] nil nil 0.137))
(close 0.137 (first-at (run nil [(bonus 0.137 0 :ad -1)] nil nil 0.13701)))
(def unchanged-fields {:health 10 :resource 9.98 :abilities [(merge spell {:cost (stat :health)})
                                                             (merge spell {:id "fixture-w" :slot :w :cost (branch (stat :ap) (stat :ap))})]})
(each event [(bonus 0.037 0 :armor 1) (mark 0.037 0 1)]
  (close 0.05 (first-at (run unchanged-fields [event]))))
(def self-buff (merge spell {:id "fixture-w" :slot :w :cost 0 :cast-time 0 :cast-lock 0.237
                             :effects [{:kind :stat-buff :stat :ad :amount -1 :duration 1 :target :self :trigger :cast-start :status :estimated}]}))
(def locked (run {:abilities [spell self-buff]}))
(close 0.237 ((first (filter |(= "fixture-q" ($ :source)) (casts locked))) :at))

# Continuous health inputs and branches containing them are deliberately not
# frozen. Retained source formulas demonstrate why this fallback is necessary.
(close 0.35 (first-at (run {:health 10 :abilities [(merge spell {:cost (stat :health)})]})))
(def unresolved (run {:abilities [(merge spell {:cost {:op :unresolved :reason "Synthetic unresolved cost"}})]}))
(none unresolved)
(assert (not (empty? (unresolved :unsupported))))
(def source-root "data/parser-fixtures/16.18.1/")
(def fonts (util/read-json (slurp (string source-root "strings.json"))))
(each id ["DrMundo" "Zac"]
  (def kit (normalize/kit id (util/read-json (slurp (string source-root id "-characters.json")))
                          (util/read-json (slurp (string source-root id "-abilities.json"))) fonts "16.18.1"))
  (each ability (kit :abilities)
    (when (and (= :health (ability :cost-resource)) (not (engine/fixed-value? (ability :cost))))
      (assert (not (engine/event-value? (ability :cost)))))))

# Synthetic cached carriers exercise expressions through compilation, the
# optimizer, exported scenarios, the copied executable and the browser.
# These are explicitly invented test abilities, not Annie/Lux mechanics.
(def root (string "build/changing-readiness-tests/" (hash/sha256 (os/cryptorand 8))))
(packages/initialize root "build/seed")
(def source (packages/load "16.19.1"))
(def response (merge spell {:cost (branch (constant 0) (constant 1000))
                            :range (branch (constant 500) (constant 0)) :cast-time 0.04}))
(def grant {:id "fixture-grant" :name "Synthetic readiness state" :slot :q :cost 0 :range 500 :cooldown 99 :cast-time 0.487 :missile-speed 0
            :effects [{:kind :buff :buff "fixture-mark" :stacks 1 :duration 1 :target :enemy :status :estimated}]})
(def champions (map (fn [id ability]
                      (merge ((source :champion-map) id)
                             {:abilities [(merge {:max-rank 5 :available true :checked false :icon-group "spell"
                                                  :icon (if (= id "Annie") "AnnieQ.png" "LuxLightBinding.png")
                                                  :tooltip "Synthetic readiness fixture; not champion mechanics."
                                                  :variables [] :record {} :cost-resource :resource
                                                  :unresolved ["Synthetic readiness fixture; not champion mechanics."]} ability)]}))
                    ["Annie" "Lux"] [response grant]))
(def bytes (util/encode-data (util/canonical {:schema 1 :parser "6" :patch "16.19.1" :champions champions :items []})))
(def snapshot (hash/sha256 bytes))
(def directory (string root "/patches/16.19.1/" snapshot))
(util/write (string directory "/package.jdn") bytes)
(util/write (string directory "/manifest.json") (util/encode-json {"initial" false "synthetic_changing_readiness" true "package_sha256" snapshot}))
(util/write (string root "/patches/16.19.1/current") snapshot)
(packages/initialize root nil)
(def caster {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items []}
             :strategy {:attacks false :abilities true :priority [:q] :movement :hold}})
(def grantor (merge caster {:champion "Lux" :kind :champion}))
(def definition {:schema 1 :patch "16.19.1" :snapshot snapshot :duration 0.532 :distance 100 :seed 1 :player caster :target grantor})
(each [input side] [[definition 0] [(merge definition {:player grantor :target (merge caster {:kind :champion})}) 1]]
  (def result (scenario/simulate input))
  (def starts (filter |(and (= :cast ($ :kind)) (= "fixture-q" ($ :source))) (result :trace)))
  (def hits (filter |(and (= :damage ($ :kind)) (= "fixture-q" ($ :source))) (result :trace)))
  (assert (= 1 (length starts) (length hits)))
  (close 0.487 ((first starts) :at))
  (close 0.527 ((first hits) :at))
  (close 10 (get-in result [:actors side :damage-dealt]))
  (assert (empty? ((engine/simulate (scenario/compile input)) :unsupported)))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= snapshot (hash/sha256 (slurp (string directory "/package.jdn")))))
(when-let [export (os/getenv "PS_CHANGING_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(util/remove-tree root)
(print "Changing stat/buff costs and ranges, exact forecasts and state reactions, recast expressions, gates, source health fallback and trace-free parity passed.")
