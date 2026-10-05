(import ./data-util :as util)

# Worker tasks are marshalled separately from their runner. A dynamic state
# binding makes both use the same worker cache instead of separate module copies.
(def capacity 2048)
(def byte-limit (* 8 1024 1024))
(def process-state @{:entries @{} :changes @{} :touches @{} :bytes 0 :sequence 0})
(defn current [] (or (dyn :powerspike-fitness-cache) process-state))
(defn unlink [state key]
  (def entries (state :entries))
  (def node (entries key))
  (def before (node :previous)) (def after (node :next))
  (if before (put (entries before) :next after) (put state :first-key after))
  (if after (put (entries after) :previous before) (put state :last-key before)))
(defn newest [state key]
  (def entries (state :entries))
  (def node (entries key))
  (when (state :last-key) (put (entries (state :last-key)) :next key))
  (put node :previous (state :last-key)) (put node :next nil)
  (unless (state :first-key) (put state :first-key key))
  (put state :last-key key))
(defn touch [state key]
  (unless (= key (state :last-key)) (unlink state key) (newest state key))
  (put state :sequence (inc (state :sequence)))
  (put (state :touches) key (state :sequence)))
(defn lookup [key]
  (def state (current))
  (when ((state :entries) key) (touch state key) (((state :entries) key) :value)))
(defn remove-entry [state key]
  (def node ((state :entries) key))
  (unlink state key) (put state :bytes (- (state :bytes) (node :bytes)))
  (put (state :entries) key nil) (put (state :changes) key nil) (put (state :touches) key nil))
(defn store [key value]
  (def state (current))
  (def entries (state :entries))
  (def frozen (util/canonical value))
  (def size (+ (length key) (length (util/encode-data frozen))))
  (when (<= size byte-limit)
    (when (entries key) (remove-entry state key))
    (while (and (state :first-key) (or (>= (length entries) capacity) (> (+ (state :bytes) size) byte-limit)))
      (remove-entry state (state :first-key)))
    (put entries key @{:value frozen :bytes size})
    (put state :bytes (+ (state :bytes) size)) (newest state key) (touch state key)
    (put (state :changes) key frozen)
    frozen))
(defn begin-job []
  (def state (current))
  (each key (keys (state :changes)) (put (state :changes) key nil))
  (each key (keys (state :touches)) (put (state :touches) key nil))
  (put state :sequence 0))
(defn clear []
  (def state (current))
  (each key (keys (state :entries)) (put (state :entries) key nil))
  (put state :first-key nil) (put state :last-key nil) (put state :bytes 0)
  (begin-job))
(defn export-changes []
  (def state (current))
  {:entries (tuple ;(map |[$ ((state :changes) $)] (keys (state :changes))))
   :touched (tuple ;(sorted (keys (state :touches)) |(< ((state :touches) $0) ((state :touches) $1))))})
(defn accept-changes [delta]
  (when delta
    (def state (current))
    (each [key value] (get delta :entries []) (store key value))
    (each key (get delta :touched []) (when ((state :entries) key) (touch state key)))
    (begin-job)))
(defn stats []
  (def state (current))
  {:entries (length (state :entries)) :bytes (state :bytes) :capacity capacity :byte-limit byte-limit})
