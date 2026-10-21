(import ./catalog :as catalog)
(import ./details :as details)

# Snapshot-scoped presentation records. Build-specific values are fetched only
# for the hovered/focused item through the existing scenario tooltip route.
(defn records [kind]
  (def package (catalog/current))
  {:patch (package :patch) :snapshot (package :snapshot) :kind kind
   :records (case kind
              "champions"
              (map (fn [champion]
                     {:id (champion :id) :name (champion :name) :icon (details/asset "champion" (champion :icon))
                      :tags (champion :tags)}) (catalog/champion-list))
              "items"
              (map (fn [item]
                     {:id (item :id) :name (item :name) :icon (details/asset "item" (item :icon))
                      :gold (item :gold) :description (item :description) :tags (item :tags)
                      :rift (if (and (item :purchasable) (item :in-store) (some |(= 11 $) (item :maps))) true false)})
                   (catalog/item-list))
              (error "Unknown catalog."))})
