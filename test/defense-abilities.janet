(import ./latest-provider :as fixtures)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/data-util :as util)
(import ../web/catalog :as catalog)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.0002) (string "Expected " expected ", got " actual)))
(def root "data/ability-fixtures/16.21.1/defenses/")
(eachp [file expected] ((util/read-json (slurp (string root "manifest.json"))) "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root file))))))
(def scratch (string "build/defense-ability-tests/" (hash/sha256 (os/cryptorand 8))))
(catalog/initialize scratch "build/seed")
(def refreshed (packages/fetch "16.21.1" (string scratch "/job") (fn [progress] nil) (fn [] false)
                               (fixtures/provider "16.21.1" root ["Riven" "JarvanIV" "Malphite"])))
(def package (packages/load "16.21.1" (refreshed :snapshot)))
(def bytes (string (slurp (string (package :directory) "/package.jdn"))))
(def order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(def idle {:abilities false :attacks false :movement :hold})
(defn actor [id]
  (def champion (get-in package [:champion-map id]))
  (assert (= (util/canonical champion) (util/canonical (normalize/semantic-kit id "16.21.1" champion))))
  (scenario/participant package {:champion id :level 18 :skill-order order} "player" 0))
(defn initial [at effect]
  {:at at :kind :effect :actor 1 :target 0 :source "fixture" :origin "fixture" :rank 1 :effect effect})
(defn run [id slot &opt distance fields events duration]
  (def source (actor id))
  (engine/simulate {:duration (or duration 1) :initial-events (or events [])
                    :actors [(merge source {:health 500 :ranks {slot 1}
                                            :base (merge (source :base) {:ad 100 :armor 40})
                                            :stats (merge (source :stats) {:hp 1000 :hp-regen 0 :mp 10000 :mp-regen 0 :ap 100 :ad 150 :armor 100})
                                            :strategy {:attacks false :abilities true :priority [slot] :movement :hold}}
                                    (or fields {}))
                             {:id "target" :kind :champion :level 18 :position (or distance 0)
                              :stats {:hp 10000 :armor 0 :mr 0 :attack-speed 1 :move-speed 100} :strategy idle}]}))
(defn traced [result kind source]
  (filter |(and (= kind ($ :kind)) (= source ($ :source))) (result :trace)))

# Riven: base 70 plus 1.1 * 50 bonus AD, shield at cast start for 1.5s.
(def riven (run "Riven" :e 1000))
(def shield (first (traced riven :shield "RivenFeint")))
(close 125 (shield :amount)) (close 0 (shield :at))
(def damage {:kind :damage :damage-type :true :amount 100})
(def hit (run "Riven" :e 1000 nil [(initial 0.001 damage) (initial 1.5 damage)] 2))
(close 100 (get-in hit [:actors 0 :absorbed]))
(close 400 (get-in hit [:actors 0 :health]))
(def riven-five (run "Riven" :e nil {:ranks {:e 5}}))
(close 225 ((first (traced riven-five :shield "RivenFeint")) :amount))

# Aegis: base 60 + .7 * 50 bonus AD, plus .013 * 1000 HP for one nearby
# champion. Its shield survives 4 seconds; the slow lasts 2 seconds.
(def near (run "JarvanIV" :w 625))
(assert (not (empty? (traced near :shield "JarvanIVGoldenAegis"))) (util/encode-json (near :unsupported)))
(close 108 ((first (traced near :shield "JarvanIVGoldenAegis")) :amount))
(close 2 ((first (traced near :control "JarvanIVGoldenAegis")) :duration))
(close 85 (get-in near [:actors 1 :stats :move-speed]))
(def far (run "JarvanIV" :w 626))
(close 95 ((first (traced far :shield "JarvanIVGoldenAegis")) :amount))
(assert (empty? (traced far :control "JarvanIVGoldenAegis")))
(def low-hit (run "JarvanIV" :w 0 {:strategy {:attacks false :abilities true :priority [:w] :movement :hold :hit-chance 0}}))
(close 108 ((first (traced low-hit :shield "JarvanIVGoldenAegis")) :amount))
(def expiry (run "JarvanIV" :w 1000 nil [(initial 3.99 damage) (initial 4.125 damage)] 4.2))
(close 95 (get-in expiry [:actors 0 :absorbed]))
(close 395 (get-in expiry [:actors 0 :health]))

# Ground Slam: total armor, not bonus armor: 60 + .4 * 100 + .6 * 100.
(def slam (run "Malphite" :e))
(close 160 ((first (traced slam :damage "Landslide")) :raw))
(close 0.7 (get-in slam [:actors 1 :stats :attack-speed]))
(def expired (run "Malphite" :e nil nil nil 3.3))
(close 1 (get-in expired [:actors 1 :stats :attack-speed]))
(def high (run "Malphite" :e nil {:ranks {:e 5}}))
(close 300 ((first (traced high :damage "Landslide")) :raw))
(close 0.5 (get-in high [:actors 1 :stats :attack-speed]))
# The reviewed armor enum is local to this rule; unrelated source formula
# mappings and future patches are still unresolved.
(assert (= :unresolved ((expr/stat-node {"mStat" 1} {"__powerspike_patch" "16.21.1"}) :op)))
(assert (= :unresolved ((expr/stat-node {"mStat" 6} {"__powerspike_patch" "16.21.1"}) :op)))
(def injected (normalize/ability :e "fixture" {"mSpell" {"__powerspike_stat_scope" [[1 0]]}}
                                 {} {} "16.21.1"))
(assert (not (get-in injected [:record "__powerspike_stat_scope"])))
(def future (normalize/semantic-kit "Malphite" "16.22.1"
                                    {:abilities [(normalize/ability :e "fixture" {} {} {} "16.22.1")]}))
(assert (not (some |(= :estimated ($ :status)) (get-in future [:abilities 0 :effects]))))

(def cases @[])
(each [id slot source kind] [["Riven" :e "RivenFeint" :shield] ["JarvanIV" :w "JarvanIVGoldenAegis" :shield] ["Malphite" :e "Landslide" :damage]]
  (each active [0 1]
    (def selected {:champion id :level 18 :skill-order order :ranks {:q 0 :w (if (= slot :w) 1 0) :e (if (= slot :e) 1 0) :r 0}
                   :strategy {:abilities true :attacks false :priority [slot] :movement :hold}})
    (def other {:champion (if (= id "Riven") "JarvanIV" "Riven") :level 18 :skill-order order :strategy idle})
    (def definition {:schema 1 :patch "16.21.1" :snapshot (refreshed :snapshot) :duration 1 :distance 100 :seed 1 :samples 1
                     :player (if (= active 0) selected other) :target (merge (if (= active 1) selected other) {:kind :champion})})
    (def result (scenario/simulate definition))
    (assert (= (result :metrics) ((scenario/fitness definition) :metrics)))
    (assert (= 1 (length (traced result kind source))))
    (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (result :metrics)
                       :sources (if (= kind :damage) [source] []) :trace-counts [{:kind kind :source source :count 1}]})))
(when-let [export (os/getenv "PS_DEFENSE_ABILITY_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string scratch "/patches") (string export "/seed"))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(assert (= bytes (string (slurp (string (package :directory) "/package.jdn")))))
(util/remove-tree scratch)
(print "Defense abilities: Riven shield timing/AD scaling, Jarvan self-cast/nearby shield/slow, scoped Malphite armor/AP damage and attack-speed reduction, both roles and scoring parity passed.")
