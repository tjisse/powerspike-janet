(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(def spell {:id "fixture-q" :slot :q :cost 0 :cooldown 99 :cast-time 0.04 :missile-speed 0 :range 500
            :effects [{:kind :damage :damage-type :true :amount 10 :target :enemy :status :estimated}]})
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :base {:hp 1000 :mp 1000 :ad 10 :ap 0}
          :stats {:hp 1000 :mp 1000 :ad 10 :ap 0 :armor 0 :mr 0 :attack-speed 1}
          :health 1000 :resource 1000 :abilities [spell] :ranks {:q 1 :w 1} :position 0 :attack-range 500
          :strategy {:attacks false :abilities true :movement :hold :activation {:q {:self-health-below 0.5}}}} (or fields {})))
(def dummy (unit "dummy" {:abilities [] :strategy {:attacks false :abilities false :movement :hold}}))
(defn effect [time target data]
  {:at time :kind :effect :actor (- 1 target) :target target :source "fixture" :origin (string "fixture/" time) :effect data})
(defn hit [time target amount] (effect time target {:kind :damage :damage-type :true :amount amount}))
(defn heal [time target amount] (effect time target {:kind :heal :amount amount}))
(defn input [events &opt fields duration side other]
  {:duration (or duration 0.5) :initial-events events
   :actors (if (= side 1) [(or other dummy) (unit "active" fields)] [(unit "active" fields) (or other dummy)])})
(defn run [events &opt fields duration side other] (engine/simulate (input events fields duration side other)))
(defn casts [result] (filter |(and (= :cast ($ :kind)) (= "active" ($ :actor))) (result :trace)))
(defn first-at [result] ((first (casts result)) :at))
(defn none [result] (assert (empty? (casts result))))

# Inclusive self/target rules react at the actual hit, in both actor roles.
(each side [0 1]
  (each rule [:self-health-below :target-health-below]
    (def victim (if (= rule :self-health-below) side (- 1 side)))
    (def fields {:strategy {:attacks false :abilities true :movement :hold :activation {:q {rule 0.5}}}})
    (def definition (input [(hit 0.137 victim 500)] fields 0.3 side))
    (def result (engine/simulate definition))
    (assert (= 1 (length (casts result))))
    (close 0.137 (first-at result))
    (assert (= (result :metrics) ((engine/simulate (merge definition {:trace false})) :metrics)))
    (close 0.237 (first-at (run [(hit 0.137 victim 499) (hit 0.237 victim 1)] fields 0.4 side)))))
(def both {:strategy {:attacks false :abilities true :movement :hold
                      :activation {:q {:self-health-below 0.5 :target-health-below 0.5}}}})
(close 0.237 (first-at (run [(hit 0.137 0 500) (hit 0.237 1 500)] both)))

# Same-timestamp healing suppresses the queued response, and a later crossing
# can wake it again. Snapshots must also account for regeneration between hits.
(none (run [(hit 0.137 0 500) (heal 0.137 0 100)]))
(close 0.237 (first-at (run [(hit 0.137 0 500) (heal 0.137 0 100) (hit 0.237 0 100)])))
(def regrown (run [(hit 0.137 0 0.137)] {:health 500 :stats (merge (dummy :stats) {:hp-regen 5})
                                         :abilities [(merge spell {:cooldown 0.1})]} 0.3))
(assert (= 2 (length (casts regrown))))
(close 0 (((casts regrown) 0) :at))
(close 0.137 (((casts regrown) 1) :at))

# Existing locks, cooldowns, activation times and resource gates remain binding.
(def locked-fields {:abilities [spell (merge spell {:id "fixture-w" :slot :w :cast-lock 0.4})]})
(def locked (run [(hit 0.137 0 500)] locked-fields))
(close 0.4 ((first (filter |(= "fixture-q" ($ :source)) (casts locked))) :at))
(def healed-lock (run [(hit 0.137 0 500) (heal 0.237 0 100)] locked-fields))
(assert (not (some |(= "fixture-q" ($ :source)) (casts healed-lock))))
(def regrown-lock (run [(hit 0.137 0 500)] (merge locked-fields {:stats (merge (dummy :stats) {:hp-regen 5})})))
(assert (not (some |(= "fixture-q" ($ :source)) (casts regrown-lock))))
(def cooldown (run [(heal 0.1 0 500) (hit 0.137 0 500)] {:health 500 :abilities [(merge spell {:cooldown 0.337})]} 0.4))
(assert (= 2 (length (casts cooldown))))
(close 0.337 (((casts cooldown) 1) :at))
(def delayed {:strategy {:attacks false :abilities true :movement :hold :activation {:q {:self-health-below 0.5 :after 0.337}}}})
(close 0.337 (first-at (run [(hit 0.137 0 500)] delayed)))
(none (run [(hit 0.137 0 500)] {:resource 0 :abilities [(merge spell {:cost 10})]}))
(close 0.5 (first-at (run [(hit 0.137 0 500)] {:resource 9.5 :stats (merge (dummy :stats) {:mp-regen 5})
                                               :abilities [(merge spell {:cost 10})]} 0.55)))
(each control [:stun :silence]
  (close 0.337 (first-at (run [(hit 0.137 0 500) (effect 0.137 0 {:kind :control :control control :duration 0.2})]))))
(each dying [0 1]
  (none (run [(hit 0.137 0 500) (hit 0.137 dying 1000)])))

# Health costs notify self rules after setting the cast lock, and notify the
# other participant's target rule when the payer spends health.
(def payment (merge spell {:id "fixture-w" :slot :w :cost-resource :health :cost 500 :cast-lock 0.4}))
(def paid (run [] {:abilities [spell payment]}))
(def paid-q (filter |(= "fixture-q" ($ :source)) (casts paid)))
(assert (= 1 (length paid-q)))
(close 0.4 ((first paid-q) :at))
(def payer (unit "payer" {:abilities [(merge payment {:id "payment" :slot :q :cast-lock 0.04})]
                          :strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.137}}}}))
(close 0.137 (first-at (run [] {:strategy {:attacks false :abilities true :movement :hold
                                           :activation {:q {:target-health-below 0.5}}}} 0.3 0 payer)))
(each rule [:self-health-below :target-health-below]
  (def victim (if (= rule :self-health-below) 0 1))
  (close 0.137 (first-at (run [(effect 0.137 victim {:kind :stat-buff :stat :hp :amount 1000 :duration 1})]
                              {:strategy {:attacks false :abilities true :movement :hold :activation {:q {rule 0.5}}}}))))
(def expired-lock (run [(effect 0.137 0 {:kind :stat-buff :stat :hp :amount 1000 :duration 0.1})] locked-fields))
(assert (not (some |(= "fixture-q" ($ :source)) (casts expired-lock))))

# Priority/coalescing, actual post-shield damage, immunity/parry/miss and disabled
# or unlearned abilities. A health event is not an unconditional extra decision.
(def priority (run [(hit 0.137 0 250) (hit 0.137 0 250) (hit 0.137 0 0)]
                   {:abilities [spell (merge spell {:id "fixture-w" :slot :w})]
                    :strategy {:attacks false :abilities true :priority [:w :q] :movement :hold
                               :activation {:q {:self-health-below 0.5} :w {:self-health-below 0.5}}}}))
(assert (= ["fixture-w" "fixture-q"] (tuple ;(map |($ :source) (casts priority)))))
(close 0.137 (((casts priority) 0) :at))
(close 0.177 (((casts priority) 1) :at))
(none (run [(effect 0 0 {:kind :shield :amount 200 :duration 1}) (hit 0.137 0 600)]))
(none (run [(hit 0.137 0 600)] {:spell-immune true}))
(def parry {:at 0 :kind :effect :actor 0 :target 0 :source "parry" :origin "parry"
            :effect {:kind :parry :duration 0.3 :source-kinds [:champion]}})
(none (run [parry (hit 0.137 0 600)]))
(none (run [] {:stats (merge (dummy :stats) {:ad 600})
               :strategy {:attacks true :abilities true :hit-chance 0 :movement :hold :activation {:q {:target-health-below 0.5}}}}))
(none (run [(hit 0.137 0 500)] {:strategy {:attacks false :abilities false :movement :hold :activation {:q {:self-health-below 0.5}}}}))
(none (run [(hit 0.137 0 500)] {:ranks {:q 0}}))
(none (run [(hit 0.137 0 500)] {:position 1000}))
(def unchanged (run [(hit 0.037 0 1)] {:health 100 :resource 9.98 :stats (merge (dummy :stats) {:mp-regen 5})
                                       :abilities [(merge spell {:cost {:op :stat :stat :ad :formula 0}})]}))
(close 0.05 (first-at unchanged))
(none (run [(hit 0.137 0 500)] nil 0.137))
(def just-after (run [(hit 0.137 0 500)] nil 0.13701))
(close 0.137 (first-at just-after))
(close 0 (just-after :damage))

# Source-backed target-health response to an ordinary projectile already in
# flight. No synthetic abilities or champion values are added to the package.
(def root (string "build/health-activation-tests/" (hash/sha256 (os/cryptorand 8))))
(def package (packages/initialize root "build/seed"))
(def player {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items []}
             :strategy {:attacks true :abilities true :priority [:q] :movement :hold :activation {:q {:target-health-below 0.95}}}})
(def opponent (merge player {:kind :champion :strategy {:attacks false :abilities false :movement :hold}}))
(def draft {:schema 1 :patch "16.19.1" :snapshot (package :snapshot) :duration 2 :distance 200 :seed 1 :player player :target opponent})
(def compiled (scenario/compile draft))
(def actor (get-in compiled [:actors 0]))
(def ability (find |(= "AnnieQ" ($ :id)) (actor :abilities)))
(def ready (+ (/ (actor :windup-fraction) (get-in actor [:stats :attack-speed])) (/ 200 (actor :attack-missile-speed))))
(def impact (+ ready (ability :cast-time) (/ 200 (ability :missile-speed))))
(def definition (merge draft {:duration (+ impact 0.005)}))
(each [input side] [[definition 0] [(merge definition {:player opponent :target (merge player {:kind :champion})}) 1]]
  (def result (scenario/simulate input))
  (def shots (filter |(and (= :damage ($ :kind)) (= "attack" ($ :source))) (result :trace)))
  (def response (filter |(and (= :cast ($ :kind)) (= "AnnieQ" ($ :source))) (result :trace)))
  (def hits (filter |(and (= :damage ($ :kind)) (= "AnnieQ" ($ :source))) (result :trace)))
  (assert (= 1 (length shots) (length response) (length hits)))
  (close ready ((first shots) :at))
  (close ((first shots) :at) ((first response) :at))
  (close impact ((first hits) :at))
  (assert (> (get-in result [:actors side :damage-dealt]) ((first shots) :damage)))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= (package :snapshot) (hash/sha256 (slurp (string (package :directory) "/package.jdn")))))
(when-let [export (os/getenv "PS_HEALTH_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(util/remove-tree root)
(print "Health activation crossings, self/target rules, healing/regen rechecks, costs/caps, action gates and retained projectile response/fitness parity passed.")
