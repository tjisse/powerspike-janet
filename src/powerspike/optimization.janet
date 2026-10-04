(import ./builds :as builds)
(import ./validation :as v)

# Enumerate a small pool exactly. The score callback can close over all scenario
# parameters, so no global memoization can leak scores between targets/patches.
(defn exact-search [pool options score]
  (def slots (v/integer-between (get options :slots 6) 0 6 "slots"))
  (def max-evaluations (v/integer-between (get options :max-evaluations 100000) 1 10000000 "max evaluations"))
  (def ids @{})
  (each item pool
    (assert (not (ids (item :id))) "duplicate item ID in candidate pool")
    (put ids (item :id) true))
  (var evaluated 0)
  (var truncated false)
  (var best nil)
  (defn visit [start chosen]
    (unless truncated
      (def inspection (builds/inspect-build chosen options))
      (when (inspection :legal)
        (if (>= evaluated max-evaluations)
          (set truncated true)
          (do
            (++ evaluated)
            (def value (v/finite-number (score chosen) "score"))
            (when (or (nil? best) (> value (best :score))
                      (and (= value (best :score)) (< (inspection :cost) (best :cost))))
              (set best {:items (tuple ;chosen) :score value :cost (inspection :cost)}))
            (when (< (length chosen) slots)
              (for index start (length pool)
                (unless truncated
                  (def item (pool index))
                  (array/push chosen item)
                  (visit (if (item :stackable) index (+ index 1)) chosen)
                  (array/pop chosen)))))))))
  (visit 0 @[])
  {:best best :evaluated evaluated :complete (not truncated)
   :guarantee (if truncated :best-found :optimal-within-pool)})
