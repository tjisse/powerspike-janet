(import ./expressions :as expr)
(import ./damage :as damage)
(import ./data-util :as util)
(import ./runes :as runes)
(import ./stats :as stats)
(import ./status-timeline :as status-timeline)
(import pshash :as hash)

(def version "combat-2")
(def identity (hash/sha256 (string version (slurp "src/powerspike/engine.janet")
                                   (slurp "src/powerspike/status-timeline.janet")
                                   (slurp "src/powerspike/expressions.janet") (slurp "src/powerspike/stats.janet")
                                   (slurp "src/powerspike/damage.janet") (slurp "src/powerspike/effects.janet")
                                   (slurp "src/powerspike/normalize.janet")
                                   (slurp "src/powerspike/champion-abilities.janet")
                                   (slurp "src/powerspike/attacks.janet")
                                   (slurp "data/attack-fixtures/latest-form-projectiles.jdn")
                                   (slurp "data/attack-fixtures/16.20.1/kayle-manifest.json")
                                   (slurp "data/form-fixtures/16.20.1/manifest.json")
                                   (slurp "data/form-fixtures/16.20.1/jayce-manifest.json")
                                   (slurp "data/form-fixtures/16.20.1/elise-manifest.json")
                                   (slurp "data/form-fixtures/16.20.1/gnar-manifest.json")
                                   (slurp "data/rune-fixtures/16.20.1/manifest.json")
                                   (slurp "data/item-fixtures/16.20.1/manifest.json")
                                   (slurp "data/attack-fixtures/16.21.1/kayle-manifest.json")
                                   (slurp "data/form-fixtures/16.21.1/manifest.json")
                                   (slurp "data/form-fixtures/16.21.1/jayce-manifest.json")
                                   (slurp "data/form-fixtures/16.21.1/elise-manifest.json")
                                   (slurp "data/form-fixtures/16.21.1/gnar-manifest.json")
                                   (slurp "data/rune-fixtures/16.21.1/manifest.json")
                                   (slurp "data/item-fixtures/16.21.1/manifest.json")
                                   (slurp "src/powerspike/attack-limits.janet")
                                   (slurp "data/attack-fixtures/16.19.1/reviewed-speed-cap.jdn")
                                   (slurp "src/powerspike/forms.janet")
                                   (slurp "data/form-fixtures/16.19.1/manifest.json")
                                   (slurp "data/form-fixtures/16.19.1/Nidalee-characters.json")
                                   (slurp "data/form-fixtures/16.19.1/NidaleeCougar-characters.json")
                                   (slurp "data/form-fixtures/16.19.1/strings.json")
                                   (slurp "data/form-fixtures/16.19.1/jayce-manifest.json")
                                   (slurp "data/form-fixtures/16.19.1/Jayce-characters.json")
                                   (slurp "data/form-fixtures/16.19.1/Jayce-strings.json")
                                   (slurp "data/form-fixtures/16.19.1/elise-manifest.json")
                                   (slurp "data/form-fixtures/16.19.1/Elise-characters.json")
                                   (slurp "data/form-fixtures/16.19.1/EliseSpider-characters.json")
                                   (slurp "data/form-fixtures/16.19.1/Elise-strings.json")
                                   (slurp "data/form-fixtures/16.19.1/gnar-manifest.json")
                                   (slurp "data/form-fixtures/16.19.1/Gnar-characters.json")
                                   (slurp "data/form-fixtures/16.19.1/GnarBig-characters.json")
                                   (slurp "data/form-fixtures/16.19.1/Gnar-strings.json")
                                   (slurp "data/combat-fixtures/16.19.1/Ahri-characters.json")
                                   (slurp "data/combat-fixtures/16.19.1/Annie-characters.json")
                                   (slurp "data/combat-fixtures/16.19.1/Viktor-characters.json")
                                   (slurp "data/attack-fixtures/16.19.1/reviewed-timing.jdn")
                                   (slurp "data/attack-fixtures/latest-mage-timing.jdn")
                                   (slurp "data/attack-fixtures/16.19.1/reviewed-form-projectiles.jdn")
                                   (slurp "data/attack-fixtures/16.19.1/kayle-manifest.json")
                                   (slurp "data/attack-fixtures/16.19.1/Kayle-characters.json")
                                   (slurp "data/attack-fixtures/16.19.1/Kayle-strings.json")
                                   (slurp "data/combat-fixtures/16.19.1/manifest.json")
                                   (slurp "data/16.19.1/catalog/sources/champions-ddragon.json")
                                   (slurp "data/16.19.1/catalog/manifest.json")
                                   (slurp "src/powerspike/packages.janet")
                                   (slurp "src/powerspike/tooltip.janet")
                                   (slurp "src/powerspike/runes.janet")
                                   (slurp "data/rune-fixtures/16.18.1/records.json")
                                   (slurp "data/rune-fixtures/16.19.1/records.json")
                                   (slurp "data/rune-fixtures/16.18.1/styles.json")
                                   (slurp "data/rune-fixtures/16.19.1/styles.json")
                                   (slurp "data/16.19.1/sources/annie-character-record.json")
                                   (slurp "data/16.19.1/sources/garen-character-record.json")
                                   (slurp "src/powerspike/objectives.janet")
                                   (slurp "src/powerspike/scenario.janet") (slurp "src/powerspike/skills.janet")
                                   (slurp "src/powerspike/builds.janet") (slurp "data/16.19.1/annie.janet")
                                   (slurp "data/semantic-overrides.jdn"))))
(defn less? [a b]
  (cond (not= (a :at) (b :at)) (< (a :at) (b :at))
    (not= (a :priority) (b :priority)) (< (a :priority) (b :priority))
    (< (a :sequence) (b :sequence))))
(defn push [heap event]
  (array/push heap event)
  (var i (dec (length heap)))
  (while (> i 0)
    (def parent (math/floor (/ (dec i) 2)))
    (unless (less? (heap i) (heap parent)) (break))
    (def value (heap parent)) (put heap parent (heap i)) (put heap i value) (set i parent)))
(defn pop [heap]
  (def event (heap 0))
  (def tail (array/pop heap))
  (unless (empty? heap)
    (put heap 0 tail)
    (var i 0)
    (forever
      (def left (+ (* i 2) 1))
      (when (>= left (length heap)) (break))
      (def right (inc left))
      (def child (if (and (< right (length heap)) (less? (heap right) (heap left))) right left))
      (unless (less? (heap child) (heap i)) (break))
      (def value (heap i)) (put heap i (heap child)) (put heap child value) (set i child)))
  event)
(defn random-at [seed trial actor kind index]
  (/ (scan-number (string "0x" (string/slice (hash/sha256 (string seed "/" trial "/" actor "/" kind "/" index)) 0 8))) 4294967296))
(defn state [actor index]
  (def stats (merge @{} (actor :stats)))
  (assert (and (util/finite? (stats :hp)) (> (stats :hp) 0)) "Actor needs positive maximum health.")
  (merge @{} actor {:index index :target (- 1 index) :stats stats :original-stats (merge {} stats)
                    :health (min (stats :hp) (get actor :health (stats :hp)))
                    :resource (min (get stats :mp 0) (get actor :resource (get stats :mp 0)))
                    :position (get actor :position 0) :velocity 0 :busy-until 0 :attack-ready 0
                    :parry-until 0 :parry-source-kinds [] :ready @{} :charges @{} :recasts @{} :controls @{} :buffs @{} :buff-counts @{} :shields @[] :stat-effects @{}
                    :counters @{} :proc-ready @{} :proc-counts @{} :modifiers @[] :pending-pulses @{} :terrify-ready @{}
                    :damage-dealt 0 :attack-damage 0 :breakdown @{} :damage-taken 0 :healed 0 :absorbed 0 :control-time 0 :actions 0}))
(defn context [actor target rank]
  (def stats (merge @{} (actor :stats)
                    {:health (actor :health) :health-percent (/ (actor :health) ((actor :stats) :hp))
                     :missing-health (- ((actor :stats) :hp) (actor :health))
                     :missing-health-percent (- 1 (/ (actor :health) ((actor :stats) :hp)))}))
  {:stats stats :base (actor :base) :rank rank :level (actor :level) :patch (get actor :patch "unknown") :buffs (actor :buff-counts)
   :ranged (get actor :ranged)
   :shards (get actor :shards []) :shard-bonuses (get actor :shard-bonuses [])
   :champion-target (some |(= $ :champion) (get target :tags [(target :kind)]))
   :target (merge (target :stats) {:health (target :health)
                                   :missing-health-percent (- 1 (/ (target :health) ((target :stats) :hp)))
                                   :missing-health (- ((target :stats) :hp) (target :health))})})
(defn value [expression actor target rank]
  (if (number? expression) expression (expr/evaluate expression (context actor target rank))))
(defn fixed-value? [expression &opt depth]
  (def nesting (or depth 0))
  (cond
    (> nesting 32) false
    (number? expression) (util/finite? expression)
    (not (dictionary? expression)) false
    (some |(= $ (expression :op)) [:constant :rank :level-values :level-interpolation]) true
    (some |(= $ (expression :op)) [:sum :multiply :with-rank])
    (and (indexed? (expression :children))
         (not (some |(not (fixed-value? $ (inc nesting))) (expression :children))))
    false))
(defn event-value? [expression &opt depth]
  # These inputs can change only at applied stat/buff events. Never freeze
  # health-derived expressions while continuous regeneration is running.
  (def nesting (or depth 0))
  (cond
    (> nesting 32) false
    (number? expression) (util/finite? expression)
    (not (dictionary? expression)) false
    (some |(= $ (expression :op)) [:constant :rank :level-values :level-interpolation :buff-count]) true
    (some |(= $ (expression :op)) [:stat :target-stat])
    (not (some |(= $ (expression :stat)) [:health :health-percent :missing-health :missing-health-percent]))
    (some |(= $ (expression :op)) [:sum :multiply :with-rank :conditional])
    (and (indexed? (expression :children))
         (not (some |(not (event-value? $ (inc nesting))) (expression :children))))
    false))
(defn health-affine? [expression &opt depth]
  (def nesting (or depth 0))
  (cond
    (> nesting 32) false
    (event-value? expression) true
    (not (dictionary? expression)) false
    (= :stat (expression :op))
    (and (= 0 (expression :formula))
         (some |(= $ (expression :stat)) [:health :health-percent :missing-health :missing-health-percent]))
    (some |(= $ (expression :op)) [:sum :multiply :with-rank :conditional])
    (and (indexed? (expression :children))
         (not (some |(not (health-affine? $ (inc nesting))) (expression :children)))
         (or (not= :multiply (expression :op))
             (<= (length (filter |(not (event-value? $)) (expression :children))) 1)))
    false))
(defn health-form [expression actor target rank &opt depth]
  # Algebraic coefficients in current health; never infer a slope by sampling.
  (def nesting (or depth 0))
  (assert (<= nesting 32) "Health cost nesting limit.")
  (defn next [child] (health-form child actor target rank (inc nesting)))
  (def result
    (cond
      (event-value? expression) [0 (value expression actor target rank)]
      (= :stat (expression :op))
      (case (expression :stat)
        :health [1 0]
        :health-percent [(/ 1 ((actor :stats) :hp)) 0]
        :missing-health [-1 ((actor :stats) :hp)]
        :missing-health-percent [(/ -1 ((actor :stats) :hp)) 1]
        (error "Unsupported health cost stat."))
      (= :with-rank (expression :op))
      (health-form ((expression :children) 0) actor target
                   (if (number? (expression :rank)) (expression :rank) rank) (inc nesting))
      (= :conditional (expression :op))
      (next ((expression :children) (if (not= (> (get (actor :buff-counts) (expression :buff) 0) 0) (expression :invert)) 0 1)))
      (= :sum (expression :op))
      (reduce (fn [a b] [(+ (a 0) (b 0)) (+ (a 1) (b 1))]) [0 0] (map next (expression :children)))
      (= :multiply (expression :op))
      (reduce (fn [a b]
                (assert (or (= 0 (a 0)) (= 0 (b 0))) "Nonlinear health cost.")
                [(+ (* (a 0) (b 1)) (* (b 0) (a 1))) (* (a 1) (b 1))]) [0 1] (map next (expression :children)))
      (error "Unsupported health cost expression.")))
  (assert (not (some |(not (util/finite? $)) result)) "Non-finite health cost coefficients.")
  result)
(defn affine-cost? [ability expression]
  (and (= :health (ability :cost-resource)) (not (event-value? expression)) (health-affine? expression)))
(defn regeneration [stats health?]
  (if health? (* (/ (get stats :hp-regen 0) 5) (get stats :healing-multiplier 1))
    (/ (get stats :mp-regen 0) 5)))
(defn alive? [actor] (not (actor :dead-at)))
(defn controlled? [actor controls at]
  (some |(> (get (actor :controls) $ 0) at) controls))
(defn health-permitted? [actor target activation]
  (and (<= (/ (actor :health) ((actor :stats) :hp)) (get activation :self-health-below 1))
       (<= (/ (target :health) ((target :stats) :hp)) (get activation :target-health-below 1))))
(defn target-allowed? [effect target]
  (and (or (not (effect :target-kinds))
           (some |(some (fn [kind] (= $ kind)) (get target :tags [(target :kind)])) (effect :target-kinds)))
       (not (some |(= $ (target :objective)) (get effect :exclude-objectives [])))))
(defn simulate [scenario &opt cancelled]
  (def duration (scenario :duration))
  (assert (and (util/finite? duration) (< 0 duration 180)) "Combat duration must be below 180 seconds.")
  (assert (= 2 (length (scenario :actors))) "This model supports exactly two participants.")
  (def actors (map state (scenario :actors) [0 1]))
  # Definitions, learned ranks and strategy order stay fixed during a fight.
  # Keep this private so decision scans share it without changing actor output.
  (def decision-abilities
    (map (fn [actor]
           (def ordered @[])
           (each slot (get-in actor [:strategy :priority] [:q :w :e :r])
             (def ability (find |(= slot ($ :slot)) (get actor :abilities [])))
             (def rank (get (actor :ranks) slot 0))
             (when (and ability (> rank 0) (some |(= :estimated ($ :status)) (ability :effects)))
               (array/push ordered [ability rank (get-in actor [:strategy :activation slot :after])
                                    (event-value? (ability :cost))
                                    (and (ability :recast) (event-value? (get-in ability [:recast :cost] 0)))
                                    (affine-cost? ability (ability :cost))
                                    (and (ability :recast) (affine-cost? ability (get-in ability [:recast :cost] 0)))])))
           ordered) actors))
  (defn input-value [expression actor rank &opt affine]
    (def result (protect (if affine (health-form expression actor (actors (actor :target)) rank)
                           (max 0 (value expression actor (actors (actor :target)) rank)))))
    (when (and (first result) (or affine (util/finite? (result 1)))) (result 1)))
  (def changing-inputs
    (map (fn [actor ordered]
           (def inputs @[])
           (when (get-in actor [:strategy :abilities] true)
             (each [ability rank] ordered
               (each [field expression] [[:cost (ability :cost)] [:recast-cost (get-in ability [:recast :cost] 0)]
                                         [:range (ability :range)]]
                 (when (and (not (fixed-value? expression)) (event-value? expression)
                            (or (not= field :range)
                                (some |(and (= :enemy ($ :target)) (not= :attack (get $ :trigger))) (ability :effects))))
                   (array/push inputs @{:rank rank :field field :expression expression
                                        :value (input-value expression actor rank)}))
                 (when (and (not= field :range) (affine-cost? ability expression))
                   (array/push inputs @{:rank rank :field field :expression expression :affine true
                                        :value (input-value expression actor rank true)})))))
           inputs) actors decision-abilities))
  (def watching-inputs? (some |(not (empty? $)) changing-inputs))
  (var inputs-dirty false)
  (def moving? (some |(some (fn [mode] (= mode (get-in $ [:strategy :movement]))) [:approach :hold-range]) actors))
  (def range-boundaries
    (when moving?
      (map (fn [actor ordered]
             (def ranges @[])
             (when (get-in actor [:strategy :attacks] true) (array/push ranges (get actor :attack-range 125)))
             (when (get-in actor [:strategy :abilities] true)
               (each [ability rank] ordered
                 (when (and (fixed-value? (ability :range))
                            (some |(and (= :enemy ($ :target)) (not= :attack (get $ :trigger))) (ability :effects)))
                   (def result (protect (max 0 (value (ability :range) actor (actors (actor :target)) rank))))
                   (when (and (first result) (util/finite? (result 1))) (array/push ranges (result 1))))))
             (each input (changing-inputs (actor :index)) (when (= :range (input :field)) (array/push ranges input)))
             ranges) actors decision-abilities)))
  (def recovery-pools
    (map (fn [ordered]
           (def pools @{})
           (each [ability rank after forecastable recast-forecastable affine recast-affine] ordered
             (when (or forecastable recast-forecastable affine recast-affine)
               (put pools (if (= :health (ability :cost-resource)) :health :resource) true)))
           pools) decision-abilities))
  (def health-conditions
    (map (fn [actor ordered]
           (if (get-in actor [:strategy :abilities] true)
             (seq [[ability] :in ordered
                   :let [activation (get-in actor [:strategy :activation (ability :slot)] {})]
                   :when (or (< (get activation :self-health-below 1) 1)
                             (< (get activation :target-health-below 1) 1))]
               activation)
             [])) actors decision-abilities))
  (def watching-health? (some |(not (empty? $)) health-conditions))
  (def queue @[])
  (def decision-at @[nil nil])
  (def trace @[])
  (def hits @[])
  (def unsupported @[])
  (def tracing (get scenario :trace true))
  (def statuses (when tracing (status-timeline/create)))
  (def seed (get scenario :seed 1))
  (def trial (get scenario :trial 0))
  (var sequence 0)
  (var at 0)
  (var processed 0)
  (var before nil)
  (def limit (min 100000 (get scenario :event-limit 10000)))
  (defn note [message]
    (unless (some |(= $ message) unsupported) (array/push unsupported message)))
  (defn schedule [time priority kind fields]
    (when (< time duration)
      (assert (and (util/finite? time) (>= time at)) "Invalid event timestamp.")
      (assert (< (length queue) (get scenario :pending-limit 20000)) "Pending event limit reached.")
      (++ sequence) (push queue (merge fields {:at time :priority priority :kind kind :sequence sequence}))))
  (defn request-decision [index time]
    (when (and (< time duration) (or (nil? (decision-at index)) (< time (decision-at index))))
      (put decision-at index time)
      (schedule time 30 :decide {:actor index})))
  (defn resume [actor]
    (when (and (alive? actor) (alive? (actors (actor :target))))
      (request-decision (actor :index) (max at (actor :busy-until)))))
  (defn refresh-inputs []
    (when inputs-dirty
      (set inputs-dirty false)
      (eachp [index inputs] changing-inputs
        (def actor (actors index))
        (each input inputs
          (def current (input-value (input :expression) actor (input :rank) (input :affine)))
          (when (not= current (input :value))
            (put input :value current)
            (resume actor))))))
  (defn velocity [actor]
    (if (or (> (actor :busy-until) at) (controlled? actor [:stun :root :charm :fear :airborne :suppression] at))
      0 (actor :velocity)))
  (defn steer []
    (when moving?
      (def distance (math/abs (- ((actors 0) :position) ((actors 1) :position))))
      (each actor actors
        (def strategy (get actor :strategy {}))
        (def mode (get strategy :movement :hold))
        (def desired (if (= mode :hold-range) (get strategy :preferred-range (get actor :attack-range 125)) (get actor :attack-range 125)))
        (def target-position ((actors (actor :target)) :position))
        (def direction (cond (< (actor :position) target-position) 1
                         (> (actor :position) target-position) -1
                         (= 0 (actor :index)) 1
                         -1))
        (def intent (* direction (actor :velocity)))
        (put actor :velocity
             (if (and (alive? actor) (alive? (actors (actor :target))))
               (cond (and (some |(= $ mode) [:approach :hold-range]) (> distance desired)
                          (or (= mode :approach) (> distance (+ desired 1)) (> intent 0)))
                 (* direction (get (actor :stats) :move-speed 0))
                 (and (= mode :hold-range) (< distance desired) (or (< distance (- desired 1)) (< intent 0)))
                 (* -1 direction (get (actor :stats) :move-speed 0))
                 0)
               0)))
      (def closing (* (if (<= ((actors 0) :position) ((actors 1) :position)) 1 -1)
                      (- (velocity (actors 0)) (velocity (actors 1)))))
      (each actor actors
        (when (and (alive? actor) (alive? (actors (actor :target))))
          (defn crossing [boundary]
            (when (and (not= closing 0) (> (/ (- distance boundary) closing) 0))
              # Forecasts never relax the strict range gate. Round forward so
              # floating-point integration reaches the boundary before retrying.
              (def deadline (/ (math/ceil (* 1e9 (+ at (max 1e-9 (/ (- distance boundary) closing))))) 1e9))
              (when (util/finite? deadline) (request-decision (actor :index) deadline))))
          (when (> closing 0)
            (each entry (range-boundaries (actor :index))
              (def boundary (if (number? entry) entry (entry :value)))
              (when (and (util/finite? boundary) (> distance boundary)) (crossing boundary))))
          (when (and (get-in actor [:channel :leash]) (not (get-in actor [:channel :cancelled])))
            (crossing (+ (get-in actor [:channel :leash]) 0.0000001)))
          (when (not= 0 (actor :velocity))
            (def desired (get-in actor [:strategy :preferred-range] (get actor :attack-range 125)))
            (crossing (if (= :hold-range (get-in actor [:strategy :movement])) desired (get actor :attack-range 125)))
            (when (> (actor :busy-until) at) (request-decision (actor :index) (actor :busy-until))))))))
  (defn health-status []
    # Sample immediately before each mutation, so regeneration or intervening
    # healing cannot leave a cached predicate stale.
    (when watching-health?
      (map (fn [actor conditions]
             (map |(health-permitted? actor (actors (actor :target)) $) conditions)) actors health-conditions)))
  (defn health-changed [previous]
    (when previous
      (eachp [index conditions] health-conditions
        (def actor (actors index))
        (eachp [position activation] conditions
          (when (and (not (get-in previous [index position]))
                     (health-permitted? actor (actors (actor :target)) activation)
                     (>= at (get activation :after 0)))
            (resume actor))))))
  (defn recover [actor pool]
    (when (and (get-in actor [:strategy :abilities] true) ((recovery-pools (actor :index)) pool)) (resume actor)))
  (defn reset-attack [actor]
    (def earlier (> (actor :attack-ready) at))
    (put actor :attack-ready at)
    (when (and earlier (get-in actor [:strategy :attacks] true)) (resume actor)))
  (defn refresh-stats [actor]
    (when watching-inputs? (set inputs-dirty true))
    (def previous (actor :stats))
    (def totals (merge @{} (actor :original-stats)))
    (def active (filter |(and (> ($ :expires) at)
                              (or (not ($ :requires-buff)) (> (get (actor :buff-counts) ($ :requires-buff) 0) 0)))
                        (values (actor :stat-effects))))
    (defn apply-modifier [modifier]
      (def key (modifier :stat))
      (def before (get totals key (if (some |(= key $) [:outgoing-multiplier :healing-multiplier]) 1 0)))
      (put totals key (case (modifier :mode)
                        :multiply (* before (modifier :amount))
                        :maximum (max before (modifier :amount))
                        (+ before (modifier :amount)))))
    # Bonus attack speed scales with the champion's ratio, not total speed.
    # Derive it before applying any direct attack-speed multipliers.
    (each modifier active (when (= :attack-speed-bonus (modifier :stat)) (apply-modifier modifier)))
    (def delta (- (get totals :attack-speed-bonus 0) (get (actor :original-stats) :attack-speed-bonus 0)))
    (when (not= delta 0)
      (assert (and (util/finite? (actor :attack-speed-ratio)) (util/finite? (actor :attack-speed-cap)))
              "Bonus attack speed requires the champion's attack-speed ratio and cap.")
      (def raw (+ (get (actor :original-stats) :attack-speed-uncapped (totals :attack-speed))
                  (* delta (actor :attack-speed-ratio))))
      (put totals :attack-speed-uncapped raw)
      (put totals :attack-speed (max 0 (min raw (actor :attack-speed-cap)))))
    (def resistance (actor :form-resistance))
    (defn resistance-stat? [modifier] (some |(= $ (modifier :stat)) [:armor :mr]))
    (each modifier active
      (unless (or (= :attack-speed-bonus (modifier :stat)) (and resistance (resistance-stat? modifier)))
        (apply-modifier modifier)))
    (when resistance
      (def base-ad (get-in actor [:base :ad]))
      (def change (- (stats/form-resistance resistance (totals :ad) base-ad)
                     (stats/form-resistance resistance (get-in actor [:original-stats :ad]) base-ad)))
      (each key [:armor :mr] (put totals key (+ (get totals key 0) change)))
      (each modifier active (when (resistance-stat? modifier) (apply-modifier modifier))))
    (def health-before (when (not= (previous :hp) (totals :hp)) (health-status)))
    (put actor :stats totals)
    (put actor :health (min (actor :health) (totals :hp)))
    (health-changed health-before)
    (each [pool maximum health?] [[:health :hp true] [:resource :mp false]]
      (when (or (not= (get previous maximum 0) (get totals maximum 0))
                (not= (regeneration previous health?) (regeneration totals health?)))
        (recover actor pool))))
  (defn participants []
    (map |{:id ($ :id) :health ($ :health) :resource ($ :resource) :position ($ :position)} actors))
  (defn record [kind fields]
    (when tracing
      (array/push trace (merge fields {:at at :kind kind :before before :participants (participants)}))))
  (defn interrupt-channel [actor]
    (when (and (actor :channel) (> (get-in actor [:channel :end]) at) (not (get-in actor [:channel :cancelled])))
      (put (actor :channel) :cancelled true)
      (put actor :busy-until at)
      (record :interrupted {:actor (actor :id) :source (get-in actor [:channel :source])})))
  (defn finish-drain [actor &opt refund]
    (when (and (get-in actor [:channel :drain]) (not (get-in actor [:channel :cancelled])))
      (def channel (actor :channel))
      (def remaining (max 0 (- (get (actor :ready) (channel :source) at) at)))
      (def fraction (if (= false refund) 1 (- 1 (channel :refund))))
      (put (actor :ready) (channel :source) (+ at (* remaining fraction)))
      (put actor :channel nil) (put actor :busy-until at)
      (record :channel-end {:actor (actor :id) :source (channel :source) :cooldown-left (* remaining fraction)})
      (resume actor)))
  (defn advance [time]
    (def dt (- time at))
    (def positions (map |($ :position) actors))
    (def velocities (map velocity actors))
    (each actor actors
      (when (alive? actor)
        (put actor :health (min ((actor :stats) :hp) (+ (actor :health) (* dt (regeneration (actor :stats) true)))))
        (put actor :resource (min (get (actor :stats) :mp 0) (+ (actor :resource) (* dt (regeneration (actor :stats) false)))))
        (def active (or (get-in actor [:strategy :attacks] false) (get-in actor [:strategy :abilities] false) (not= 0 (actor :velocity))))
        (def blocked (and active
                          (or (controlled? actor [:stun :charm :fear :airborne :suppression] at)
                              (and (not= 0 (actor :velocity)) (controlled? actor [:root] at))
                              (and (get-in actor [:strategy :abilities] false) (controlled? actor [:silence] at)))))
        (def impairment (cond blocked 1
                          (and (not= 0 (actor :velocity)) (controlled? actor [:slow] at)) (- 1 (get-in actor [:stat-effects :slow :amount] 1))
                          0))
        (put actor :control-time (+ (actor :control-time) (* dt impairment)))
        (unless (= 0 (velocities (actor :index)))
          (def step (* dt (velocities (actor :index))))
          (put actor :position (+ (actor :position) step)))))
    # Two approaching points cannot pass through each other between events.
    (def gap (- (positions 1) (positions 0)))
    (when (< (* gap (- ((actors 1) :position) ((actors 0) :position))) 0)
      (def contact (+ (positions 0) (* (velocities 0) (/ gap (- (velocities 0) (velocities 1))))))
      (each actor actors (put actor :position contact)))
    (set at time))
  (defn trigger [owner target event-key origin depth &opt slot]
    (when (< depth 3)
      (each effect (get owner :triggers [])
        (def id (effect :id))
        (when (and (some |(= $ event-key) (get effect :on []))
                   (or (not (effect :ability-slots)) (some |(= $ slot) (effect :ability-slots)))
                   (<= (get (owner :proc-ready) id 0) at)
                   (or (not (effect :requires-ready)) (<= (get (owner :proc-ready) (effect :requires-ready) 0) at))
                   (or (not (effect :requires-buff)) (> (get (owner :buff-counts) (effect :requires-buff) 0) 0))
                   (target-allowed? effect target))
          (def result (protect
                        (def counter (get (owner :proc-counts) id @{:count 0 :last (- math/inf) :origins @[]}))
                        (def window (value (get effect :window 999) owner target 1))
                        (when (> (- at (get counter :first (- math/inf))) window) (put counter :count 0) (put counter :origins @[]))
                        (when (= 0 (counter :count)) (put counter :first at))
                        (unless (some |(= $ origin) (counter :origins))
                          (put counter :count (inc (counter :count))) (array/push (counter :origins) origin))
                        (put counter :last at) (put (owner :proc-counts) id counter)
                        (when (>= (counter :count) (value (get effect :every 1) owner target 1))
                          (put counter :count 0) (put counter :origins @[])
                          (when (effect :consume-buff)
                            (put (owner :buff-counts) (effect :consume-buff) 0)
                            (refresh-stats owner))
                          (put (owner :proc-ready) id (+ at (max 0.001 (value (get effect :cooldown 0) owner target 1))))
                          (schedule (+ at (max 0 (value (get effect :delay 0) owner target 1))) 10 :effect {:actor (owner :index) :target (if (= :self (effect :target)) (owner :index) (target :index)) :effect effect :rank 1
                                                                                                            :source id :origin origin :depth (inc depth)}))))
          (unless (first result) (note (string id ": " (result 1))))))))
  (defn apply-effect [event]
    (def owner (actors (event :actor)))
    (def target (actors (event :target)))
    (def supplied (event :effect))
    (def effect (if (supplied :upgrade-on-control)
                  (merge supplied {:control (cond
                                              (controlled? target [:root :stun :charm :fear :airborne :suppression :grounded] at) :stun
                                              (controlled? target [:slow] at) :root
                                              :slow)}) supplied))
    (def rank (get event :rank 1))
    (def depth (get event :depth 0))
    (def source (event :source))
    (def blocked (and (target :spell-immune) (not= (owner :index) (target :index))
                      (not= :attack (get event :trigger)) (not (effect :affects-structures))))
    (def parried (and (not= (owner :index) (target :index)) (> (target :parry-until) at)
                      (some |(= $ (owner :kind)) (target :parry-source-kinds))
                      (some |(= $ (effect :kind)) [:damage :control :buff :stat-buff :terrify])))
    (when (and parried (alive? target) (target-allowed? effect target)
               (not= :unresolved (get effect :condition :always)))
      (record :parried {:source source :actor (owner :id) :target (target :id) :effect-kind (effect :kind) :origin (event :origin)})
      # Only Spellblade subscribes to a parried attack. Ordinary damage/on-hit
      # counters never run, and generated proc damage cannot recursively consume.
      (when (and (= :damage (effect :kind)) (= :attack (get event :trigger)) (= depth 0))
        (trigger owner target :parried-attack (event :origin) depth)))
    (def unknown-slow (and (= :control (effect :kind)) (= :slow (effect :control)) (not (effect :strength))))
    (when blocked (record :immune {:source source :target (target :id)}))
    (when unknown-slow (note (string source ": Slow strength unresolved; movement reduction and utility contribution excluded.")))
    (when (and (alive? target) (not= :unresolved (get effect :condition :always))
               (or (not (effect :requires-caster-alive)) (and (alive? owner) (> (owner :health) 0)))
               (or (not (effect :range-at-impact))
                   (<= (math/abs (- (owner :position) (target :position)))
                       (+ 0.0000001 (value (effect :range-at-impact) owner target rank))))
               (or (not (effect :refresh-pulse))
                   (and (> (owner :health) 0) (= (event :pulse-key) (get-in owner [:pending-pulses source]))))
               (target-allowed? effect target) (not blocked) (not unknown-slow) (not parried))
      (def outcome (protect
                     (case (effect :kind)
                       :damage
                       (do
                         (def raw (max 0 (value (effect :amount) owner target rank)))
                         (def capped (if (and (= :objective (target :kind)) (effect :monster-cap))
                                       (min raw (value (effect :monster-cap) owner target rank)) raw))
                         (def type (if (= :adaptive (effect :damage-type))
                                     (if (>= (get (owner :stats) :ap 0) (/ (get (owner :stats) :bonus-ad 0) 0.6)) :magic :physical)
                                     (effect :damage-type)))
                         (def outgoing (* (if (= :true type) 1 (get (owner :stats) :outgoing-multiplier 1))
                                          (runes/damage-multiplier (get owner :damage-rules [])
                                                                   (/ (owner :health) ((owner :stats) :hp)) (/ (target :health) ((target :stats) :hp))
                                                                   type (some |(= $ :champion) (get target :tags [(target :kind)])))))
                         (def hit (damage/resolve-hit (* capped outgoing) type (owner :stats) (target :stats)))
                         (var remaining (* (hit :damage) (get target :damage-multiplier 1)))
                         (def before remaining)
                         (each shield (target :shields)
                           (when (and (> remaining 0) (> (shield :expires) at)
                                      (or (= :all (shield :type)) (= (hit :type) (shield :type))))
                             (def absorbed (min remaining (shield :amount)))
                             (-= remaining absorbed) (put shield :amount (- (shield :amount) absorbed))))
                         (def applied (min (target :health) remaining))
                         (def health-before (when (> applied 0) (health-status)))
                         (put target :health (max 0 (- (target :health) remaining)))
                         (health-changed health-before)
                         (put target :absorbed (+ (target :absorbed) (- before remaining)))
                         (put target :damage-taken (+ (target :damage-taken) applied))
                         (put owner :damage-dealt (+ (owner :damage-dealt) applied))
                         (put (owner :breakdown) source (+ (get (owner :breakdown) source 0) applied))
                         (when (= "attack" source) (put owner :attack-damage (+ (owner :attack-damage) applied)))
                         (when tracing
                           (def summary (merge hit {:at at :source source :actor (owner :id) :target (target :id)
                                                    :damage applied :absorbed (- before remaining) :health (target :health)
                                                    :origin (event :origin)}))
                           (put summary :critical (get event :critical false))
                           (array/push hits summary)
                           (record :damage summary))
                         (when (<= (target :health) 0) (schedule at 20 :death {:actor (target :index)}))
                         # Proc damage does not recursively trigger other damage procs by default.
                         (when (= depth 0)
                           (trigger owner target (get event :trigger :spell-hit) (event :origin) depth (event :ability-slot))
                           (trigger owner target :damage (event :origin) depth)
                           (trigger target owner :damage-taken (event :origin) depth))
                         (when (and (effect :heal-owner-ratio) (alive? owner) (> (owner :health) 0))
                           (apply-effect (merge event {:target (owner :index)
                                                       :effect {:kind :heal :amount (* capped outgoing (effect :heal-owner-ratio))}})))
                         (when (effect :judgment-hit)
                           (def spin (owner :judgment))
                           (put spin :landed (inc (spin :landed)))
                           (def threshold (spin :shred-hits))
                           # Grant on the sixth landed hit; refresh on the next
                           # hit and each subsequent group of six, without stacking.
                           (when (and (some |(= $ :champion) (get target :tags [(target :kind)])) (> ((target :stats) :armor) 0)
                                      (or (= threshold (spin :landed))
                                          (and (> (spin :landed) threshold) (= 1 (% (spin :landed) threshold)))))
                             (apply-effect (merge event {:effect {:kind :stat-buff :target :enemy :stat :armor
                                                                  :mode :multiply :relative true
                                                                  :amount (- (spin :shred-amount)) :duration (spin :shred-duration)}})))))
                       :judgment
                       (do
                         (def duration (value (effect :duration) owner target rank))
                         (def bonus (get-in owner [:original-stats :attack-speed-item-growth]))
                         (assert (and (util/finite? bonus) (>= bonus 0)) "Judgment requires item/level attack-speed provenance.")
                         (def per-spin (value (effect :attack-speed-per-spin) owner target rank))
                         (assert (> per-spin 0) "Invalid attack speed per spin.")
                         (def count (value (effect :spins) owner target rank))
                         (assert (and (= count (math/floor count)) (<= 1 count 100) (< 0 duration 10)) "Invalid Judgment spin schedule.")
                         (def spin @{:origin (event :origin) :source source :end (+ at duration) :landed 0
                                     :shred-hits (value (effect :shred-hits) owner target rank)
                                     :shred-amount (value (effect :shred-amount) owner target rank)
                                     :shred-duration (value (effect :shred-duration) owner target rank)})
                         (assert (and (= (spin :shred-hits) (math/floor (spin :shred-hits))) (> (spin :shred-hits) 0)
                                      (<= 0 (spin :shred-amount) 1) (> (spin :shred-duration) 0)) "Invalid Judgment armor reduction.")
                         (put owner :judgment spin)
                         (for i 1 (inc count)
                           (schedule (+ at (* duration (/ i count))) 10 :judgment-tick
                                     (merge event {:spin-index i})))
                         (schedule (spin :end) 15 :judgment-end {:actor (owner :index) :origin (event :origin)})
                         (record :buff {:actor (owner :id) :target (owner :id) :source source :buff "Judgment" :duration duration}))
                       :terrify
                       (do
                         (def recent (> (get (target :terrify-ready) (owner :id) 0) at))
                         (def raw (* (if recent 2 1) (max (value (effect :minimum) owner target rank)
                                                          (* (target :health) (value (effect :amount) owner target rank)))))
                         (apply-effect (merge event {:effect {:kind :damage :damage-type :magic :amount raw}}))
                         (unless recent
                           (apply-effect (merge event {:effect {:kind :control :control :fear :duration (effect :duration)}}))
                           (put (target :terrify-ready) (owner :id)
                                (+ at (damage/cooldown (value (effect :fear-cooldown) owner target rank)
                                                       (get-in owner [:stats :ability-haste] 0))))))
                       :drain
                       (do
                         (assert (= (event :origin) (get-in owner [:channel :origin])) "Drain channel is not active.")
                         (def duration (value (effect :duration) owner target rank))
                         (def interval (value (effect :interval) owner target rank))
                         (def count (/ duration interval))
                         (assert (and (= count (math/floor count)) (<= 1 count 100)) "Invalid drain tick schedule.")
                         (put (owner :channel) :drain true)
                         (put (owner :channel) :leash (value (effect :leash) owner target rank))
                         (put (owner :channel) :refund (value (effect :refund) owner target rank))
                         (for i 1 (inc count)
                           (schedule (+ at (* i interval)) 10 :drain-tick (merge event {:final (= i count)}))))
                       :parry
                       (do
                         (assert (= (owner :index) (target :index)) "Parry must target its caster.")
                         (def duration (value (effect :duration) owner target rank))
                         (assert (and (util/finite? duration) (< 0 duration 10)) "Invalid parry duration.")
                         (def expires (+ at duration))
                         (assert (and (indexed? (effect :source-kinds)) (not (empty? (effect :source-kinds))))
                                 "Parry requires explicitly supported incoming source kinds.")
                         (put target :parry-source-kinds (effect :source-kinds))
                         (put target :parry-until (max (target :parry-until) expires))
                         (record :parry-start {:source source :actor (owner :id) :expires expires}))
                       :heal
                       (do (when (effect :refresh-pulse) (put (owner :pending-pulses) source nil))
                         (def amount (min (- ((target :stats) :hp) (target :health))
                                          (max 0 (* (value (effect :amount) owner target rank) (get (target :stats) :healing-multiplier 1)))))
                         (def health-before (when (> amount 0) (health-status)))
                         (put target :health (+ (target :health) amount))
                         (health-changed health-before)
                         (put owner :healed (+ (owner :healed) amount)) (record :heal {:source source :amount amount :actor (owner :id)})
                         (when (> amount 0) (recover target :health)))
                       :shield
                       (do (def nearby (actors (owner :target)))
                         (def bonus (if (and (effect :nearby-bonus)
                                             (some |(= $ :champion) (get nearby :tags [(nearby :kind)]))
                                             (<= (math/abs (- (owner :position) (nearby :position))) (value (effect :nearby-radius) owner nearby rank)))
                                      (value (effect :nearby-bonus) owner nearby rank) 0))
                         (def amount (max 0 (+ bonus (value (effect :amount) owner target rank))))
                         (def expires (+ at (value (effect :duration) owner target rank)))
                         (array/push (target :shields) @{:amount amount :expires expires :type (get effect :shield-type :all)})
                         (schedule expires 0 :expire {:actor (target :index)})
                         (record :shield {:source source :amount amount :actor (owner :id)}))
                       :control
                       (unless (some |(= $ (effect :control)) (get target :immunities []))
                         (def length (* (max 0 (value (effect :duration) owner target rank))
                                        (if (some |(= $ (effect :control)) [:airborne :suppression]) 1
                                          (- 1 (max 0 (min 1 (get (target :stats) :tenacity 0)))))))
                         (put (target :controls) (effect :control) (max (get (target :controls) (effect :control) 0) (+ at length)))
                         (when (and (> length 0) (some |(= $ (effect :control))
                                                       (get-in target [:channel :interrupts] [:stun :charm :fear :airborne :suppression :silence])))
                           (interrupt-channel target))
                         (when (= :slow (effect :control))
                           (if (effect :strength)
                             (do (put (target :stat-effects) :slow {:stat :move-speed :mode :multiply
                                                                    :amount (- 1 (max 0 (min 1 (value (effect :strength) owner target rank))))
                                                                    :expires (+ at length)})
                               (refresh-stats target))
                             (note (string source ": Slow strength unresolved; movement reduction excluded."))))
                         (schedule (+ at length) 0 :expire {:actor (target :index) :control (when (> length 0) (effect :control))})
                         (record :control {:source source :control (effect :control) :duration length :target (target :id)}))
                       :buff
                       (do
                         (def expires (+ at (value (effect :duration) owner target rank)))
                         # Resolve all bonuses before changing the buff, so missing
                         # source values cannot leave a partially applied effect.
                         (def bonuses (tabseq [[stat expression] :pairs (get effect :stat-bonuses {})]
                                        stat (value expression owner target rank)))
                         (when (has-key? bonuses :attack-speed-bonus)
                           (assert (and (util/finite? (target :attack-speed-ratio)) (util/finite? (target :attack-speed-cap)))
                                   "Bonus attack speed requires the champion's attack-speed ratio and cap."))
                         (put (target :buff-counts) (effect :buff) (if (effect :refresh) (get effect :stacks 1)
                                                                     (+ (get (target :buff-counts) (effect :buff) 0) (get effect :stacks 1))))
                         (when (effect :refresh) (put (target :buffs) (effect :buff) expires))
                         (eachp [stat amount] bonuses
                           (put (target :stat-effects) (string/format "%j" (tuple :buff (effect :buff) stat))
                                {:stat stat :mode :add :amount amount :expires expires :requires-buff (effect :buff)}))
                         (refresh-stats target)
                         (schedule expires 0 :buff-expire
                                   {:actor (target :index) :buff (effect :buff) :stacks (get effect :stacks 1) :refresh (effect :refresh) :expires expires})
                         (record :buff {:source source :buff (effect :buff) :target (target :id)}))
                       :stat-buff
                       (do (def amount (value (effect :amount) owner target rank))
                         (def expires (+ at (value (effect :duration) owner target rank)))
                         (def id (string/format "%j" (tuple :stat-buff (get effect :buff source) (effect :stat))))
                         (put (target :stat-effects) id {:stat (effect :stat) :mode (get effect :mode :add)
                                                         :amount (if (effect :relative) (+ 1 amount) amount) :expires expires})
                         (refresh-stats target) (schedule expires 0 :expire {:actor (target :index)})
                         (record :stat-buff {:source source :stat (effect :stat) :amount amount :duration (- expires at) :target (target :id)}))
                       :cleanse
                       (do (def removed (some |(> (get (target :controls) $ 0) at) (effect :controls)))
                         (each control (effect :controls) (put (target :controls) control at))
                         (put (target :stat-effects) :slow nil) (refresh-stats target)
                         (when removed (resume target))
                         (record :cleanse {:source source :target (target :id)}))
                       :reset (reset-attack owner)
                       (note (string source ": Unsupported effect kind " (effect :kind))))))
      (unless (first outcome) (note (string source ": " (outcome 1))))))
  (defn cast-lock [ability actor target rank]
    (def duration (if (ability :cast-lock) (value (ability :cast-lock) actor target rank) 0))
    (assert (and (util/finite? duration) (<= 0 duration 10)) "Unsupported cast action-lock duration.")
    (max (get ability :cast-time 0.25) duration))
  (defn permitted? [actor target ability]
    (def activation (get-in actor [:strategy :activation (ability :slot)] {}))
    (and (not (and (actor :judgment) (> (get-in actor [:judgment :end]) at)
                   (some |(= $ (ability :slot)) [:e :r])))
         (>= at (get activation :after 0))
         (not (controlled? actor (get ability :disabled-controls []) at))
         (health-permitted? actor target activation)))
  (defn release-effect [event actor target ability effect travel]
    (if (or (= :unresolved (get effect :status)) (= :unresolved (get effect :condition)))
      (note (string (ability :id) ": " (get-in effect [:evidence :tooltip] "Unresolved effect")))
      (unless (and (effect :requires-shield-at-cast)
                   (not (some |(and (> ($ :expires) at) (> ($ :amount) 0)) (actor :shields))))
        (case (get effect :trigger :cast)
          :attack
          (do
            (when (has-key? effect :attack-delivery)
              (assert (and (= :release (effect :attack-delivery)) (= :damage (effect :kind))
                           (= :replace (get effect :attack-mode :replace)))
                      "Attack delivery overrides require a supported replacement damage effect."))
            (def duration (effect :duration))
            (def count (if (has-key? effect :attack-count) (effect :attack-count) 1))
            (assert (or duration (not= count :all)) "Timed attack empowerment requires a duration.")
            (unless duration (note (string (ability :id) ": Empowerment expiry unavailable; retained until its attack count is consumed.")))
            (def window (when duration (value duration actor target (event :rank))))
            (when duration (assert (and (util/finite? window) (>= window 0)) "Empowered attack duration must be nonnegative."))
            (def expires (if duration (+ at window) math/inf))
            (def remaining (if (= count :all) math/inf (value count actor target (event :rank))))
            (assert (and (> remaining 0) (or (= remaining math/inf) (= remaining (math/floor remaining))))
                    "Empowered attack count must be a positive integer.")
            # Recasting refreshes this effect; separate abilities may coexist.
            (put actor :modifiers (filter |(not (and (= ($ :source) (ability :id))
                                                     (= (get-in $ [:effect :id]) (effect :id)))) (actor :modifiers)))
            (array/push (actor :modifiers) @{:effect effect :source (ability :id) :rank (event :rank)
                                             :remaining remaining :expires expires})
            (when (effect :reset) (reset-attack actor)))
          :cast
          (do
            (def impact (+ at (* travel (get effect :travel-multiplier 1))
                           (value (get effect :delay 0) actor target (event :rank))))
            (def count (min 100 (max 1 (value (get effect :hits 1) actor target (event :rank)))))
            (def interval (value (get effect :interval 0) actor target (event :rank)))
            (when (effect :refresh-pulse) (put (actor :pending-pulses) (ability :id) impact))
            (for i 0 count
              (schedule (+ impact (* i interval)) 10 :effect
                        {:actor (actor :index) :target (if (= :self (effect :target)) (actor :index) (target :index))
                         :effect effect :rank (event :rank) :source (ability :id) :origin (event :origin) :ability-slot (ability :slot)
                         :pulse-key (when (effect :refresh-pulse) impact)})))
          (note (string (ability :id) ": Unsupported effect trigger"))))))
  (defn release [event]
    (def actor (actors (event :actor)))
    (def target (actors (event :target)))
    (when (alive? actor)
      (def ability (event :ability))
      (def distance (math/abs (- (actor :position) (target :position))))
      (def speed (get ability :missile-speed (get actor :attack-missile-speed 0)))
      (def travel (if (> speed 0) (/ distance speed) 0))
      (def hit-chance (get-in actor [:strategy :hit-chance] 1))
      (cond
        (and (get ability :interruptible-channel)
             (or (not= (event :origin) (get-in actor [:channel :origin])) (get-in actor [:channel :cancelled])))
        nil
        (and (= :attack (event :action)) (controlled? actor [:stun :charm :fear :airborne :suppression] at))
        (record :interrupted {:source "attack" :actor (actor :id)})
        (and (or (= :attack (event :action))
                 (and (not (get ability :self-cast)) (some |(and (= :enemy ($ :target)) (not= :attack (get $ :trigger))) (get ability :effects []))))
             (>= (random-at seed trial (actor :id) (event :source) (event :counter)) hit-chance))
        (record :miss {:source (event :source) :actor (actor :id)})
        (= :attack (event :action))
        (do
          (def critical (and (not (target :no-crit)) (< (random-at seed trial (actor :id) :crit (event :counter)) (get (actor :stats) :crit-chance 0))))
          (var raw (* (get (actor :stats) :ad 0) (if critical (get (actor :stats) :crit-damage 1.75) 1)))
          (when (actor :attack-ramp)
            (def ramp (actor :attack-ramp))
            (def stacks (if (> (- at (get actor :ramp-last (- math/inf))) (ramp :window)) 0 (get actor :ramp-stacks 0)))
            (*= raw (+ 1 (* stacks (ramp :step))))
            (put actor :ramp-last at) (put actor :ramp-stacks (min (ramp :maximum) (inc stacks))))
          (def modifiers (filter |(and (> ($ :expires) at) (> ($ :remaining) 0)) (actor :modifiers)))
          (def replacement (find |(and (= :damage (get-in $ [:effect :kind]))
                                       (= :replace (get-in $ [:effect :attack-mode] :replace))) modifiers))
          # The selected replacement owns delivery for the whole attack,
          # including bonus effects and on-hits. Expired/unselected modifiers
          # cannot change an ordinary projectile's travel.
          (def attack-travel (if (= :release (get-in replacement [:effect :attack-delivery])) 0 travel))
          (unless replacement
            (schedule (+ at attack-travel) 10 :effect {:actor (actor :index) :target (target :index)
                                                       :effect {:kind :damage :damage-type :physical :amount raw :condition :always}
                                                       :rank 1 :source "attack" :trigger :attack :origin (event :origin) :critical critical}))
          (each modifier modifiers
            (put modifier :remaining (dec (modifier :remaining)))
            (def effect (modifier :effect))
            (when (or (= modifier replacement) (not= :damage (effect :kind)) (= :bonus (get effect :attack-mode)))
              (schedule (+ at attack-travel) 10 :effect {:actor (actor :index)
                                                         :target (if (= :self (effect :target)) (actor :index) (target :index)) :effect effect
                                                         :rank (modifier :rank) :source (modifier :source)
                                                         :trigger :attack :origin (event :origin)
                                                         :critical (and critical (= modifier replacement))}))))
        (and (get ability :channel false) (controlled? actor [:stun :charm :fear :airborne :suppression :silence] at))
        (record :interrupted {:source (ability :id) :actor (actor :id)})
        (do
          (when (ability :blink-to-target)
            (put actor :position (event :destination))
            (record :blink {:actor (actor :id) :source (ability :id) :position (actor :position)}))
          (when (ability :finish-channel-on-release) (put actor :channel nil))
          (when (event :echo)
            (record :echo {:actor (actor :id) :source (ability :id)})
            (each effect (filter |(= :cast-start (get $ :trigger)) (ability :effects))
              (def started (protect (release-effect event actor target ability (merge effect {:trigger :cast}) 0)))
              (unless (first started) (note (string (ability :id) ": " (started 1))))))
          (each effect (filter |(not= :cast-start (get $ :trigger)) (ability :effects))
            (def released (protect (release-effect event actor target ability effect travel)))
            (unless (first released) (note (string (ability :id) ": " (released 1)))))))))
  (defn decide [actor]
    (def target (actors (actor :target)))
    (when (and (alive? actor) (alive? target))
      (def strategy (get actor :strategy {}))
      (def distance (math/abs (- (actor :position) (target :position))))
      (when (and (get-in actor [:channel :leash]) (> distance (get-in actor [:channel :leash])))
        (finish-drain actor false))
      (def range (get actor :attack-range 125))
      (var selected nil)
      (var rank 0)
      (var cost 0)
      (var cooldown 0)
      (var recovery-deadline nil)
      (var next (+ at 0.05))
      (when (and (<= (actor :busy-until) at)
                 (not (controlled? actor [:stun :charm :fear :airborne :suppression :silence] at))
                 (get strategy :abilities true))
        (each [ability learned after forecastable recast-forecastable affine recast-affine] (decision-abilities (actor :index))
          (unless selected
            (def recast (get (actor :recasts) (ability :id)))
            (def recasting (and recast (> (recast :expires) at) (> (recast :remaining) 0)))
            (when (and (if recasting (<= (recast :next) at) (<= (get (actor :ready) (ability :id) 0) at))
                       (permitted? actor target ability))
              (def result (protect
                            (def cast-time (get ability :cast-time 0.25))
                            (assert (not= :unresolved (ability :cost-resource)) "Resource cost semantics require a handler.")
                            (assert (and (util/finite? cast-time) (<= 0 cast-time 10)) "Cast timing directive requires a handler.")
                            (cast-lock ability actor target learned)
                            (def resource-cost (max 0 (value (if recasting (get-in ability [:recast :cost] 0) (ability :cost)) actor target learned)))
                            (def ability-range (max 0 (value (ability :range) actor target learned)))
                            (def cd (damage/cooldown (max 0 (value (ability :cooldown) actor target learned))
                                                     (if (ability :unhasted) 0 (get (actor :stats) :ability-haste 0))))
                            # A zero cooldown often represents a stack-gated
                            # activation, toggle or transformation. Repeatedly
                            # casting it would suppress every ordinary attack.
                            (assert (or (> cd 0) recasting (ability :max-charges))
                                    "Zero-cooldown activation requires a charge, recast or champion handler; effect excluded.")
                            (when (ability :max-charges)
                              (unless ((actor :charges) (ability :id))
                                (def maximum (value (ability :max-charges) actor target learned))
                                (assert (<= 1 maximum 10) "Invalid charge count.")
                                (put (actor :charges) (ability :id) @{:available maximum :maximum maximum :recovering false})))
                            (def charged (get (actor :charges) (ability :id)))
                            (def self-only (or (ability :self-cast) (not (some |(and (= :enemy ($ :target)) (not= :attack (get $ :trigger))) (ability :effects)))))
                            (def blocked (and (target :spell-immune) (not self-only)
                                              (not (some |($ :affects-structures) (ability :effects)))))
                            (when blocked (note (string (ability :id) ": Target is immune to this ability.")))
                            (def pool (if (= :health (get ability :cost-resource)) (actor :health) (actor :resource)))
                            (def health? (= :health (ability :cost-resource)))
                            (def required (+ resource-cost (if health? 1 0)))
                            (when (and (not blocked) (or self-only (<= distance ability-range))
                                       (or (not charged) (> (charged :available) 0)))
                              (if (>= pool required)
                                (do (set selected ability) (set rank learned) (set cost resource-cost) (set cooldown cd))
                                (when (or (if recasting recast-forecastable forecastable) (if recasting recast-affine affine))
                                  (def rate (regeneration (actor :stats) health?))
                                  (var threshold required)
                                  (when (if recasting recast-affine affine)
                                    (def forecast (protect (health-form (if recasting (get-in ability [:recast :cost] 0) (ability :cost)) actor target learned)))
                                    (def form (when (first forecast) (forecast 1)))
                                    # For a < 1, h - max(0, a*h+b) >= 1 is
                                    # monotone, with threshold max(1, (b+1)/(1-a)).
                                    (set threshold (when (and form (< (form 0) 1)) (max 1 (/ (+ 1 (form 1)) (- 1 (form 0)))))))
                                  (when (and (util/finite? rate) (> rate 0) (util/finite? threshold) (> threshold pool)
                                             (<= threshold (get (actor :stats) (if health? :hp :mp) 0)))
                                    # Round forecasts upward to nanoseconds so
                                    # roundoff cannot move a nominal boundary
                                    # just ahead of a same-time control/damage event.
                                    (def deadline (/ (math/ceil (* 1e9 (+ at (max 1e-9 (/ (- threshold pool) rate))))) 1e9))
                                    (when (util/finite? deadline)
                                      (set recovery-deadline (min (or recovery-deadline deadline) deadline)))))))))
              (unless (first result) (note (string (ability :id) ": " (result 1))))))))
      (cond
        selected
        (do
          (def cast-time (get selected :cast-time 0.25))
          (assert (and (util/finite? cast-time) (<= 0 cast-time 10)) "Unsupported cast time.")
          (def counter (get (actor :counters) (selected :id) 0))
          (put (actor :counters) (selected :id) (inc counter))
          (put actor :actions (inc (actor :actions)))
          (def resource-key (if (= :health (selected :cost-resource)) :health :resource))
          (def health-before (when (and (= resource-key :health) (> cost 0)) (health-status)))
          (put actor resource-key (- (actor resource-key) cost))
          (put actor :busy-until (+ at (cast-lock selected actor target rank)))
          (health-changed health-before)
          (def charged ((actor :charges) (selected :id)))
          (def recast ((actor :recasts) (selected :id)))
          (cond
            charged
            (do (put charged :available (dec (charged :available)))
              (def recharge (if (selected :recharge-time)
                              (damage/cooldown (value (selected :recharge-time) actor target rank)
                                               (if (selected :recharge-unhasted) 0 (get (actor :stats) :ability-haste 0)))
                              cooldown))
              (assert (> recharge 0) "Charge recharge time unavailable.")
              (unless (charged :recovering)
                (put charged :recovering true)
                (put charged :next-recharge (+ at recharge))
                (schedule (+ at recharge) 0 :charge {:actor (actor :index) :id (selected :id) :cooldown recharge}))
              (put (actor :ready) (selected :id) (+ at (max 0.05 (value (get selected :charge-delay cooldown) actor target rank)))))
            (and recast (> (recast :expires) at) (> (recast :remaining) 0))
            (do (put recast :remaining (dec (recast :remaining)))
              (put recast :next (+ at (value (get-in selected [:recast :delay] 0.1) actor target rank))))
            (do
              (put (actor :ready) (selected :id) (+ at (if (= :end (get selected :cooldown-start :start)) cast-time 0) (max 0.05 cooldown)))
              (when (selected :recast)
                (def expires (+ at (value (get-in selected [:recast :window]) actor target rank)))
                (def count (value (get-in selected [:recast :count] 1) actor target rank))
                (assert (and (= count (math/floor count)) (<= 0 count 10)) "Invalid recast count.")
                (put (actor :recasts) (selected :id) @{:remaining count
                                                       :next (+ at (value (get-in selected [:recast :delay] 0.1) actor target rank)) :expires expires}))))
          (record :cast {:actor (actor :id) :source (selected :id) :rank rank :cost cost :cooldown cooldown})
          (def origin (string (actor :id) "/" (selected :id) "/" counter))
          (when (selected :interruptible-channel)
            (put actor :channel @{:origin origin :source (selected :id) :name (selected :name) :end (actor :busy-until)
                                  :interrupts (get selected :channel-interrupts [:stun :charm :fear :airborne :suppression :silence])}))
          (unless (selected :unhasted) (trigger actor target :cast origin 0))
          (each effect (filter |(= :cast-start (get $ :trigger)) (selected :effects))
            (def started (protect (release-effect {:rank rank :origin origin} actor target selected
                                                  (merge effect {:trigger :cast}) 0)))
            (unless (first started) (note (string (selected :id) ": " (started 1)))))
          (schedule (+ at cast-time) 5 :release {:actor (actor :index) :target (target :index) :ability selected
                                                 :rank rank :action :spell :source (selected :id) :counter counter :origin origin
                                                 :destination (when (selected :blink-to-target) (target :position))})
          (when (and (actor :echo) (some |(= $ (selected :slot)) [:q :w :e]))
            (put actor :echo-count (inc (get actor :echo-count 0)))
            (when (= 0 (% (actor :echo-count) (get-in actor [:echo :every])))
              (def echo-delay (value (get-in actor [:echo :delay]) actor target 1))
              (assert (< 0 echo-delay 2) "Invalid Echo delay.")
              (schedule (+ at cast-time echo-delay) 5 :release {:actor (actor :index) :target (target :index) :ability selected
                                                                :rank rank :action :spell :source (selected :id) :counter counter :origin origin :echo true})))
          (set next (max (+ at 0.01) (actor :busy-until))))
        (and (<= (actor :busy-until) at) (<= (actor :attack-ready) at)
             (not (and (actor :judgment) (> (get-in actor [:judgment :end]) at)))
             (<= distance range) (get strategy :attacks true)
             (not (controlled? actor [:stun :charm :fear :airborne :suppression] at))
             (> (get (actor :stats) :attack-speed 0) 0))
        (do
          (def period (/ 1 ((actor :stats) :attack-speed)))
          (def windup (* period (get actor :windup-fraction 0.3)))
          (def counter (get (actor :counters) :attack 0))
          (put (actor :counters) :attack (inc counter))
          (put actor :actions (inc (actor :actions)))
          (put actor :busy-until (+ at windup)) (put actor :attack-ready (+ at period))
          (record :attack {:actor (actor :id) :source "attack"})
          (schedule (+ at windup) 5 :release {:actor (actor :index) :target (target :index) :action :attack :source "attack"
                                              :counter counter :origin (string (actor :id) "/attack/" counter)})
          (set next (max (+ at 0.01) (actor :busy-until)))))
      # Known readiness boundaries reuse ordinary decisions; resource, range,
      # control and priority checks still apply. Past deadlines keep polling
      # rather than retrying a blocked action indefinitely at the same time.
      (defn wake [deadline]
        (when (and (util/finite? deadline) (> deadline at))
          (set next (min next (max deadline (actor :busy-until))))))
      (when (and (get strategy :attacks true) (> (get (actor :stats) :attack-speed 0) 0)
                 (> (actor :attack-ready) at))
        (wake (actor :attack-ready)))
      (when (get strategy :abilities true)
        (each [ability learned after] (decision-abilities (actor :index))
          (def recast (get (actor :recasts) (ability :id)))
          (if (and recast (> (recast :expires) at) (> (recast :remaining) 0))
            (do (wake (recast :next)) (wake (recast :expires)))
            (wake (get (actor :ready) (ability :id) 0)))
          (wake (get-in actor [:charges (ability :id) :next-recharge]))
          (wake after)))
      (when recovery-deadline (wake recovery-deadline))
      (when (actor :judgment) (wake (get-in actor [:judgment :end])))
      (request-decision (actor :index) next)))
  (record :start {})
  (each actor actors (request-decision (actor :index) 0))
  (each event (get scenario :initial-events []) (schedule (event :at) (get event :priority 10) (event :kind) event))
  (while (not (empty? queue))
    (++ processed)
    (assert (<= processed limit) "Combat event limit reached.")
    (when (and cancelled (= 0 (% processed 32)) (cancelled)) (error "Cancelled."))
    (def event (pop queue))
    # An earlier expiry/cleanse wake supersedes the old queued decision. Skip
    # it before advancing time so it cannot add a second decision stream.
    (unless (and (= :decide (event :kind)) (not= (event :at) (decision-at (event :actor))))
      (advance (event :at))
      (when tracing (set before (participants)))
      (case (event :kind)
        :decide (do (put decision-at (event :actor) nil) (decide (actors (event :actor))))
        :release (release event)
        :effect (apply-effect event)
        :drain-tick
        (let [actor (actors (event :actor)) target (actors (event :target)) effect (event :effect)]
          (when (and (alive? actor) (> (actor :health) 0) (= (event :origin) (get-in actor [:channel :origin]))
                     (not (get-in actor [:channel :cancelled])))
            (if (or (not (alive? target)) (<= (target :health) 0)
                    (> (math/abs (- (actor :position) (target :position))) (get-in actor [:channel :leash])))
              (finish-drain actor (or (not (alive? target)) (<= (target :health) 0)))
              (do
                (def raw (+ (value (effect :amount) actor target (event :rank))
                            (if (event :final) (* (value (effect :finisher-ratio) actor target (event :rank))
                                                  (- ((target :stats) :hp) (target :health))) 0)))
                (apply-effect (merge event {:effect {:kind :damage :damage-type :magic :amount raw
                                                     :heal-owner-ratio (value (effect :heal-ratio) actor target (event :rank))}}))
                (when (or (event :final) (<= (target :health) 0)) (finish-drain actor))))))
        :judgment-tick
        (let [actor (actors (event :actor)) target (actors (event :target)) effect (event :effect)]
          (when (and (alive? actor) (> (actor :health) 0) (= (event :origin) (get-in actor [:judgment :origin]))
                     (<= (math/abs (- (actor :position) (target :position))) (value (effect :radius) actor target (event :rank))))
            (def outcome (protect
                           (def critical (and (not (target :no-crit))
                                              (< (random-at seed trial (actor :id) (event :origin) (event :spin-index))
                                                 (get-in actor [:stats :crit-chance] 0))))
                           (def multiplier (if critical (+ 1 (* (value (effect :crit-mod) actor target (event :rank))
                                                                (- (get-in actor [:stats :crit-damage] 2) 1))) 1))
                           (def raw (* (value (effect :amount) actor target (event :rank)) multiplier
                                       (+ 1 (value (effect :nearest-bonus) actor target (event :rank)))))
                           (apply-effect (merge event {:critical critical
                                                       :effect {:kind :damage :damage-type :physical :target-kinds [:champion :practice]
                                                                :amount raw :judgment-hit true}}))))
            (unless (first outcome) (note (string (event :source) ": " (outcome 1))))))
        :judgment-end (let [actor (actors (event :actor))]
                        (when (= (event :origin) (get-in actor [:judgment :origin]))
                          (put actor :judgment nil) (resume actor)))
        :death (let [actor (actors (event :actor))]
                 (when (and (alive? actor) (<= (actor :health) 0))
                   (put actor :dead-at at) (put actor :velocity 0)
                   (record :death {:actor (actor :id)})
                   (trigger (actors (actor :target)) actor :kill (string "death/" (actor :id)) 0)
                   (finish-drain (actors (actor :target)))))
        :buff-expire (let [actor (actors (event :actor))]
                       (when (or (not (event :refresh)) (= (event :expires) ((actor :buffs) (event :buff))))
                         (put (actor :buff-counts) (event :buff) (max 0 (- (get (actor :buff-counts) (event :buff) 0) (event :stacks))))
                         (refresh-stats actor)))
        :charge (let [actor (actors (event :actor)) charged ((actor :charges) (event :id))]
                  (put charged :available (min (charged :maximum) (inc (charged :available))))
                  (if (< (charged :available) (charged :maximum))
                    (do (put charged :next-recharge (+ at (event :cooldown)))
                      (schedule (+ at (event :cooldown)) 0 :charge event))
                    (do (put charged :recovering false) (put charged :next-recharge nil)))
                  (record :charge {:actor (actor :id) :source (event :id) :charges (charged :available)}))
        :expire (let [actor (actors (event :actor))]
                  (refresh-stats actor)
                  (when (and (event :control) (= (get (actor :controls) (event :control) 0) at)) (resume actor))
                  (record :expire {:actor (actor :id)}))
        (note (string "Unsupported event: " (event :kind))))
      (refresh-inputs)
      (steer)
      (when tracing (status-timeline/capture statuses actors at duration))))
  (advance duration)
  (when tracing (set before (participants)))
  (record :end {})
  (def player (actors 0))
  (def opponent (actors 1))
  (def attack-damage (player :attack-damage))
  {:engine version :model identity :actors actors :trace trace :statuses (if tracing (status-timeline/intervals statuses) [])
   :damage-breakdown (table/to-struct (player :breakdown))
   :events (filter |(= (player :id) ($ :actor)) hits) :unsupported unsupported
   :assumptions ["Declared ability priority precedes basic attacks."
                 "Cooldowns start on cast unless an override declares otherwise."
                 "Ordinary attacks use each actor's windup fraction; unsupported champions default to an assumed 30%."
                 "Projectile travel uses distance at release; collision geometry is omitted."
                 "Ability resource costs use the participant's configured resource pool."
                 "Parsed effects are estimates; unresolved effects are excluded and reported."
                 "Damage triggers follow the initiating damage; exact game proc ordering remains unvalidated."]
   :damage (player :damage-dealt) :dps (/ (player :damage-dealt) duration)
   :attack-dps (/ attack-damage duration) :ability-dps (/ (- (player :damage-dealt) attack-damage) duration)
   :resource-left (player :resource)
   :metrics {:damage (player :damage-dealt) :attack-damage attack-damage :resource (player :resource)
             :damage-taken (player :damage-taken) :health (player :health)
             :healing (player :healed) :absorbed (player :absorbed) :control (opponent :control-time)
             :kill-time (opponent :dead-at) :death-time (player :dead-at)}})

(defn trials [scenario samples &opt cancelled retain-damage]
  (assert (and (number? samples) (= samples (math/floor samples)) (<= 1 samples 256)) "Trial count must be from 1 to 256.")
  (def totals @{})
  (def squared @{})
  (def sources @{})
  # Comparisons may retain one scalar per trial; fitness runs keep aggregates only.
  (def damages (when retain-damage @[]))
  (var representative nil)
  (var kills 0)
  (var deaths 0)
  (var wins 0)
  (var kill-sum 0)
  (var death-sum 0)
  (def omissions @[])
  (for trial 0 samples
    (when (and cancelled (cancelled)) (error "Cancelled."))
    (def result (simulate (merge scenario {:trial trial :trace (and (get scenario :trace true) (= trial 0))}) cancelled))
    (unless representative (set representative result))
    (eachp [source damage] (result :damage-breakdown) (put sources source (+ (get sources source 0) damage)))
    (each message (result :unsupported) (unless (some |(= $ message) omissions) (array/push omissions message)))
    (def metrics (result :metrics))
    (when damages (array/push damages (metrics :damage)))
    (when (metrics :kill-time) (++ kills) (+= kill-sum (metrics :kill-time)))
    (when (metrics :death-time) (++ deaths) (+= death-sum (metrics :death-time)))
    (when (and (metrics :kill-time) (or (not (metrics :death-time)) (< (metrics :kill-time) (metrics :death-time)))) (++ wins))
    (each key [:damage :attack-damage :resource :damage-taken :health :healing :absorbed :control]
      (def value (get metrics key 0))
      (put totals key (+ (get totals key 0) value))
      (put squared key (+ (get squared key 0) (* value value)))))
  (def means (tabseq [[key total] :pairs totals] key (/ total samples)))
  (def uncertainty (tabseq [[key mean] :pairs means]
                     key (if (> samples 1)
                           (* 1.96 (math/sqrt (/ (max 0 (- (squared key) (* samples mean mean))) (* samples (dec samples))))) nil)))
  (merge representative (if damages {:trial-damage (tuple ;damages)} {})
         {:unsupported omissions :samples samples :uncertainty uncertainty
          :damage-breakdown (table/to-struct (tabseq [[source total] :pairs sources] source (/ total samples)))
          :damage (means :damage) :dps (/ (means :damage) (scenario :duration)) :resource-left (means :resource)
          :attack-dps (/ (means :attack-damage) (scenario :duration))
          :ability-dps (/ (- (means :damage) (means :attack-damage)) (scenario :duration))
          :metrics (table/to-struct (merge means {:win-rate (/ wins samples) :kill-rate (/ kills samples) :death-rate (/ deaths samples)
                                                  :mean-kill-time (when (> kills 0) (/ kill-sum kills))
                                                  :mean-death-time (when (> deaths 0) (/ death-sum deaths))}))
          :sampling-note (if (= samples 1) "One seeded trial; sampling uncertainty unavailable."
                           "Mean outcomes with approximate 95% sampling intervals; trace shows trial zero. Times average successful events only.")}))
