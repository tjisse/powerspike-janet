(import ../src/powerspike/https :as https)
(import ../src/powerspike/storage :as storage)

(def pending @{})
(def failures @{})
(var active 0)
(var waiting 0)
(def maximum-bytes (* 1024 1024))
(defn clock [] (os/clock :monotonic))
(defn failure [path now]
  (def record (failures path))
  (when record
    (if (< now (record :expires)) record
      (do (put failures path nil) nil))))
(defn remember [path message now]
  (each key (keys failures) (failure key now))
  (when (>= (length failures) 256)
    (def oldest (first (sorted (keys failures) |(< (get-in failures [$0 :expires]) (get-in failures [$1 :expires])))))
    (put failures oldest nil))
  (def message (string message))
  (def record {:expires (+ now 30) :error (string/slice message 0 (min 1024 (length message)))})
  (put failures path record)
  record)
(defn unavailable [record now]
  {:status :failed :error (record :error) :retry-after (max 1 (math/ceil (- (record :expires) now)))})
(defn fetch [root path url quota &opt requester time-source]
  (label done
    (def request (or requester https/get-async))
    (def now (or time-source clock))
    (when (os/stat path) (put failures path nil) (return done {:status :ready :path path}))
    (when-let [record (failure path (now))] (return done (unavailable record (now))))
    (when (>= waiting 128) (return done {:status :busy :retry-after 1}))
    (++ waiting)
    (def waited (protect (while (or (>= active 8) (pending path)) (ev/sleep 0.02))))
    (-- waiting)
    (unless (first waited) (error (waited 1)))
    # Another request may have completed or failed while this caller waited.
    (when (os/stat path) (return done {:status :ready :path path}))
    (when-let [record (failure path (now))] (return done (unavailable record (now))))
    (++ active) (put pending path true)
    (def fetched (protect
                   (def bytes (request (if (function? url) (url) url) maximum-bytes))
                   (assert (<= (length bytes) maximum-bytes) "Provider asset exceeds 1 MB.")
                   (assert (string/has-prefix? "\x89PNG\r\n\x1a\n" bytes) "Provider asset is not PNG.")
                   (storage/write-async root path bytes quota)))
    (-- active) (put pending path nil)
    (if (first fetched) {:status :ready :path path}
      (unavailable (remember path (fetched 1) (now)) (now)))))
