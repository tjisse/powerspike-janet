(import ./validation :as v)

(defn validate-ranks [ranks level]
  (v/integer-between level 1 18 "level")
  (var spent 0)
  (eachp [slot rank] ranks
    (assert (some (fn [x] (= x slot)) [:q :w :e :r]) "unknown skill slot")
    (v/integer-between rank 0 (if (= slot :r) 3 5) (string "rank " slot))
    (def cap (if (= slot :r)
               (cond (>= level 16) 3 (>= level 11) 2 (>= level 6) 1 0)
               (min 5 (math/floor (/ (+ level 1) 2)))))
    (assert (<= rank cap) (string "skill rank is unavailable at this level: " slot))
    (+= spent rank))
  (assert (<= spent level) "more skill points spent than earned")
  ranks)

(defn ranks-from-order [order level]
  (v/integer-between level 1 18 "level")
  (assert (>= (length order) level) "skill order must cover the requested level")
  (def ranks @{:q 0 :w 0 :e 0 :r 0})
  (for index 0 level
    (def slot (order index))
    (assert (has-key? ranks slot) "unknown skill slot")
    (put ranks slot (+ 1 (ranks slot)))
    (validate-ranks ranks (+ index 1)))
  ranks)
