(import datastar :as ds)
(import datastar/adapter/spork :as adapter)
(import ./model :as model)
(import ./ui :as ui)
(import ./catalog :as catalog)

(def assets
  (merge {"/assets/app.css" {:type "text/css; charset=utf-8" :body (slurp "web/assets/app.css")}
          "/assets/app.js" {:type "text/javascript" :body (slurp "web/assets/app.js")}
          "/assets/datastar.js" {:type "text/javascript" :body (slurp "build/web-assets/datastar.js")}}
         (tabseq [entry :in [;(map |["champion" ($ :icon)] catalog/champion-list)
                             ;(map |["item" ($ :icon)] catalog/item-list)
                             ["spell" "AnnieQ"] ["spell" "AnnieW"]]]
           (string "/assets/" (entry 0) "/" (entry 1) ".png")
           {:type "image/png" :body (slurp (string "build/web-assets/" (entry 0) "/" (entry 1) ".png"))})))
(def evidence (model/evidence))

(defn response [status body &opt content-type]
  {:status status :body body
   :headers {"Content-Type" (or content-type "text/html; charset=utf-8")
             "Cache-Control" "no-store" "X-Content-Type-Options" "nosniff"
             "Referrer-Policy" "same-origin"
             "Content-Security-Policy" "default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"}})

(defn evaluate [req]
  (def result (protect (model/compare (model/parse-state (ds/get-signals req)))))
  (adapter/sse-response req
                        {:on-open (fn [gen]
                                    (ds/with-open-sse gen
                                                      (ds/patch-elements gen
                                                                         (if (first result) (ui/render (ui/results (result 1)) (ui/champion-display (result 1)))
                                                                           (ui/render (ui/error-result (string (result 1))))))))}))

(defn app [req]
  (cond
    (not= "GET" (req :method)) (response 405 "Use GET." "text/plain")
    (= "/healthz" (req :route)) (response 200 "ok\n" "text/plain")
    (get assets (req :route)) (do (def asset (assets (req :route))) (response 200 (asset :body) (asset :type)))
    (= "/" (req :route))
    (do (def result (protect (model/compare (model/parse-state (get req :query {})))))
      (if (first result) (response 200 (ui/page (result 1) evidence))
        (response 400 (ui/page (model/compare model/default-state) evidence (string (result 1))))))
    (= "/evaluate" (req :route)) (evaluate req)
    (response 404 "Not found." "text/plain")))

(defn start [port &opt host]
  (def address (or host "127.0.0.1"))
  (adapter/server app address port)
  (print "PowerSpike listening on http://" address ":" port)
  (flush))
