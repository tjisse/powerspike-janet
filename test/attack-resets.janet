(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/tooltip :as tooltip)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :base {:hp 10000 :ad 10 :ap 0}
          :stats {:hp 10000 :mp 20 :ad 10 :ap 0 :armor 0 :mr 0 :attack-speed 1 :crit-chance 0}
          :abilities [] :ranks {:q 1} :position 0 :attack-range 500
          :strategy {:attacks true :abilities false :movement :hold}} (or fields {})))
(def dummy (unit "dummy" {:position 300 :strategy {:attacks false :abilities false :movement :hold}}))
(defn effect [time side data &opt target]
  {:at time :kind :effect :actor side :target (or target side) :source "fixture" :origin (string "fixture/" time) :effect data})
(defn reset [time side] (effect time side {:kind :reset}))
(defn input [events &opt fields duration side]
  {:duration (or duration 1.7) :initial-events events
   :actors (if (= side 1) [dummy (unit "active" fields)] [(unit "active" fields) dummy])})
(defn actions [result kind] (filter |(and (= kind ($ :kind)) (= "active" ($ :actor))) (result :trace)))
(defn starts [result] (map |($ :at) (actions result :attack)))
(defn run [events &opt fields duration side] (engine/simulate (input events fields duration side)))

# Independent start, windup and travel arithmetic, including an in-flight
# first projectile. A reset changes the next start, not the attack in progress.
(each speed [0.638 1 2]
  (each travel [0 1500]
    (each side [0 1]
      (def period (/ 1 speed))
      (def when-reset (+ (* 0.3 period) 0.037))
      (def fields {:stats (merge (dummy :stats) {:attack-speed speed}) :attack-missile-speed travel})
      (def definition (input [(reset when-reset side)] fields (+ when-reset (* 1.3 period) 0.25) side))
      (def result (engine/simulate definition))
      (def hits (filter |(= "attack" ($ :source)) (actions result :damage)))
      (assert (= 3 (length (starts result)) (length hits)))
      (each [expected actual] (map tuple [0 when-reset (+ when-reset period)] (starts result)) (close expected actual))
      (each [start hit] (map tuple (starts result) hits)
        (close (+ start (* 0.3 period) (if (= travel 0) 0 0.2)) (hit :at)))
      (assert (= (result :metrics) ((engine/simulate (merge definition {:trace false})) :metrics))))))

# Resetting during windup preserves the current release and action lock.
(def winding (run [(reset 0.137 0)]))
(each [expected actual] (map tuple [0 0.3 1.3] (starts winding)) (close expected actual))
(close 0.3 ((first (actions winding :damage)) :at))
(def repeated (run [(reset 0.337 0) (reset 0.337 0) (reset 0.4 0)] nil 1.3))
(assert (= 3 (length (starts repeated))))
(each [expected actual] (map tuple [0 0.337 0.637] (starts repeated)) (close expected actual))

# Resets reuse ordinary decisions: control/death take precedence, while silence
# and root continue to permit stationary attacks.
(each kind [:stun :silence :root]
  (def result (run [(reset 0.337 0) (effect 0.337 1 {:kind :control :control kind :duration 0.2} 0)]))
  (close (if (= kind :stun) 0.537 0.337) ((starts result) 1)))
(each dying [0 1]
  (def dead (run [(reset 0.337 0) (effect 0.337 (- 1 dying) {:kind :damage :damage-type :true :amount 10000} dying)]))
  (assert (= 1 (length (starts dead)))))
(def spell {:id "fixture-q" :slot :q :cost 0 :range 500 :cooldown 99 :cast-time 0.04 :missile-speed 0
            :effects [{:kind :damage :damage-type :true :amount 7 :target :enemy :status :estimated}]})
(each lock [0.04 0.4]
  (def priority (run [(reset 0.337 0)] {:abilities [(merge spell {:cast-lock lock})]
                                        :strategy {:attacks true :abilities true :movement :hold :activation {:q {:after 0.337}}}}))
  (close 0.337 ((first (actions priority :cast)) :at))
  (close (+ 0.337 lock) ((starts priority) 1)))
(def disabled (run [(reset 0.337 0)] {:strategy {:attacks false :abilities false :movement :hold}}))
(assert (empty? (starts disabled)))
(close 0.337 (get-in disabled [:actors 0 :attack-ready]))
# A reset of an already-ready attack must not add an unrelated condition check.
(def idle (run [(reset 0.337 0)] {:attack-range 0 :resource 9.664
                                  :stats (merge (dummy :stats) {:mp-regen 5})
                                  :abilities [(merge spell {:cost 10})]
                                  :strategy {:attacks true :abilities true :movement :hold}}))
(close 0.35 ((first (actions idle :cast)) :at))
(assert (= 1 (length (starts (run [(reset 0.337 0)] nil 0.337)))))
(def just-after (run [(reset 0.337 0)] nil 0.33701))
(assert (= 2 (length (starts just-after))))
(close 10 (just-after :damage)) # The second windup has not completed.

# Retained source tags already declare these resets. Cast durations below are
# configured regression inputs, not new claims about champion cast timing.
(def fixture-path "data/combat-fixtures/16.19.1/empowered-attacks.json")
(def manifest (util/read-json (slurp "data/combat-fixtures/16.19.1/manifest.json")))
(assert (= (get-in manifest ["fixture_sha256" "empowered-attacks.json"]) (hash/sha256 (slurp fixture-path))))
(each fixture ((util/read-json (slurp fixture-path)) "cases")
  (when (some |(= "Trait_AttackReset" $) (get-in fixture ["spell" "mSpellTags"] []))
    (def parsed (tooltip/parse (fixture "tooltip") (fixture "spell")))
    (def slot (keyword (fixture "slot")))
    (each cast-time [0 0.1]
      (def ability {:id (fixture "id") :slot slot :cost 0 :cooldown 99 :range 500 :cast-time cast-time
                    :tooltip (fixture "tooltip") :record (fixture "spell") :effects (parsed :effects)})
      (def kit (normalize/semantic-kit (fixture "champion") "16.19.1" {:abilities [ability]}))
      (assert (some |($ :reset) (get-in kit [:abilities 0 :effects])))
      (def result (run [] {:abilities (kit :abilities) :ranks {slot 1}
                           :strategy {:attacks true :abilities true :priority [slot] :movement :hold
                                      :activation {slot {:after 0.337}}}}))
      (close (+ 0.337 cast-time) ((starts result) 1)))))

# A labeled synthetic package exercises delayed resets through compilation,
# optimizer scoring and the copied executable. Champion mechanics are not inferred.
(def root (string "build/attack-reset-tests/" (hash/sha256 (os/cryptorand 8))))
(packages/initialize root "build/seed")
(def source (packages/load "16.19.1"))
(def reset-spell {:id "fixture-reset" :slot :q :name "Synthetic delayed reset" :cost 0 :cost-resource :resource :range 500
                  :cooldown 99 :cast-time 0 :missile-speed 0 :max-rank 5 :available true :checked false
                  :icon-group "spell" :icon "AnnieQ.png" :tooltip "Synthetic scheduler fixture; not champion mechanics."
                  :variables [] :record {} :unresolved ["Synthetic scheduler fixture; not champion mechanics."]
                  :effects [{:kind :reset :target :self :delay 0.337 :status :estimated}]})
(def champion (merge ((source :champion-map) "Annie") {:abilities [reset-spell] :attack-speed-base 1 :attack-speed-ratio 1 :attack-speed-growth 0}))
(def target (merge ((source :champion-map) "Lux") {:abilities [] :base (merge (get-in source [:champion-map "Lux" :base])
                                                                              {:hp 10000 :armor 0 :mr 0 :hp-regen 0})}))
(def bytes (util/encode-data (util/canonical {:schema 1 :parser "6" :patch "16.19.1" :champions [champion target] :items []})))
(def snapshot (hash/sha256 bytes))
(def directory (string root "/patches/16.19.1/" snapshot))
(util/write (string directory "/package.jdn") bytes)
(util/write (string directory "/manifest.json") (util/encode-json {"initial" false "synthetic_attack_reset" true "package_sha256" snapshot}))
(util/write (string root "/patches/16.19.1/current") snapshot)
(packages/initialize root nil)
(def caster {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items []}
             :strategy {:attacks true :abilities true :priority [:q] :movement :hold}})
(def opponent {:champion "Lux" :kind :champion :level 1 :skill-order [:q] :loadout {:items []}
               :strategy {:attacks false :abilities false :movement :hold}})
(def definition {:schema 1 :patch "16.19.1" :snapshot snapshot :duration 0.843 :distance 300 :seed 1 :player caster :target opponent})
(each [input side] [[definition 0] [(merge definition {:player opponent :target (merge caster {:kind :champion})}) 1]]
  (def compiled (scenario/compile input))
  (close 1 (get-in compiled [:actors side :stats :attack-speed]))
  (close 0.3 (get-in compiled [:actors side :windup-fraction]))
  (close 1500 (get-in compiled [:actors side :attack-missile-speed]))
  (def result (scenario/simulate input))
  (def starts (filter |(= :attack ($ :kind)) (result :trace)))
  (assert (= 2 (length starts)))
  (each [expected event] (map tuple [0.01 0.337] starts) (close expected (event :at)))
  (def hits (filter |(and (= :damage ($ :kind)) (= "attack" ($ :source))) (result :trace)))
  (assert (= 2 (length hits)))
  (each [expected event] (map tuple [0.51 0.837] hits) (close expected (event :at)))
  (close (* 2 (get-in compiled [:actors side :stats :ad])) (get-in result [:actors side :damage-dealt]))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= snapshot (hash/sha256 (slurp (string directory "/package.jdn")))))
(when-let [export (os/getenv "PS_RESET_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(util/remove-tree root)
(print "Exact reset wakes, independent windup/travel math, source-tagged empowerments, action gates, both roles and compiled/fitness parity passed.")
