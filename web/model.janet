(import ../src/powerspike/skills :as skills)
(import ../src/powerspike/observations :as observations)
(import ../data/16.19.1/snapshot :as snapshot)
(import ../data/16.19.1/annie :as annie)
(import ./catalog :as catalog)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/stats :as stats)
(import ../src/powerspike/combat :as combat)
(import ../src/powerspike/rotation :as rotation)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/damage :as damage)
(import ../src/powerspike/jobs :as jobs)
(import ../src/powerspike/scenario :as scenarios)
(import ../src/powerspike/objectives :as objectives)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(def default-state {:champion "Annie" :level 18 :armor 80 :mr 80 :duration 5 :target-health 2500
                    :selected "penetration" :slot1 "" :slot2 "" :slot3 "" :slot4 "" :slot5 "" :slot6 ""})
(def slot-keys [:slot1 :slot2 :slot3 :slot4 :slot5 :slot6])
(def enemy-slot-keys [:enemyslot1 :enemyslot2 :enemyslot3 :enemyslot4 :enemyslot5 :enemyslot6])
(def builds [{:id "penetration" :name "Penetration" :ids ["3089" "3135" "3020"]}
             {:id "ability-power" :name "More ability power" :ids ["3089" "3135" "1052"]}
             {:id "haste" :name "More haste" :ids ["3089" "3135" "3158"]}])
(def default-order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])

(defn numeric [value field-name minimum maximum &opt integer]
  (def parsed (if (string? value) (scan-number value) value))
  (assert (and (number? parsed) (> parsed (- math/inf)) (< parsed math/inf)
               (<= minimum parsed maximum) (or (not integer) (= parsed (math/floor parsed))))
          (string field-name " must be " (if integer "a whole number" "a number")
                  " from " minimum " to " maximum "."))
  parsed)

(defn flag [input name fallback]
  (def value (get input name fallback))
  (assert (some |(= value $) [true false "true" "false"]) "Invalid on/off setting.")
  (or (= value true) (= value "true")))
(defn ability-fields [input]
  (def fields @{})
  (each prefix ["" "enemy"]
    (each slot scenarios/slots
      (def base (string prefix slot))
      (when (some |(= $ slot) [:q :w :e :r])
        (put fields (keyword (string base "rank")) (numeric (get input (string base "rank") -1) "Ability rank (-1 = automatic)" -1 (if (= :r slot) 3 5) true)))
      (each [suffix minimum maximum fallback] [["after" 0 120 0] ["selfbelow" 0 1 1] ["targetbelow" 0 1 1]]
        (def name (string base suffix))
        (put fields (keyword name) (numeric (get input name fallback) "Ability activation" minimum maximum)))))
  fields)

(defn parse-state [input]
  (assert (dictionary? input) "Expected scenario fields.")
  (assert (or (nil? (get input "savedmodel")) (and (string? (get input "savedmodel")) (= 64 (length (get input "savedmodel"))))) "Invalid saved model identity.")
  (def patch (get input "patch" packages/default-version))
  (def package (packages/load patch (get input "snapshot")))
  (def selected (get input "selected" (default-state :selected)))
  (assert (or (= selected "custom") (some |(= selected ($ :id)) builds)) "Choose a supported comparison build.")
  (def champion (get input "champion" "Annie"))
  (assert ((package :champion-map) champion) "Choose a champion from this patch.")
  (def slots (tabseq [key :in [;slot-keys ;enemy-slot-keys]]
               key (do (def enemy-index (find-index |(= $ key) enemy-slot-keys))
                     (def previous (get input "opponentitems" []))
                     (def previous-list (if (string? previous) (string/split "," previous) previous))
                     (def id (get input (string key) (if (and enemy-index (indexed? previous-list)) (get previous-list enemy-index "") "")))
                     (assert (and (string? id) (or (= id "") ((package :item-map) id))) "Choose an item from this patch.") id)))
  (def mode (get input "mode" "practice"))
  (assert (some |(= $ mode) ["practice" "duel" "legacy" ;(map |(string ($ :id)) objectives/presets)]) "Choose a supported scenario preset.")
  (def opponent (get input "opponent" "Garen"))
  (assert ((package :champion-map) opponent) "Choose an opponent from this patch.")
  (defn list-field [name]
    (def raw (get input name ""))
    (assert (and (or (string? raw) (indexed? raw)) (<= (length raw) 256)) "Invalid loadout list.")
    (def values (if (string? raw) (string/split "," raw) (map string raw)))
    (filter |(not= $ "") (map string/trim values)))
  (defn plan [name]
    (def values (list-field name))
    (if (empty? values) scenarios/slots
      (map (fn [name] (def slot (find |(= name (string $)) scenarios/slots)) (assert slot "Use Q/W/E/R/D/F in the priority.") slot)
           (map string/ascii-lower values))))
  (merge slots (ability-fields input) {:patch patch :snapshot (package :snapshot) :champion champion :level (numeric (get input "level" 18) "Level" 1 18 true)
                                       :armor (numeric (get input "armor" 80) "Target armor" 0 1000)
                                       :mr (numeric (get input "mr" 80) "Target magic resistance" 0 1000)
                                       :duration (numeric (get input "duration" 5) "Combat window" 0.5 120)
                                       :target-health (numeric (get input "targethealth" (get input "target-health" (default-state :target-health))) "Target health" 1 1000000)
                                       :distance (numeric (get input "distance" 300) "Starting distance" 0 10000)
                                       :mode mode :opponent opponent :opponentlevel (numeric (get input "opponentlevel" 18) "Opponent level" 1 18 true)
                                       :opponentitems (if (has-key? input "enemyslot1") (filter |(not= "" $) (map |(slots $) enemy-slot-keys)) (list-field "opponentitems"))
                                       :runes (map |(numeric $ "Rune ID" 1 99999 true)
                                                   (if (has-key? input "runepage1") (filter |(not= "" $) (map |(string (get input (string "runepage" $) "")) (range 1 7))) (list-field "runes")))
                                       :opponentrunes (map |(numeric $ "Opponent rune ID" 1 99999 true)
                                                           (if (has-key? input "enemyrunepage1") (filter |(not= "" $) (map |(string (get input (string "enemyrunepage" $) "")) (range 1 7))) (list-field "opponentrunes")))
                                       :summoners (if (has-key? input "summoner1") (filter |(not= $ "") [(get input "summoner1" "") (get input "summoner2" "")]) (list-field "summoners"))
                                       :opponentsummoners (if (has-key? input "opponentsummoner1") (filter |(not= $ "") [(get input "opponentsummoner1" "") (get input "opponentsummoner2" "")]) (list-field "opponentsummoners"))
                                       :priority (plan "priority") :opponentpriority (plan "opponentpriority")
                                       :skillorder (when (not (empty? (list-field "skillorder"))) (map keyword (list-field "skillorder")))
                                       :opponentskillorder (when (not (empty? (list-field "opponentskillorder"))) (map keyword (list-field "opponentskillorder")))
                                       :movement (get input "movement" "approach") :opponentmovement (get input "opponentmovement" "approach")
                                       :hit-chance (numeric (get input "hitchance" (get input "hit-chance" 1)) "Hit chance" 0 1)
                                       :opponent-hit-chance (numeric (get input "opponenthitchance" (get input "opponent-hit-chance" 1)) "Opponent hit chance" 0 1)
                                       :health-fraction (numeric (get input "healthfraction" (get input "health-fraction" 1)) "Starting health fraction" 0.01 1)
                                       :resource-fraction (numeric (get input "resourcefraction" (get input "resource-fraction" 1)) "Starting resource fraction" 0 1)
                                       :opponent-health-fraction (numeric (get input "opponenthealthfraction" (get input "opponent-health-fraction" 1)) "Opponent starting health" 0.01 1)
                                       :opponent-resource-fraction (numeric (get input "opponentresourcefraction" (get input "opponent-resource-fraction" 1)) "Opponent starting resource" 0 1)
                                       :attacks (flag input "attacks" true) :abilities (flag input "abilities" true)
                                       :opponentattacks (flag input "opponentattacks" true) :opponentabilities (flag input "opponentabilities" true)
                                       :preferredrange (numeric (get input "preferredrange" 500) "Preferred distance" 0 10000)
                                       :opponentpreferredrange (numeric (get input "opponentpreferredrange" 500) "Opponent preferred distance" 0 10000)
                                       :objectivelevel (numeric (get input "objectivelevel" 10) "Objective level" 1 30 true)
                                       :gametime (numeric (get input "gametime" 20) "Game time in minutes" 0 120)
                                       :minionspresent (flag input "minionspresent" true) :retaliation (flag input "retaliation" true)
                                       :samples (numeric (get input "samples" 1) "Trials" 1 64 true) :seed (numeric (get input "seed" 1) "Seed" 0 2147483647 true)
                                       :savedmodel (get input "savedmodel")
                                       :snapshotlocked (flag input "snapshotlocked" false)
                                       :selected (if (and (= champion "Annie") ((package :manifest) "initial")) selected "custom")}))

(defn ability-settings [champion totals level ranks]
  (map (fn [ability]
         (def rank (get ranks (ability :slot) (if (= :p (ability :slot)) 1 0)))
         (def cooldown (protect (damage/cooldown (expr/evaluate (ability :cooldown)
                                                                {:rank rank :level level :stats totals :base {} :buffs {}})
                                                 (if (ability :unhasted) 0 (get totals :ability-haste 0)))))
         (merge ability {:rank rank :effective-cooldown (when (first cooldown) (cooldown 1))})) (get champion :abilities [])))
(defn estimated-combat [champion totals state ranks]
  (def result (engine/simulate
                {:duration (state :duration) :seed 1
                 :actors [{:id "player" :kind :champion :level (state :level) :stats totals
                           :base (merge (stats/base-stats champion (state :level)) {:ap 0 :crit-chance 0 :crit-damage (champion :crit-damage)})
                           :abilities (get champion :abilities []) :ranks ranks :attack-range (get champion :attack-range 125)
                           :position 0 :strategy {:priority [:q :w :e :r] :attacks true :abilities true :movement :approach}}
                          {:id "target" :kind :practice :level 1 :stats {:hp (get state :target-health (default-state :target-health))
                                                                         :armor (state :armor) :mr (state :mr)}
                           :position (get state :distance 300) :strategy {:attacks false :abilities false :movement :hold}}]}))
  (merge result {:events (map |(merge $ {:source (if (= "attack" ($ :source)) :attack ($ :source))}) (result :events))}))

(defn warnings [champion items]
  (def messages @[])
  (unless (and (= (champion :id) "Annie") (((catalog/current) :manifest) "initial"))
    (each text (champion :limitations) (array/push messages text)))
  (def seen @{})
  (def groups @{})
  (each item items
    (each text (item :limitations) (array/push messages (string (item :name) ": " text)))
    (unless (and (item :purchasable) (item :in-store) (some |(= 11 $) (item :maps)))
      (array/push messages (string (item :name) " is not a regular purchasable Summoner's Rift item.")))
    (when (and (not= "" (item :required-champion)) (not= (champion :id) (item :required-champion)))
      (array/push messages (string (item :name) " requires " (item :required-champion) ".")))
    (when (and (seen (item :id)) (not (item :stackable)))
      (array/push messages (string (item :name) ": duplicate unique item; this sandbox still sums its stats.")))
    (put seen (item :id) true)
    (each group (item :groups)
      (when (groups group) (array/push messages "Conflicting item groups; inventory legality is unvalidated."))
      (put groups group true)))
  messages)

(defn compare-legacy [state]
  (def package (packages/load (get state :patch packages/default-version) (get state :snapshot)))
  (with-dyns [:patch-package package]
    (def champion (catalog/champions (get state :champion "Annie")))
    (def is-annie (and (= "16.19.1" (package :patch)) ((package :manifest) "initial") (= "Annie" (champion :id))))
    (def ranks (cond is-annie (skills/ranks-from-order annie/skill-order (state :level))
                 (not (empty? (get champion :abilities [])))
                 (let [standard (skills/ranks-from-order default-order (state :level))]
                   (tabseq [ability :in (champion :abilities) :when (not= :p (ability :slot))]
                     (ability :slot) (min (get standard (ability :slot) 0) (ability :max-rank))))
                 {}))
    (def custom {:id "custom" :name "Custom build"
                 :ids (filter |(not= "" $) (map |(get state $ "") slot-keys))})
    (def candidates (if is-annie [;builds custom] [custom]))
    (def rows (map (fn [build]
                     (def items (map |(catalog/items $) (build :ids)))
                     # Catalog builds are a stat sandbox. Preserve all source availability flags;
                     # report restrictions instead of claiming the inventory is game-legal.
                     (def totals (stats/apply-rank-penetration champion
                                                               (stats/total-stats champion (state :level) items) ranks))
                     (def target {:armor (get state :armor 80) :mr (state :mr)})
                     (def scenario {:duration (state :duration) :windup-fraction 0.3 :distance 300
                                    :attack-travel-time 0 :travel-time 0 :include-attacks true})
                     (def outcome (if is-annie (rotation/evaluate totals target scenario annie/spells ranks)
                                    (if (empty? (get champion :abilities []))
                                      (do (def result (combat/auto-attacks totals target scenario))
                                        (merge result {:ability-dps 0 :attack-dps (result :dps)}))
                                      (estimated-combat champion totals state ranks))))
                     (merge build {:stats totals :cost (sum (map |($ :gold) items)) :combat outcome
                                   :items items :ranks ranks :ability-settings (ability-settings champion totals (state :level) ranks)
                                   :limitations [;(warnings champion items) ;(get outcome :unsupported [])
                                                 ;(mapcat |($ :unresolved) (get champion :abilities []))]})) candidates))
    {:state state :champion champion :package package
     :rows (sorted rows (fn [a b] (> ((a :combat) :damage) ((b :combat) :damage))))
     :selected (find |(= ($ :id) (if is-annie (state :selected) "custom")) rows)}))

(defn definition [state ids]
  (defn spec [opponent]
    (def prefix (if opponent "enemy" ""))
    (def ranks (tabseq [slot :in [:q :w :e :r] :let [rank (get state (keyword (string prefix slot "rank")) -1)] :when (>= rank 0)] slot rank))
    (def activation (tabseq [slot :in scenarios/slots] slot {:after (get state (keyword (string prefix slot "after")) 0)
                                                             :self-health-below (get state (keyword (string prefix slot "selfbelow")) 1)
                                                             :target-health-below (get state (keyword (string prefix slot "targetbelow")) 1)}))
    {:champion (get state (if opponent :opponent :champion) (if opponent "Garen" "Annie"))
     :level (get state (if opponent :opponentlevel :level) 18)
     :loadout {:items (if opponent (get state :opponentitems []) ids)
               :runes (get state (if opponent :opponentrunes :runes) [])
               :summoners (get state (if opponent :opponentsummoners :summoners) [])}
     :health-fraction (get state (if opponent :opponent-health-fraction :health-fraction) 1)
     :resource-fraction (get state (if opponent :opponent-resource-fraction :resource-fraction) 1)
     :skill-order (get state (if opponent :opponentskillorder :skillorder))
     :ranks (when (not (empty? ranks)) ranks)
     :strategy {:priority (get state (if opponent :opponentpriority :priority) scenarios/slots)
                :movement (keyword (get state (if opponent :opponentmovement :movement) "approach"))
                :activation activation :attacks (get state (if opponent :opponentattacks :attacks) true)
                :abilities (get state (if opponent :opponentabilities :abilities) true)
                :preferred-range (get state (if opponent :opponentpreferredrange :preferredrange) 500)
                :hit-chance (get state (if opponent :opponent-hit-chance :hit-chance) 1)}})
  {:schema 1 :patch (get state :patch packages/default-version) :snapshot (state :snapshot) :duration (state :duration) :model (get state :savedmodel)
   :seed (get state :seed 1) :samples (get state :samples 1) :player (spec false) :distance (get state :distance 300)
   :target (cond (= "duel" (state :mode)) (merge (spec true) {:kind :champion})
             (some |(= (state :mode) (string ($ :id))) objectives/presets)
             {:kind :objective :objective (keyword (state :mode)) :level (get state :objectivelevel 10)
              :game-time (* 60 (get state :gametime 20)) :minions-present (get state :minionspresent true) :retaliation (get state :retaliation true)}
             {:kind :practice :hp (get state :target-health (default-state :target-health)) :armor (state :armor) :mr (state :mr)})})
(defn compare [state]
  (if (or (= "legacy" (state :mode)) (not (state :mode))) (compare-legacy state)
    (do
      (def package (packages/load (state :patch) (state :snapshot)))
      (def champion ((package :champion-map) (state :champion)))
      (with-dyns [:patch-package package]
        (def custom {:id "custom" :name "Custom build" :ids (filter |(not= "" $) (map |(get state $ "") slot-keys))})
        (def candidates (if (and (= "Annie" (state :champion)) (get-in package [:manifest "initial"])) [;builds custom] [custom]))
        (def rows (map (fn [build]
                         (def compiled (scenarios/compile (definition state (build :ids))))
                         (def actor ((compiled :actors) 0))
                         (def result (engine/trials compiled (get state :samples 1) (dyn :simulation-cancelled)))
                         (def events (map |(merge $ {:source (if (= "attack" ($ :source)) :attack ($ :source))}) (result :events)))
                         (def combat (merge result {:events events :scenario (compiled :definition) :scenario-id (scenarios/identity compiled)}))
                         (def items (map |((package :item-map) $) (build :ids)))
                         (merge build {:stats (actor :stats) :ranks (actor :ranks) :items items :cost (sum (map |($ :gold) items))
                                       :combat combat :ability-settings (ability-settings (merge champion {:abilities (actor :abilities)})
                                                                                          (actor :stats) (actor :level) (actor :ranks))
                                       :opponent ((compiled :actors) 1)
                                       :limitations [;(compiled :coverage) ;(combat :unsupported)]})) candidates))
        {:state state :package package :champion champion :rows (sorted rows |(> (get-in $0 [:combat :metrics :damage]) (get-in $1 [:combat :metrics :damage])))
         :selected (or (find |(= ($ :id) (state :selected)) rows) (find |(= "custom" ($ :id)) rows))}))))

(def fixture-files ["annie-level1-no-items.jdn" "annie-level1-cloak.jdn"
                    "annie-level1-void-staff.jdn" "annie-level6-void-staff.jdn"
                    "annie-level6-void-staff-r1.jdn"])
(def cache @{})
(defn compare-task [state progress cancelled]
  (when (cancelled) (error "Cancelled."))
  (progress {:message "Simulating" :completed 0 :total 1})
  (def result (with-dyns [:simulation-cancelled cancelled] (compare state)))
  # Keep complete packages in the shared cache, rather than in every job result.
  (merge result {:package {:patch (get state :patch packages/default-version) :snapshot (state :snapshot)}}))
(defn compare-async [state]
  (def package (packages/load (state :patch) (state :snapshot)))
  (def champion ((package :champion-map) (state :champion)))
  (if (and (or (= "legacy" (state :mode)) (not (state :mode))) (empty? (get champion :abilities []))) (compare state)
    (do
      # State, exact package and model completely determine the result. Avoid
      # compiling and hashing full actors just to look up an existing result.
      (def key (hash/sha256 (util/encode-data (util/canonical [engine/identity (package :patch) (package :snapshot) state]))))
      (or (when (cache key) (merge (cache key) {:package package}))
          (do
            (def job (jobs/submit :simulation key compare-task state))
            (while (not (jobs/terminal? job)) (ev/sleep 0.01))
            (assert (= :done (job :status)) (or (job :error) "Simulation cancelled."))
            (def result (merge (job :result) {:package package}))
            (when (>= (length cache) 64) (each key (keys cache) (put cache key nil)))
            (put cache key (job :result)) result)))))
(defn context [state]
  {:state state :package (packages/load (state :patch) (state :snapshot))})
(defn item-input [package value]
  (def entries (if (string? value) (string/split "," value) value))
  (assert (and (indexed? entries) (<= (length entries) 2000)) "Invalid search item selection.")
  (map (fn [name]
         (def key (string/trim (string name)))
         (def item (or ((package :item-map) key) (find |(= (string/ascii-lower ($ :name)) (string/ascii-lower key)) (package :items))))
         (assert item (string "Unknown search item: " key)) (item :id))
       (filter |(not= "" (string/trim (string $))) entries)))
(defn search-options [input state]
  (def package (packages/load (state :patch) (state :snapshot)))
  (defn locks [name count]
    (seq [index :range [0 count] :when (flag input (string name (inc index)) false)] index))
  (def pool (item-input package (get input "searchpool" "")))
  (def owned (filter |(not= "" $) (map |(get state $ "") slot-keys)))
  (def options {:budget (numeric (get input "searchbudget" 10000) "Search gold budget" 0 100000 true)
                :slots (numeric (get input "searchslots" 6) "Search slots" 0 6 true)
                :seconds (numeric (get input "searchseconds" 5) "Search seconds" 0.01 30)
                :preset (keyword (get input "searchpreset" "burst")) :samples (state :samples)
                :locked (filter |(not= "" $) (map |(get state (slot-keys $) "") (locks "lockslot" 6)))
                :exclusions (item-input package (get input "searchexclude" ""))
                :next-purchase (flag input "nextpurchase" false)
                :runes (flag input "searchrunes" false) :summoners (flag input "searchsummoners" false) :skills (flag input "searchskills" false)
                :rune-locks (locks "lockrune" 6) :summoner-locks (locks "locksummoner" 2)
                :skill-locks (tabseq [index :range [0 (state :level)] :when (flag input (string "lockskill" (inc index)) false)]
                               index ((or (state :skillorder) default-order) index))})
  (if (empty? pool) options (merge options {:pool pool})))
(defn search-task [input progress cancelled]
  (def package (packages/load (get-in input [:definition :patch]) (get-in input [:definition :snapshot])))
  (search/run package (input :definition) (input :options) progress cancelled))
(defn optimize [input]
  (var state (parse-state input))
  (when (not= "custom" (state :selected))
    (def preset (find |(= ($ :id) (state :selected)) builds))
    (when preset (set state (merge state (tabseq [index :range [0 6]] (slot-keys index) (get (preset :ids) index ""))))))
  (assert (not= "legacy" (state :mode)) "Choose a combat scenario to optimize.")
  (def ids (filter |(not= "" $) (map |(get state $ "") slot-keys)))
  (def canonical ((scenarios/compile (definition state ids)) :definition))
  (def options (search-options input state))
  # A separate cancellation capability per request prevents one user's cancel
  # from stopping another user's search, even with identical scenarios.
  (def job (jobs/submit :optimization (hash/sha256 (os/cryptorand 16)) search-task
                        {:definition canonical :options options}))
  (put job :gold-budget (options :budget))
  (put job :next-purchase (options :next-purchase))
  (put job :scenario-summary (string (get-in canonical [:player :champion]) " · patch " (canonical :patch)
                                     " · " (canonical :duration) " seconds · " (get-in canonical [:target :kind] :practice)
                                     (if (= :practice (get-in canonical [:target :kind]))
                                       (string " · " (get-in canonical [:target :hp]) " target HP · " (get-in canonical [:target :armor])
                                               " armor / " (get-in canonical [:target :mr]) " MR") "")))
  (put job :limit (get-in job [:input :options :seconds] 5))
  job)
(defn state-from-definition [definition]
  (def compiled (scenarios/compile definition))
  (def input @{"patch" (compiled :patch) "snapshot" (compiled :snapshot) "selected" "custom"
               "snapshotlocked" true
               "savedmodel" (definition :model)
               "duration" (definition :duration) "distance" (get definition :distance 300)
               "samples" (min 64 (get definition :samples 1)) "seed" (get definition :seed 1)})
  (each [spec opponent] [[(definition :player) false] [(definition :target) true]]
    (when (or (not opponent) (= :champion (get spec :kind)))
      (def prefix (if opponent "opponent" ""))
      (def enemy (if opponent "enemy" ""))
      (put input (if opponent "opponent" "champion") (spec :champion))
      (put input (string prefix "level") (get spec :level 18))
      (put input (string prefix "healthfraction") (get spec :health-fraction 1))
      (put input (string prefix "resourcefraction") (get spec :resource-fraction 1))
      (for index 0 6 (put input (string enemy "slot" (inc index)) (get-in spec [:loadout :items index] "")))
      (when (spec :skill-order) (put input (string prefix "skillorder") (map string (spec :skill-order))))
      (put input (string prefix "runes") (get-in spec [:loadout :runes] []))
      (put input (string prefix "summoners") (get-in spec [:loadout :summoners] []))
      (def strategy (get spec :strategy {}))
      (each [from to fallback] [[:priority "priority" scenarios/slots] [:movement "movement" :approach] [:attacks "attacks" true]
                                [:abilities "abilities" true] [:hit-chance "hitchance" 1] [:preferred-range "preferredrange" 500]]
        (put input (string prefix to) (if (= from :movement) (string (get strategy from fallback)) (get strategy from fallback))))
      (def actor ((compiled :actors) (if opponent 1 0)))
      (each slot [:q :w :e :r] (put input (string enemy slot "rank") (get-in actor [:ranks slot] 0)))
      (each slot scenarios/slots
        (each [from to fallback] [[:after "after" 0] [:self-health-below "selfbelow" 1] [:target-health-below "targetbelow" 1]]
          (put input (string enemy slot to) (get-in strategy [:activation slot from] fallback))))))
  (def target (definition :target))
  (case (get target :kind :practice)
    :champion (put input "mode" "duel")
    :objective (do (put input "mode" (string (target :objective)))
                 (put input "objectivelevel" (get target :level 10)) (put input "gametime" (/ (get target :game-time 1200) 60))
                 (put input "minionspresent" (get target :minions-present true)) (put input "retaliation" (get target :retaliation true)))
    (do (put input "mode" "practice") (put input "targethealth" (get target :hp 10000))
      (put input "armor" (get target :armor 80)) (put input "mr" (get target :mr 80))))
  (parse-state input))
(defn evidence []
  (map (fn [file]
         (def records (parse-all (slurp (string "observations/16.19.1/" file))))
         (assert (= 1 (length records)) "Expected one measured fixture.")
         (def record (records 0))
         (def report (observations/compare-stats (snapshot/champions "Annie")
                                                 (map |(snapshot/items $) (record :item-ids)) record snapshot/stat-shards))
         {:file file :level (record :level) :r-rank ((record :ranks) :r)
          :items (record :item-ids) :status (report :status) :checked (report :checked)}) fixture-files))
