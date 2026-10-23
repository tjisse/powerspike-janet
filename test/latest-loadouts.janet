(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/runes :as runes)
(import ../src/powerspike/forms :as forms)
(import ../src/powerspike/attacks :as attacks)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/data-util :as util)
(import ../web/catalog :as catalog)
(import ../web/details :as details)
(import pshash :as hash)

(defn close [expected actual]
  (assert (and (number? actual) (< (math/abs (- expected actual)) 0.0001))
          (string "Expected " expected ", got " actual)))
(def scratch (string "build/latest-loadouts/" (hash/sha256 (os/cryptorand 8))))
(def cases @[])
(defn retain-case [definition]
  (def outcome (scenario/simulate definition))
  (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (outcome :metrics)
                     :actors (map (fn [actor]
                                    (tabseq [key :in [:form :ranged :attack-range :attack-missile-speed :shards]
                                             :when (has-key? actor key)] key (actor key))) (outcome :actors))}))
(def order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(defn read [path] (util/read-json (slurp path)))
(defn verify [root manifest-name]
  (def manifest (read (string root manifest-name)))
  (eachp [file expected] (get manifest "fixture_sha256" (get manifest "sha256" {}))
    (assert (= expected (hash/sha256 (slurp (string root file)))) (string "Corrupt loadout fixture: " root file)))
  manifest)
(defn spec [champion form level &opt items]
  (merge {:champion champion :level level :skill-order order :loadout {:items (or items ["3153"])}
          :strategy {:attacks true :abilities false :movement :hold}}
         (if form {:form form} {})))

(each patch ["16.20.1" "16.21.1"]
  (def items-root (string "data/item-fixtures/" patch "/"))
  (def runes-root (string "data/rune-fixtures/" patch "/"))
  (def form-root (string "data/form-fixtures/" patch "/"))
  (def kayle-root (string "data/attack-fixtures/" patch "/"))
  (verify items-root "manifest.json") (verify runes-root "manifest.json")
  (verify kayle-root "kayle-manifest.json")
  (each manifest ["manifest.json" "jayce-manifest.json" "elise-manifest.json" "gnar-manifest.json"] (verify form-root manifest))
  (def roots {"Kayle" kayle-root "Nidalee" form-root "Jayce" form-root "Elise" form-root "Gnar" form-root})
  (def fonts @{})
  (each path [(string items-root "strings.json") (string runes-root "strings.json")
              (string kayle-root "Kayle-strings.json") (string form-root "strings.json")
              (string form-root "Jayce-strings.json") (string form-root "Elise-strings.json") (string form-root "Gnar-strings.json")]
    (merge-into fonts ((read path) "entries")))
  (def details (tabseq [[id root] :pairs roots] id (read (string root id "-abilities.json"))))
  (defn provider [url cancelled]
    (assert (not (cancelled)))
    (def detail-id (find |(string/find (string "/champion/" $ ".json") url) (keys roots)))
    (def character-id (find |(string/find (string "/characters/" (string/ascii-lower $) "/") url) (keys roots)))
    (util/encode-json
      (cond
        (string/has-suffix? "/champion.json" url) {"version" patch "data" (tabseq [[id detail] :pairs details] id (get-in detail ["data" id]))}
        (string/has-suffix? "/item.json" url) (read (string items-root "items.json"))
        (string/has-suffix? "/summoner.json" url) {"version" patch "data" {}}
        (string/find "/runesReforged.json" url) (read (string runes-root "styles.json"))
        (string/find "/perks.cdtb.bin.json" url) (read (string runes-root "records.json"))
        (string/find "/items.cdtb.bin.json" url) (read (string items-root "records.json"))
        (string/find "/lol.stringtable.json" url) {"entries" fonts}
        detail-id (details detail-id)
        character-id (read (string (roots character-id) character-id "-characters.json"))
        {})))
  (catalog/initialize scratch "build/seed")
  (def refreshed (packages/fetch patch (string scratch "/jobs/" patch) (fn [progress] nil) (fn [] false) provider))
  (def package (packages/load patch (refreshed :snapshot)))
  (def snapshot-file (string (package :directory) "/package.jdn"))
  (def snapshot-bytes (string (slurp snapshot-file)))
  (assert (= "7" (package :parser)))
  (defn definition [champion form level &opt items]
    {:schema 1 :patch patch :snapshot (refreshed :snapshot) :duration 1.3 :distance 0 :seed 1 :samples 1
     :player (spec champion form level items) :target {:kind :practice :hp 1000 :armor 0 :mr 0}})
  (each [champion form level ranged range]
    [["Kayle" nil 1 false 175] ["Kayle" nil 5 false 175] ["Kayle" nil 6 true 525]
     ["Kayle" nil 15 true 525] ["Kayle" nil 16 true 625] ["Kayle" nil 18 true 625]
     ["Nidalee" "human" 6 true 525] ["Nidalee" "cougar" 6 false 125]
     ["Jayce" "hammer" 6 false 125] ["Jayce" "cannon" 6 true 500]
     ["Elise" "human" 6 true 550] ["Elise" "spider" 6 false 125]
     ["Gnar" "mini" 1 true 400] ["Gnar" "mini" 18 true 500] ["Gnar" "mega" 18 false 175]]
    (def definition (definition champion form level))
    (def compiled (scenario/compile definition))
    (def actor (get-in compiled [:actors 0]))
    (assert (= ranged (actor :ranged)))
    (each path [[:attack-range] [:stats :attack-range] [:base :attack-range]] (close range (get-in actor path)))
    (assert (not (some |(string/find "effects requiring an attack type are excluded" $) (compiled :coverage))))
    (assert (= ((scenario/simulate definition) :metrics) ((scenario/fitness definition) :metrics)))
    (def duel (merge definition {:target (merge (definition :player) {:kind :champion})}))
    (assert (= ranged (get-in (scenario/compile duel) [:actors 1 :ranged])))
    (close range (get-in (scenario/compile duel) [:actors 1 :attack-range]))
    (assert (= ((scenario/simulate duel) :metrics) ((scenario/fitness duel) :metrics)))
    (retain-case definition) (retain-case duel)
    (def target (get-in compiled [:actors 1]))
    (def context (engine/context (engine/state actor 0) (engine/state target 1) 1))
    (assert (some |(= (if ranged "6%" "9%") ($ :text))
                  (mapcat identity ((details/item ((package :item-map) "3153") context) :body-rich))))
    (each side [0 1]
      # Isolate the item's attack-type coefficient from champion on-hit damage.
      (def attacker (merge actor {:stats (merge (actor :stats) {:ad 100 :attack-speed 1 :crit-chance 0})
                                  :triggers (filter |(= "item/3153/mist" ($ :id)) (actor :triggers))}))
      (def result (engine/simulate {:duration 0.7 :actors (if (= side 0) [attacker target] [target attacker])}))
      (def proc (find |(= "item/3153/mist" ($ :source)) (result :trace)))
      (assert proc (string "Missing on-hit: " champion " " form " at level " level " on side " side))
      (close (* 900 (if ranged 0.06 0.09)) (proc :damage))
      # The complete model deliberately applies Kayle's passive before Mist's Edge.
      (when (and (= champion "Kayle") (= patch "16.21.1") (> (get-in actor [:ranks :e] 0) 0))
        (def full-attacker (merge attacker {:triggers (actor :triggers)}))
        (def complete (engine/simulate {:duration 0.7 :actors (if (= side 0) [full-attacker target] [target full-attacker])}))
        (def e-rank (get-in actor [:ranks :e]))
        (def passive (+ ([0 15 20 25 30 35] e-rank) (* 0.2 (get-in actor [:stats :ap])) (* 0.1 (- 100 (get-in actor [:base :ad])))))
        (close (* (- 900 passive) (if ranged 0.06 0.09)) ((find |(= "item/3153/mist" ($ :source)) (complete :trace)) :damage)))))
  # Fixed forms retain their matching-patch ordinary/critical projectile profiles.
  (each [champion form speed] [["Nidalee" "human" 2500] ["Elise" "human" 1600] ["Jayce" "cannon" 2000]]
    (def definition (merge (definition champion form 6 []) {:distance 300 :duration 2}))
    (each side [0 1]
      (def compiled (scenario/compile (if (= side 0) definition
                                        (merge definition {:target (merge (definition :player) {:kind :champion})}))))
      (def actor (get-in compiled [:actors side]))
      (close speed (actor :attack-missile-speed))
      (assert (= patch (get-in (attacks/form-profile champion patch form) [:source :patch])))
      (def attacker (merge actor {:stats (merge (actor :stats) {:ad 100 :crit-chance 0 :attack-speed 1})}))
      (def target (merge (get-in compiled [:actors 1]) {:position 300 :stats {:hp 10000 :armor 0 :mr 0}
                                                        :strategy {:attacks false :abilities false}}))
      (def outcome (engine/simulate {:duration 1 :actors [(merge attacker {:position 0}) target]}))
      (close (+ 0.3 (/ 300 speed)) ((first (filter |(= "attack" ($ :source)) (outcome :events))) :at))))
  # Package-derived rune choices, adaptive shards and haste must survive the
  # same refresh path and participate in both actor and optimizer compilation.
  (def plain (definition "Nidalee" "human" 8 []))
  (def configured (merge plain {:player (merge (plain :player) {:loadout {:items [] :runes [8210 8237] :shards [5008 5008 5011]}})}))
  (def actor (get-in (scenario/compile configured) [:actors 0]))
  (close 18 (get-in actor [:stats :ap]))
  (close 10 (get-in actor [:stats :ability-haste]))
  (close (+ 65 (get-in (scenario/compile plain) [:actors 0 :stats :hp])) (get-in actor [:stats :hp]))
  (assert (some |(= "rune/8237" ($ :id)) (actor :triggers)))
  (assert (not (some |(string/find "source formula unresolved" $) (actor :coverage))))
  (assert (= ((scenario/simulate configured) :metrics) ((scenario/fitness configured) :metrics)))
  (def searched (search/run package configured {:pool ["3153" "3115"] :slots 1 :budget 4000 :seconds 5 :final-samples 1}
                            (fn [progress] nil) (fn [] false)))
  (assert (searched :complete))
  (each row (searched :rows) (assert (= (row :metrics) ((scenario/fitness (row :definition)) :metrics))))
  (retain-case configured)
  # Older parser-7 packages can omit shard arrays. Use the bundled exact-patch
  # records without rewriting this immutable snapshot or its current pointer.
  (def old-data (tabseq [[key value] :pairs (util/read-data snapshot-file) :when (not= key :shards)] key value))
  (def old-bytes (util/encode-data old-data))
  (def old-id (hash/sha256 old-bytes))
  (def old-directory (string scratch "/patches/" patch "/" old-id))
  (util/write (string old-directory "/package.jdn") old-bytes)
  (util/write (string old-directory "/manifest.json") (util/encode-json {"initial" false "package_sha256" old-id}))
  (def old-definition (merge configured {:snapshot old-id}))
  (assert (= ((scenario/simulate configured) :metrics) ((scenario/simulate old-definition) :metrics)))
  (retain-case old-definition)
  (assert (= old-id (hash/sha256 (slurp (string old-directory "/package.jdn")))))
  (assert (= snapshot-bytes (string (slurp snapshot-file))))
  (assert (= (refreshed :snapshot) (string/trim (slurp (string scratch "/patches/" patch "/current")))))
  # A future patch does not inherit the reviewed semantics.
  (assert (empty? (effects/item-triggers (merge ((package :item-map) "3100") {:patch "16.22.1"}) true)))
  (assert (not (runes/supported-patch? "16.22.1")))
  (assert (empty? (forms/choices "Nidalee" "16.22.1")))
  (def kayle (merge ((package :champion-map) "Kayle") {:patch "16.22.1"}))
  (assert (= kayle (attacks/at-level kayle 18 {:q 5 :w 5 :e 5 :r 3}))))
(when-let [export (os/getenv "PS_LATEST_LOADOUT_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (each patch ["16.20.1" "16.21.1"]
    (util/copy-tree (string scratch "/patches/" patch) (string export "/seed/" patch)))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(util/remove-tree scratch)
(print "Latest loadouts: retained refresh, item/rune formulas, Kayle boundaries, four fixed forms, projectiles, tooltip scaling, both roles, optimizer parity and immutable snapshots passed.")
