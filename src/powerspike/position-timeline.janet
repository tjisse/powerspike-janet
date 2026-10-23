# Presentation-only keyframes: linear movement between events, duplicate times
# for instantaneous displacement. Never schedule or alter combat state.
(defn capture [frames at positions]
  (def count (length frames))
  (def last (when (> count 0) (frames (dec count))))
  (unless (and last (= at (last :at)) (= positions (last :positions)))
    (when (and (> count 1) (> at (last :at)))
      (def previous (frames (- count 2)))
      (when (< (previous :at) (last :at))
        (def fraction (/ (- (last :at) (previous :at)) (- at (previous :at))))
        (when (all (fn [index]
                     (< (math/abs (- ((last :positions) index)
                                     (+ ((previous :positions) index)
                                        (* fraction (- (positions index) ((previous :positions) index)))))) 1e-8)) [0 1])
          (array/pop frames))))
    (array/push frames {:at at :positions (tuple ;positions)})))
