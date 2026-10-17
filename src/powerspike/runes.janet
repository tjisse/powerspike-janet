(import ./expressions :as expr)
(import ./stats :as stats)
(import ./data-util :as util)
(import ./validation :as v)
(import pshash :as hash)

(def shard-rows [[5008 5005 5007] [5008 5010 5001] [5011 5001]])
(def shard-names {5008 "Adaptive force" 5005 "Attack speed" 5007 "Ability haste"
                  5010 "Move speed" 5011 "Health" 5001 "Scaling health"})
(def retained @{})
(def preferences @{})
(defn supported-patch? [patch]
  (some |(= $ (util/cdragon-version patch)) ["16.17" "16.18" "16.19"]))
(defn source-data [patch]
  (when (some |(= patch $) ["16.18.1" "16.19.1"])
    (or (retained patch)
        (do
          (def root (string "data/rune-fixtures/" patch "/"))
          (def manifest (util/read-json (slurp (string root "manifest.json"))))
          (eachp [name expected] (manifest "sha256")
            (assert (= expected (hash/sha256 (slurp (string root name)))) "Rune source corruption."))
          (def data {:records (util/read-json (slurp (string root "records.json")))
                     :styles (util/read-json (slurp (string root "styles.json"))) :sources (manifest "sources")})
          (put retained patch data) data))))
# JPM serializes module values into the executable. Read bundled records during
# import so relocated binaries never need these source-tree paths at runtime.
(each patch ["16.18.1" "16.19.1"] (source-data patch))
(def initial-root-records
  (tabseq [id :in ["Annie" "Garen"]]
    id (util/read-json (slurp (string "data/16.19.1/sources/" (string/ascii-lower id) "-character-record.json")))))
(defn spell [rune patch]
  (def script (get-in rune [:record "mScript" "mSpellScriptData"] {}))
  {"__powerspike_patch" patch
   "mDataValues" (seq [[name value] :pairs (get script "mEffectAmount" {})] {"mName" name "mValue" value})
   "mSpellCalculations" (get script "mCalculations" {})})
(defn shard-records [objects patch]
  (seq [raw :in (values objects) :when (and (dictionary? raw) (shard-names (get raw "mPerkId")))]
    {:id (raw "mPerkId") :name (shard-names (raw "mPerkId")) :patch patch :record raw}))
(defn shards [package]
  (if (has-key? package :shards) (package :shards)
    (if-let [data (source-data (package :patch))] (shard-records (data :records) (package :patch)) [])))
(defn term [record name level]
  (expr/evaluate (expr/variable name (spell record (record :patch))) {:rank 1 :level level}))
(defn adaptive-kind [package champion totals preference]
  (assert (some |(= preference $) [:auto :ad :ap]) "Choose automatic, AD or AP adaptive force.")
  (cond
    (not= preference :auto) preference
    (> (totals :ap) (/ (totals :bonus-ad) 0.6)) :ap
    (< (totals :ap) (/ (totals :bonus-ad) 0.6)) :ad
    (do
      (def key [(package :patch) (package :snapshot) (champion :id)])
      (def known (or (get champion :adaptive-stat) (preferences key)))
      (or known
          (do
            (def path (string (get package :directory "") "/sources/characters/" (champion :id) ".json"))
            (def initial (and (= "16.19.1" (package :patch)) (some |(= $ (champion :id)) ["Annie" "Garen"])))
            (def object (cond
                          (os/stat path)
                          (do (def bytes (slurp path))
                            (def source (find |(= (get $ "path") (string "sources/characters/" (champion :id) ".json"))
                                              (get-in package [:manifest "sources"] [])))
                            (assert (and source (= (source "sha256") (hash/sha256 bytes))) "Champion adaptive source integrity check failed.")
                            (get (util/read-json bytes) (champion :root)))
                          initial (initial-root-records (champion :id))))
            (assert object "Champion adaptive preference unavailable; select AD or AP explicitly.")
            (def choice (if (> (get object "mAdaptiveForceToAbilityPowerWeight" 0) 0) :ap :ad))
            (when (>= (length preferences) 512) (each key (keys preferences) (put preferences key nil)))
            (put preferences key choice) choice)))))
(defn shard-modifiers [package champion items selected preference level]
  (assert (and (indexed? selected) (or (empty? selected) (= 3 (length selected)))) "Choose three shard slots (zero means None).")
  (assert (some |(= preference $) [:auto :ad :ap]) "Choose automatic, AD or AP adaptive force.")
  (def available (shards package))
  (def adaptive (when (some |(= $ 5008) selected) (adaptive-kind package champion (stats/total-stats champion level items) preference)))
  (seq [[index id] :pairs selected :when (not= id 0)]
    (v/integer-between id 1 99999 "Shard ID")
    (assert (some |(= $ id) (shard-rows index)) "Shard unavailable in this slot.")
    (def record (find |(= id ($ :id)) available))
    (assert record "Shard source unavailable on this patch; refresh patch data.")
    (case id
      5008 {adaptive (term record (if (= adaptive :ap) "StatGain2" "StatGain1") level)}
      5005 {:attack-speed-bonus (/ (term record "StatGain" level) 100)}
      5007 {:ability-haste (term record "HasteGain" level)}
      5010 {:move-speed-percent (/ (term record "StatGain1" level) 100)}
      5011 {:hp (term record "StatGain" level)}
      5001 {:hp (+ (term record "StatGainMin" level) (* (/ (dec level) 17) (- (term record "StatGainMax" level) (term record "StatGainMin" level))))})))
(defn stat-modifiers [chosen patch level]
  (seq [rune :in chosen :when (= 8210 (rune "id"))]
    (def record (merge rune {:patch patch}))
    {:ability-haste (+ (if (>= level (term record "LevelToTurnOn" level)) (* 100 (term record "HasteBonus1" level)) 0)
                       (if (>= level (term record "LevelToTurnOn2" level)) (* 100 (term record "HasteBonus2" level)) 0))}))
(defn damage-rules [chosen patch]
  (seq [rune :in chosen :when (some |(= $ (rune "id")) [8014 8017 8299])]
    (def record (merge rune {:patch patch}))
    (defn amount [name] (term record name 1))
    (case (rune "id")
      8014 {:kind :target-below :threshold (amount "EnemyHealthPercentageThreshold") :bonus (amount "BonusPercentDamage")}
      8017 {:kind :target-above :threshold (amount "EnemyHealthPercentageThreshold") :bonus (amount "BonusPercentDamage")}
      8299 {:kind :self-below :threshold (amount "HealthThresholdStart") :maximum-at (amount "HealthThresholdEnd")
            :bonus (amount "MinBonusDamagePercent") :maximum (amount "MaxBonusDamagePercent")})))
(defn damage-multiplier [rules self-health target-health type champion-target]
  (if (or (empty? rules) (= :true type) (not champion-target)) 1
    (product (map (fn [rule]
                    (+ 1 (case (rule :kind)
                           :target-below (if (< target-health (- (rule :threshold) 0.0000001)) (rule :bonus) 0)
                           :target-above (if (> target-health (+ (rule :threshold) 0.0000001)) (rule :bonus) 0)
                           :self-below (if (< self-health (- (rule :threshold) 0.0000001))
                                         (+ (rule :bonus) (* (min 1 (/ (- (rule :threshold) self-health) (- (rule :threshold) (rule :maximum-at))))
                                                             (- (rule :maximum) (rule :bonus)))) 0)
                           0))) rules))))
(defn coverage [rune]
  (case (rune "id")
    8210 ["Transcendence: level-gated haste modeled; takedown cooldown refunds are excluded."]
    (if (some |(= $ (rune "id")) [8112 8237 8014 8017 8299])
      [(string (rune "name") ": patch-derived estimate; unvalidated in-game.")]
      [(string (rune "name") ": trigger handler unavailable.")])))
(defn compile [chosen patch level]
  (def modifiers @[])
  (def rules @[])
  (def notes @[])
  (each rune chosen
    (def result (protect
                  (when (some |(= $ (rune "id")) [8210 8237 8014 8017 8299])
                    (assert (supported-patch? patch) "Rune semantics require a handler for this patch.")
                    (assert (not (empty? (get-in rune [:record "mScript" "mSpellScriptData"] {}))) "Rune source record unavailable."))
                  (def stats (stat-modifiers [rune] patch level))
                  (def damage (damage-rules [rune] patch))
                  (array/concat modifiers stats) (array/concat rules damage)))
    (array/concat notes (if (first result) (coverage rune)
                          [(string (rune "name") ": source formula unresolved; effect excluded. " (result 1))])))
  {:stats modifiers :rules rules :coverage notes})
