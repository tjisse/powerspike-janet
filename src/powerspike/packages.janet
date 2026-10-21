(import ./data-util :as util)
(import ./https :as https)
(import ./normalize :as normalize)
(import ./expressions :as expr)
(import ./tooltip :as tooltip)
(import ./objectives :as objectives)
(import ./runes :as rune-data)
(import ./storage :as storage)
(import pshash :as hash)

(var data-dir nil)
(var default-version "16.19.1")
(def loaded @{})
(defn refresh-timeout []
  (def seconds (scan-number (os/getenv "PS_PATCH_TIMEOUT_SECONDS" "300")))
  (assert (and (number? seconds) (= seconds (math/floor seconds)) (<= 1 seconds 1800))
          "PS_PATCH_TIMEOUT_SECONDS must be a whole number from 1 to 1800.")
  seconds)
(defn storage-limit []
  (def text (os/getenv "PS_DATA_LIMIT_MB" "5120"))
  (def megabytes (scan-number text))
  (assert (and (number? megabytes) (= megabytes (math/floor megabytes)) (<= 100 megabytes 1048576))
          "PS_DATA_LIMIT_MB must be a whole number from 100 to 1048576.")
  (* megabytes 1024 1024))
(defn directory [version snapshot]
  (assert (util/version? version) "Invalid patch identifier.")
  (assert (and (string? snapshot) (= 64 (length snapshot))
               (peg/match ~(* (some (range "09" "af")) -1) snapshot)) "Invalid snapshot identifier.")
  (string data-dir "/patches/" version "/" snapshot))

(defn available []
  (def root (string data-dir "/patches"))
  (if (os/stat root) (filter |(and (util/version? $) (os/stat (string root "/" $ "/current"))) (os/dir root)) []))

(defn load [version &opt snapshot]
  (assert data-dir "Initialize the runtime data directory first.")
  (assert (util/version? version) "Invalid patch identifier.")
  (def id (or snapshot (string/trim (slurp (string data-dir "/patches/" version "/current")))))
  (def key (string version "/" id))
  (or (loaded key)
      (do
        (def dir (directory version id))
        (def bytes (slurp (string dir "/package.jdn")))
        (def manifest (util/read-json (slurp (string dir "/manifest.json"))))
        (assert (= id (hash/sha256 bytes) (manifest "package_sha256")) "Corrupted data snapshot.")
        (def data (util/read-data (string dir "/package.jdn")))
        (assert (and (= 1 (data :schema)) (= version (data :patch))) "Incompatible data package.")
        (def champions (map |(normalize/semantic-kit ($ :id) version $) (data :champions)))
        (def items (map normalize/semantic-item (data :items)))
        (def runes (normalize/semantic-runes (get data :runes []) version))
        (def summoners (map |(merge $ {:parsed (expr/refresh (get $ :parsed {}) (get $ :record {}))}) (get data :summoners [])))
        (def shard-source (string dir "/sources/rune-effects.json"))
        (def shard-data (when (and (not (has-key? data :shards)) (os/stat shard-source))
                          (def bytes (slurp shard-source))
                          (def source (find |(= "sources/rune-effects.json" (get $ "path")) (get manifest "sources" [])))
                          (assert (and source (= (source "sha256") (hash/sha256 bytes))) "Rune source integrity check failed.")
                          (rune-data/shard-records (util/read-json bytes) version)))
        (def package (merge data {:snapshot id :directory dir :manifest manifest :champions champions
                                  :champion-map (tabseq [champion :in champions] (champion :id) champion)
                                  :items items :runes runes :summoners summoners
                                  :item-map (tabseq [item :in items] (item :id) item)}))
        (when shard-data (put package :shards shard-data))
        (when (and (not (has-key? package :shards)) (rune-data/source-data version))
          (put package :rune-sources ((rune-data/source-data version) :sources)))
        (when (and (manifest "initial") (empty? (get package :runes [])) (rune-data/source-data version))
          (def retained (rune-data/source-data version))
          (put package :runes (normalize/rune-effects (retained :styles) (retained :records) {} version)))
        (when (>= (length loaded) 4) (put loaded (first (keys loaded)) nil))
        (put loaded key package)
        package)))

(defn initialize [directory seed]
  (storage-limit)
  (refresh-timeout)
  (storage/initialize)
  (each key (keys loaded) (put loaded key nil))
  (set data-dir (util/mkdirs directory))
  (util/mkdirs (string data-dir "/patches"))
  (util/mkdirs (string data-dir "/jobs"))
  (when (and seed (os/stat seed))
    (each version (os/dir seed)
      (when (and (util/version? version) (not (os/stat (string data-dir "/patches/" version "/current"))))
        (storage/exclusive
          (fn []
            (when (and (not (os/stat (string data-dir "/patches/" version "/current")))
                       (<= (+ (util/tree-size data-dir) (util/tree-size (string seed "/" version))) (storage-limit)))
              (util/copy-tree (string seed "/" version) (string data-dir "/patches/" version))))))))
  (def patches (available))
  (assert (not (empty? patches)) "No cached patches. Check PS_SEED_DIR and allow enough PS_DATA_LIMIT_MB space to import the seed.")
  (def candidates (if (some |(= default-version $) patches) [default-version ;patches] patches))
  (var selected nil)
  (each version candidates
    (unless selected
      (def result (protect (load version)))
      (when (first result) (set selected (result 1)) (set default-version version))))
  (assert selected "No usable data snapshots. Restore a retained package or reinstall the seed data.")
  selected)

(defn versions []
  (def path (string data-dir "/versions.json"))
  (def response (protect (https/get-async "https://ddragon.leagueoflegends.com/api/versions.json")))
  (when (first response)
    (def values (util/read-json (response 1)))
    (assert (and (indexed? values) (not (some |(not (util/version? $)) values))) "Invalid provider patch list.")
    # Discovery must not make cached patches unusable when storage is full.
    (protect (storage/write-async data-dir path (response 1) (storage-limit))))
  (if (os/stat path) (util/read-json (slurp path)) (available)))

(defn parser-mismatch? [package]
  (not= normalize/parser-version (get package :parser)))

(defn raw-sources? [package]
  (def paths (map |(get $ "path") (get-in package [:manifest "sources"] [])))
  (and (some |(= "sources/champions.json" $) paths)
       (some |(= "sources/items.json" $) paths) true))

# Fetching and explicit local reparsing share the same normalization pipeline.
# Executed only on a background worker. Publish the current pointer last.
(defn- build-patch [version staging progress cancelled requester clock retained]
  (assert (util/version? version) "Invalid patch identifier.")
  (def now (or clock (fn [] (os/clock :monotonic))))
  (def deadline (+ (now) (refresh-timeout)))
  (defn check []
    (when (cancelled) (error "Cancelled."))
    (when (>= (now) deadline)
      (error (string "Patch " (if retained "reparse" "refresh") " timed out. Cached patches remain available. Try again."))))
  (def request (or requester (fn [url cancelled] (https/get url cancelled nil deadline))))
  (def sources @[])
  (def missing @[])
  (def quota (storage-limit))
  (defn obtain [url relative &opt optional]
    (check)
    (def source (get-in retained [:sources relative]))
    # A retained source that is missing or corrupt is an integrity failure,
    # including for optional inputs. Never replace it with a silent gap.
    (def local (when source
                 (def path (string (retained :directory) "/" relative))
                 (assert (os/stat path) (string "Saved source missing: " relative ". Refresh patch data to download it again."))
                 (assert (<= (os/stat path :size) (* 64 1024 1024)) "Saved source exceeds the provider file-size limit.")
                 (def bytes (slurp path))
                 (assert (= (source "sha256") (hash/sha256 bytes))
                         (string "Saved source integrity check failed: " relative ". Refresh patch data to download it again."))
                 bytes))
    (def result (if retained
                  (if source [true local] [false "Source was not retained."])
                  (protect (request url cancelled))))
    # Optional provider errors can reduce coverage; expiry/cancellation must
    # instead stop the entire refresh and preserve the previous current pointer.
    (check)
    (if (first result)
      (do
        (def bytes (result 1))
        (storage/write data-dir (string staging "/" relative) bytes quota)
        (array/push sources {"url" (if source (source "url") url) "path" relative "sha256" (hash/sha256 bytes)})
        (util/read-json bytes))
      (if optional (do (array/push missing (string "Unavailable source: " relative)) nil)
        (error (string (result 1))))))
  (util/mkdirs staging)
  (def dd (string "https://ddragon.leagueoflegends.com/cdn/" version "/data/en_US/"))
  (def cd (string "https://raw.communitydragon.org/" (util/cdragon-version version) "/"))
  (progress {:message (if retained "Reading saved champion and item catalog" "Downloading champion and item catalog") :completed 0 :total 1})
  (def champion-data (obtain (string dd "champion.json") "sources/champions.json"))
  (def item-data (obtain (string dd "item.json") "sources/items.json"))
  (assert (and (util/provider-version? version (champion-data "version"))
               (= (champion-data "version") (item-data "version"))) "Provider patch mismatch.")
  (def runes (obtain (string dd "runesReforged.json") "sources/runes.json" true))
  (def summoners (obtain (string dd "summoner.json") "sources/summoners.json" true))
  (progress {:message (if retained "Reading saved ability descriptions" "Downloading localized ability descriptions") :completed 0 :total 1})
  (def strings (or (obtain (string cd "game/en_us/data/menu/en_us/lol.stringtable.json?powerspike=1") "sources/strings.json" true)
                   (obtain (string cd "game/data/menu/fontconfig_en_us.txt.json?powerspike=1") "sources/strings-legacy.json" true)))
  (def fonts (if strings (get strings "entries" strings) {}))
  (def item-records (or (obtain (string cd "game/items.cdtb.bin.json?powerspike=1") "sources/item-effects.json" true) {}))
  (def perk-records (or (obtain (string cd "game/perks.cdtb.bin.json?powerspike=1") "sources/rune-effects.json" true) {}))
  (def shared-records (or (obtain (string cd "game/shared.cdtb.bin.json?powerspike=1") "sources/shared-effects.json" true) {}))
  (def objective-records
    (map (fn [preset]
           (progress {:message (string (if retained "Parsing " "Downloading ") (preset :name)) :completed 0 :total 1})
           (def name (preset :file))
           (def records (obtain (string cd "game/data/characters/" name "/" name ".bin.json?powerspike=1")
                                (string "sources/objectives/" name ".json") true))
           (objectives/normalize preset (or records {}) item-records version)) objectives/presets))
  (def champions @[])
  (def ids (sorted (keys (champion-data "data"))))
  (eachp [index id] ids
    (check)
    (progress {:message (string (if retained "Parsing " "Downloading ") id) :completed index :total (length ids)})
    (def name (string/ascii-lower id))
    (def objects (obtain (string cd "game/data/characters/" name "/" name ".bin.json?powerspike=1")
                         (string "sources/characters/" id ".json") true))
    (def detail (obtain (string dd "champion/" id ".json") (string "sources/abilities/" id ".json") true))
    (when detail (assert (util/provider-version? version (detail "version")) "Ability data patch mismatch."))
    (array/push champions (merge (normalize/champion version ((champion-data "data") id) (or objects {}))
                                 (normalize/kit id (or objects {}) (or detail {}) fonts version))))
  (def package {:schema 1 :parser normalize/parser-version :patch version :communitydragon (util/cdragon-version version)
                :champions champions
                :items (seq [id :in (sorted (keys (item-data "data")))]
                         (normalize/item-effects (normalize/item version id ((item-data "data") id)) item-records fonts))
                :runes (normalize/rune-effects (if (indexed? runes) runes []) perk-records fonts version)
                :shards (rune-data/shard-records perk-records version)
                :summoners (if summoners (map (fn [spell]
                                                (def record (get-in shared-records [(string "Shared/Spells/" (spell "id")) "mSpell"] {}))
                                                (merge spell {:parsed (tooltip/parse (get spell "tooltip" "") record spell)
                                                              :record record :available true :checked false})) (values (summoners "data"))) [])
                :objectives objective-records :coverage missing :sources sources})
  (def bytes (util/encode-data package))
  (check)
  (def id (hash/sha256 bytes))
  (storage/write data-dir (string staging "/package.jdn") bytes quota)
  (storage/write data-dir (string staging "/manifest.json")
                 (util/encode-json (merge {"schema" 1 "patch" version "snapshot" id "parser" normalize/parser-version "package_sha256" id
                                           "sources" sources "downloaded_at" (if retained (get-in retained [:manifest "downloaded_at"]) (os/time)) "initial" false}
                                          (if retained {"reparsed_at" (os/time) "reparsed_from" (retained :snapshot)} {}))) quota)
  (check)
  (def destination (directory version id))
  (storage/publish data-dir staging destination (string data-dir "/patches/" version "/current") id quota check)
  {:patch version :snapshot id})

(defn fetch [version staging progress cancelled &opt requester clock]
  (build-patch version staging progress cancelled requester clock nil))

(defn reparse [version snapshot staging progress cancelled &opt clock]
  (def package (load version snapshot))
  (assert (raw-sources? package) "Saved raw data is unavailable. Refresh patch data to download it.")
  (assert (= (util/canonical (get package :sources [])) (util/canonical (get-in package [:manifest "sources"] [])))
          "Saved source manifest does not match the snapshot. Refresh patch data to download it again.")
  (def sources @{})
  (each source (get-in package [:manifest "sources"] [])
    (def path (get source "path"))
    (assert (and (string? path) (string/has-prefix? "sources/" path)
                 (all |(and (util/safe-id? $) (not= "." $)) (string/split "/" path)))
            "Invalid saved source path.")
    (assert (not (sources path)) "Duplicate saved source path.")
    (put sources path source))
  (build-patch version staging progress cancelled nil clock
               {:directory (package :directory) :snapshot snapshot :manifest (package :manifest) :sources sources}))
