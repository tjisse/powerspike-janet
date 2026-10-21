# No native-module dependency: the curated core and full scenario engine share
# this reviewed limit. Resolve the source profile while embedding the executable.
(def review
  (let [forms (parse-all (slurp "data/attack-fixtures/16.19.1/reviewed-speed-cap.jdn"))]
    (assert (= 1 (length forms)) "Expected one attack-speed limit review.")
    (def value (first forms))
    (assert (and (= "16.19.1" (value :patch)) (= 3.0 (value :baseline-cap)) (= 2.5 (value :previous-assumption)))
            "Attack-speed limit review requires a supported patch and baseline.")
    value))

(defn baseline [patch]
  (when (= patch (review :patch)) (review :baseline-cap)))

(defn cap [champion]
  (def configured (get champion :attack-speed-cap))
  # Old normalized snapshots and the curated core carry the generic 2.5 value.
  # Explicit alternative limits still belong to their own handlers/fixtures.
  (or (when (or (nil? configured) (= configured (review :previous-assumption)))
        (baseline (get champion :patch)))
      configured))

(defn notes [patch limitations]
  (if (baseline patch)
    (mapcat (fn [note]
              (case note
                "Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions."
                ["Windup 30% and projectile travel zero are assumptions."]
                "Attack-speed cap 2.5 and windup 30% remain estimates."
                ["Windup 30% remains an estimate."]
                "Attack-speed cap 2.5 remains an estimate." []
                [note])) limitations)
    limitations))
