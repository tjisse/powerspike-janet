(import ./data-util :as util)
(import ./packages :as packages)
(import pshash :as hash)
(def records @{})
(def queue @[])
(var active nil)
(defn get-job [id] (get records id))
(defn terminal? [job] (some |(= $ (job :status)) [:done :failed :cancelled]))
(defn cancel [id]
  (def job (records id))
  (assert job "Unknown job.")
  (unless (terminal? job)
    (util/write (job :cancel-file) "cancel")
    (put job :status (if (= :queued (job :status)) :cancelled :cancelling)))
  job)
(defn pump []
  (unless active
    (while (not (empty? queue))
      (def selected (first queue))
      (array/remove queue 0 1)
      (unless (terminal? selected)
        (set active (selected :id))
        (put selected :status :running)
        (def channel (ev/thread-chan 8))
        (ev/thread
          (fn [[channel task input cancel-file]]
            (def result (protect
                          (task input (fn [value] (ev/give channel [:progress value]))
                                (fn [] (os/stat cancel-file)))))
            (ev/give channel [:finished result]))
          [channel (selected :task) (selected :input) (selected :cancel-file)] :n)
        (ev/go (fn []
                 (forever
                   (def message (ev/take channel))
                   (case (first message)
                     :progress (put selected :progress (message 1))
                     :finished
                     (do
                       (def result (message 1))
                       (cond
                         (os/stat (selected :cancel-file)) (put selected :status :cancelled)
                         (first result) (do (put selected :status :done) (put selected :result (result 1)))
                         (do (put selected :status :failed) (put selected :error (string (result 1)))))
                       (util/remove-tree (selected :cancel-file))
                       (put selected :task nil) (put selected :input nil)
                       (set active nil) (pump) (break))))))
        (break)))))
(defn submit [kind key task input]
  (def shared (find |(and (= kind ($ :kind)) (= key ($ :key)) (not (terminal? $))) (values records)))
  (or shared
      (do
        (assert (< (length queue) 8) "The work queue is full. Try again shortly.")
        (def id (string/slice (hash/sha256 (os/cryptorand 32)) 0 32))
        (def job @{:id id :kind kind :key key :status :queued :task task :input input
                   :cancel-file (string packages/data-dir "/jobs/" id ".cancel")
                   :progress {:message "Queued" :completed 0 :total 1}})
        (put records id job) (array/push queue job)
        (when (> (length records) 64)
          (def old (find terminal? (values records)))
          (when old (put records (old :id) nil)))
        (pump) job)))
(defn fetch-task [input progress cancelled]
  (def staging (string packages/data-dir "/jobs/" (input :id) ".download"))
  (def result (protect (packages/fetch (input :patch) staging progress cancelled)))
  (unless (first result) (util/remove-tree staging) (error (string (result 1))))
  (result 1))
(defn fetch-patch [patch]
  (assert (util/version? patch) "Invalid patch identifier.")
  (submit :patch patch fetch-task {:patch patch :id (string/slice (hash/sha256 (os/cryptorand 16)) 0 16)}))
