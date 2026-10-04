(import ./validation :as v)
(import ./stats :as stats)
(import ./skills :as skills)
(import ./core :as core)

(def required-stats [:ad :ap :hp :armor :mr :attack-speed :move-speed :ability-haste])

(defn compare-stats [champion items record &opt shard-data]
  (assert (= 1 (record :schema-version)) "unsupported observation schema")
  (assert (= (champion :patch) (record :patch)) "observation patch does not match model")
  (assert (= (champion :id) (record :champion)) "observation champion does not match model")
  (assert (and (= 11 (record :map-id))
               (some (fn [mode] (= mode (record :game-mode))) ["CLASSIC" "PRACTICETOOL"]))
          "stat model requires Summoner's Rift CLASSIC or PRACTICETOOL mode")
  (assert (= false (record :is-dead)) "capture a living player")
  (core/validate-patches champion items)
  (skills/validate-ranks (record :ranks) (record :level))
  (def shard-ids (get record :shard-ids []))
  (def shard-modifiers
    (map (fn [id]
           (def shard (get (or shard-data {}) id))
           (assert shard (string "unsupported observed stat shard: " id))
           (assert (= (champion :patch) (shard :patch)) "stat shard patch mismatch")
           (shard :stats)) shard-ids))
  (def totals (stats/apply-rank-penetration champion
                                            (stats/total-stats champion (record :level) items shard-modifiers) (record :ranks)))
  (def observed (record :observed))
  (def excluded (map (fn [stat]
                       (assert (or (keyword? stat) (string? stat)) "excluded stat must be a name")
                       (if (keyword? stat) stat (keyword stat)))
                     (get record :excluded-stats [])))
  (def fields @{})
  (each key required-stats (put fields key true))
  (eachp [key value] observed
    (assert (has-key? totals key) (string "unknown observed stat: " key))
    (put fields key true))
  (each key excluded (assert (has-key? totals key) "unknown excluded stat") (put fields key true))
  (var missing 0)
  (var mismatches 0)
  (var checked 0)
  (def rows @[])
  (each key (sort (keys fields))
    (def actual (get observed key))
    (def expected (totals key))
    (def row @{:stat key :expected expected :observed actual})
    (cond
      (some (fn [x] (= x key)) excluded) (put row :status :excluded)
      (= nil actual) (do (++ missing) (put row :status :missing))
      (do
        (v/finite-number actual "observed stat")
        (def tolerance (or (get (record :tolerances) key)
                           (get (record :tolerances) :default)))
        (assert tolerance "observation requires explicit tolerances")
        (v/nonnegative (tolerance :absolute) "absolute tolerance")
        (v/nonnegative (tolerance :relative) "relative tolerance")
        (def limit (+ (tolerance :absolute) (* (tolerance :relative) (math/abs expected))))
        (def difference (- actual expected))
        (def matches (<= (math/abs difference) limit))
        (++ checked)
        (unless matches (++ mismatches))
        (put row :difference difference)
        (put row :tolerance limit)
        (put row :status (if matches :match :mismatch))))
    (array/push rows row))
  (def context-reviewed
    (and (= true (record :context-reviewed))
         (or (tuple? (record :buffs)) (array? (record :buffs)))
         (= 0 (length (record :buffs)))
         (= "inactive" (record :role-quest-state))))
  {:status (cond (not context-reviewed) :needs-context
             (> mismatches 0) :mismatch
             (or (> missing 0) (= checked 0)) :incomplete
             :consistent)
   :scope :checked-stats-only :checked checked :missing missing :mismatches mismatches
   :context-reviewed context-reviewed :source (record :source)
   :applied-shard-ids shard-ids
   :unmapped-fields (get record :unmapped-fields []) :rows rows})
