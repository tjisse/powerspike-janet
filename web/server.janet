(import datastar :as ds)
(import datastar/adapter/spork :as adapter)
(import ./model :as model)
(import ./ui :as ui)
(import ./catalog :as catalog)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/jobs :as jobs)
(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/https :as https)

(def assets
  {"/assets/app.css" {:type "text/css; charset=utf-8" :body (slurp "web/assets/app.css")}
   "/assets/app.js" {:type "text/javascript" :body (slurp "web/assets/app.js")}
   "/assets/datastar.js" {:type "text/javascript" :body (slurp "build/web-assets/datastar.js")}})
(def evidence (model/evidence))
(def asset-pending @{})
(var asset-active 0)
(var asset-waiting 0)

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
  (assert (and (some |(= $ group) ["champion" "item" "spell" "passive"])
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
                     (def bytes (https/get-async (string "https://ddragon.leagueoflegends.com/cdn/" (package :patch) "/img/" group "/" file) (* 1024 1024)))
                     (assert (string/has-prefix? "\x89PNG\r\n\x1a\n" bytes) "Provider asset is not PNG.")
                     (assert (<= (+ (util/tree-size-async packages/data-dir) (* 8 1024 1024)) (packages/storage-limit)) "Data storage allowance reached.")
                     (util/atomic-write path bytes)))
      (-- asset-active) (put asset-pending path nil)
      (unless (first fetched) (error (string (fetched 1))))))
  (merge (response 200 (slurp path) "image/png")
         {:headers {"Content-Type" "image/png" "Cache-Control" "public, max-age=31536000, immutable" "X-Content-Type-Options" "nosniff"}}))

(defn evaluate [req]
  (def result (protect (model/compare-async (model/parse-state (ds/get-signals req)))))
  (adapter/sse-response req
                        {:on-open (fn [gen]
                                    (ds/with-open-sse gen
                                                      (ds/patch-elements gen
                                                                         (if (first result) (with-dyns [:patch-package ((result 1) :package)]
                                                                                              (ui/render (ui/results (result 1)) (ui/champion-display (result 1)) (ui/tactics (result 1))))
                                                                           (ui/render (ui/error-result (string (result 1))))))))}))

(defn app-inner [req]
  (cond
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
      (fragment req (ui/render (ui/patch-panel (model/context (model/parse-state {})) job))))
    (not= "GET" (req :method)) (response 405 "Use GET or a supported action." "text/plain")
    (= "/healthz" (req :route)) (response 200 "ok\n" "text/plain")
    (get assets (req :route)) (do (def asset (assets (req :route))) (response 200 (asset :body) (asset :type)))
    (string/has-prefix? "/assets/" (req :route)) (asset-response (req :route))
    (= "/patches/status" (req :route))
    (do (def signals (ds/get-signals req))
      (def job (jobs/get-job (get signals "job" "")))
      (fragment req (ui/render (ui/patch-panel (model/context (model/parse-state signals)) job))))
    (= "/api/patches" (req :route)) (response 200 (util/encode-json {:available catalog/patch-list :cached (packages/available)}) "application/json")
    (= "/" (req :route))
    (do (def result (protect (model/compare-async (model/parse-state (get req :query {})))))
      (if (first result) (with-dyns [:patch-package ((result 1) :package)] (response 200 (ui/page (result 1) evidence)))
        (response 400 (ui/page (model/compare (model/parse-state {})) evidence (string (result 1))))))
    (= "/evaluate" (req :route)) (evaluate req)
    (response 404 "Not found." "text/plain")))

(defn app [req]
  (def result (protect (app-inner req)))
  (if (first result) (result 1)
    (if (= "true" (get-in req [:headers "datastar-request"])) (fragment req (ui/render (ui/error-result (string (result 1)))))
      (response 400 (string (result 1)) "text/plain"))))

(defn start [port &opt host data seed]
  (catalog/initialize (or data "build/runtime-data") (or seed "build/seed"))
  (catalog/discover)
  (def address (or host "127.0.0.1"))
  (adapter/server app address port)
  (print "PowerSpike listening on http://" address ":" port)
  (flush))
