(import ./latest-provider :as fixtures)
(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)
(import ../web/catalog :as catalog)
(import ../web/model :as model)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.0001) (string "Expected " expected ", got " actual)))
(def scratch (string "build/latest-mage-tests/" (hash/sha256 (os/cryptorand 8))))
(def context {:level 18 :rank 1 :stats {:ad 150 :ap 100} :base {:ad 80 :ap 0} :buffs {}})
(defn definition [patch snapshot champion &opt input]
  (model/definition
    (model/parse-state (merge {"patch" patch "snapshot" snapshot "snapshotlocked" true
                               "champion" champion "opponent" (if (= champion "Ahri") "Viktor" "Ahri")
                               "selected" "custom" "samples" 1} (or input {}))) []))
(defn isolated [definition slot &opt fields duration distance]
  (def actor (get-in (scenario/compile definition) [:actors 0]))
  (engine/simulate
    {:duration (or duration 3)
     :actors [(merge actor {:ranks {:q 1 :w 1 :e 1 :r 3}
                            :stats (merge (actor :stats) {:ad 150 :ap 100 :attack-speed 1 :mp 1000 :mp-regen 0})
                            :strategy {:abilities true :attacks false :priority [slot] :movement :hold}}
                     (or fields {}))
              {:id "target" :kind :practice :tags [:practice :champion] :level 1 :position (or distance 0)
               :stats {:hp 100000 :armor 0 :mr 0} :strategy {:attacks false :abilities false}}]}))
(defn hits [outcome source] (filter |(= source ($ :source)) (outcome :events)))

(each patch ["16.20.1" "16.21.1"]
  (def root (string "data/combat-fixtures/" patch "/"))
  (def manifest (util/read-json (slurp (string root "manifest.json"))))
  (eachp [file expected] (manifest "fixture_sha256")
    (assert (= expected (hash/sha256 (slurp (string root file)))) (string "Corrupt mage fixture: " patch "/" file)))
  # Run the actual manual-download publication path against retained responses.
  # Neither a new parser nor a package repair/migration is needed for semantics.
  (catalog/initialize scratch "build/seed")
  (def refreshed (packages/fetch patch (string scratch "/jobs/mages-" patch)
                                 (fn [progress] nil) (fn [] false)
                                 (fixtures/provider patch root ["Ahri" "Viktor"])))
  (def package (packages/load patch (refreshed :snapshot)))
  (def snapshot-file (string (package :directory) "/package.jdn"))
  (def snapshot-bytes (string (slurp snapshot-file)))
  (assert (= "7" (package :parser)))
  (def fonts (util/read-json (slurp (string root "strings.json"))))
  (each id ["Ahri" "Viktor"]
    (def loaded ((package :champion-map) id))
    (def fresh (normalize/kit id (util/read-json (slurp (string root id "-characters.json")))
                              (util/read-json (slurp (string root id "-abilities.json"))) fonts patch))
    (assert (= (util/canonical (fresh :abilities)) (util/canonical (loaded :abilities))))
    (assert (= (util/canonical loaded) (util/canonical (normalize/semantic-kit id patch loaded))))
    # Passives and evolved/conditional effects must not disappear from coverage.
    (assert (all |(= :unresolved ($ :status)) (get-in loaded [:abilities 4 :effects])))
    (def duel (definition patch (refreshed :snapshot) id {"mode" "duel" "duration" 10 "distance" 200}))
    (def outcome (scenario/simulate duel))
    (each [actor champion] [["player" id] ["opponent" (if (= id "Ahri") "Viktor" "Ahri")]]
      (assert (some |(and (= actor ($ :actor)) (= :cast ($ :kind)) (= (string champion "R") ($ :source)))
                    (outcome :trace))))
    (assert (= (outcome :metrics) ((scenario/fitness duel) :metrics))))

  (def ahri (definition patch (refreshed :snapshot) "Ahri"))
  (def orb (hits (isolated ahri :q nil 3 200) "AhriQ"))
  (assert (= 2 (length orb)))
  (assert (= :magic ((orb 0) :type)))
  (assert (= :true ((orb 1) :type)))
  (each hit orb (close 85 (hit :damage))) # Rank-one base 35 + .5 AP on each phase.
  (assert (< ((orb 0) :at) ((orb 1) :at)))
  (def fires (hits (isolated ahri :w) "AhriW"))
  (assert (= 3 (length fires)))
  (close 80 ((fires 0) :damage))
  (each hit (array/slice fires 1) (close 32 (hit :damage)))
  (def rush (isolated ahri :r))
  (def rush-hits (hits rush "AhriR"))
  (assert (= 3 (length rush-hits)))
  (close 630 (rush :damage))
  (for index 1 3 (close 1 (- ((rush-hits index) :at) ((rush-hits (dec index)) :at))))
  (def casts (filter |(= :cast ($ :kind)) (rush :trace)))
  (close 100 (sum (map |($ :cost) casts)))

  (def viktor (definition patch (refreshed :snapshot) "Viktor"))
  (def q (isolated viktor :q {:strategy {:abilities true :attacks true :priority [:q] :movement :hold}}))
  (def q-hits (hits q "ViktorQ"))
  (assert (= 2 (length q-hits)))
  (close 100 ((q-hits 0) :damage))
  (close 220 ((q-hits 1) :damage))
  (assert (= :magic ((q-hits 1) :type)))
  (close 620 (q :damage))
  (assert (= 1 (length (hits (isolated viktor :q) "ViktorQ"))))
  (def q-effects (get-in package [:champion-map "Viktor" :abilities 0 :effects]))
  (def shield (find |(and (= :shield ($ :kind)) (= :estimated ($ :status))) q-effects))
  # The selected raw patch, not the copied semantic rule, owns the numbers:
  # 16.20: 140 + .25 AP; 16.21: 130 + .20 AP at level 18.
  (close (if (= patch "16.20.1") 165 150) (expr/evaluate (shield :amount) context))
  (def shield-events (filter |(and (= :shield ($ :kind)) (= "ViktorQ" ($ :source))) (q :trace)))
  (assert (= 1 (length shield-events)))
  (close (if (= patch "16.20.1") 165 150) ((shield-events 0) :amount))
  (assert (some |(and (= :shield ($ :kind)) (= :unresolved ($ :status))) q-effects))
  (def storm (isolated viktor :r nil 7))
  (def ticks (hits storm "ViktorR"))
  (assert (= 7 (length ticks)))
  (close 300 ((ticks 0) :damage))
  (for index 1 7
    (close 180 ((ticks index) :damage))
    (close 1 (- ((ticks index) :at) ((ticks (dec index)) :at))))
  (close 1380 (storm :damage))
  (close 300 ((isolated viktor :r nil 0.5) :damage))
  (assert (= snapshot-bytes (string (slurp snapshot-file))))
  # Reconstruct a parser-7 snapshot from before these reviewed handlers existed.
  # Loading uses the existing semantic model path and leaves its bytes/current
  # pointer intact. It does not silently reparse an older parser's formulas.
  (def generic (map (fn [champion]
                      (def id (champion :id))
                      (def objects (util/read-json (slurp (string root id "-characters.json"))))
                      (def detail (get-in (util/read-json (slurp (string root id "-abilities.json"))) ["data" id]))
                      (merge champion
                             {:abilities (map (fn [ability index]
                                                (normalize/ability (ability :slot) (ability :path) (objects (ability :path))
                                                                   (if (= :p (ability :slot)) (detail "passive") ((detail "spells") index))
                                                                   fonts patch))
                                              (champion :abilities) (range 5))})) (package :champions)))
  (assert (not (get-in (find |(= "Ahri" ($ :id)) generic) [:abilities 3 :recast])))
  (def previous-bytes (util/encode-data (util/canonical (merge (util/read-data snapshot-file) {:champions generic}))))
  (def previous-id (hash/sha256 previous-bytes))
  (def previous-dir (string scratch "/patches/" patch "/" previous-id))
  (util/write (string previous-dir "/package.jdn") previous-bytes)
  (util/write (string previous-dir "/manifest.json") (util/encode-json {"initial" false "package_sha256" previous-id}))
  (def previous (packages/load patch previous-id))
  (each id ["Ahri" "Viktor"]
    (assert (= (util/canonical (get-in package [:champion-map id :abilities]))
               (util/canonical (get-in previous [:champion-map id :abilities])))))
  (assert (= previous-id (hash/sha256 (slurp (string previous-dir "/package.jdn")))))
  (assert (= (refreshed :snapshot) (string/trim (slurp (string scratch "/patches/" patch "/current"))))))

# Data review is bounded to the two retained releases. New patches do not
# inherit multi-hit, empowered-attack or recast behavior without review.
(each id ["Ahri" "Viktor"]
  (def root "data/combat-fixtures/16.21.1/")
  (def future (normalize/kit id (util/read-json (slurp (string root id "-characters.json")))
                             (merge (util/read-json (slurp (string root id "-abilities.json"))) {"version" "16.22.1"})
                             (util/read-json (slurp (string root "strings.json"))) "16.22.1"))
  (assert (not (get-in future [:abilities 3 :recast])))
  (assert (not (some |(and (= :attack ($ :trigger)) (= :estimated ($ :status)))
                     (get-in future [:abilities 0 :effects])))))
(util/remove-tree scratch)
(print "Latest mage patches: retained refresh, fresh/loaded parity, immutable packages, multi-hit/recast/empowered/tick execution, patch-specific shields, both sides and optimizer parity passed.")
