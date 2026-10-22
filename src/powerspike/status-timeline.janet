# Presentation intervals observe applied state; they never schedule or alter it.
(defn active [actor at]
  (def statuses @{})
  (when (and (not (actor :dead-at)) (> (actor :health) 0))
    (eachp [control expires] (actor :controls)
      (when (> expires at)
        (put statuses [:control control] {:kind :control :effect control :expires expires})))
    (eachp [buff stacks] (actor :buff-counts)
      (when (> stacks 0) (put statuses [:buff buff] {:kind :buff :effect buff})))
    (eachp [id effect] (actor :stat-effects)
      # Slow and named buff bonuses are already represented by their status.
      (when (and effect (> (effect :expires) at) (not= id :slow) (not (effect :requires-buff)))
        (put statuses [:stat-buff id] {:kind :stat-buff :effect (effect :stat) :amount (effect :amount)
                                       :mode (effect :mode) :expires (effect :expires)})))
    (def shields (filter |(and (> ($ :amount) 0) (> ($ :expires) at)) (actor :shields)))
    (unless (empty? shields)
      (put statuses [:shield] {:kind :shield :effect :shield :expires (max ;(map |($ :expires) shields))}))
    (when (> (actor :parry-until) at)
      (put statuses [:parry] {:kind :parry :effect :parry :expires (actor :parry-until)}))
    (when (> (get-in actor [:judgment :end] 0) at)
      (put statuses [:buff "Judgment"] {:kind :buff :effect "Judgment" :expires (get-in actor [:judgment :end])}))
    (each modifier (actor :modifiers)
      (when (and (> (modifier :remaining) 0) (> (modifier :expires) at))
        (def key [:empowerment (modifier :source)])
        (put statuses key {:kind :empowerment :effect (modifier :source)
                           :expires (max (get-in statuses [key :expires] 0) (modifier :expires))}))))
  statuses)

(defn create [] @{:open @{} :rows @[]})

(defn capture [timeline actors at duration]
  (def next @{})
  (each actor actors
    (eachp [key status] (active actor at)
      (put next (tuple (actor :id) key) (merge status {:actor (actor :id) :id (string/format "%j" key)}))))
  (eachp [key row] (timeline :open)
    (unless (next key)
      (put row :end (min at (row :end)))))
  (def open @{})
  (eachp [key status] next
    (def prior ((timeline :open) key))
    (def row (or (when (and prior (>= (prior :end) at)) prior)
                 (let [row @{:actor (status :actor) :id (status :id) :kind (status :kind)
                             :effect (status :effect) :start at}]
                   (array/push (timeline :rows) row) row)))
    (put row :end (min duration (get status :expires duration)))
    (put open key row))
  (put timeline :open open))

(defn intervals [timeline]
  (def rows @[])
  (def previous @{})
  (each row (timeline :rows)
    (when (< (row :start) (row :end))
      (def key [(row :actor) (row :id)])
      (def last (previous key))
      (if (and last (= (last :end) (row :start)))
        (put last :end (row :end))
        (do (put previous key row) (array/push rows row)))))
  (sort rows
        (fn [a b]
          (cond (not= (a :start) (b :start)) (< (a :start) (b :start))
            (not= (a :actor) (b :actor)) (< (a :actor) (b :actor))
            (< (a :id) (b :id))))))
