(import jurl)
(import jurl/native :as native)

(def hosts ["https://ddragon.leagueoflegends.com/" "https://raw.communitydragon.org/"])
(defn get [url &opt cancelled limit deadline]
  (assert (some |(string/has-prefix? $ url) hosts) "Unsupported data provider.")
  (defn expired? [] (and deadline (>= (os/clock :monotonic) deadline)))
  (defn check []
    (when (and cancelled (cancelled)) (error "Cancelled."))
    (when (expired?) (error "Provider request timed out.")))
  (check)
  (def timeout (if deadline (min 45000 (max 1 (math/ceil (* 1000 (- deadline (os/clock :monotonic)))))) 45000))
  (def output @"")
  (def maximum (or limit (* 64 1024 1024)))
  (def response (jurl/request
                  {:url url :method :get
                   :options {:protocols "https" :followlocation false :ssl-verifypeer true :ssl-verifyhost 2
                             :connecttimeout-ms (min 5000 timeout) :timeout-ms timeout :maxfilesize maximum
                             :useragent "Mozilla/5.0 PowerSpike/2" :nosignal true
                             :noprogress (not (or cancelled deadline))
                             :xferinfofunction (fn [& counts] (not (or (expired?) (and cancelled (cancelled)))))}
                   :stream (fn [bytes]
                             (if (or (expired?) (and cancelled (cancelled)) (> (+ (length output) (length bytes)) maximum))
                               0 (do (buffer/push output bytes) (length bytes))))}))
  (native/reset (response :handle))
  (check)
  (assert (and (= :ok (response :error)) (= 200 (response :status)))
          (string "Provider request failed (" (response :status) "): " url))
  (string output))

(defn get-async [url &opt limit]
  (def channel (ev/thread-chan 1))
  (ev/thread (fn [[channel url limit]] (ev/give channel (protect (get url nil limit)))) [channel url limit] :n)
  (def result (ev/take channel))
  (unless (first result) (error (string (result 1))))
  (result 1))
