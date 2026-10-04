(import jurl)
(import jurl/native :as native)

(def hosts ["https://ddragon.leagueoflegends.com/" "https://raw.communitydragon.org/"])
(defn get [url &opt cancelled limit]
  (assert (some |(string/has-prefix? $ url) hosts) "Unsupported data provider.")
  (def output @"")
  (def maximum (or limit (* 64 1024 1024)))
  (def response (jurl/request
                  {:url url :method :get
                   :options {:protocols "https" :followlocation false :ssl-verifypeer true :ssl-verifyhost 2
                             :connecttimeout-ms 5000 :timeout-ms 45000 :maxfilesize maximum
                             :useragent "Mozilla/5.0 PowerSpike/2" :nosignal true}
                   :stream (fn [bytes]
                             (if (or (and cancelled (cancelled)) (> (+ (length output) (length bytes)) maximum))
                               0 (do (buffer/push output bytes) (length bytes))))}))
  (native/reset (response :handle))
  (when (and cancelled (cancelled)) (error "Cancelled."))
  (assert (and (= :ok (response :error)) (= 200 (response :status)))
          (string "Provider request failed (" (response :status) "): " url))
  (string output))

(defn get-async [url &opt limit]
  (def channel (ev/thread-chan 1))
  (ev/thread (fn [[channel url limit]] (ev/give channel (protect (get url nil limit)))) [channel url limit] :n)
  (def result (ev/take channel))
  (unless (first result) (error (string (result 1))))
  (result 1))
