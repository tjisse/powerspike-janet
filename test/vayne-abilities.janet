(import ./latest-provider :as fixtures)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/data-util :as util)
(import ../scripts/lib/ability-audit :as audit)
(import ../web/catalog :as catalog)
(import ../web/tooltip :as tooltip)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.0001) (string "Expected " expected ", got " actual)))
(def root "data/ability-fixtures/16.21.1/passives/")
(eachp [file expected] ((util/read-json (slurp (string root "manifest.json"))) "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root file))))))
(def scratch (string "build/vayne-tests/" (hash/sha256 (os/cryptorand 8))))
(catalog/initialize scratch "build/seed")
(def refreshed (packages/fetch "16.21.1" (string scratch "/job") (fn [progress] nil) (fn [] false)
                               (fixtures/provider "16.21.1" root ["Vayne"])))
(def package (packages/load "16.21.1" (refreshed :snapshot)))
(def champion (get-in package [:champion-map "Vayne"]))
(assert (= (util/canonical champion) (util/canonical (normalize/semantic-kit "Vayne" "16.21.1" champion))))
(def order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(def source (scenario/participant package {:champion "Vayne" :level 18 :skill-order order} "player" 0))
(def idle {:abilities false :attacks false :movement :hold})
(defn run [&opt fields target events duration]
  (def actor (merge source {:ranks {:w 1} :health 1000 :resource 1000 :attack-missile-speed 0
                            :stats (merge (source :stats) {:hp 1000 :hp-regen 0 :mp 1000 :mp-regen 0 :ad 10 :attack-speed 1 :crit-chance 0})
                            :strategy {:abilities false :attacks true :priority [:w] :movement :hold}} (or fields {})))
  (put actor :triggers (effects/ability-triggers (actor :abilities) (actor :ranks)))
  (engine/simulate {:duration (or duration 3.5) :initial-events (or events [])
                    :actors [actor (merge {:id "target" :kind :champion :level 18 :position 0
                                           :stats {:hp 2000 :armor 0 :mr 0} :strategy idle} (or target {}))]}))
(defn bolts [result] (filter |(and (= :damage ($ :kind)) (= "VayneSilveredBolts" ($ :source))) (result :trace)))
(def normal (run))
(assert (= 1 (length (bolts normal))))
(close 80 ((first (bolts normal)) :raw))
(close 2.3 ((first (bolts normal)) :at))
(assert (not (some |(= :cast ($ :kind)) (normal :trace))))
(close 1000 (get-in normal [:actors 0 :resource]))
(assert (some |(and (= "Silver Bolts" ($ :effect)) (< ($ :start) 2.3)) (normal :statuses)))
(each [rank hp expected] [[1 100 40] [1 1000 40] [1 2000 80] [5 500 100] [5 2000 200]]
  (def result (run {:ranks {:w rank}} {:stats {:hp hp :armor 1000 :mr 1000}}))
  (close expected ((first (bolts result)) :raw))
  (close expected ((first (bolts result)) :damage)))
(def critical (run {:stats (merge (source :stats) {:hp 1000 :mp 1000 :ad 10 :attack-speed 1 :crit-chance 1 :crit-damage 2 :hp-regen 0})}))
(close 80 ((first (bolts critical)) :raw))
(assert (not ((first (bolts critical)) :critical)))
(assert (empty? (bolts (run {:ranks {:w 0}}))))

(defn hit [at origin &opt spell]
  {:at at :kind :effect :actor 0 :target 1 :rank 1 :source (if spell "VayneCondemn" "attack")
   :trigger (if spell :spell-hit :attack) :ability-slot (when spell :e) :origin origin
   :effect {:kind :damage :damage-type :physical :amount 10}})
(def quiet {:strategy idle})
# The timeout refreshes after each distinct hit, rather than measuring from
# the first hit. A hit exactly at expiry starts a new stack sequence.
(def refreshed-window (run quiet nil [(hit 0 "a") (hit 3 "b") (hit 6 "c")] 6.1))
(assert (= 1 (length (bolts refreshed-window))))
(assert (empty? (bolts (run quiet nil [(hit 0 "a") (hit 3.5 "b") (hit 7 "c")] 7.1))))
# Condemn and attacks share the counter. Additional damage components of one
# originating action do not create another stack.
(def mixed (run quiet nil [(hit 0 "a") (hit 0.5 "e" true) (hit 0.5 "e" true) (hit 1 "b")] 1.1))
(assert (= 1 (length (bolts mixed))))
(def simultaneous (run quiet nil [(hit 0 "a") (hit 1 "b") (hit 1 "e" true) (hit 1 "e" true)
                                  (hit 1 "c") (hit 2 "d") (hit 3 "f")] 3.1))
(assert (= 2 (length (bolts simultaneous))))
(def parry {:at 0 :priority 0 :kind :effect :actor 1 :target 1 :source "fixture" :origin "parry"
            :effect {:kind :parry :duration 1.5 :source-kinds [:champion]}})
(assert (empty? (bolts (run quiet nil [parry (hit 0.5 "a") (hit 1 "b") (hit 2 "c")] 2.1))))
(def learned (find |(= :w ($ :slot)) (champion :abilities)))
(def displayed (tooltip/body (learned :tooltip) (learned :variables)
                             (engine/context (engine/state source 0) (engine/state source 1) 1)))
(assert (string/find "4%" (string/join (mapcat |(map (fn [segment] (segment :text)) $) displayed))))
(def probe (audit/inspect "Vayne" learned))
(assert (= :executes (probe :status))) (assert (= 0 (probe :cast-count)))
(assert (> (probe :effect-count) 0))

(def cases @[])
(each active [0 1]
  (def selected {:champion "Vayne" :level 18 :skill-order order :ranks {:q 0 :w 5 :e 0 :r 0}
                 :strategy {:abilities false :attacks true :movement :hold}})
  (def other (merge selected {:strategy idle}))
  (def definition {:schema 1 :patch "16.21.1" :snapshot (refreshed :snapshot) :duration 3 :distance 0 :seed 1 :samples 1
                   :player (if (= active 0) selected other) :target (merge (if (= active 1) selected other) {:kind :champion})})
  (def result (scenario/simulate definition))
  (assert (= (result :metrics) ((scenario/fitness definition) :metrics)))
  (assert (= 1 (length (bolts result))))
  (assert (not (some |(= :cast ($ :kind)) (result :trace))))
  (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (result :metrics)
                     :sources ["VayneSilveredBolts"] :passive-side (if (= active 0) "player" "opponent")
                     :tooltips [{:side (if (= active 0) "player" "opponent") :slot "w" :contains "10%" :stats [["Type" "Passive"]]}]
                     :trace-counts [{:kind :damage :source "VayneSilveredBolts" :count 1}]}))
(when-let [export (os/getenv "PS_VAYNE_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string scratch "/patches") (string export "/seed"))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(util/remove-tree scratch)
(print "Vayne Silver Bolts: passive activation, rank/health floors, true damage, refreshed mark expiry, distinct/simultaneous hits, parry, zero casts, both roles and scoring parity passed.")
