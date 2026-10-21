(import ./latest-provider :as fixtures)
(import ../src/powerspike/attacks :as attacks)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(def scratch (string "build/latest-attack-tests/" (hash/sha256 (os/cryptorand 8))))
(def cases @[])
(packages/initialize scratch "build/seed")
(defn definition [patch snapshot champion]
  {:schema 1 :patch patch :snapshot snapshot :duration 2 :distance 300 :seed 1 :samples 1
   :player {:champion champion :level 1 :loadout {:items []} :skill-order [:q]
            :strategy {:attacks true :abilities false :movement :hold}}
   :target {:kind :practice :hp 10000 :armor 0 :mr 0}})

(each patch ["16.20.1" "16.21.1"]
  # Combine the already retained fixture providers; the actual fetch pipeline
  # sees exact matching-patch responses and publishes one immutable snapshot.
  (def mages (fixtures/provider patch (string "data/combat-fixtures/" patch "/") ["Ahri" "Viktor"]))
  (def defaults (fixtures/provider patch))
  (def provider (fn [url cancelled]
                  (cond
                    (string/find "/lol.stringtable.json" url)
                    (let [a (util/read-json (mages url cancelled)) b (util/read-json (defaults url cancelled))]
                      (util/encode-json {"entries" (merge (get a "entries" a) (get b "entries" b))}))
                    (string/has-suffix? "/champion.json" url)
                    (let [a (util/read-json (mages url cancelled)) b (util/read-json (defaults url cancelled))]
                      (util/encode-json (merge a {"data" (merge (a "data") (b "data"))})))
                    (or (string/find "/Ahri.json" url) (string/find "/ahri/" url)
                        (string/find "/Viktor.json" url) (string/find "/viktor/" url))
                    (mages url cancelled)
                    (defaults url cancelled))))
  (def fetched (packages/fetch patch (string scratch "/jobs/" patch) (fn [progress] nil) (fn [] false) provider))
  (def package (packages/load patch (fetched :snapshot)))
  (def source-file (string (package :directory) "/package.jdn"))
  (def snapshot-bytes (string (slurp source-file)))
  # A parser-7 snapshot produced before the reviewed attack profiles existed.
  # Existing model loading must supply them without rewriting the package.
  (def prior-data (merge (util/read-data source-file)
                         {:champions (map (fn [champion]
                                            (tabseq [[key value] :pairs champion
                                                     :when (not (some |(= key $) [:attack-projectile :attack-windup]))] key value))
                                          (package :champions))}))
  (def prior-bytes (util/encode-data (util/canonical prior-data)))
  (def prior-id (hash/sha256 prior-bytes))
  (def prior-dir (string scratch "/patches/" patch "/" prior-id))
  (util/write (string prior-dir "/package.jdn") prior-bytes)
  (util/write (string prior-dir "/manifest.json") (util/encode-json {"initial" false "package_sha256" prior-id}))
  (def prior (packages/load patch prior-id))
  (each [id speed windup] [["Ahri" 1750 0.2] ["Annie" 1500 0.3] ["Viktor" 2300 0.3]]
    (def loaded ((package :champion-map) id))
    (def movement (attacks/profile id patch))
    (close speed (movement :missile-speed))
    (assert (= patch (get-in movement [:source :patch])) "Profiles must not share cache entries across patches.")
    (assert (= (get-in movement [:source :sha256]) (hash/sha256 (slurp (get-in movement [:source :path])))))
    (def objects (util/read-json (slurp (get-in movement [:source :path]))))
    (def previous (util/read-json (slurp (string "data/combat-fixtures/16.19.1/" id "-characters.json"))))
    (def root (string "Characters/" id "/CharacterRecords/Root"))
    (each field ["basicAttack" "critAttacks" "extraAttacks" "purchaseIdentities"]
      (assert (= (util/canonical (get-in objects [root field])) (util/canonical (get-in previous [root field])))
              (string patch "/" id " changed attack identities or windup: " field)))
    (assert (= 3 (length (movement :spell-paths))))
    (each path (movement :spell-paths)
      (assert (= (util/canonical (objects path)) (util/canonical (previous path)))))
    (assert (= (util/canonical loaded) (util/canonical (normalize/semantic-kit id patch loaded))))
    (when (= id "Ahri")
      (close windup (get-in loaded [:attack-windup :fraction]))
      (assert (= patch (get-in loaded [:attack-windup :source :patch])))
      (assert (not (some |(string/find "Windup 30%" $) (loaded :limitations)))))
    (assert (not (some |(string/find "projectile travel zero" $) (loaded :limitations))))
    (when (= id "Annie")
      (close 1200 (movement :legacy-speed))
      (assert (not (first (protect (attacks/fixed-projectile objects (movement :spell-paths)))))))
    (assert (= (util/canonical (loaded :attack-projectile))
               (util/canonical (get-in prior [:champion-map id :attack-projectile]))))
    (def spec (definition patch prior-id id))
    (def compiled (scenario/compile spec))
    (def player (get-in compiled [:actors 0]))
    (close speed (player :attack-missile-speed))
    (close windup (player :windup-fraction))
    (def outcome (scenario/simulate spec))
    (close (+ (/ windup (get-in player [:stats :attack-speed])) (/ 300 speed)) (get-in outcome [:events 0 :at]))
    (assert (= (outcome :metrics) ((scenario/fitness spec) :metrics)))
    (array/push cases {:document (util/read-json (wire/encode spec)) :metrics (outcome :metrics)
                       :first-impact (get-in outcome [:events 0 :at]) :missile-speed speed :windup windup})
    # Independent release-plus-travel expectations include critical attacks,
    # changed attack speeds and the half-open endpoint of the scoring window.
    (each attack-speed [0.5 1 2]
      (def impact (+ (/ windup attack-speed) (/ 300 speed)))
      (def actor (merge player {:stats (merge (player :stats) {:attack-speed attack-speed :ad 100 :crit-chance 1})}))
      (def target (get-in compiled [:actors 1]))
      (def boundary (engine/simulate {:duration impact :actors [actor target]}))
      (assert (empty? (boundary :events)))
      (def inside (engine/simulate {:duration (+ impact 0.00001) :actors [actor target]}))
      (close impact (get-in inside [:events 0 :at]))
      (assert (get-in inside [:events 0 :critical])))
    # Both actors use their selected patch's profile and the optimizer's score.
    (def duel (merge spec {:target (merge (spec :player) {:kind :champion :champion (if (= id "Ahri") "Viktor" "Ahri")})}))
    (def duel-actors ((scenario/compile duel) :actors))
    (each actor duel-actors
      (close ((attacks/profile (actor :champion) patch) :missile-speed) (actor :attack-missile-speed)))
    (def duel-result (scenario/simulate duel))
    (assert (= (duel-result :metrics) ((scenario/fitness duel) :metrics)))
    (when (= id "Viktor")
      (def q-spec (merge spec {:distance 500 :duration 3
                               :player (merge (spec :player) {:strategy {:abilities true :attacks true :priority [:q] :movement :hold}})}))
      (def q-actor (get-in (scenario/compile q-spec) [:actors 0]))
      (def q (find |(= :q ($ :slot)) (q-actor :abilities)))
      (def q-result (scenario/simulate q-spec))
      (def release (+ (q :cast-time) (/ 0.3 (get-in q-actor [:stats :attack-speed]))))
      (assert (= 1 (length (filter |(and (= "ViktorQ" ($ :source)) (< (math/abs (- release ($ :at))) 0.000001)) (q-result :events)))))
      (def ordinary (first (filter |(= "attack" ($ :source)) (q-result :events))))
      (def starts (filter |(and (= :attack ($ :kind)) (= "player" ($ :actor))) (q-result :trace)))
      (close (+ ((starts 1) :at) (/ 0.3 (get-in q-actor [:stats :attack-speed])) (/ 500 2300)) (ordinary :at))
      (assert (= (q-result :metrics) ((scenario/fitness q-spec) :metrics)))
      (array/push cases {:document (util/read-json (wire/encode q-spec)) :metrics (q-result :metrics)
                         :empowered-at release :ordinary-at (ordinary :at)})))
  (assert (= snapshot-bytes (string (slurp source-file))))
  (assert (= prior-id (hash/sha256 (slurp (string prior-dir "/package.jdn")))))
  (assert (= (package :snapshot) (string/trim (slurp (string scratch "/patches/" patch "/current"))))))

(each id ["Ahri" "Annie" "Viktor"]
  (assert (nil? (attacks/profile id "16.22.1")))
  (assert (nil? (attacks/windup-profile id "16.22.1"))))
(when-let [export (os/getenv "PS_LATEST_ATTACK_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (each patch ["16.20.1" "16.21.1"]
    (util/copy-tree (string scratch "/patches/" patch) (string export "/seed/" patch)))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(util/remove-tree scratch)
(print "Latest attacks: matching sources, all variants, patch-specific caches, explicit refresh, unchanged snapshots, critical/endpoint timing, both actors and optimizer parity passed.")
