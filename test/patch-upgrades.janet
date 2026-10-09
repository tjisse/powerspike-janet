(import ../web/server :as server)
(import ../web/model :as model)
(import ../web/catalog :as catalog)
(import ../web/ui :as ui)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/jobs :as jobs)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

# Synthetic revisions and jobs exercise navigation without provider requests.
(def root (string "build/patch-upgrade-tests/" (hash/sha256 (os/cryptorand 8))))
(def seed (catalog/initialize root "build/seed"))
(set catalog/versions-ready true)
(def pending @{:id "automatic-fixture" :kind :patch :key "16.19.1" :status :running
               :progress {:message "Downloading" :completed 1 :total 173}})
(put server/automatic-spell-jobs "16.19.1" pending)
(put jobs/records (pending :id) pending)
(defn compare [fields]
  (model/compare (model/parse-state (merge {"selected" "custom"} fields))))
(defn emitted [response]
  (def output @"")
  ((response :on-open) @{:send-event (fn [self event context] (buffer/push output event) true)
                         :close (fn [self] true)})
  (string output))
(defn evaluate [fields]
  (emitted (server/app-inner {:method "GET" :route "/evaluate"
                              :query {"datastar" (util/encode-json fields)}})))

(def ahri (compare {"champion" "Ahri"}))
(assert (= pending (server/spell-data-job ahri)))
(assert (nil? (server/spell-data-job (compare {"champion" "Annie"}))))
(def duel (compare {"champion" "Annie" "opponent" "Ahri" "mode" "duel"}))
(def prepared (server/prepare-result duel))
(assert (= pending (prepared :patch-job) (prepared :spell-data-job)))
(assert (string/find "Downloading ability data for Ahri" (ui/render (ui/results prepared))))
(assert (nil? (server/spell-data-job (compare {"champion" "Annie" "opponent" "Annie" "mode" "duel"}))))

(def document (wire/encode (get-in ahri [:selected :combat :scenario])))
(def restored (model/state-from-definition (wire/decode document)))
(assert (restored :snapshotlocked))
(assert (nil? (server/spell-data-job (model/compare restored))))
(def signals (model/parse-state (util/read-json (util/encode-json (ui/signals restored)))))
(assert (signals :snapshotlocked))
(assert (= (seed :snapshot) (signals :snapshot)))
(assert (nil? (server/spell-data-job (model/compare signals))))
(def imported (emitted (server/app-inner {:method "POST" :route "/scenario/import"
                                          :body (buffer (util/encode-json {"scenariojson" document "job" (pending :id)}))})))
(assert (not (string/find "Downloading ability data" imported)))
(assert (not (string/find (pending :id) imported)))

# A completed revision is cached, while the saved document still pins the seed.
(def bytes (util/encode-data (merge (util/read-data (string (seed :directory) "/package.jdn")) {:parser "navigation-fixture"})))
(def complete-id (hash/sha256 bytes))
(def complete-dir (packages/directory "16.19.1" complete-id))
(util/write (string complete-dir "/package.jdn") bytes)
(util/write (string complete-dir "/manifest.json") (util/encode-json {"initial" false "package_sha256" complete-id}))
(util/atomic-write (string root "/patches/16.19.1/current") complete-id)
(def shared (server/app-inner {:method "GET" :route "/" :query {"scenario" document}}))
(assert (= 200 (shared :status)))
(assert (string/find (seed :snapshot) (shared :body)))
(assert (not (string/find "location.assign(next)" (shared :body))))
(def pinned (server/app-inner {:method "GET" :route "/" :query {"champion" "Ahri" "snapshot" (seed :snapshot)}}))
(assert (not (string/find "location.assign(next)" (pinned :body))))
(def latest (server/prepare-result ahri))
(assert (= complete-id (get-in latest [:patch-job :result :snapshot])))

# Each browser keeps its own explicit refresh, including refreshes of other patches.
(def manual @{:id "manual-fixture" :kind :patch :key "16.19.1" :status :running
              :progress {:message "Downloading" :completed 2 :total 173}})
(put jobs/records (manual :id) manual)
(each champion ["Annie" "Ahri"]
  (def text (evaluate {"champion" champion "duration" 8 "job" (manual :id)}))
  (assert (string/find (manual :id) text))
  (assert (string/find "data-poll=\"true\"" text)))
(put manual :key "16.18.1")
(assert (string/find "16.18.1" (evaluate {"champion" "Annie" "job" (manual :id)})))
(put manual :status :done)
(put manual :result {:patch "16.18.1" :snapshot (string/repeat "b" 64)})
(def finished (evaluate {"champion" "Annie" "job" (manual :id)}))
(assert (string/find "location.assign(next)" finished))
(assert (string/find (string/repeat "b" 64) finished))
(put jobs/records "compute-fixture" {:id "compute-fixture" :kind :simulation :status :running})
(assert (nil? (get-in (server/prepare-result (compare {"champion" "Annie"}) "compute-fixture") [:patch-job])))

(util/remove-tree root)
(print "Saved/imported/shared snapshots, explicit snapshot links, manual refresh tracking and both duel participants passed.")
