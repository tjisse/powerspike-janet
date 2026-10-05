(import ./skills :as skills)

# Rune pages contain four primary choices (one per slot) and two secondary
# choices from different non-keystone slots. Shards are outside this schema.
(defn rune-position [package id]
  (find identity
        (map (fn [style]
               (find identity (map (fn [slot index]
                                     (when (some |(= id (get $ "id")) (get slot "runes" []))
                                       {:style (style "id") :slot index}))
                                   (get style "slots" []) (range 0 (length (get style "slots" []))))))
             (get package :runes []))))
(defn legal-page? [package page]
  (and (indexed? page) (= 6 (length page))
       (= 6 (length (keys (tabseq [id :in page] id true))))
       (let [positions (map |(rune-position package $) page)]
         (and (not (some nil? positions))
              (all (fn [index] (and (= index ((positions index) :slot))
                                    (= ((positions 0) :style) ((positions index) :style)))) (range 0 4))
              (not= ((positions 0) :style) ((positions 4) :style))
              (= ((positions 4) :style) ((positions 5) :style))
              (> ((positions 4) :slot) 0) (> ((positions 5) :slot) 0)
              (not= ((positions 4) :slot) ((positions 5) :slot))))))
(defn initial-pages [package]
  (def styles (get package :runes []))
  (seq [primary :in styles secondary :in styles :when (not= (primary "id") (secondary "id"))]
    [(get-in primary ["slots" 0 "runes" 0 "id"])
     (get-in primary ["slots" 1 "runes" 0 "id"])
     (get-in primary ["slots" 2 "runes" 0 "id"])
     (get-in primary ["slots" 3 "runes" 0 "id"])
     (get-in secondary ["slots" 1 "runes" 0 "id"])
     (get-in secondary ["slots" 2 "runes" 0 "id"])]))
(defn page-neighbors [package page locked]
  (def result @[])
  (for index 0 6
    (unless (some |(= $ index) locked)
      (each style (get package :runes [])
        (each slot (get style "slots" [])
          (each rune (get slot "runes" [])
            (def next (array/slice page))
            (put next index (rune "id"))
            (when (legal-page? package next) (array/push result (tuple ;next))))))))
  result)
(defn summoner-pairs [package level locked current]
  (def spells (filter |(and (<= (get $ "summonerLevel" 1) level)
                            (some (fn [mode] (= "CLASSIC" mode)) (get $ "modes" [])))
                      (get package :summoners [])))
  (seq [a :in spells b :in spells :when (not= (a "id") (b "id"))
        :when (and (or (not (some |(= $ 0) locked)) (= (a "id") (get current 0)))
                   (or (not (some |(= $ 1) locked)) (= (b "id") (get current 1))))]
    [(a "id") (b "id")]))
(defn skill-orders [level locked]
  (def result @[])
  (each a [:q :w :e]
    (each b [:q :w :e]
      (unless (= a b)
        (def c (find |(and (not= $ a) (not= $ b)) [:q :w :e]))
        (def ranks @{:q 0 :w 0 :e 0 :r 0})
        (def order @[])
        (for index 0 level
          (def at (inc index))
          (def next (or (get locked index)
                        (when (some |(= $ at) [6 11 16]) :r)
                        (find (fn [slot]
                                (def attempt (merge ranks {slot (inc (ranks slot))}))
                                (first (protect (skills/validate-ranks attempt at)))) [a b c])))
          (when next (put ranks next (inc (ranks next))) (array/push order next)))
        (when (and (= level (length order)) (first (protect (skills/ranks-from-order order level))))
          (array/push result (tuple ;order))))))
  result)
