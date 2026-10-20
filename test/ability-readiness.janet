(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(def spell {:id "fixture-q" :slot :q :cast-time 0.04 :cost 0 :cooldown 0.731 :range 500
            :effects [{:kind :damage :damage-type :true :amount 10 :target :enemy :status :estimated}]})
(defn unit [id &opt extra]
  (merge {:id id :kind :champion :level 1 :base {:hp 10000 :ad 10 :ap 0}
          :stats {:hp 10000 :mp 10000 :ad 10 :ap 0 :armor 0 :mr 0 :ability-haste 0 :attack-speed 0}
          :abilities [spell] :ranks {:q 1 :w 1} :position 0 :attack-range 500
          :strategy {:attacks false :abilities true :priority [:q :w] :movement :hold}} (or extra {})))
(def dummy (unit "dummy" {:abilities [] :strategy {:attacks false :abilities false :movement :hold}}))
(defn casts [result] (filter |(= :cast ($ :kind)) (result :trace)))
(defn run [actor duration &opt events side]
  (engine/simulate {:duration duration :actors (if (= side 1) [dummy actor] [actor dummy]) :initial-events (or events [])}))

# Independent arithmetic from configured cooldown/haste and cooldown origin.
(each haste [0 37 100]
  (each unhasted [false true]
    (each origin [:start :end]
      (each side [0 1]
        (def cooldown (/ 0.731 (if unhasted 1 (+ 1 (/ haste 100)))))
        (def period (+ cooldown (if (= origin :end) 0.04 0)))
        (def actor (unit "caster" {:stats (merge (dummy :stats) {:ability-haste haste})
                                   :abilities [(merge spell {:unhasted unhasted :cooldown-start origin})]}))
        (def duration (+ (* 3 period) 0.05))
        (def result (run actor duration nil side))
        (assert (= 4 (length (casts result))))
        (eachp [index event] (casts result) (close (* index period) (event :at)))
        (def input {:duration duration :actors (if (= side 1) [dummy actor] [actor dummy])})
        (assert (= (result :metrics) ((engine/simulate (merge input {:trace false})) :metrics)))))))

# Each ability retains its own phase; a wake for Q cannot postpone W.
(def phased (run (unit "caster" {:abilities [(merge spell {:cooldown 0.333})
                                             (merge spell {:id "fixture-w" :slot :w :cooldown 0.333})]}) 1.05))
(each [id offset] [["fixture-q" 0] ["fixture-w" 0.04]]
  (def selected (filter |(= id ($ :source)) (casts phased)))
  (assert (= 4 (length selected)))
  (eachp [index event] selected (close (+ offset (* index 0.333)) (event :at))))

# Fixed activation deadlines preserve declared priority and extended cast locks.
(def activated (run (unit "caster" {:abilities [spell (merge spell {:id "fixture-w" :slot :w})]
                                    :strategy {:attacks false :abilities true :priority [:q :w] :movement :hold
                                               :activation {:q {:after 0.337}}}}) 0.5))
# W can cast at zero; Q must become eligible at exactly its configured time.
(close 0.337 ((first (filter |(= "fixture-q" ($ :source)) (casts activated))) :at))
(def tied (run (unit "caster" {:abilities [spell (merge spell {:id "fixture-w" :slot :w})]
                               :strategy {:attacks false :abilities true :priority [:q :w] :movement :hold
                                          :activation {:q {:after 0.337} :w {:after 0.337}}}}) 0.5))
(assert (= ["fixture-q" "fixture-w"] (tuple ;(map |($ :source) (casts tied)))))
(close 0.337 (((casts tied) 0) :at))
(close 0.377 (((casts tied) 1) :at))
(def locked (run (unit "caster" {:abilities [(merge spell {:cooldown 0.173 :cast-lock 0.4})]}) 0.81))
(each [expected event] (map tuple [0 0.4 0.8] (casts locked)) (close expected (event :at)))
(assert (= 3 (length (casts locked))))
(def boundary-actor (unit "caster" {:resource 20 :abilities [(merge spell {:cost 10})]}))
(assert (= 1 (length (casts (run boundary-actor 0.731)))))
(def just-after (run boundary-actor 0.73101))
(assert (= 2 (length (casts just-after))))
(close 0 (just-after :resource-left))
(close 10 (just-after :damage)) # Second cast started, but its hit lies outside the window.

# Once a cooldown has elapsed, blocked resources must resume periodic checks,
# not retry forever at the same timestamp. Health costs cannot kill the caster.
(def drained (run (unit "caster" {:resource 20 :abilities [(merge spell {:cost 10 :cooldown 0.333})]}) 2))
(assert (= 2 (length (casts drained))))
(close 0 (drained :resource-left))
(def health (run (unit "caster" {:health 20 :abilities [(merge spell {:cost 10 :cost-resource :health :cooldown 0.333})]}) 1))
(assert (= 1 (length (casts health))))
(close 10 (get-in health [:actors 0 :health]))
(def disabled (run (unit "caster" {:strategy {:attacks false :abilities false :priority [:q] :movement :hold}}) 1))
(assert (empty? (casts disabled)))
(def unlearned (run (unit "caster" {:ranks {:q 0}}) 1))
(assert (empty? (casts unlearned)))

# A short main cooldown must not bypass an active recast's own delay.
(def recast (run (unit "caster" {:abilities [(merge spell {:cooldown 0.173 :recast {:window 2 :count 2 :delay 0.37 :cost 0}})]}) 0.75))
(assert (= 3 (length (casts recast))))
(each [expected event] (map tuple [0 0.37 0.74] (casts recast)) (close expected (event :at)))
(def expires-at-ready (run (unit "caster" {:abilities [(merge spell {:cooldown 99 :recast {:window 0.5 :count 1 :delay 0.5 :cost 0}})]}) 0.6))
(assert (= 1 (length (casts expires-at-ready))))
(each cooldown [0.3 0.7]
  (def expired (run (unit "caster" {:resource 20 :abilities [(merge spell {:cost 10 :cooldown cooldown
                                                                           :recast {:window 0.5 :count 1 :delay 0.6 :cost 0}})]}) 0.8))
  (assert (= 2 (length (casts expired))))
  (close (max 0.5 cooldown) (((casts expired) 1) :at))
  (each event (casts expired) (close 10 (event :cost))))

# Charge recovery is processed before its readiness check at the same timestamp.
(def charged-spell (merge spell {:cooldown 99 :max-charges 2 :charge-delay 0.173 :recharge-time 0.637}))
(def charged (run (unit "caster" {:abilities [charged-spell]}) 1.3))
(assert (= 4 (length (casts charged))))
(each [expected event] (map tuple [0 0.173 0.637 1.274] (casts charged)) (close expected (event :at)))
(def full (run (unit "caster" {:resource 10 :abilities [(merge charged-spell {:cost 10 :max-charges 1})]}) 1))
(assert (= 1 (length (casts full))))
(assert (= false (get-in full [:actors 0 :charges "fixture-q" :recovering])))
(assert (nil? (get-in full [:actors 0 :charges "fixture-q" :next-recharge])))
(close 1 (get-in full [:actors 0 :charges "fixture-q" :available]))

# Same-timestamp silence/death still precede decisions at a cooldown boundary.
(def silenced (run (unit "caster" {:abilities [(merge spell {:cooldown 0.333})]}) 0.6
                   [{:at 0.333 :kind :effect :actor 1 :target 0 :source "silence" :origin "silence"
                     :effect {:kind :control :control :silence :duration 0.2}}]))
(assert (= 2 (length (casts silenced))))
(assert (<= 0.533 (((casts silenced) 1) :at) 0.583001))
(each dying [0 1]
  (def killed (run (unit "caster" {:abilities [(merge spell {:cooldown 0.333})]}) 1
                   [{:at 0.333 :kind :effect :actor (- 1 dying) :target dying :source "fatal" :origin "fatal"
                     :effect {:kind :damage :damage-type :true :amount 10000}}]))
  (assert (= 1 (length (casts killed)))))

# Source-backed cached scenario and optimizer parity: the retained Annie Q
# subset plus Ionian Boots, with four casts at the independent hasted interval.
(def root (string "build/ability-readiness-tests/" (hash/sha256 (os/cryptorand 8))))
(def package (packages/initialize root "build/seed"))
(def player {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items ["3158"]}
             :strategy {:attacks false :abilities true :priority [:q] :movement :hold}})
(def definition {:schema 1 :patch "16.19.1" :snapshot (package :snapshot) :duration 12 :distance 300 :seed 1
                 :player player :target {:kind :practice :hp 10000 :armor 0 :mr 0}})
(def compiled (scenario/compile definition))
(def haste (get-in compiled [:actors 0 :stats :ability-haste]))
(assert (> haste 0))
(def period (/ 4 (+ 1 (/ haste 100))))
(each input [definition (merge definition {:player (merge player {:strategy {:attacks false :abilities false :movement :hold}})
                                           :target (merge player {:kind :champion})})]
  (def result (scenario/simulate input))
  (def selected (filter |(= "AnnieQ" ($ :source)) (casts result)))
  (assert (= 4 (length selected)))
  (eachp [index event] selected (close (* index period) (event :at)))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= (package :snapshot) (hash/sha256 (slurp (string (package :directory) "/package.jdn")))))
(util/remove-tree root)
(print "Exact cooldown/recast/charge/activation deadlines, independent haste math, cast/resource/control gates and cached scenario/optimizer parity passed.")
