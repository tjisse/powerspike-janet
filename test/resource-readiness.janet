(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(def spell {:id "fixture-q" :slot :q :cost 10 :cooldown 0.173 :cast-time 0.04 :missile-speed 0 :range 500
            :effects [{:kind :damage :damage-type :true :amount 10 :target :enemy :status :estimated}]})
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :base {:hp 1000 :mp 1000 :ad 10 :ap 0}
          :stats {:hp 1000 :mp 1000 :ad 10 :ap 0 :armor 0 :mr 0 :attack-speed 0 :mp-regen 5 :hp-regen 5}
          :abilities [spell] :ranks {:q 1 :w 1} :resource 9.663 :health 10.663 :position 0 :attack-range 500
          :strategy {:attacks false :abilities true :movement :hold}} (or fields {})))
(def dummy (unit "dummy" {:abilities [] :health 1000 :strategy {:attacks false :abilities false :movement :hold}}))
(defn input [fields duration &opt events side]
  {:duration duration :event-limit 2000 :initial-events (or events [])
   :actors (if (= side 1) [dummy (unit "active" fields)] [(unit "active" fields) dummy])})
(defn run [fields duration &opt events side] (engine/simulate (input fields duration events side)))
(defn casts [result] (filter |(= :cast ($ :kind)) (result :trace)))
(defn first-at [result] ((first (casts result)) :at))
(defn effect [time data &opt target]
  {:at time :kind :effect :actor 1 :target (or target 0) :source "fixture" :origin (string "fixture/" time) :effect data})

# Independent affordability arithmetic for both resource pools and actor roles.
(each health? [false true]
  (each rate [0.7 1 3.7 20]
    (each side [0 1]
      (def fields {:health (- 11 (* rate 0.337)) :resource (- 10 (* rate 0.337))
                   :stats (merge (dummy :stats) {:hp-regen (* rate 5) :mp-regen (* rate 5)})
                   :abilities [(merge spell {:cost-resource (if health? :health :resource)})]})
      (def definition (input fields 0.38 nil side))
      (def result (engine/simulate definition))
      (assert (= 1 (length (casts result))))
      (close 0.337 (first-at result))
      (close 10 ((first (casts result)) :cost))
      (assert (>= (get-in result [:actors side (if health? :health :resource)]) (if health? 1 0)))
      (assert (= (result :metrics) ((engine/simulate (merge definition {:trace false})) :metrics))))))

# Rank/level constants and arithmetic remain fixed; stat-dependent formulas
# now forecast between stat events. Current-health formulas retain polling.
(each cost [10 {:op :constant :value 10} {:op :rank :offset -1 :values [10 20]}
            {:op :level-values :values [0 10]} {:op :level-interpolation :start 10 :end 20}
            {:op :multiply :children [{:op :constant :value 2} {:op :constant :value 5}]}
            {:op :sum :children [{:op :constant :value 3} {:op :constant :value 7}]}
            {:op :with-rank :rank 2 :children [{:op :rank :offset -1 :values [20 10]}]}]
  (close 0.337 (first-at (run {:abilities [(merge spell {:cost cost})]} 0.4))))
(close 0.337 (first-at (run {:abilities [(merge spell {:cost {:op :stat :stat :ad :formula 0}})]} 0.4)))
(def health-percentage {:op :multiply :children [{:op :constant :value 0.5} {:op :stat :stat :health :formula 0}]})
(def changing-cost (run {:health 1.663 :abilities [(merge spell {:cost health-percentage :cost-resource :health})]} 0.4))
(assert (= 1 (length (casts changing-cost))))
(close 0.35 (first-at changing-cost))
(close (* 0.5 (+ 1.663 0.35)) ((first (casts changing-cost)) :cost))
(each multiplier [0.37 1.7]
  (close 0.337 (first-at (run {:health (- 11 (* multiplier 0.337))
                               :stats (merge (dummy :stats) {:healing-multiplier multiplier})
                               :abilities [(merge spell {:cost-resource :health})]} 0.4))))
(each health? [false true]
  (def fields {:resource 0 :health 1 :stats (merge (dummy :stats) {:mp-regen 18.5 :hp-regen 18.5})
               :abilities [(merge spell {:cost 1 :cost-resource (if health? :health :resource)})]})
  (def result (run fields 1.13))
  (assert (= 4 (length (casts result))))
  (eachp [index event] (casts result) (close (/ (inc index) 3.7) (event :at))))

# Selection priority, cooldown, activation, recast/charge costs and action locks
# must still bind even when the pool crosses its threshold first.
(def priority (run {:abilities [spell (merge spell {:id "fixture-w" :slot :w})]
                    :strategy {:attacks false :abilities true :priority [:w :q] :movement :hold}} 0.4))
(assert (= 1 (length (casts priority))))
(assert (= "fixture-w" ((first (casts priority)) :source)))
(close 0.337 (first-at priority))
(def locked (run {:resource 0.663 :abilities [(merge spell {:cost 1})
                                              (merge spell {:id "fixture-w" :slot :w :cost 0 :cast-lock 0.4})]} 0.9))
(close 0 (first-at locked))
(close 0.4 ((get (filter |(= "fixture-q" ($ :source)) (casts locked)) 0) :at))
(def cooldown (run {:resource 10 :abilities [(merge spell {:cooldown 0.737})]
                    :stats (merge (dummy :stats) {:mp-regen 100})} 0.8))
(close 0.737 (((casts cooldown) 1) :at))
(close 0.337 (first-at (run {:resource 10 :strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.337}}}} 0.4)))
(def recast (run {:resource 0.963 :abilities [(merge spell {:cost 1 :cooldown 99 :recast {:count 1 :window 1 :delay 0.1 :cost 0.3}})]} 0.4))
(close 0.037 (first-at recast))
(close 0.337 (((casts recast) 1) :at))
(def charged (run {:resource 0.963 :abilities [(merge spell {:cost 1 :max-charges 2 :recharge-time 99 :charge-delay 0.1})]} 1.1))
(close 0.037 (first-at charged))
(close 1.037 (((casts charged) 1) :at))

# Recompute after rate changes/expiry and maximum-pool changes. Rate changes
# between polls must wake an actor whose old prediction was later or absent.
(close 0.1517 (first-at (run {:resource 9.5} 0.22
                             [(effect 0.113 {:kind :stat-buff :stat :mp-regen :amount 45 :duration 0.1})])))
(close 0.383 (first-at (run {:resource 9.5} 0.45
                            [(effect 0 {:kind :stat-buff :stat :mp-regen :amount 45 :duration 0.013})])))
(close 0.023 (first-at (run {:resource 9.99 :stats (merge (dummy :stats) {:mp-regen 0})} 0.1
                            [(effect 0.013 {:kind :stat-buff :stat :mp-regen :amount 5 :duration 1})])))
(close 0.023 (first-at (run {:health 10.99 :stats (merge (dummy :stats) {:healing-multiplier 0})
                             :abilities [(merge spell {:cost-resource :health})]} 0.1
                            [(effect 0.013 {:kind :stat-buff :stat :healing-multiplier :amount 1 :duration 1})])))
(each [health? maximum pool] [[false :mp :resource] [true :hp :health]]
  (def result (run {pool (if health? 10 9) :stats (merge (dummy :stats) {maximum (if health? 10 9)})
                    :abilities [(merge spell {:cost-resource (if health? :health :resource)})]} 1.1
                   [(effect 0.013 {:kind :stat-buff :stat maximum :amount 1 :duration 2})]))
  (close 1.013 (first-at result)))

# Healing can make a health-cost spell affordable at once. Incoming damage at
# a predicted deadline must postpone casting; no free resource is credited.
(close 0.013 (first-at (run {:health 10 :abilities [(merge spell {:cost-resource :health})]
                             :stats (merge (dummy :stats) {:hp-regen 0})} 0.1
                            [(effect 0.013 {:kind :heal :amount 1})])))
(close 0.437 (first-at (run {:abilities [(merge spell {:cost-resource :health})]} 0.5
                            [(effect 0.337 {:kind :damage :damage-type :true :amount 0.1})])))
(each [health? pool maximum] [[false :resource :mp] [true :health :hp]]
  (each rate [0 -5]
    (assert (empty? (casts (run {:stats (merge (dummy :stats) {:mp-regen rate :hp-regen rate})
                                 :abilities [(merge spell {:cost-resource (if health? :health :resource)})]} 2)))))
  (assert (empty? (casts (run {:stats (merge (dummy :stats) {maximum (if health? 10 9)})
                               :abilities [(merge spell {:cost-resource (if health? :health :resource)})]} 2)))))
(assert (empty? (casts (run {:strategy {:attacks false :abilities false :movement :hold}} 1))))
(assert (empty? (casts (run {:ranks {:q 0}} 1))))
(assert (empty? (casts (run {:abilities [(merge spell {:range 0})] :position 1000} 1))))
(each dying [0 1]
  (assert (empty? (casts (run {} 0.5 [(effect 0.337 {:kind :damage :damage-type :true :amount 1000} dying)])))))
(close 0.537 (first-at (run {} 0.6 [(effect 0.337 {:kind :control :control :silence :duration 0.2})])))
(def boundary (run {:resource 9.75} 0.25))
(assert (empty? (casts boundary)))
(close 0.25 (first-at (run {:resource 9.75} 0.25001)))
(close 0 ((run {:resource 9.75} 0.25001) :damage))

# Retained Annie Q and source regeneration, with a native-control-friendly 10%
# starting resource. Only the declared starting fraction and window differ.
(def root (string "build/resource-readiness-tests/" (hash/sha256 (os/cryptorand 8))))
(def package (packages/initialize root "build/seed"))
(def player {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items []}
             :strategy {:attacks false :abilities true :priority [:q] :movement :hold}})
(def opponent (merge player {:kind :champion :strategy {:attacks false :abilities false :movement :hold}}))
(def draft {:schema 1 :patch "16.19.1" :snapshot (package :snapshot) :duration 1 :distance 0 :seed 1 :player player :target opponent})
(def compiled (scenario/compile draft))
(def actor (get-in compiled [:actors 0]))
(def ability (find |(= "AnnieQ" ($ :id)) (actor :abilities)))
(def cost (expr/evaluate (ability :cost) {:rank 1 :level 1}))
(def rate (/ (get-in actor [:stats :mp-regen]) 5))
(assert (> rate 0))
(def ready (/ (- cost (* 0.1 (get-in actor [:stats :mp]))) rate))
(def impact (+ ready (ability :cast-time)))
(def definition (merge draft {:duration (+ impact 0.01) :player (merge player {:resource-fraction 0.1})}))
(each [input side] [[definition 0] [(merge definition {:player opponent :target (merge (definition :player) {:kind :champion})}) 1]]
  (def result (scenario/simulate input))
  (assert (= 1 (length (casts result))))
  (close ready (first-at result))
  (def hits (filter |(and (= :damage ($ :kind)) (= "AnnieQ" ($ :source))) (result :trace)))
  (assert (= 1 (length hits)))
  (close impact ((first hits) :at))
  (assert (> (get-in result [:actors side :damage-dealt]) 0))
  (assert (>= (get-in result [:actors side :resource]) 0))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= (package :snapshot) (hash/sha256 (slurp (string (package :directory) "/package.jdn")))))
(when-let [export (os/getenv "PS_RESOURCE_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(util/remove-tree root)
(print "Fixed resource recovery deadlines, independent mana/health arithmetic, rate/cap/heal changes, strict costs, action gates and retained scenario/fitness parity passed.")
