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
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(def default-state {:champion "Annie" :level 18 :armor 80 :mr 80 :duration 5
                    :selected "penetration" :slot1 "" :slot2 "" :slot3 "" :slot4 "" :slot5 "" :slot6 ""})
(def slot-keys [:slot1 :slot2 :slot3 :slot4 :slot5 :slot6])
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

(defn parse-state [input]
  (assert (dictionary? input) "Expected scenario fields.")
  (def patch (get input "patch" packages/default-version))
  (def package (packages/load patch (get input "snapshot")))
  (def selected (get input "selected" (default-state :selected)))
  (assert (or (= selected "custom") (some |(= selected ($ :id)) builds)) "Choose a supported comparison build.")
  (def champion (get input "champion" "Annie"))
  (assert ((package :champion-map) champion) "Choose a champion from this patch.")
  (def slots (tabseq [key :in slot-keys]
               key (do (def id (get input (string key) ""))
                     (assert (and (string? id) (or (= id "") ((package :item-map) id))) "Choose an item from this patch.") id)))
  (merge slots {:patch patch :snapshot (package :snapshot) :champion champion :level (numeric (get input "level" 18) "Level" 1 18 true)
                :armor (numeric (get input "armor" 80) "Target armor" 0 1000)
                :mr (numeric (get input "mr" 80) "Target magic resistance" 0 1000)
                :duration (numeric (get input "duration" 5) "Combat window" 0.5 30)
                :target-health (numeric (get input "targethealth" (get input "target-health" 10000)) "Target health" 1 1000000)
                :distance (numeric (get input "distance" 300) "Starting distance" 0 10000)
                :selected (if (and (= champion "Annie") ((package :manifest) "initial")) selected "custom")}))

(defn ability-settings [champion totals level ranks]
  (map (fn [ability]
         (def rank (get ranks (ability :slot) (if (= :p (ability :slot)) 1 0)))
         (def cooldown (protect (damage/cooldown (expr/evaluate (ability :cooldown)
                                                                {:rank rank :level level :stats totals :base {} :buffs {}})
                                                 (get totals :ability-haste 0))))
         (merge ability {:rank rank :effective-cooldown (when (first cooldown) (cooldown 1))})) (get champion :abilities [])))
(defn estimated-combat [champion totals state ranks]
  (def result (engine/simulate
                {:duration (state :duration) :seed 1
                 :actors [{:id "player" :kind :champion :level (state :level) :stats totals
                           :base (merge (stats/base-stats champion (state :level)) {:ap 0 :crit-chance 0 :crit-damage (champion :crit-damage)})
                           :abilities (get champion :abilities []) :ranks ranks :attack-range (get champion :attack-range 125)
                           :position 0 :strategy {:priority [:q :w :e :r] :attacks true :abilities true :movement :approach}}
                          {:id "target" :kind :practice :level 1 :stats {:hp (get state :target-health 10000)
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

(defn compare [state]
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

(def fixture-files ["annie-level1-no-items.jdn" "annie-level1-cloak.jdn"
                    "annie-level1-void-staff.jdn" "annie-level6-void-staff.jdn"
                    "annie-level6-void-staff-r1.jdn"])
(def cache @{})
(defn compare-task [state progress cancelled]
  (when (cancelled) (error "Cancelled."))
  (progress {:message "Simulating" :completed 0 :total 1})
  (def result (compare state))
  # Keep complete packages in the shared cache, rather than in every job result.
  (merge result {:package {:patch (get state :patch packages/default-version) :snapshot (state :snapshot)}}))
(defn compare-async [state]
  (def package (packages/load (state :patch) (state :snapshot)))
  (def champion ((package :champion-map) (state :champion)))
  (if (empty? (get champion :abilities [])) (compare state)
    (do
      (def key (hash/sha256 (util/encode-data [engine/identity state])))
      (or (cache key)
          (do
            (def job (jobs/submit :simulation key compare-task state))
            (while (not (jobs/terminal? job)) (ev/sleep 0.01))
            (assert (= :done (job :status)) (or (job :error) "Simulation cancelled."))
            (def result (merge (job :result) {:package package}))
            (when (>= (length cache) 64) (each key (keys cache) (put cache key nil)))
            (put cache key result) result)))))
(defn context [state]
  {:state state :package (packages/load (state :patch) (state :snapshot))})
(defn evidence []
  (map (fn [file]
         (def records (parse-all (slurp (string "observations/16.19.1/" file))))
         (assert (= 1 (length records)) "Expected one measured fixture.")
         (def record (records 0))
         (def report (observations/compare-stats (snapshot/champions "Annie")
                                                 (map |(snapshot/items $) (record :item-ids)) record snapshot/stat-shards))
         {:file file :level (record :level) :r-rank ((record :ranks) :r)
          :items (record :item-ids) :status (report :status) :checked (report :checked)}) fixture-files))
