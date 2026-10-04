(defn finite-number [value field-name]
  (assert (and (number? value) (< math/-inf value math/inf))
          (string field-name " must be a finite number"))
  value)

(defn nonnegative [value field-name]
  (finite-number value field-name)
  (assert (>= value 0) (string field-name " must be nonnegative"))
  value)

(defn fraction [value field-name]
  (nonnegative value field-name)
  (assert (<= value 1) (string field-name " must be a fraction between 0 and 1"))
  value)

(defn integer-between [value lo hi field-name]
  (finite-number value field-name)
  (assert (and (= value (math/floor value)) (<= lo value hi))
          (string field-name " must be an integer from " lo " to " hi))
  value)
