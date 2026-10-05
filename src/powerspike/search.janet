(import ./scenario :as scenario)
(import ./builds :as builds)
(import ./loadouts :as loadouts)
(import ./data-util :as util)
(import ./validation :as v)
(import ./engine :as engine)
(import ../../data/16.19.1/snapshot :as initial)
(import pshash :as hash)

(def version "search-1")
(def presets [:burst :sustained :duel :survival :utility :objective])
(def explanations
  {:burst "Damage within the configured combat window; lower cost breaks ties."
   :sustained "Damage per second over the configured window; lower cost breaks ties."
   :duel "Win probability, then kill probability, earlier successful kills, then remaining health. Simultaneous deaths are not wins."
   :survival "Survival probability, then remaining health, then absorbed damage."
   :utility "Effective control time, then effective healing, then absorbed damage. These metrics are compared in order, not added."
   :objective "Objective kill probability, then earlier successful kills, then damage within the configured window."})
(defn score [metrics preset duration]
  (case preset
    :burst [(get metrics :damage 0)]
    :sustained [(/ (get metrics :damage 0) duration)]
    :duel [(get metrics :win-rate 0) (get metrics :kill-rate 0) (- (get metrics :mean-kill-time duration)) (get metrics :health 0)]
    :survival [(- 1 (get metrics :death-rate 0)) (get metrics :health 0) (get metrics :absorbed 0)]
    :utility [(get metrics :control 0) (get metrics :healing 0) (get metrics :absorbed 0)]
    :objective [(get metrics :kill-rate 0) (- (get metrics :mean-kill-time duration)) (get metrics :damage 0)]
    (error "Unknown scoring preset.")))
(defn better? [a b]
  (var comparison 0)
  (for index 0 (length (a :score))
    (when (and (= 0 comparison) (not= ((a :score) index) ((b :score) index)))
      (set comparison (if (> ((a :score) index) ((b :score) index)) 1 -1))))
  (if (= 0 comparison)
    (if (= (a :cost) (b :cost)) (< (a :key) (b :key)) (< (a :cost) (b :cost)))
    (> comparison 0)))
(defn inventory [package ids]
  (map (fn [id] (def item ((package :item-map) id)) (assert item "Search item unavailable on this patch.") item) ids))
(defn replace-items [definition ids]
  (merge definition {:player (merge (definition :player)
                                    {:loadout (merge (get-in definition [:player :loadout] {}) {:items ids})})}))
(defn legal [package ids options champion]
  (builds/inspect-build (inventory package ids) (merge options {:champion champion})))
(defn unique [values] (keys (tabseq [value :in values] value true)))
(defn contains-all? [values required]
  (def remaining (array/slice values))
  (all (fn [id] (def index (find-index |(= id $) remaining))
         (when index (array/remove remaining index 1) true)) required))

# A next purchase may complete one item with currently owned components. Walk
# the recipe tree once, consuming each owned component at most once. Gold
# credit is bounded by the recipe's total value, never a sale or invented refund.
(defn next-purchases [package owned pool options champion]
  (def result @[])
  (each id pool
    (def item ((package :item-map) id))
    (def remaining (array/slice owned))
    (var credit 0)
    (defn consume [component depth]
      (assert (< depth 20) "Cyclic or excessive item recipe.")
      (def index (find-index |(= component $) remaining))
      (if index
        (do (array/remove remaining index 1) (+= credit (((package :item-map) component) :gold)))
        (each child (get ((package :item-map) component) :from []) (consume child (inc depth)))))
    (each component (get item :from []) (consume component 0))
    (def price (max 0 (- (item :gold) credit)))
    (def ids [;remaining id])
    (when (and (<= price (get options :budget 10000))
               (contains-all? ids (get options :locked []))
               ((legal package ids (merge options {:budget math/inf :owned owned}) champion) :legal))
      (array/push result {:items ids :purchase id :purchase-cost price :consumed-count (- (length owned) (length remaining))})))
  result)
(defn run [package definition options progress cancelled &opt evaluator]
  (def duration (definition :duration))
  (def preset (get options :preset :burst))
  (assert (some |(= preset $) presets) "Choose a supported optimization preset.")
  (when (= preset :objective) (assert (= :objective (get-in definition [:target :kind])) "Objective scoring requires an objective."))
  (when (= preset :duel) (assert (= :champion (get-in definition [:target :kind])) "Duel scoring requires a champion opponent."))
  (def seconds (v/finite-number (get options :seconds 5) "Search budget"))
  (assert (<= 0.01 seconds 30) "Search compute budget must be from 0.01 to 30 seconds.")
  (def slots (v/integer-between (get options :slots 6) 0 6 "Search slots"))
  (def budget (v/nonnegative (get options :budget 10000) "Gold budget"))
  (def champion (get-in definition [:player :champion]))
  (def owned (get-in definition [:player :loadout :items] []))
  (def locked (get options :locked []))
  (assert (contains-all? owned locked) "Locked items must be present in the current inventory.")
  (def next? (get options :next-purchase false))
  (def limits (merge options {:slots slots :budget (if next? math/inf budget) :owned locked}))
  (assert ((legal package locked limits champion) :legal) "Locked inventory violates the budget or purchase restrictions.")
  (def requested (get options :pool (map |($ :id) (package :items))))
  (assert (and (indexed? requested) (<= (length requested) 2000)) "Invalid item pool.")
  (inventory package requested)
  (def pool (sorted (filter (fn [id] (and (or (not (get-in package [:manifest "initial"])) (initial/items id))
                                          ((legal package [id] (merge limits {:slots 6 :owned [] :budget math/inf}) champion) :legal)))
                            (unique requested))
                    |(< (hash/sha256 (string (get definition :seed 1) $0)) (hash/sha256 (string (get definition :seed 1) $1)))))
  (def samples (v/integer-between (get options :samples (get definition :samples 1)) 1 64 "Search trials"))
  (def final-samples (v/integer-between (get options :final-samples (max samples 16)) samples 256 "Finalist trials"))
  (def optional? (some |(get options $ false) [:runes :summoners :skills]))
  (when next? (assert (not optional?) "Next-purchase search keeps runes, summoners and skills fixed."))
  (def exact? (and (not optional?) (or next? (or (<= (length pool) 8) (and (<= (length pool) 10) (<= (- slots (length locked)) 3))))))
  (def started (os/clock :monotonic))
  (def deadline (+ started seconds))
  (def search-deadline (if exact? deadline (+ started (* seconds 0.75))))
  (def seen @{})
  (var archive @[])
  (var evaluated 0)
  (var truncated false)
  (var phase :search)
  (defn stop? [] (or (cancelled) (>= (os/clock :monotonic) (if (= phase :search) search-deadline deadline))))
  (def evaluate (or evaluator (fn [candidate stop] (scenario/simulate candidate stop))))
  (defn publish [message]
    (progress {:message message :completed evaluated :total 0 :seconds (- (os/clock :monotonic) started)
               :best (tuple ;(take 5 (sorted archive better?))) :preset preset :explanation (explanations preset)}))
  (defn visit [candidate &opt purchase count-samples force]
    (unless (stop?)
      (def ids (get-in candidate [:player :loadout :items] []))
      (def inspection (legal package ids (merge limits {:budget (if next? math/inf budget) :owned (if next? owned locked)}) champion))
      (when (and (inspection :legal) (contains-all? ids locked)
                 (or (not (get options :runes false)) (loadouts/legal-page? package (get-in candidate [:player :loadout :runes] [])))
                 (or (not (get options :summoners false)) (= 2 (length (get-in candidate [:player :loadout :summoners] [])))))
        (def trials (or count-samples (if exact? final-samples (min samples 8))))
        (def normalized (merge candidate {:samples trials :model engine/identity}))
        (def key (hash/sha256 (util/encode-data [version engine/identity (package :snapshot) normalized preset purchase])))
        (unless (and (seen key) (not force))
          (when (< (length seen) 4096)
            (put seen key true)
            (def outcome (protect (evaluate normalized stop?)))
            (unless (or (first outcome) (stop?)) (error (string "Candidate simulation failed: " (outcome 1))))
            (when (first outcome)
              (++ evaluated)
              (def result (outcome 1))
              (def row {:key key :definition normalized :ids (tuple ;ids) :cost (inspection :cost)
                        :purchase (get purchase :purchase) :purchase-cost (get purchase :purchase-cost)
                        :score (score (result :metrics) preset duration) :metrics (result :metrics)
                        :uncertainty (get result :uncertainty {}) :samples trials
                        :coverage (get result :unsupported [])})
              (array/push archive row)
              (when (> (length archive) 40) (set archive (array/slice (take 20 (sorted archive better?)))))
              (when (or (= evaluated 1) (= 0 (mod evaluated 8))) (publish "Searching builds"))
              row))))))
  (var baseline definition)
  (when (get options :runes false)
    (def current (get-in definition [:player :loadout :runes] []))
    (unless (loadouts/legal-page? package current)
      (def page (find (fn [next] (all |(= (get next $) (get current $)) (get options :rune-locks []))) (loadouts/initial-pages package)))
      (assert page "No legal rune page satisfies the locked choices.")
      (set baseline (merge baseline {:player (merge (baseline :player) {:loadout (merge (get-in baseline [:player :loadout] {}) {:runes page})})}))))
  (when (get options :summoners false)
    (def pair (first (loadouts/summoner-pairs package (get-in definition [:player :level] 18)
                                              (get options :summoner-locks []) (get-in definition [:player :loadout :summoners] []))))
    (assert pair "No legal summoner pair satisfies the locked choices.")
    (set baseline (merge baseline {:player (merge (baseline :player) {:loadout (merge (get-in baseline [:player :loadout] {}) {:summoners pair})})})))
  (def base (replace-items baseline locked))
  (defn expand [candidate]
    (def ids (get-in candidate [:player :loadout :items] []))
    (when (get options :runes false)
      (def page (get-in candidate [:player :loadout :runes] []))
      (def choices [;(loadouts/page-neighbors package page (get options :rune-locks []))
                    ;(filter (fn [next] (all |(= (get next $) (get page $)) (get options :rune-locks []))) (loadouts/initial-pages package))])
      (each page choices
        (visit (merge candidate {:player (merge (candidate :player)
                                                {:loadout (merge (get-in candidate [:player :loadout] {}) {:runes page})})}))))
    (when (get options :summoners false)
      (each pair (loadouts/summoner-pairs package (get-in candidate [:player :level] 18)
                                          (get options :summoner-locks []) (get-in definition [:player :loadout :summoners] []))
        (visit (merge candidate {:player (merge (candidate :player)
                                                {:loadout (merge (get-in candidate [:player :loadout] {}) {:summoners pair})})}))))
    (when (get options :skills false)
      (each order (loadouts/skill-orders (get-in definition [:player :level] 18) (get options :skill-locks {}))
        (def player (merge @{} (candidate :player)))
        (put player :ranks nil) (put player :skill-order order)
        (visit (merge candidate {:player player}))))
    (each id pool
      (when (stop?) (break))
      (when (< (length ids) slots) (visit (replace-items candidate [;ids id])))
      (for index 0 (length ids)
        (unless (some |(= $ (ids index)) locked)
          (def next (array/slice ids)) (put next index id)
          (visit (replace-items candidate (tuple ;next))))))
    (for index 0 (length ids)
      (def next (array/slice ids)) (array/remove next index 1)
      (when (contains-all? next locked) (visit (replace-items candidate (tuple ;next))))))
  (cond
    next? (each purchase (next-purchases package owned pool (merge limits {:budget budget}) champion)
            (when (stop?) (set truncated true) (break))
            (visit (replace-items definition (purchase :items)) purchase))
    exact?
    (do (defn enumerate [start ids]
          (if (stop?) (set truncated true)
            (when ((legal package ids limits champion) :legal)
              (visit (replace-items definition ids))
              (when (< (length ids) slots)
                (for index start (length pool)
                  (when (stop?) (set truncated true) (break))
                  (def item ((package :item-map) (pool index)))
                  (enumerate (if (item :stackable) index (inc index)) [;ids (item :id)]))))))
      (enumerate 0 locked))
    (do (visit base)
      (when (and (contains-all? owned locked) ((legal package owned limits champion) :legal)) (visit (replace-items baseline owned)))
      (def expanded @{})
      (while (not (stop?))
        (def next (find |(not (expanded ($ :key))) (sorted archive better?)))
        (unless next (break))
        (put expanded (next :key) true) (expand (next :definition)))
      (set truncated true)))
  # Exact searches evaluate every candidate with the same final trial schedule.
  # Heuristic finalists all use the same larger schedule; reserve wall time.
  (when (and (not exact?) (not (cancelled)))
    (set phase :finalists)
    (def finalists (take 5 (sorted archive better?)))
    (def refined @[])
    (each row finalists
      (def next (visit (row :definition) {:purchase (row :purchase) :purchase-cost (row :purchase-cost)} final-samples true))
      (when next (array/push refined next)))
    (when (not (empty? refined)) (set archive refined)))
  (def rows (tuple ;(take 5 (sorted archive better?))))
  (publish "Search finished")
  {:version version :patch (package :patch) :snapshot (package :snapshot) :model engine/identity
   :preset preset :explanation (explanations preset) :rows rows :evaluated evaluated :pool-size (length pool)
   :seconds (- (os/clock :monotonic) started) :limit seconds :cancelled (not (not (cancelled)))
   :complete (and exact? (not truncated) (not (cancelled)) (< (os/clock :monotonic) deadline))
   :guarantee (if (and exact? (not truncated) (not (cancelled)) (< (os/clock :monotonic) deadline)) :optimal-within-pool :best-found)
   :search (if exact? :exhaustive :heuristic) :next-purchase next?
   :notes ["Scores compare a fixed opponent and declared strategies using common seeds."
           "The initial excerpt searches only curated purchase rules; refresh the selected patch to search its complete shop."
           "Missing effects can change rankings. See coverage for every recommendation."
           "Heuristic alternatives are the best found within the compute budget; optimal play is not modeled."
           "Utility compares effective control, healing and protection in order. Team protection and spatial effects are outside this duel model."]})
