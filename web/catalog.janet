(import ../data/16.19.1/snapshot :as snapshot)

# Data-only parsing: downloaded catalog strings never execute as Janet code.
(def records (parse-all (slurp "data/16.19.1/catalog/catalog.jdn")))
(assert (= 1 (length records)) "Expected one catalog record.")
(def data (first records))
(assert (= snapshot/patch (data :patch)) "Catalog patch mismatch.")
(def champions
  (tabseq [record :in (data :champions)] (record :id)
    (merge record (get snapshot/champions (record :id) {}) {:status "unvalidated"})))
(def items
  (tabseq [record :in (data :items)] (record :id)
    (merge record (get snapshot/items (record :id) {}) {:status "unvalidated"})))
(def champion-list (sorted (values champions) (fn [a b] (< (compare (a :name) (b :name)) 0))))
(def item-list (sorted (values items) (fn [a b]
                                        (def by-name (compare (a :name) (b :name)))
                                        (if (= 0 by-name) (< (scan-number (a :id)) (scan-number (b :id))) (< by-name 0)))))
