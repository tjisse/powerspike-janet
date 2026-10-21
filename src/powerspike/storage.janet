(import ./data-util :as util)

# Thread channels retain their shared identity when a worker VM is cloned.
# All writers in one service process use this gate, including patch downloads.
(var gate nil)
(defn initialize []
  # Create the channel in the running process, before cloning worker VMs.
  # Executable images must not contain a build-time channel instance.
  (unless gate
    (set gate (ev/thread-chan 1))
    (ev/give gate true))
  gate)
(defn exclusive [task]
  (def shared (initialize))
  (ev/take shared)
  (def result (protect (task)))
  (ev/give shared true)
  (unless (first result) (error (result 1)))
  (result 1))

(defn check [root additional quota]
  (assert (<= (+ (util/tree-size root) additional) quota)
          "Data storage allowance reached. Cached patches remain available."))
(defn write [root path bytes quota]
  (exclusive (fn []
               # Atomic replacement temporarily retains both the old file and
               # the complete new file. Charge that peak, not only the growth.
               (check root (length bytes) quota)
               (util/atomic-write path bytes))))
(defn write-async [root path bytes quota]
  (initialize)
  (def channel (ev/thread-chan 1))
  (ev/thread (fn [[channel root path bytes quota]]
               (ev/give channel (protect (write root path bytes quota))))
             [channel root path bytes quota] :n)
  (def result (ev/take channel))
  (unless (first result) (error (result 1)))
  (result 1))
(defn remove [path] (exclusive (fn [] (util/remove-tree path))))
(defn publish [root staging destination pointer id quota &opt ready]
  (exclusive (fn []
               # Reserve the atomic pointer before moving any directory. A
               # quota failure must leave the previous current snapshot usable.
               (check root (length id) quota)
               # Recheck a caller's cancellation/deadline after waiting for the
               # writer guard and scanning the quota, before publishing anything.
               (when ready (ready))
               (def parts (string/split "/" destination))
               (util/mkdirs (string/join (take (dec (length parts)) parts) "/"))
               (if (os/stat destination) (util/remove-tree staging) (os/rename staging destination))
               (util/atomic-write pointer id))))
