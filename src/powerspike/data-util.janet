(import pshash :as hash)
(import spork/json :as json)

(defn mkdirs [path]
  (def parts (string/split "/" path))
  (var prefix (if (string/has-prefix? "/" path) "/" ""))
  (each part parts
    (unless (or (= "" part) (= "." part))
      (set prefix (string prefix part "/"))
      (os/mkdir prefix)))
  path)

(defn write [path bytes]
  (def parts (string/split "/" path))
  (def parent (string/join (take (- (length parts) 1) parts) "/"))
  (unless (= "" parent) (mkdirs parent))
  (with [file (file/open path :wb)] (file/write file bytes)))

(defn atomic-write [path bytes]
  (def temp (string path "." (string/slice (hash/sha256 (os/cryptorand 16)) 0 12) ".tmp"))
  (write temp bytes)
  (os/rename temp path))

(defn read-data [path]
  (def records (parse-all (slurp path)))
  (assert (= 1 (length records)) "Expected one data record.")
  (first records))

(defn encode-data [value] (string/format "%j\n" value))
(defn canonical [value]
  (cond (dictionary? value) (struct ;(mapcat (fn [[key child]] [key (canonical child)]) (pairs value)))
    (indexed? value) (tuple ;(map canonical value))
    value))
(defn read-json [bytes] (json/decode bytes))
(defn encode-json [value] (json/encode value))

(defn copy-tree [source target]
  (mkdirs target)
  (each name (os/dir source)
    (def from (string source "/" name))
    (def to (string target "/" name))
    (if (= :directory (os/stat from :mode)) (copy-tree from to) (write to (slurp from)))))

(defn tree-size [directory]
  (if (= :directory (os/stat directory :mode))
    (sum (map |(tree-size (string directory "/" $)) (os/dir directory)))
    (or (os/stat directory :size) 0)))

(defn tree-size-async [directory]
  (def channel (ev/thread-chan 1))
  (ev/thread (fn [[channel directory]] (ev/give channel (protect (tree-size directory)))) [channel directory] :n)
  (def result (ev/take channel))
  (unless (first result) (error (string (result 1))))
  (result 1))

(defn remove-tree [path]
  (when (os/stat path)
    (if (= :directory (os/stat path :mode))
      (do (each name (os/dir path) (remove-tree (string path "/" name))) (os/rmdir path))
      (os/rm path))))

(defn finite? [value] (and (number? value) (< (- math/inf) value math/inf)))
(defn safe-id? [value]
  (and (string? value) (> (length value) 0) (<= (length value) 100)
       (peg/match ~(* (some (range "az" "AZ" "09" "__" "--" "..")) -1) value)
       (not (string/find ".." value))))
(defn version? [version]
  (and (string? version) (<= (length version) 32)
       (peg/match ~(* (+ (* (some (range "09")) "." (some (range "09")) "." (some (range "09")))
                         (* "lolpatch_" (some (range "09")) "." (some (range "09")))) -1) version)))
(defn cdragon-version [version]
  (string/join (take 2 (string/split "." (string/replace "lolpatch_" "" version))) "."))
(defn provider-version? [requested actual]
  (or (= requested actual)
      (and (string/has-prefix? "lolpatch_" requested) (string? actual)
           (= (cdragon-version requested) (cdragon-version actual)))))
