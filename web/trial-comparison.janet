# Descriptive changes within matching trial indices, with the same seeds and
# fight inputs supplied by model/compare. These are not confidence intervals.
(defn damage [current pinned]
  (def n (get current :samples))
  (def a (get current :trial-damage))
  (def b (get pinned :trial-damage))
  (when (and (number? n) (= n (math/floor n)) (<= 1 n 256) (= n (get pinned :samples))
             (indexed? a) (indexed? b) (= n (length a) (length b))
             (not (some |(not (and (number? $) (<= 0 $) (< $ math/inf))) [;a ;b])))
    (def changes (map - a b))
    {:samples n :mean (/ (sum changes) n) :lowest (min ;changes) :highest (max ;changes)
     :current-higher (count |(> $ 0) changes) :pinned-higher (count |(< $ 0) changes) :tied (count |(= $ 0) changes)}))
