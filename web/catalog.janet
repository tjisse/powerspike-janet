(import ../src/powerspike/packages :as packages)
(var patch-list [])
(var versions-ready false)
(defn initialize [data seed]
  (def package (packages/initialize data seed))
  (set patch-list (packages/available)) package)
(defn current [] (or (dyn :patch-package) (packages/load packages/default-version)))
(defn champions [id] (((current) :champion-map) id))
(defn items [id] (((current) :item-map) id))
(defn champion-list [] (sorted ((current) :champions) |(< (compare ($0 :name) ($1 :name)) 0)))
(defn item-list [] (sorted ((current) :items) |(< (compare ($0 :name) ($1 :name)) 0)))
(defn discover []
  (ev/go (fn []
           (def result (protect (packages/versions)))
           (when (first result) (set patch-list (result 1)))
           (set versions-ready true))))
