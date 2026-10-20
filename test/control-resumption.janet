(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(def spell {:id "fixture-q" :slot :q :name "Synthetic timing spell" :cast-time 0.04 :missile-speed 0 :cost 0 :cooldown 0.173 :range 500
            :effects [{:kind :damage :damage-type :true :amount 10 :target :enemy :status :estimated}]})
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :base {:hp 10000 :ad 10 :ap 0}
          :stats {:hp 10000 :mp 10000 :ad 10 :ap 0 :armor 0 :mr 0 :attack-speed 1 :move-speed 100}
          :abilities [spell] :ranks {:q 1} :position 0 :attack-range 500
          :strategy {:attacks false :abilities true :movement :hold}} (or fields {})))
(def dummy (unit "dummy" {:abilities [] :strategy {:attacks false :abilities false :movement :hold}}))
(defn effect [time side data]
  {:at time :kind :effect :actor (- 1 side) :target side :source "fixture-control" :origin (string "fixture/" time)
   :effect data})
(defn control [time side kind duration]
  (effect time side {:kind :control :control kind :duration duration}))
(defn run [events &opt fields duration side]
  (def index (or side 0))
  (engine/simulate {:duration (or duration 0.8) :initial-events events
                    :actors (if (= index 0) [(unit "active" fields) dummy] [dummy (unit "active" fields)])}))
(defn actions [result kind] (filter |(and (= kind ($ :kind)) (= "active" ($ :actor))) (result :trace)))
(defn starts [result kind] (map |($ :at) (actions result kind)))

# All modeled action-blocking controls release at their actual expiry, even
# when application and expiry both fall between consecutive decision polls.
(each side [0 1]
  (each kind [:stun :charm :fear :airborne :suppression :silence]
    (each length [0.013 0.337]
      (def expires (+ 0.001 length))
      (def result (run [(control 0.001 side kind length)]
                       {:strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.005}}}}
                       0.6 side))
      (close expires ((starts result :cast) 0))
      (close length (get-in result [:actors side :control-time]))
      (eachp [index event] (actions result :cast) (close (+ expires (* index 0.173)) (event :at))))))

# Tenacity changes the scheduled duration, except for the existing airborne
# and suppression exemptions. The duration policy itself is unchanged.
(each kind [:stun :silence :airborne :suppression]
  (def result (run [(control 0.001 0 kind 0.337)]
                   {:stats (merge (dummy :stats) {:tenacity 0.37})
                    :strategy {:attacks false :abilities true :movement :hold :activation {:q {:after 0.005}}}}))
  (close (+ 0.001 (* 0.337 (if (some |(= kind $) [:airborne :suppression]) 1 0.63))) ((starts result :cast) 0)))

# Same-type refresh and different overlapping controls cannot release early.
(each events [[(control 0 0 :stun 0.137) (control 0.1 0 :stun 0.237)]
              [(control 0 0 :stun 0.137) (control 0.1 0 :silence 0.237)]]
  (def result (run events))
  (close 0.337 ((starts result :cast) 0))
  (close 0.337 (get-in result [:actors 0 :control-time])))
# Reapplication at the exact expiry wins over the requested priority-30 decision.
(def reapplied (run [(control 0 0 :stun 0.137) (control 0.137 0 :stun 0.2)]))
(close 0.337 ((starts reapplied :cast) 0))

# Cleanse resumes at application, while remaining controls and cast locks bind.
(def cleanse (effect 0.137 0 {:kind :cleanse :controls [:stun]}))
(def cleaned (run [(control 0 0 :stun 0.7) cleanse]))
(close 0.137 ((starts cleaned :cast) 0))
(close 0.137 (get-in cleaned [:actors 0 :control-time]))
(eachp [index event] (actions cleaned :cast) (close (+ 0.137 (* index 0.173)) (event :at)))
(def partial (run [(control 0 0 :stun 0.7) (control 0 0 :silence 0.337) cleanse]))
(close 0.337 ((starts partial :cast) 0))
(def locked (run [(control 0.001 0 :silence 0.136)] {:abilities [(merge spell {:cast-lock 0.4})]} 0.85))
(assert (= 3 (length (actions locked :cast))))
(each [expected actual] (map tuple [0 0.4 0.8] (starts locked :cast)) (close expected actual))

# Expiry retains ordinary ability priority and never bypasses cooldown or cost.
(def priority (run [(control 0 0 :stun 0.137)] {:strategy {:attacks true :abilities true :movement :hold}} 0.3))
(close 0.137 ((starts priority :cast) 0))
(close 0.177 ((starts priority :attack) 0))
(def later (run [(control 0.1 0 :silence 0.037)] {:abilities [(merge spell {:cooldown 0.337})]}))
(close 0.337 ((starts later :cast) 1))
(def drained (run [(control 0.1 0 :silence 0.237)] {:resource 10 :abilities [(merge spell {:cost 10})]}))
(assert (= 1 (length (actions drained :cast))))
(close 0 (drained :resource-left))
(each kind [:silence :root]
  (def unaffected (run [(control 0 0 kind 0.337)] {:strategy {:attacks true :abilities false :movement :hold}} 0.5))
  (close 0 ((starts unaffected :attack) 0)))
(def immune (run [(control 0 0 :stun 0.337)] {:immunities [:stun]}))
(close 0 ((starts immune :cast) 0))
(def zero (run [(control 0.001 0 :stun 0)]))
(close 0.173 ((starts zero :cast) 1))
# Resource readiness crosses between polls. A 13 ms control must wake even
# when no decision observed its application; no-op removal must not wake.
# A stat-dependent cost retains condition polling instead of a fixed forecast.
(def recovering {:resource 9.99 :stats (merge (dummy :stats) {:mp-regen 5})
                 :abilities [(merge spell {:cost {:op :stat :stat :ad :formula 0} :cooldown 99})]})
(close 0.014 ((starts (run [(control 0.001 0 :silence 0.013)] recovering) :cast) 0))
(each event [(effect 0.014 0 {:kind :cleanse :controls [:stun]}) (control 0.014 0 :stun 0)]
  (close 0.05 ((starts (run [event] recovering) :cast) 0)))
(each side [0 1]
  (each kind [:stun :charm :fear :airborne :suppression]
    (def attacking (run [(control 0 side kind 0.137)]
                        {:strategy {:attacks true :abilities false :movement :hold}} 1.5 side))
    (assert (= 2 (length (actions attacking :attack))))
    (each [expected actual] (map tuple [0.137 1.137] (starts attacking :attack)) (close expected actual))))

# Movement resumes exactly after root expiry; silence does not stop it.
(each kind [:root :silence]
  (def moving (run [(control 0 0 kind 0.137)]
                   {:strategy {:attacks false :abilities false :movement :approach}
                    :position -100 :attack-range 0} 0.3))
  (close (+ -100 (* 100 (if (= kind :root) (- 0.3 0.137) 0.3))) (get-in moving [:actors 0 :position])))

# Simultaneous expiry events coalesce. No stale wake creates another action
# stream, including where a superseded poll equals a later live deadline.
(def many (run [(control 0 0 :stun 0.137) (control 0 0 :silence 0.137) (control 0 0 :root 0.137)]
               {:abilities [(merge spell {:cooldown 0.05 :cast-time 0})]} 0.6))
(assert (= 10 (length (actions many :cast))))
(eachp [index event] (actions many :cast) (close (+ 0.137 (* index 0.05)) (event :at)))
(each dying [0 1]
  (def dead (run [(control 0 0 :stun 0.137) (effect 0.137 dying {:kind :damage :damage-type :true :amount 10000})]))
  (assert (empty? (actions dead :cast))))
(assert (empty? (actions (run [(control 0 0 :stun 0.137)] nil 0.137) :cast)))
(close 0.137 ((starts (run [(control 0 0 :stun 0.137)] nil 0.13701) :cast) 0))
(close 0 (get-in (run [(control 0 0 :stun 0.137)] nil 0.13701) [:damage]))

# Synthetic carriers exercise compiled scenarios and trace-free fitness through
# a retained package. Their control timings are fixtures, not champion evidence.
(def root (string "build/control-resumption-tests/" (hash/sha256 (os/cryptorand 8))))
(packages/initialize root "build/seed")
(def source (packages/load "16.19.1"))
(def control-spell {:id "fixture-silence" :name "Synthetic silence" :slot :q :cost 0 :range 500 :cooldown 99 :cast-time 0.013 :missile-speed 0
                    :effects [{:kind :control :control :silence :duration 0.437 :target :enemy :status :estimated}]})
(def champions (map (fn [id ability]
                      (merge ((source :champion-map) id)
                             {:abilities [(merge {:max-rank 5 :available true :checked false :icon-group "spell"
                                                  :icon (if (= id "Annie") "AnnieQ.png" "LuxLightBinding.png")
                                                  :tooltip "Synthetic scheduler fixture; not champion mechanics."
                                                  :variables [] :record {} :cost-resource :resource
                                                  :unresolved ["Synthetic scheduler fixture; not champion mechanics."]} ability)]}))
                    ["Annie" "Lux"] [spell control-spell]))
(def bytes (util/encode-data (util/canonical {:schema 1 :parser "6" :patch "16.19.1" :champions champions :items []})))
(def snapshot (hash/sha256 bytes))
(def directory (string root "/patches/16.19.1/" snapshot))
(util/write (string directory "/package.jdn") bytes)
(util/write (string directory "/manifest.json") (util/encode-json {"initial" false "synthetic_control_resumption" true "package_sha256" snapshot}))
(util/write (string root "/patches/16.19.1/current") snapshot)
(packages/initialize root nil)
(def caster {:champion "Annie" :level 1 :skill-order [:q] :loadout {:items []}
             :strategy {:attacks false :abilities true :priority [:q] :movement :hold}})
(def controller (merge caster {:champion "Lux" :kind :champion}))
(def definition {:schema 1 :patch "16.19.1" :snapshot snapshot :duration 0.5 :distance 100 :seed 1
                 :player caster :target controller})
(each [input side] [[definition 0] [(merge definition {:player controller :target (merge caster {:kind :champion})}) 1]]
  (def result (scenario/simulate input))
  (def selected (filter |(and (= :cast ($ :kind)) (= "fixture-q" ($ :source))) (result :trace)))
  (assert (= 2 (length selected)) (util/encode-json {:trace (result :trace) :coverage (result :coverage)}))
  (close (+ 0.013 0.437) ((selected 1) :at))
  (close 20 (get-in result [:actors side :damage-dealt]))
  (assert (= (result :metrics) ((scenario/fitness input) :metrics))))
(assert (= snapshot (hash/sha256 (slurp (string directory "/package.jdn")))))
(when-let [export (os/getenv "PS_CONTROL_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(util/remove-tree root)
(print "Exact control expiry/cleanse resumption, short effects, overlap, tenacity, coalesced decisions, action gates, movement and compiled/fitness parity passed.")
