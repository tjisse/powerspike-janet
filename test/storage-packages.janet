(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/storage :as storage)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(def root (string "build/storage-package-tests/" (hash/sha256 (os/cryptorand 8))))
(packages/initialize root "build/seed")
(def retained ((packages/load "16.19.1") :snapshot))
(os/setenv "PS_DATA_LIMIT_MB" "100")
(def quota (packages/storage-limit))
(def filler (string root "/filler"))
(defn headroom [amount]
  (when (os/stat filler) (storage/remove filler))
  (def size (- quota (util/tree-size root) amount))
  (assert (> size 0))
  # The budget measures logical file bytes. A sparse file keeps this test small.
  (with [file (file/open filler :wb)] (file/seek file :set (dec size)) (file/write file "x")))
(headroom (* 9 1024 1024))
(var first-request true)
(defn concurrent-provider [url cancelled]
  (when first-request
    (set first-request false)
    # Model separate artwork completing after the patch's initial size scan.
    (for index 0 8
      (storage/write root (string root "/art/" index) (string/repeat "a" (* 1024 1024)) quota))
    (storage/write root (string root "/art/last") (string/repeat "a" (* 512 1024)) quota))
  (util/encode-json {"version" "16.19.1" "data" {} "padding" (string/repeat "p" 600000)}))
(def staging (string root "/jobs/race"))
(def failed (protect (packages/fetch "16.19.1" staging (fn [&]) (fn [] false) concurrent-provider)))
(assert (not (first failed)) "Patch writes ignored artwork completed after their initial size scan.")
(assert (string/find "storage allowance" (string (failed 1))))
(assert (<= (util/tree-size root) quota))
(assert (= retained ((packages/load "16.19.1") :snapshot)))
(storage/remove staging) (storage/remove (string root "/art")) (storage/remove filler)

# Small synthetic packages isolate normalized data and manifest accounting.
(var revision 1)
(defn provider [url cancelled]
  (util/encode-json
    (cond
      (string/has-suffix? "champion.json" url)
      {"version" "16.18.1" "data" {"Test" {"id" "Test" "name" "Test" "title" "Fixture"
                                           "image" {"full" "Test.png"} "stats" {"hp" revision "attackspeed" 0.6}
                                           "partype" "Mana" "tags" []}}}
      (string/has-suffix? "item.json" url) {"version" "16.18.1" "data" {}}
      (string/has-suffix? "summoner.json" url) {"version" "16.18.1" "data" {}}
      (string/find "/champion/Test.json" url) {"version" "16.18.1" "data" {}}
      {})))
(defn fetch [] (packages/fetch "16.18.1" staging (fn [&]) (fn [] false) provider))
(def published (fetch))
(def directory (packages/directory "16.18.1" (published :snapshot)))
(def raw-size (util/tree-size (string directory "/sources")))
(def package-size (os/stat (string directory "/package.jdn") :size))
(set revision 2)
(headroom (+ raw-size 1))
(assert (not (first (protect (fetch)))) "Normalized package bytes escaped the quota.")
(assert (= raw-size (util/tree-size staging)))
(assert (not (os/stat (string staging "/package.jdn"))))
(assert (= (published :snapshot) ((packages/load "16.18.1") :snapshot)))
(storage/remove staging)
(headroom (+ raw-size package-size 1))
(assert (not (first (protect (fetch)))) "Manifest bytes escaped the quota.")
(assert (os/stat (string staging "/package.jdn")))
(assert (not (os/stat (string staging "/manifest.json"))))
(assert (= (published :snapshot) ((packages/load "16.18.1") :snapshot)))
(assert (<= (util/tree-size root) quota))
(storage/remove staging)
# Existing cached patches remain available at the quota, even when an optional
# bundled seed revision cannot fit during restart.
(headroom 0)
(def extra-seed (string root "-seed"))
(util/write (string extra-seed "/16.17.1/current") "unaffordable seed")
(packages/initialize root extra-seed)
(assert (= retained ((packages/load "16.19.1") :snapshot)))
(assert (not (os/stat (string root "/patches/16.17.1/current"))))
(assert (= quota (util/tree-size root)))
(storage/remove filler)
(set revision 3)
(def recovered (fetch))
(assert (not= (published :snapshot) (recovered :snapshot)))
(assert (= 3 (get-in (packages/load "16.18.1") [:champion-map "Test" :base :hp])))
(storage/remove root) (storage/remove extra-seed)
(print "Patch storage: interleaved artwork, normalized/manifest quotas, immutable current pointers, restart at quota and recovery after reclaim passed.")
