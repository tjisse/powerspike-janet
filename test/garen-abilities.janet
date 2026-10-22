(import ./latest-provider :as fixtures)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/stats :as stats)
(import ../src/powerspike/data-util :as util)
(import ../web/catalog :as catalog)
(import ../web/model :as model)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.0002) (string "Expected " expected ", got " actual)))
(def scratch (string "build/garen-tests/" (hash/sha256 (os/cryptorand 8))))
(def cases @[])
(def idle {:attacks false :abilities false :movement :hold})
(defn hits [result source] (filter |(= source ($ :source)) (result :events)))
(defn probe [actor slot &opt fields target events duration]
  (engine/simulate {:duration (or duration 3.01) :initial-events (or events [])
                    :actors [(merge actor {:ranks {:e 1 :r 1} :health 10000
                                           :stats (merge (actor :stats) {:hp 10000 :hp-regen 0 :ad 150 :ap 0 :attack-speed 1
                                                                         :attack-speed-item-growth 0 :crit-chance 0})
                                           :strategy {:attacks false :abilities true :priority [slot] :movement :hold}}
                                    (or fields {}))
                             (merge {:id "target" :kind :champion :position 0 :level 18
                                     :stats {:hp 10000 :armor 0 :mr 0 :move-speed 0} :strategy idle} (or target {}))]}))
(defn initial [at actor target effect]
  {:at at :kind :effect :actor actor :target target :effect effect :rank 1 :source "fixture" :origin "fixture"})

(each patch ["16.20.1" "16.21.1"]
  (def root (string "data/parser-fixtures/" patch "/"))
  (def manifest (util/read-json (slurp (string root "manifest.json"))))
  (eachp [file expected] (manifest "fixture_sha256")
    (assert (= expected (hash/sha256 (slurp (string root file))))))
  (catalog/initialize scratch "build/seed")
  (def refreshed (packages/fetch patch (string scratch "/jobs/garen-" patch)
                                 (fn [progress] nil) (fn [] false) (fixtures/provider patch)))
  (def package (packages/load patch (refreshed :snapshot)))
  (def file (string (package :directory) "/package.jdn"))
  (def bytes (string (slurp file)))
  (assert (= "7" (package :parser)))
  (def champion (get-in package [:champion-map "Garen"]))
  (assert (= (util/canonical champion) (util/canonical (normalize/semantic-kit "Garen" patch champion))))
  (def spec {:champion "Garen" :level 18 :skill-order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e]})
  (def actor (scenario/participant package spec "player" 0))
  (def spin-display (find |(= "f1" ($ :name)) (get-in champion [:abilities 2 :variables])))
  (close 9 (expr/evaluate (spin-display :expression) (engine/context (engine/state actor 0) (engine/state actor 1) 1)))
  (def future (normalize/semantic-kit "Garen" "16.22.1"
                                      {:abilities [(normalize/ability :e "" {} {} {} "16.22.1")]}))
  (assert (not (some |(= :estimated ($ :status)) (get-in future [:abilities 0 :effects]))))
  (def missing (normalize/semantic-kit "Garen" patch
                                       {:abilities [(normalize/ability :e "" {} {} {} patch)]}))
  (assert (= :unresolved (get-in missing [:abilities 0 :effects 0 :status])))

  # Independent source arithmetic: rank-one spin = (4 + .4 * 150) * 1.25.
  (def spins (probe actor :e))
  (def damage (hits spins "GarenE"))
  (assert (= 7 (length damage)))
  (each hit damage (close 80 (hit :raw)))
  (close 560 (spins :damage))
  (for i 0 7 (close (* 3 (/ (inc i) 7)) ((damage i) :at)))
  (assert (some |(and (= "Judgment" ($ :effect)) (= 0 ($ :start)) (= 3 ($ :end))) (spins :statuses)))
  (assert (empty? (hits (probe actor :e nil nil nil (/ 3 7)) "GarenE")))
  (assert (= 6 (length (hits (probe actor :e nil nil nil 3) "GarenE"))))

  # AS thresholds are exact, and arbitrary temporary bonus AS cannot add spins.
  (each [bonus count] [[0.24999 7] [0.25 8] [0.5 9] [0.99 10]]
    (def fields {:stats (merge (get-in spins [:actors 0 :original-stats]) {:attack-speed-item-growth bonus})})
    (assert (= count (length (hits (probe actor :e fields) "GarenE")))))
  (def buff (initial 0.1 0 0 {:kind :stat-buff :target :self :stat :attack-speed-bonus :amount 1 :duration 5}))
  (assert (= 7 (length (hits (probe (merge actor {:attack-speed-ratio 0.625 :attack-speed-cap 3}) :e nil nil [buff]) "GarenE"))))
  (def synthetic-item {:supported true :stats {:attack-speed-bonus 0.25}})
  (def totals (stats/total-stats champion 1 [synthetic-item] [{:attack-speed-bonus 0.1}]))
  (close 0.35 (totals :attack-speed-bonus))
  (close 0.25 (totals :attack-speed-item-growth))
  (close 0.6205 ((stats/total-stats champion 18 []) :attack-speed-item-growth))

  # Crit chance one: source multiplier 1 + .3 * (total crit damage - 1).
  (each [critical-damage expected] [[2 104] [2.3 111.2]]
    (def fields {:stats (merge (get-in spins [:actors 0 :original-stats]) {:crit-chance 1 :crit-damage critical-damage})})
    (each hit (hits (probe actor :e fields) "GarenE")
      (close expected (hit :raw)) (assert (hit :critical))))
  (def rank-five (probe actor :e {:ranks {:e 5}}))
  (each hit (hits rank-five "GarenE") (close 117.5 (hit :raw)))

  # The sixth hit is mitigated by the old armor; the seventh sees the shred.
  (def armored (probe actor :e nil {:stats {:hp 10000 :armor 100 :mr 100}} nil 9.01))
  (def armor-hits (take 7 (hits armored "GarenE")))
  (each hit (take 6 armor-hits) (close 40 (hit :damage)))
  (close (/ 80 1.75) ((armor-hits 6) :damage))
  (def practice (probe actor :e nil {:kind :practice :tags [:practice :champion] :stats {:hp 10000 :armor 100 :mr 0}}))
  (close (/ 80 1.75) ((last (hits practice "GarenE")) :damage))
  (def shred (filter |(and (= :stat-buff ($ :kind)) (= "GarenE" ($ :source))) (armored :trace)))
  (close (/ 18 7) ((shred 0) :at))
  (close 3 ((shred 1) :at))
  (assert (some |(and (= :stat-buff ($ :kind)) (= :armor ($ :effect)) (= 9 ($ :end))) (armored :statuses)))

  # Parried spins cannot build armor-shred stacks; a dead caster stops spinning.
  (def parry (initial 0 1 1 {:kind :parry :duration 1 :source-kinds [:champion]}))
  (def parried (probe actor :e nil nil [parry]))
  (assert (= 5 (length (hits parried "GarenE"))))
  (assert (not (some |(and (= :stat-buff ($ :kind)) (= "GarenE" ($ :source))) (parried :trace))))
  (def lethal (initial 1 1 0 {:kind :damage :damage-type :true :amount 20000}))
  (assert (= 2 (length (hits (probe actor :e nil nil [lethal]) "GarenE"))))
  (def distant (probe actor :e nil {:position 326}))
  (assert (empty? (hits distant "GarenE")))
  (def escaping (probe actor :e nil {:position 300 :stats {:hp 10000 :armor 0 :mr 0 :move-speed 100}
                                     :strategy {:abilities false :attacks false :movement :hold-range :preferred-range 1000}}))
  (assert (empty? (hits escaping "GarenE")) "Each spin must check current range.")

  # E excludes basic attacks for three seconds while allowing Q/W. The automatic
  # strategy finishes E before R, then resumes attacks at the exact end.
  (def attacking (probe actor :e {:strategy {:abilities true :attacks true :priority [:e] :movement :hold}} nil nil 3.5))
  (def attacks (filter |(= :attack ($ :kind)) (attacking :trace)))
  (close 3 ((attacks 0) :at))
  (def combo (probe actor :e {:strategy {:abilities true :attacks false :priority [:e :q :w :r] :movement :hold}
                              :ranks {:q 1 :w 1 :e 1 :r 1}} nil nil 4))
  (def r-cast (find |(and (= :cast ($ :kind)) (= "GarenR" ($ :source))) (combo :trace)))
  (close 3 (r-cast :at))
  (assert (= 7 (length (hits combo "GarenE"))))
  (assert (some |(and (= :cast ($ :kind)) (= "GarenW" ($ :source)) (< ($ :at) 3)) (combo :trace)))

  # R samples changing health on impact, without physical/magic mitigation.
  (each [rank base ratio] [[1 125 0.25] [2 200 0.3] [3 275 0.35]]
    (def result (probe actor :r {:ranks {:r rank}} {:health 1500 :stats {:hp 2000 :armor 10000 :mr 10000}}))
    (def hit (first (hits result "GarenR")))
    (close (+ base (* ratio 500)) (hit :raw))
    (close (hit :raw) (hit :damage))
    (close 0.435 (hit :at)))
  (def prior (initial 0.2 0 1 {:kind :damage :damage-type :true :amount 200}))
  (def healed (initial 0.3 1 1 {:kind :heal :amount 100}))
  (close 275 ((first (hits (probe actor :r nil {:health 1500 :stats {:hp 2000 :armor 0 :mr 0}} [prior healed]) "GarenR")) :raw))
  (def shield (initial 0.1 1 1 {:kind :shield :amount 100 :duration 2}))
  (def shielded (first (hits (probe actor :r nil nil [shield]) "GarenR")))
  (close 125 (shielded :raw)) (close 100 (shielded :absorbed)) (close 25 (shielded :damage))

  # Both matchup positions and scoring use the same semantic model.
  (each [player target] [["Garen" "Annie"] ["Annie" "Garen"]]
    (def definition (model/definition
                      (model/parse-state {"patch" patch "snapshot" (refreshed :snapshot) "snapshotlocked" true
                                          "champion" player "opponent" target "mode" "duel" "duration" 10
                                          "distance" 100 "samples" 1}) []))
    (def outcome (scenario/simulate definition))
    (each source ["GarenE" "GarenR"]
      (assert (some |(and (= :damage ($ :kind)) (= source ($ :source))) (outcome :trace))))
    (assert (= (outcome :metrics) ((scenario/fitness definition) :metrics)))
    (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (outcome :metrics)
                       :sources ["GarenE" "GarenR"]}))
  (assert (= bytes (string (slurp file))) "Combat semantics must not rewrite saved snapshot bytes."))

(when-let [export (os/getenv "PS_GAREN_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string scratch "/patches") (string export "/seed"))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(util/remove-tree scratch)

(print "Garen E/R: matching sources, independent damage/crit/AS arithmetic, spin timing and range, armor shred, parry/death, action locks, live-health execute, both actors and scoring parity passed.")
