(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(defn unit [id speed &opt extra]
  (merge {:id id :kind :champion :level 1 :base {:ad 10 :ap 0 :hp 10000}
          :stats {:hp 10000 :mp 20 :ad 10 :ap 0 :armor 0 :mr 0 :attack-speed speed :crit-chance 0 :crit-damage 1.75}
          :position 0 :attack-range 500 :ranks {:q 1}
          :strategy {:attacks true :abilities false :movement :hold}} (or extra {})))
(def dummy (unit "dummy" 0 {:position 300 :strategy {:attacks false :abilities false :movement :hold}}))
(defn attacks [outcome] (filter |(= :attack ($ :kind)) (outcome :trace)))
(defn damage-hits [outcome] (filter |(and (= :damage ($ :kind)) (= "attack" ($ :source))) (outcome :trace)))

# Independent constant-speed reference: start n / AS, impact (n + windup) / AS
# plus travel. Exercise awkward periods and both actor positions in the queue.
(each speed [0.5 0.638 0.658 1 1.3 2 2.5]
  (each travel-speed [0 1500]
    (each side [0 1]
      (def attacker (unit "attacker" speed {:attack-missile-speed travel-speed}))
      (def actors (if (= side 0) [attacker dummy] [dummy attacker]))
      (def input {:duration (+ (/ 5 speed) 0.00001) :actors actors})
      (def result (engine/simulate input))
      (def starts (attacks result))
      (def hits (damage-hits result))
      (assert (= 6 (length starts)))
      (assert (= 5 (length hits)))
      (eachp [index event] starts (close (/ index speed) (event :at)))
      (eachp [index event] hits
        (close (+ (/ (+ index 0.3) speed) (if (= travel-speed 0) 0 (/ 300 travel-speed))) (event :at)))
      (assert (= (result :metrics) ((engine/simulate (merge input {:trace false})) :metrics))))))

# This short window previously lost the second attack to a 50ms polling delay.
(defn short [duration]
  (engine/simulate {:duration duration :actors [(unit "attacker" 2) (merge dummy {:position 0})]}))
(assert (= 1 (length (damage-hits (short 0.65)))))
(assert (= 2 (length (damage-hits (short 0.65001)))))
(close 0.5 ((get (attacks (short 0.65001)) 1) :at))

# A ready-time wake goes through ordinary decisions: spells keep priority,
# extended cast locks remain binding, and same-timestamp control blocks attacks.
(def spell {:id "fixture-q" :slot :q :cast-time 0.1 :cost 0 :cooldown 99 :range 500
            :effects [{:kind :damage :damage-type :true :amount 7 :target :enemy :status :estimated}]})
(def priority (engine/simulate {:duration 0.8 :actors [(unit "attacker" 2 {:abilities [spell]
                                                                           :strategy {:attacks true :abilities true :movement :hold
                                                                                      :activation {:q {:after 0.5}}}})
                                                       (merge dummy {:position 0})]}))
(close 0.5 ((first (filter |(= :cast ($ :kind)) (priority :trace))) :at))
(close 0.6 (((attacks priority) 1) :at))
(def locked (engine/simulate {:duration 1 :actors [(unit "attacker" 2 {:abilities [(merge spell {:cast-lock 0.4})]
                                                                       :strategy {:attacks true :abilities true :movement :hold
                                                                                  :activation {:q {:after 0.2}}}})
                                                   (merge dummy {:position 0})]}))
(def cast ((first (filter |(= :cast ($ :kind)) (locked :trace))) :at))
(close (+ cast 0.4) (((attacks locked) 1) :at))
(def controlled (engine/simulate {:duration 0.9 :actors [(unit "attacker" 2) (merge dummy {:position 0})]
                                  :initial-events [{:at 0.5 :kind :effect :actor 1 :target 0 :source "fixture" :origin "stun"
                                                    :effect {:kind :control :control :stun :duration 0.2}}]}))
(assert (= 2 (length (attacks controlled))))
(assert (<= 0.7 (((attacks controlled) 1) :at) 0.750001))
(each dying [0 1]
  (def killed (engine/simulate {:duration 0.9 :actors [(unit "attacker" 2) (merge dummy {:position 0})]
                                :initial-events [{:at 0.5 :kind :effect :actor (- 1 dying) :target dying :source "fixture" :origin "fatal"
                                                  :effect {:kind :damage :damage-type :true :amount 10000}}]}))
  (assert (= 1 (length (attacks killed))))
  (close 0.5 (get-in killed [:actors dying :dead-at])))

# Changing attack speed does not rescale the period/windup already sampled at
# start. The next attack samples the new speed, including after buff expiry.
(def changing (engine/simulate {:duration 2.4 :actors [(unit "attacker" 1) (merge dummy {:position 0})]
                                :initial-events [{:at 0.8 :kind :effect :actor 0 :target 0 :source "fixture" :origin "speed"
                                                  :effect {:kind :stat-buff :stat :attack-speed :amount 1 :duration 1}}]}))
(each [expected event] (map tuple [0 1 1.5 2] (attacks changing)) (close expected (event :at)))
(assert (= 4 (length (attacks changing))))

# Source-backed cached scenario: the corrected cadence moves the fourth Human
# Nidalee hit inside 5.3 seconds. Its projectile and windup policies are unchanged.
(def root (string "build/attack-cadence-tests/" (hash/sha256 (os/cryptorand 8))))
(def package (packages/initialize root "build/seed"))
(def player {:champion "Nidalee" :form "human" :level 1 :loadout {:items []} :skill-order [:q]
             :strategy {:attacks true :abilities false :movement :hold}})
(def definition {:schema 1 :patch "16.19.1" :snapshot (package :snapshot) :duration 5.3 :distance 300 :seed 1
                 :player player :target {:kind :practice :hp 10000 :armor 0 :mr 0}})
(def compiled (scenario/compile definition))
(def speed (get-in compiled [:actors 0 :stats :attack-speed]))
(close 0.638 speed)
(def result (scenario/simulate definition))
(assert (= 4 (length (result :events))))
(eachp [index event] (result :events) (close (+ (/ (+ index 0.3) speed) (/ 300 2500)) (event :at)))
(close (* 4 (get-in compiled [:actors 0 :stats :ad])) (result :damage))
(assert (= (result :metrics) ((scenario/fitness definition) :metrics)))
(def reversed (merge definition {:player (merge player {:strategy {:attacks false :abilities false :movement :hold}})
                                 :target (merge player {:kind :champion})}))
(def incoming (scenario/simulate reversed))
(assert (= 4 (length (damage-hits incoming))))
(eachp [index event] (damage-hits incoming) (close (+ (/ (+ index 0.3) speed) (/ 300 2500)) (event :at)))
(assert (= (incoming :metrics) ((scenario/fitness reversed) :metrics)))
(assert (= (package :snapshot) (hash/sha256 (slurp (string (package :directory) "/package.jdn")))))
(util/remove-tree root)
(print "Exact attack deadlines, independent cadence/travel arithmetic, both roles, endpoint boundaries, cast/control priority, speed changes and source-backed optimizer parity passed.")
