(import ./scenario :as scenario)
(import ./builds :as builds)
(import ./loadouts :as loadouts)
(import ./data-util :as util)
(import ./validation :as v)
(import ./engine :as engine)
(import ./effects :as effects)
(import ./fitness-cache :as cache)
(import ../../data/16.19.1/snapshot :as initial)
(import pshash :as hash)

(def version "search-5")
(defn fitness-key [package definition]
  (hash/sha256 (util/encode-data (util/canonical ["fitness-1" engine/identity (package :patch) (package :snapshot) definition]))))
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
(defn distinct-rows [rows]
  (def seen @{})
  (filter (fn [row] (unless (seen (row :key)) (put seen (row :key) true) true)) rows))
(defn alternatives [rows]
  (take 10 (distinct-rows (sorted rows better?))))
(defn replace-items [definition ids]
  (merge definition {:player (merge (definition :player)
                                    {:loadout (merge (get-in definition [:player :loadout] {}) {:items ids})})}))
(defn legal [package ids options champion]
  (builds/inspect-build (inventory package ids) (merge options {:champion champion})))
(defn unique [values]
  (def seen @{})
  (filter (fn [value] (unless (seen value) (put seen value true) true)) values))
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
  (when (get options :skills false)
    (def abilities (get-in package [:champion-map champion :abilities] []))
    (when (not (empty? abilities))
      (assert (all (fn [slot]
                     (= (get (find |(= slot ($ :slot)) abilities) :max-rank (if (= slot :r) 3 5)) (if (= slot :r) 3 5))) [:q :w :e :r])
              "This kit needs an exceptional leveling handler. Keep skill choices fixed to search its items, runes or summoners.")))
  (def owned (get-in definition [:player :loadout :items] []))
  (def locked (get options :locked []))
  (assert (contains-all? owned locked) "Locked items must be present in the current inventory.")
  (def next? (get options :next-purchase false))
  (def limits (merge options {:slots slots :budget (if next? math/inf budget) :owned locked}))
  (assert ((legal package locked limits champion) :legal) "Locked inventory violates the budget or purchase restrictions.")
  (def requested (get options :pool (map |($ :id) (package :items))))
  (assert (and (indexed? requested) (<= (length requested) 2000)) "Invalid item pool.")
  (inventory package requested)
  (def ranged (> (get-in package [:champion-map champion :attack-range] 125) 300))
  (def priorities
    (tabseq [id :in requested :let [item ((package :item-map) id)]] id
      (+ (if (and (item :patch) (not (empty? (get item :record {}))) (not (empty? (effects/item-triggers item ranged)))) 4 0)
         (if (or (>= (get-in item [:source "depth"] 0) 3) (>= (item :gold) 2000)
                 (and (some |(= "Boots" $) (get item :tags [])) (>= (get-in item [:source "depth"] 0) 2))) 2 0)
         (if (not (empty? (get item :stats {}))) 1 0))))
  (def pool-order (tabseq [id :in requested] id (hash/sha256 (string (get definition :seed 1) id))))
  (def pool (sorted (filter (fn [id] (and (or (not (get-in package [:manifest "initial"])) (initial/items id))
                                          ((legal package [id] (merge limits {:slots 6 :owned [] :budget math/inf}) champion) :legal)))
                            (unique requested))
                    (fn [a b] (if (= (priorities a) (priorities b))
                                (< (pool-order a) (pool-order b))
                                (> (priorities a) (priorities b))))))
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
  (var simulated 0)
  (var cache-hits 0)
  (var truncated false)
  (var phase :search)
  (var incumbent nil)
  (var last-publish (- started 0.1))
  (defn stop? [] (or (cancelled) (and (= phase :search) (>= (length seen) 4096))
                     (>= (os/clock :monotonic) (if (= phase :search) search-deadline deadline))))
  (def evaluate (or evaluator (fn [candidate stop] (scenario/fitness candidate stop))))
  (defn publish [message &opt force]
    (def now (os/clock :monotonic))
    (when (or force (>= (- now last-publish) 0.1))
      (set last-publish now)
      (progress {:message message :completed evaluated :simulated simulated :cache-hits cache-hits :total 0 :seconds (- now started)
                 :best (tuple ;(alternatives archive)) :preset preset :explanation (explanations preset)})))
  (defn visit [candidate &opt purchase count-samples force]
    (unless (stop?)
      (def ids (get-in candidate [:player :loadout :items] []))
      (def inspection (legal package ids (merge limits {:budget (if next? math/inf budget) :owned (if next? owned locked)}) champion))
      (when (and (inspection :legal) (contains-all? ids locked)
                 (or (not (get options :runes false)) (loadouts/legal-page? package (get-in candidate [:player :loadout :runes] [])))
                 (or (not (get options :summoners false)) (= 2 (length (get-in candidate [:player :loadout :summoners] [])))))
        # Item slots do not change our modeled effects. A stable inventory order
        # avoids evaluating permutations and fixes trigger order across builds.
        (def trials (or count-samples (if exact? final-samples (min samples 8))))
        (def normalized (merge (replace-items candidate (tuple ;(sorted ids))) {:samples trials :model engine/identity}))
        (def purchase-key (when (get purchase :purchase) {:purchase (purchase :purchase) :purchase-cost (purchase :purchase-cost)}))
        (def key (hash/sha256 (util/encode-data (util/canonical [version engine/identity (package :snapshot) normalized preset purchase-key]))))
        (unless (and (seen key) (not force))
          (when (or force (< (length seen) 4096))
            (put seen key true)
            # Custom evaluators are deliberately isolated from the real-engine
            # cache. Purchase restrictions and scores are checked anew on hits.
            (def metric-key (unless evaluator (fitness-key package normalized)))
            (def cached (when metric-key (cache/lookup metric-key)))
            (def outcome (if cached (do (++ cache-hits) [true cached])
                           (protect
                             (def result (evaluate normalized stop?))
                             (++ simulated)
                             (if metric-key (or (cache/store metric-key result) result) result))))
            (unless (or (first outcome) (stop?)) (error (string "Candidate simulation failed: " (outcome 1))))
            (when (first outcome)
              (++ evaluated)
              (def result (outcome 1))
              (def row {:key key :definition normalized :ids (get-in normalized [:player :loadout :items]) :cost (inspection :cost)
                        :purchase (get purchase :purchase) :purchase-cost (get purchase :purchase-cost)
                        :score (score (result :metrics) preset duration) :metrics (result :metrics)
                        :uncertainty (get result :uncertainty {}) :samples trials
                        :coverage (get result :unsupported [])})
              (array/push archive row)
              (when (> (length archive) 40)
                (set archive (array/slice (distinct-rows [;(take 20 (sorted archive better?)) ;(alternatives archive)]))))
              (when (or (= evaluated 1) (= 0 (mod evaluated 8))) (publish "Searching builds" (= evaluated 1)))
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
  (defn expand-choices [candidate]
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
        (visit (merge candidate {:player player})))))
  # Complete legal inventories are proposals only. Every score still comes from
  # the same chronological combat engine, including interactions and coverage.
  (defn fill [order]
    (def ids (array/slice locked))
    (var cost (sum (map |(((package :item-map) $) :gold) locked)))
    (for pass 0 slots
      (def count (length ids))
      (each id order
        (when (or (stop?) (>= (length ids) slots)) (break))
        (def item ((package :item-map) id))
        (def next [;ids id])
        (when (and (<= (+ cost (item :gold)) budget)
                   (or (item :stackable) (not (some |(= id $) ids)))
                   ((legal package next limits champion) :legal))
          (array/push ids id) (+= cost (item :gold))))
      (when (= count (length ids)) (break)))
    (tuple ;ids))
  (var random-state (inc (mod (get definition :seed 1) 2147483646)))
  (defn choose [values]
    (when (not (empty? values))
      (set random-state (mod (* random-state 48271) 2147483647))
      (values (mod random-state (length values)))))
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
    (do
      (def base-row (visit base))
      (when (and (contains-all? owned locked) ((legal package owned limits champion) :legal))
        (set incumbent (visit (replace-items baseline owned) nil final-samples true)))
      (def singles @[])
      (def screening-deadline (+ started (* seconds 0.35)))
      (each id pool
        (when (or (stop?) (>= (os/clock :monotonic) screening-deadline)) (break))
        (def row (visit (replace-items baseline [;locked id]) nil samples))
        (when row (array/push singles (merge row {:added id}))))
      (def ranked (sorted singles better?))
      # Cost efficiency orders proposals using only the preset's first metric;
      # it never adds unlike outcome metrics or replaces simulation scoring.
      (defn efficiency [row]
        (/ (- ((row :score) 0) (get-in base-row [:score 0] 0)) (max 1 (- (row :cost) (get-in base-row [:cost] 0)))))
      (def efficient (sorted singles (fn [a b] (if (= (efficiency a) (efficiency b)) (better? a b) (> (efficiency a) (efficiency b))))))
      (def raw-order (unique [;(map |($ :added) ranked) ;pool]))
      (def efficient-order (unique [;(map |($ :added) efficient) ;pool]))
      (each order [raw-order efficient-order]
        (visit (replace-items baseline (fill order))))
      # Give complementary stat families their own starts. This avoids a mixed
      # standalone ranking suppressing AD/crit, AP/penetration or defense builds.
      # These are proposal buckets, not hardcoded champion builds or item scores.
      (each stat [:ad :ap :attack-speed-bonus :crit-chance :ability-haste :hp :armor :mr]
        (when (stop?) (break))
        (def family (filter |(> (get-in package [:item-map $ :stats stat] 0) 0) raw-order))
        (when (not (empty? family)) (visit (replace-items baseline (fill [;family ;raw-order])))))
      (when optional? (expand-choices baseline))
      # Seed several full inventories before any exhaustive neighborhood sweep.
      # Mutations and crossovers revisit leaders after each small batch, rather
      # than exhausting every item/slot permutation of one shallow candidate.
      (for index 0 (min 12 (length pool))
        (each order [raw-order efficient-order]
          (when (stop?) (break))
          (visit (replace-items baseline (fill [;(array/slice order index) ;(take index order)])))))
      (var generation 0)
      (while (and (not (stop?)) (not (empty? archive)) (not (empty? pool)))
        (def leaders (take 4 (sorted archive better?)))
        (each row leaders
          (def parent (row :definition))
          (def ids (row :ids))
          (def editable (seq [index :range [0 (length ids)]
                              :when (contains-all? [;(take index ids) ;(drop (inc index) ids)] locked)] index))
          (for mutation 0 8
            (when (stop?) (break))
            (def remaining (array/slice ids))
            (when (not (empty? editable)) (array/remove remaining (choose editable) 1))
            (when (and (= 0 (mod mutation 4)) (not (empty? remaining)))
              (def removable (filter (fn [index] (contains-all? [;(take index remaining) ;(drop (inc index) remaining)] locked))
                                     (range 0 (length remaining))))
              (when (not (empty? removable)) (array/remove remaining (choose removable) 1)))
            (def order (if (= 0 (mod mutation 2)) raw-order efficient-order))
            (def proposal @[(choose pool) ;remaining ;order])
            (when (= 0 (mod mutation 4)) (array/insert proposal 0 (choose pool)))
            (visit (replace-items parent (fill proposal))))
          # Remove weak filler too: spending all gold or filling six slots is
          # not itself a goal, and lower cost breaks equal outcome scores.
          (each index editable
            (when (stop?) (break))
            (visit (replace-items parent [;(take index ids) ;(drop (inc index) ids)])))
          (when (and optional? (= 0 (mod generation 4))) (expand-choices parent)))
        (when (> (length leaders) 1)
          (def a (first leaders)) (def b (choose (drop 1 leaders)))
          (def crossed @[])
          (for index 0 slots
            (each row [a b] (when (get (row :ids) index) (array/push crossed ((row :ids) index)))))
          (visit (replace-items (a :definition) (fill [;crossed ;pool]))))
        # A fresh full inventory escapes local optima, including synergies with
        # little standalone value. Its deterministic seed is scenario-specific.
        (def order (tabseq [id :in pool] id (hash/sha256 (string random-state generation id))))
        (def shuffled (sorted pool |(< (order $0) (order $1))))
        (visit (replace-items baseline (fill shuffled)))
        (++ generation))
      (set truncated true)))
  # Exact searches evaluate every candidate with the same final trial schedule.
  # Heuristic finalists all use the same larger schedule; reserve wall time.
  (when (and (not exact?) (not (cancelled)))
    (set phase :finalists)
    (def finalists (alternatives archive))
    (def refined @[])
    (each row finalists
      (def next (visit (row :definition) {:purchase (row :purchase) :purchase-cost (row :purchase-cost)} final-samples true))
      (when next (array/push refined next)))
    (when (not (empty? refined)) (set archive [;refined ;(if incumbent [incumbent] [])])))
  (def rows (tuple ;(alternatives archive)))
  (publish "Search finished" true)
  {:version version :patch (package :patch) :snapshot (package :snapshot) :model engine/identity
   :preset preset :explanation (explanations preset) :rows rows :baseline incumbent :evaluated evaluated
   :simulated simulated :cache-hits cache-hits :cache (cache/stats) :pool-size (length pool)
   :seconds (- (os/clock :monotonic) started) :limit seconds :cancelled (not (not (cancelled)))
   :complete (and exact? (not truncated) (not (cancelled)) (< (os/clock :monotonic) deadline))
   :guarantee (if (and exact? (not truncated) (not (cancelled)) (< (os/clock :monotonic) deadline)) :optimal-within-pool :best-found)
   :search (if exact? :exhaustive :heuristic) :next-purchase next?
   :notes ["Scores compare a fixed opponent and declared strategies using common seeds."
           ;(if (get-in package [:manifest "initial"])
              ["The initial excerpt searches only curated purchase rules; refresh the selected patch to search its complete shop."] [])
           "Heuristic search screens items, seeds complete legal inventories, then uses seeded mutations and crossovers. Scores always come from the combat engine."
           "Missing effects can change rankings. See coverage for every recommendation."
           "Heuristic alternatives are the best found within the compute budget; optimal play is not modeled."
           "Utility compares effective control, healing and protection in order. Team protection and spatial effects are outside this duel model."]})
