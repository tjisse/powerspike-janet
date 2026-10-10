(import datastar :as ds)
(import datastar/adapter/spork :as adapter)
(import ./model :as model)
(import ./ui :as ui)
(import ./catalog :as catalog)
(import ./optimizer :as optimizer)
(import ./workspace :as workspace)
(import ./details :as details)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/jobs :as jobs)
(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/https :as https)
(import ../src/powerspike/scenario-wire :as wire)
(import spork/http :as http)

(def assets
  {"/assets/app.css" {:type "text/css; charset=utf-8" :body (slurp "web/assets/app.css")}
   "/assets/hud.js" {:type "text/javascript" :body (slurp "web/assets/hud.js")}
   "/assets/app.js" {:type "text/javascript" :body (slurp "web/assets/app.js")}
   "/assets/datastar.js" {:type "text/javascript" :body (slurp "build/web-assets/datastar.js")}})
(def evidence (model/evidence))
(def asset-pending @{})
(var asset-active 0)
(var asset-waiting 0)
(def automatic-spell-jobs @{})

(defn needs-spell-data? [result]
  (def state (result :state))
  (and (get-in result [:package :manifest "initial"])
       (or (not= "Annie" (state :champion))
           (and (= "duel" (state :mode)) (not= "Annie" (state :opponent))))))

(defn spell-data-job [result]
  (def package (result :package))
  (when (and (not (get-in result [:state :snapshotlocked])) (needs-spell-data? result))
    (def current (packages/load (package :patch)))
    (if (not (get-in current [:manifest "initial"]))
      {:id "" :key (package :patch) :status :done
       :result {:patch (current :patch) :snapshot (current :snapshot)}
       :progress {:message "Champion abilities ready" :completed 1 :total 1}}
      (or (automatic-spell-jobs (package :patch))
          (let [job (jobs/fetch-patch (package :patch))]
            (put automatic-spell-jobs (package :patch) job) job)))))

(defn prepare-result [result &opt job-id]
  # A browser's explicit refresh remains tracked when combat controls change.
  # Imported scenarios start without an inherited job and keep their snapshot.
  (def requested (jobs/get-job (or job-id "")))
  (def manual (when (= :patch (get requested :kind)) requested))
  (def upgrade (if manual
                 (when (and (= (manual :key) (get-in result [:package :patch])) (needs-spell-data? result)) manual)
                 (spell-data-job result)))
  (merge result {:spell-data-job upgrade :patch-job (or manual upgrade)}))

(defn response [status body &opt content-type]
  {:status status :body body
   :headers {"Content-Type" (or content-type "text/html; charset=utf-8")
             "Cache-Control" "no-store" "X-Content-Type-Options" "nosniff"
             "Referrer-Policy" "same-origin"
             "Content-Security-Policy" "default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"}})

(defn fragment [req content]
  (adapter/sse-response req {:on-open (fn [gen]
                                        (ds/with-open-sse gen (ds/patch-elements gen content)))}))

(defn asset-response [route]
  (def parts (string/split "/" route))
  (def scoped (= 6 (length parts)))
  (assert (or scoped (= 4 (length parts))) "Invalid asset path.")
  (def package (if scoped (packages/load (parts 2) (parts 3)) (catalog/current)))
  (def group (parts (if scoped 4 2)))
  (def file (parts (if scoped 5 3)))
  (assert (and (some |(= $ group) ["champion" "item" "spell" "passive" "rune"])
               (util/safe-id? file) (string/has-suffix? ".png" file)) "Invalid asset identifier.")
  (def path (string (package :directory) "/assets/" group "/" file))
  (unless (os/stat path)
    (assert (< asset-waiting 128) "Asset queue is full. Retry shortly.")
    (++ asset-waiting)
    (while (or (>= asset-active 8) (asset-pending path)) (ev/sleep 0.02))
    (-- asset-waiting)
    (unless (os/stat path)
      (++ asset-active) (put asset-pending path true)
      (def fetched (protect
                     (def bytes (https/get-async (if (= group "rune") (details/rune-source package file)
                                                   (string "https://ddragon.leagueoflegends.com/cdn/" (package :patch) "/img/" group "/" file)) (* 1024 1024)))
                     (assert (string/has-prefix? "\x89PNG\r\n\x1a\n" bytes) "Provider asset is not PNG.")
                     (assert (<= (+ (util/tree-size-async packages/data-dir) (* 8 1024 1024)) (packages/storage-limit)) "Data storage allowance reached.")
                     (util/atomic-write path bytes)))
      (-- asset-active) (put asset-pending path nil)
      (unless (first fetched) (error (string (fetched 1))))))
  (merge (response 200 (slurp path) "image/png")
         {:headers {"Content-Type" "image/png" "Cache-Control" "public, max-age=31536000, immutable" "X-Content-Type-Options" "nosniff"}}))

(defn show-result [req result &opt state job-id]
  (def prepared (prepare-result result job-id))
  (adapter/sse-response req
                        {:on-open (fn [gen]
                                    (ds/with-open-sse gen
                                                      (when state
                                                        (def values (ui/signals state))
                                                        (when (= "/search/apply" (req :route))
                                                          (def input (ds/get-signals req))
                                                          (each key [:searchbudget :searchslots :searchseconds :searchpreset :searchpool :searchexclude :nextpurchase :searchrunes :searchsummoners :searchskills]
                                                            (when (has-key? input (string key)) (put values key (get input (string key))))))
                                                        (ds/patch-signals gen values))
                                                      (with-dyns [:patch-package (prepared :package)]
                                                        (ds/patch-elements gen
                                                                           (ui/render (ui/results prepared) (ui/loadout prepared) (ui/fight-controls prepared)
                                                                                      (when (= "/search/apply" (req :route)) (optimizer/panel prepared nil (get-in req [:query "id"])))
                                                                                      (ui/tactics prepared) (optimizer/rune-editor (prepared :package) (prepared :state))
                                                                                      (ui/patch-panel prepared (prepared :patch-job))
                                                                                      (workspace/tools prepared) (ui/coverage prepared) (workspace/evidence prepared))))))}))
(defn evaluate [req]
  (def input (ds/get-signals req))
  (def result (protect (model/compare-async (model/parse-state input))))
  (if (first result) (show-result req (result 1) nil (get input "job")) (fragment req (ui/render (ui/error-result (string (result 1)))))))

(defn app-inner [req]
  (cond
    (and (= "POST" (req :method)) (= "/details/item" (req :route)))
    (do
      (def size (scan-number (get-in req [:headers "content-length"] "0")))
      (assert (and size (<= 0 size 65536)) "Tooltip scenario must fit within 64 KB.")
      (def definition (wire/decode (http/read-body req)))
      (def package (packages/load (definition :patch) (definition :snapshot)))
      (def item ((package :item-map) (get-in req [:query "id"])))
      (assert item "Item unavailable on this patch.")
      (def opponent (= "opponent" (get-in req [:query "who"])))
      (with-dyns [:patch-package package]
        (response 200 (util/encode-json (details/item item (details/scenario-context definition opponent))) "application/json")))
    (and (= "POST" (req :method)) (= "/scenario/import" (req :route)))
    (do (def input (ds/get-signals req))
      (def definition (wire/decode (get input "scenariojson" "")))
      (def state (model/state-from-definition definition))
      (def result (model/compare-async state))
      (show-result req result state))
    (and (= "POST" (req :method)) (= "/search" (req :route)))
    (do (def input (ds/get-signals req)) (def state (model/parse-state input))
      (def job (model/optimize input))
      (with-dyns [:patch-package ((model/context state) :package)]
        (fragment req (ui/render (optimizer/panel (model/context state) job)))))
    (= "/search/status" (req :route))
    (do (def input (ds/get-signals req)) (def job (jobs/get-job (get input "searchjob" "")))
      (def state (model/parse-state input))
      (fragment req (ui/render (optimizer/panel (model/context state) job))))
    (and (= "POST" (req :method)) (= "/search/apply" (req :route)))
    (do (def job (jobs/get-job (get-in req [:query "id"])))
      (assert (and job (= :optimization (job :kind)) (jobs/terminal? job)) "Wait for the search to finish or cancel it before applying a recommendation.")
      (def row (find |(= ($ :key) (get-in req [:query "key"])) (get-in job [:result :rows] [])))
      (assert row "Recommendation is no longer retained. Run the search again.")
      (def state (model/state-from-definition (row :definition)))
      (def result (model/compare-async state))
      (show-result req result state))
    (and (= "POST" (req :method)) (= "/patches" (req :route)))
    (do
      (def signals (ds/get-signals req))
      (def patch (get signals "patchchoice" packages/default-version))
      (assert (some |(= $ patch) catalog/patch-list) "Choose a published patch.")
      (def result (model/context (model/parse-state signals)))
      (def cached (and (not= "true" (get-in req [:query "refresh"]))
                       (some |(= $ patch) (packages/available))))
      (def job (if cached {:id "" :key patch :status :done :result {:patch patch :snapshot ((packages/load patch) :snapshot)}
                           :progress {:message "Cached" :completed 1 :total 1}} (jobs/fetch-patch patch)))
      (fragment req (ui/render (ui/patch-panel result job))))
    (and (= "POST" (req :method)) (= "/jobs/cancel" (req :route)))
    (do (def job (jobs/cancel (get-in req [:query "id"])))
      (fragment req (ui/render (if (= :optimization (job :kind))
                                 (optimizer/panel (model/context (model/parse-state (ds/get-signals req))) job)
                                 (ui/patch-panel (model/context (model/parse-state {})) job)))))
    (not= "GET" (req :method)) (response 405 "Use GET or a supported action." "text/plain")
    (= "/healthz" (req :route)) (response 200 "ok\n" "text/plain")
    (get assets (req :route)) (do (def asset (assets (req :route))) (response 200 (asset :body) (asset :type)))
    (string/has-prefix? "/assets/" (req :route)) (asset-response (req :route))
    (= "/patches/status" (req :route))
    (do (def signals (ds/get-signals req))
      (def job (jobs/get-job (get signals "job" "")))
      (def state (model/parse-state signals))
      (def context (model/context state))
      (def stopped (and job (some |(= $ (job :status)) [:failed :cancelled])
                        (= (job :key) (state :patch)) (needs-spell-data? context)))
      (if stopped
        (do (def result (merge (model/compare-async state) {:spell-data-job job :patch-job job}))
          (fragment req (with-dyns [:patch-package (result :package)]
                          (ui/render (ui/patch-panel result job) (ui/results result)))))
        (fragment req (ui/render (ui/patch-panel context job)))))
    (= "/api/patches" (req :route)) (response 200 (util/encode-json {:available catalog/patch-list :cached (packages/available)}) "application/json")
    (= "/" (req :route))
    (do (def query (get req :query {}))
      (def result (protect (model/compare-async
                             (if (get-in req [:query "scenario"])
                               (model/state-from-definition (wire/decode (get-in req [:query "scenario"])))
                               (model/parse-state (merge {"snapshotlocked" (has-key? query "snapshot")} query))))))
      (if (first result) (do
                           (def prepared (prepare-result (result 1)))
                           (with-dyns [:patch-package (prepared :package)] (response 200 (ui/page prepared evidence))))
        (response 400 (ui/page (model/compare (model/parse-state {})) evidence (string (result 1))))))
    (= "/evaluate" (req :route)) (evaluate req)
    (response 404 "Not found." "text/plain")))

(defn app [req]
  (def result (protect (app-inner req)))
  (if (first result) (result 1)
    (if (= "true" (get-in req [:headers "datastar-request"]))
      (fragment req (ui/render (if (string/has-prefix? "/search" (req :route))
                                 (optimizer/error-panel (string (result 1))) (ui/error-result (string (result 1))))))
      (response 400 (string (result 1)) "text/plain"))))

(defn start [port &opt host data seed]
  (catalog/initialize (or data "build/runtime-data") (or seed "build/seed"))
  (catalog/discover)
  (def address (or host "127.0.0.1"))
  (adapter/server app address port)
  (print "PowerSpike listening on http://" address ":" port)
  (flush))
