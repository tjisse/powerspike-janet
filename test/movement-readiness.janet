(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(def spell {:id "fixture-q" :slot :q :cost 0 :cooldown 99 :cast-time 0.04 :missile-speed 0 :range 120
            :effects [{:kind :damage :damage-type :true :amount 10 :target :enemy :status :estimated}]})
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :base {:hp 10000 :ad 10 :ap 0}
          :stats {:hp 10000 :mp 1000 :ad 10 :ap 0 :armor 0 :mr 0 :attack-speed 1 :move-speed 100}
          :abilities [spell] :ranks {:q 1 :w 1} :position 0 :attack-range 100
          :strategy {:attacks true :abilities false :movement :approach}} (or fields {})))
(def dummy (unit "dummy" {:position 133.7 :abilities [] :strategy {:attacks false :abilities false :movement :hold}}))
(defn input [&opt fields events duration side other]
  {:duration (or duration 0.9) :initial-events (or events [])
   :actors (if (= side 1) [(or other dummy) (unit "active" fields)] [(unit "active" fields) (or other dummy)])})
(defn run [&opt fields events duration side other] (engine/simulate (input fields events duration side other)))
(defn actions [result &opt kind]
  (filter |(and (= (or kind :attack) ($ :kind)) (= "active" ($ :actor))) (result :trace)))
(defn first-at [result &opt kind] ((first (actions result kind)) :at))
(defn effect [time side data]
  {:at time :kind :effect :actor (- 1 side) :target side :source "fixture-motion" :origin (string "fixture/" time) :effect data})
(defn control [time side kind duration]
  (effect time side {:kind :control :control kind :duration duration}))
(def spell-strategy {:attacks false :abilities true :priority [:q] :movement :approach})

# Independent distance / relative speed arithmetic, reversed participant order,
# a moving target entering a stationary actor's range, and trace-free parity.
(each side [0 1]
  (def definition (input nil nil nil side))
  (def result (engine/simulate definition))
  (close (/ (- 133.7 100) 100) (first-at result))
  (close 33.7 (get-in result [:actors side :position]))
  (assert (= (result :metrics) ((engine/simulate (merge definition {:trace false})) :metrics)))
  (close 0.137 (first-at (run {:strategy spell-strategy} nil nil side) :cast))
  (def approaching (merge dummy {:attack-range 0 :strategy {:attacks false :abilities false :movement :approach}}))
  (close 0.337 (first-at (run {:strategy {:attacks true :abilities false :movement :hold}} nil nil side approaching)))
  (def both (run nil nil nil side (merge dummy {:strategy {:attacks false :abilities false :movement :approach}})))
  (close (/ 33.7 200) (first-at both))
  (close (/ 33.7 2) (get-in both [:actors side :position])))

# Range-limited steering stops at the chosen distance instead of overshooting
# at the next poll. Hold-range retains its one-unit start hysteresis.
(each [distance desired] [[133.7 100] [67.3 100] [100.5 100]]
  (def result (run {:strategy {:attacks false :abilities false :movement :hold-range :preferred-range desired}}
                   nil 0.9 0 (merge dummy {:position distance})))
  (close (if (= distance 100.5) 0 (- distance desired)) (get-in result [:actors 0 :position])))
(def unequal (run {:attack-range 80} nil 0.9 0
                  (merge dummy {:position 167 :stats (merge (dummy :stats) {:move-speed 200})
                                :strategy {:attacks true :abilities false :movement :approach}})))
(close (+ (/ 67 300) (/ 20 100)) (first-at unequal))
(close (/ 67 300) ((first (filter |(and (= :attack ($ :kind)) (= "dummy" ($ :actor))) (unequal :trace))) :at))
(def contact (run {:attack-range 0 :strategy {:attacks false :abilities false :movement :approach}} nil 1 0
                  (merge dummy {:attack-range 0 :strategy {:attacks false :abilities false :movement :approach}})))
(close (/ 133.7 2) (get-in contact [:actors 0 :position]))
(close (get-in contact [:actors 0 :position]) (get-in contact [:actors 1 :position]))
# Chasing must integrate against the target's new position, rather than
# clamping each step to its old position and falling permanently behind.
(def chase (run {:attack-range 0 :stats (merge (dummy :stats) {:move-speed 200})}
                nil 1.4 0 (merge dummy {:position 33.7 :strategy {:attacks false :abilities false :movement :hold-range :preferred-range 1000}})))
(close (/ 33.7 (- 200 100)) (first-at chase))
(each sign [-1 1]
  (def mirrored (run nil nil nil 0 (merge dummy {:position (* sign 133.7)})))
  (close 0.337 (first-at mirrored))
  (close (* sign 33.7) (get-in mirrored [:actors 0 :position])))
(def separate (run {:strategy {:attacks false :abilities false :movement :hold-range :preferred-range 100}}
                   nil 1 0 (merge dummy {:position 0 :strategy {:attacks false :abilities false :movement :hold-range :preferred-range 100}})))
(close -50 (get-in separate [:actors 0 :position]))
(close 50 (get-in separate [:actors 1 :position]))

# Speeds and controls change between polls. Superseded forecasts may wake a
# decision but cannot cast early or retain a second stream of actions.
(each side [0 1]
  (close 0.437 (first-at (run nil [(effect 0.113 side {:kind :control :control :slow :strength 0.5 :duration 0.2})] nil side)))
  (close 0.237 (first-at (run nil [(effect 0.113 side {:kind :stat-buff :stat :move-speed :amount 100 :duration 0.1})] nil side)))
  (close 0.537 (first-at (run nil [(control 0.113 side :root 0.2)] nil side)))
  (close 0.437 (first-at (run nil [(control 0.113 side :root 0.5) (effect 0.213 side {:kind :cleanse :controls [:root]})] nil side)))
  (close 0.337 (first-at (run nil [(control 0.113 side :silence 0.2)] nil side)))
  (close 0.537 (first-at (run nil [(control 0.337 side :stun 0.2)] nil side)))
  (def moving-target (merge dummy {:attack-range 0 :strategy {:attacks false :abilities false :movement :approach}}))
  (close 0.437 (first-at (run {:strategy {:attacks true :abilities false :movement :hold}}
                              [(effect 0.113 (- 1 side) {:kind :control :control :slow :strength 0.5 :duration 0.2})]
                              nil side moving-target))))

# Motion resumes at a cast-lock boundary even when there is no action to use.
(def self-spell (merge spell {:range 0 :cast-lock 0.137 :effects [{:kind :shield :amount 1 :duration 1 :target :self :status :estimated}]}))
(def locked (run {:abilities [self-spell] :strategy {:attacks true :abilities true :movement :approach}}))
(close (+ 0.137 0.337) (first-at locked))
# Ability priority, delayed activation, resource readiness and health rules
# remain action gates. A self-only spell needs no range forecast.
(close 0.137 (first-at (run {:strategy (merge spell-strategy {:attacks true})}) :cast))
(close 0.377 (first-at (run {:strategy (merge spell-strategy {:attacks true})})))
(close 0.237 (first-at (run {:strategy (merge spell-strategy {:activation {:q {:after 0.237}}})}) :cast))
(close 0.237 (first-at (run {:resource 0 :stats (merge (dummy :stats) {:mp-regen 5})
                             :abilities [(merge spell {:cost 0.237})] :strategy spell-strategy}) :cast))
(assert (empty? (actions (run {:resource 0 :abilities [(merge spell {:cost 10})] :strategy spell-strategy}) :cast)))
(assert (empty? (actions (run {:ranks {:q 0} :strategy spell-strategy}) :cast)))
(assert (empty? (actions (run {:strategy (merge spell-strategy {:activation {:q {:self-health-below 0.5}}})}) :cast)))
(each dying [0 1]
  (assert (empty? (actions (run nil [(effect 0.337 dying {:kind :damage :damage-type :true :amount 10000})])))))
(assert (empty? (actions (run nil nil 0.337))))
(close 0.337 (first-at (run nil nil 0.33701)))
# Stat-dependent ranges forecast between events; continuously changing health
# ranges keep polling instead of freezing their starting value.
(close 0.137 (first-at (run {:abilities [(merge spell {:range {:op :stat :stat :ad :formula 0}})]
                             :attack-range 0 :stats (merge (dummy :stats) {:ad 120}) :strategy spell-strategy}) :cast))
(close 0.15 (first-at (run {:health 120 :abilities [(merge spell {:range {:op :stat :stat :health :formula 0}})]
                            :attack-range 0 :strategy spell-strategy}) :cast))

# Retained champion data: an unmodified Annie Q approaches from 700 to 625.
# This is a software regression, not measured game movement or reaction time.
(def root (string "build/movement-readiness-tests/" (hash/sha256 (os/cryptorand 8))))
(def package (packages/initialize root "build/seed"))
(def player {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items []} :strategy spell-strategy})
(def opponent (merge player {:kind :champion :strategy {:attacks false :abilities false :movement :hold}}))
(def draft {:schema 1 :patch "16.19.1" :snapshot (package :snapshot) :duration 2 :distance 700 :seed 1 :player player :target opponent})
(def actor (get-in (scenario/compile draft) [:actors 0]))
(def ability (find |(= "AnnieQ" ($ :id)) (actor :abilities)))
(def range (actor :attack-range))
(def ready (/ (- 700 range) (get-in actor [:stats :move-speed])))
(def impact (+ ready (ability :cast-time) (/ range (ability :missile-speed))))
(def definition (merge draft {:duration (+ impact 0.005)}))
(each [input side] [[definition 0] [(merge definition {:player opponent :target (merge player {:kind :champion})}) 1]]
  (def result (scenario/simulate input))
  (def starts (filter |(= :cast ($ :kind)) (result :trace)))
  (def hits (filter |(= :damage ($ :kind)) (result :trace)))
  (assert (= 1 (length starts) (length hits)))
  (close ready ((first starts) :at))
  (close impact ((first hits) :at))
  (close (- 700 range) (if (= side 0) (get-in result [:actors side :position]) (- 700 (get-in result [:actors side :position]))))
  (assert (> (get-in result [:actors side :damage-dealt]) 0))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= (package :snapshot) (hash/sha256 (slurp (string (package :directory) "/package.jdn")))))
(when-let [export (os/getenv "PS_MOVEMENT_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(util/remove-tree root)
(print "Exact movement/range deadlines, relative motion, stopping distances, speed/control changes, action gates, retained source travel and fitness parity passed.")
