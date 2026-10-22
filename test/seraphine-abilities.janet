(import ./latest-provider :as fixtures)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)
(import ../web/catalog :as catalog)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.0002) (string "Expected " expected ", got " actual)))
(def scratch (string "build/seraphine-tests/" (hash/sha256 (os/cryptorand 8))))
(def root "data/ability-fixtures/16.21.1/")
(def cases @[])
(eachp [file expected] ((util/read-json (slurp (string root "manifest.json"))) "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root file))))))
(catalog/initialize scratch "build/seed")
(def refreshed (packages/fetch "16.21.1" (string scratch "/job") (fn [progress] nil) (fn [] false)
                               (fixtures/provider "16.21.1" root ["Seraphine"])))
(def package (packages/load "16.21.1" (refreshed :snapshot)))
(def champion (get-in package [:champion-map "Seraphine"]))
(assert (= (util/canonical champion) (util/canonical (normalize/semantic-kit "Seraphine" "16.21.1" champion))))
(def actor (scenario/participant package {:champion "Seraphine" :level 18
                                          :skill-order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e]}
                                 "player" 0))
(def stats (merge (actor :stats) {:hp 1000 :hp-regen 0 :ap 100 :mp 10000 :mp-regen 0 :attack-speed 1}))
(def base (merge actor {:health 500 :resource 10000 :stats stats :ranks {:q 1 :w 1 :e 1 :r 1}}))
(def idle {:abilities false :attacks false :movement :hold})
(defn initial [at who effect]
  {:at at :kind :effect :actor who :target who :source "fixture" :origin "fixture" :rank 1 :effect effect})
(defn run [priority &opt target events fields duration]
  (engine/simulate {:duration (or duration 3) :initial-events (or events [])
                    :actors [(merge base {:strategy {:abilities true :attacks false :priority priority :movement :hold}}
                                    (or fields {}))
                             (merge {:id "target" :kind :champion :position 0 :level 18
                                     :stats {:hp 2000 :armor 0 :mr 0 :move-speed 100} :strategy idle} (or target {}))]}))
(defn traced [result kind source]
  (filter |(and (= kind ($ :kind)) (= source ($ :source))) (result :trace)))

# Base 60 + .4 AP, linearly reaching 75% bonus at 75% missing health.
(each [health expected] [[2000 100] [1250 137.5] [500 175] [200 175]]
  (close expected ((first (traced (run [:q] {:health health}) :damage "SeraphineQ")) :raw)))
(def ordinary (run [:e]))
(def slow (first (traced ordinary :control "SeraphineE")))
(assert (= :slow (slow :control))) (close 1.1 (slow :duration))
(defn control [kind &opt strength duration]
  (initial 0 1 (merge {:kind :control :target :self :control kind :duration (or duration 2)}
                      (when strength {:strength strength}))))
(each [initial-kind expected] [[:slow :root] [:root :stun] [:stun :stun] [:grounded :stun]]
  (def result (run [:e] nil [(control initial-kind 0.2)]))
  (assert (= expected ((first (traced result :control "SeraphineE")) :control))))
(def tenacious (run [:e] {:stats {:hp 2000 :armor 0 :mr 0 :move-speed 100 :tenacity 0.5}}))
(close 0.55 ((first (traced tenacious :control "SeraphineE")) :duration))

# A lone W cannot qualify itself for healing. Qualification samples an actual
# unexpired, unconsumed shield before W adds its own shield.
(assert (empty? (traced (run [:w]) :heal "SeraphineW")))
(def shield (initial 0 0 {:kind :shield :amount 100 :duration 1}))
(def pre-shielded (run [:w] nil [shield]))
(close 40 ((first (traced pre-shielded :heal "SeraphineW")) :amount))
(close 2.5 ((first (traced pre-shielded :heal "SeraphineW")) :at))
(close 80 ((first (traced pre-shielded :shield "SeraphineW")) :amount))
(def damage (initial 1 0 {:kind :damage :damage-type :true :amount 180}))
(close 48 ((first (traced (run [:w] nil [shield damage]) :heal "SeraphineW")) :amount))
(def consumed [(initial 0 0 {:kind :shield :amount 10 :duration 1})
               (initial 0 0 {:kind :damage :damage-type :true :amount 10})])
(assert (empty? (traced (run [:w] nil consumed) :heal "SeraphineW")))

# Third basic cast echoes once. R does not consume a basic-ability Echo stack;
# the repeat uses no mana, cooldown, additional cast proc or recursive Echo.
(def echo-e (run [:q :w :e]))
(assert (= 2 (length (traced echo-e :damage "SeraphineE"))))
(assert (= [:slow :root] (tuple ;(map |($ :control) (traced echo-e :control "SeraphineE")))))
(assert (= 1 (length (traced echo-e :echo "SeraphineE"))))
(close 190 (sum (map |($ :cost) (filter |(= :cast ($ :kind)) (echo-e :trace)))))
(def echo-stun (run [:q :w :e] nil [(control :slow 0.2)]))
(assert (= [:root :stun] (tuple ;(map |($ :control) (traced echo-stun :control "SeraphineE")))))
(def echo-w (run [:q :e :w]))
(assert (= 2 (length (traced echo-w :shield "SeraphineW"))))
(assert (= 1 (length (traced echo-w :heal "SeraphineW"))))
(close 40 ((first (traced echo-w :heal "SeraphineW")) :amount))
(close 2.53 ((first (traced echo-w :heal "SeraphineW")) :at))
(def double-qualified (run [:q :e :w] nil [shield]))
(assert (= 1 (length (traced double-qualified :heal "SeraphineW"))))
(close 2.53 ((first (traced double-qualified :heal "SeraphineW")) :at))
(def with-r (run [:r :q :w :e]))
(assert (= 1 (length (traced with-r :echo "SeraphineE"))))
(def dead (run [:q :e :w] nil [(initial 1 0 {:kind :damage :damage-type :true :amount 2000})]))
(assert (empty? (traced dead :heal "SeraphineW")))
(def simultaneous (run [:w] nil [shield (initial 2.5 0 {:kind :damage :damage-type :true :amount 2000})]))
(assert (empty? (traced simultaneous :heal "SeraphineW")))
(assert (empty? (traced (run [:q :w :e] nil nil {:ranks {:q 1 :w 1 :e 0}}) :echo "SeraphineE")))
(def compiled {:duration 3 :actors [(merge base {:strategy {:abilities true :attacks false :priority [:q :e :w] :movement :hold}})
                                    {:id "target" :kind :champion :level 18 :position 0 :stats {:hp 2000 :armor 0 :mr 0} :strategy idle}]})
(assert (= ((engine/simulate compiled) :damage) ((engine/simulate (merge compiled {:trace false})) :damage)))
(def spec {:champion "Seraphine" :level 18 :skill-order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e]
           :strategy {:attacks false :abilities true :priority [:q :w :e] :movement :hold}})
(each active [0 1]
  (def other (merge spec {:strategy idle}))
  (def definition {:schema 1 :patch "16.21.1" :snapshot (refreshed :snapshot) :duration 3 :distance 0 :samples 1 :seed 1
                   :player (if (= active 0) spec other) :target (merge (if (= active 1) spec other) {:kind :champion})})
  (def result (scenario/simulate definition))
  (assert (= (result :metrics) ((scenario/fitness definition) :metrics)))
  (def damage (filter |(and (= :damage ($ :kind)) (= "SeraphineE" ($ :source))) (result :trace)))
  (assert (= 2 (length damage)))
  (assert (= (if (= active 0) "player" "opponent") ((first damage) :actor)))
  (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (result :metrics)
                     :sources ["SeraphineQ" "SeraphineE"]
                     :trace-counts [{:kind :damage :source "SeraphineE" :count 2}]}))
(when-let [export (os/getenv "PS_SERAPHINE_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string scratch "/patches") (string export "/seed"))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(util/remove-tree scratch)
(print "Seraphine: Q health amplification, E impact-time control upgrades, W shield qualification/live-health pulse, Echo costs/ordering and trace-free parity passed.")
