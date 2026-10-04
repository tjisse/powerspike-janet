(import ./stats :as stats)
(import ./builds :as builds)
(import ./combat :as combat)
(import ./optimization :as optimization)


(defn validate-patches [champion items &opt abilities]
  (def patch (champion :patch))
  (assert patch "champion requires a patch identifier")
  (each item items
    (assert (= patch (item :patch)) (string "item patch mismatch: " (item :id))))
  (each spell (or abilities [])
    (assert (= patch (spell :patch)) (string "spell patch mismatch: " (spell :id)))))

(defn evaluate-build [champion level items target scenario options]
  (validate-patches champion items)
  (def inspection (builds/inspect-build items options))
  (assert (inspection :legal) (string "illegal build: " (inspection :errors)))
  (def totals (stats/total-stats champion level items))
  {:stats totals :cost (inspection :cost)
   :combat (combat/auto-attacks totals target scenario)})

(defn optimize-attacks [champion level pool target scenario options]
  (optimization/exact-search pool options
                             (fn [items] (((evaluate-build champion level items target scenario options) :combat) :dps))))

(import ./rotation :as rotation)
(import ./skills :as skills)

(defn evaluate-rotation [champion level items target scenario options abilities ranks]
  (validate-patches champion items abilities)
  (def inspection (builds/inspect-build items options))
  (assert (inspection :legal) (string "illegal build: " (inspection :errors)))
  (skills/validate-ranks ranks level)
  (def totals (stats/apply-rank-penetration champion
                                            (stats/total-stats champion level items) ranks))
  {:stats totals :cost (inspection :cost)
   :combat (rotation/evaluate totals target scenario abilities ranks)})

(defn optimize-rotation [champion level pool target scenario options abilities ranks objective]
  (assert (or (= objective :ability) (= objective :total)) "objective must be :ability or :total")
  (optimization/exact-search pool options
                             (fn [items]
                               (def result (evaluate-rotation champion level items target scenario options abilities ranks))
                               ((result :combat) (if (= objective :ability) :ability-dps :dps)))))
