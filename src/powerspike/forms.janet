(import ./data-util :as util)
(import ./attacks :as attacks)
(import pshash :as hash)

# Resolve retained sources during import so packaged runtimes need no checkout.
(defn read-nidalee [patch]
  (let [root (string "data/form-fixtures/" patch "/")
        manifest (util/read-json (slurp (string root "manifest.json")))]
    (eachp [path expected] (manifest "fixture_sha256")
      (assert (= expected (hash/sha256 (slurp (string root path)))) "Form source integrity check failed."))
    (def human (get-in (util/read-json (slurp (string root "Nidalee-characters.json"))) ["Characters/Nidalee/CharacterRecords/Root"]))
    (def cougar (get-in (util/read-json (slurp (string root "NidaleeCougar-characters.json"))) ["Characters/NidaleeCougar/CharacterRecords/Root"]))
    (def tooltip (get-in (util/read-json (slurp (string root "strings.json"))) ["entries" "spell_aspectofthecougar_tooltip"]))
    (assert (and (= patch (manifest "patch"))
                 (= "Nidalee" (human "mCharacterName")) (= "NidaleeCougar" (cougar "mCharacterName"))
                 (= "Nidalee" (cougar "mFallbackCharacterName"))
                 (= 525 (get-in human ["attackRangeModifiable" "baseValue"]))
                 (= 125 (get-in cougar ["attackRangeModifiable" "baseValue"]))
                 (string/find "Cougar Form</keywordMajor>, gaining melee Attacks" tooltip)
                 (string/find "Human Form</keywordMajor>, gaining ranged Attacks" tooltip))
            "Nidalee source differs from the reviewed form profile.")
    # A range/type-only projection is valid here because permanent combat stats
    # agree. A future source change needs review rather than silently inheriting.
    (defn field [record key]
      (def value (record key))
      (if (dictionary? value) (value "baseValue") value))
    (each key ["baseHPModifiable" "hpPerLevelModifiable" "baseDamageModifiable" "damagePerLevelModifiable"
               "baseArmorModifiable" "armorPerLevelModifiable" "baseMR" "mrPerLevel" "critDamageMultiplier"
               "baseMoveSpeedModifiable" "attackSpeedModifiable" "attackSpeedRatioModifiable" "attackSpeedPerLevelModifiable"]
      (assert (and (util/finite? (field human key)) (= (field human key) (field cougar key)))
              "Nidalee form stats differ; form projection needs review."))
    {"human" {:name "Human" :attack-style "ranged" :attack-range (get-in human ["attackRangeModifiable" "baseValue"])}
     "cougar" {:name "Cougar" :attack-style "melee" :attack-range (get-in cougar ["attackRangeModifiable" "baseValue"])}}))
(defn read-jayce [patch]
  (let [root (string "data/form-fixtures/" patch "/")
        manifest (util/read-json (slurp (string root "jayce-manifest.json")))]
    (eachp [path expected] (manifest "fixture_sha256")
      (assert (= expected (hash/sha256 (slurp (string root path)))) "Jayce form source integrity check failed."))
    (def source (util/read-json (slurp (string root "Jayce-characters.json"))))
    (def record (source "Characters/Jayce/CharacterRecords/Root"))
    (def spell (get-in source ["Characters/Jayce/Spells/JayceStanceHtGAbility/JayceStanceHtG" "mSpell"]))
    (def increase ((find |(= "RangedFormRangeIncrease" ($ "name")) (spell "DataValues")) "values"))
    (def parts (get-in spell ["mSpellCalculations" "Resists" "mFormulaParts"]))
    (def steps (get (first parts) "mBreakpoints"))
    (def ratio (get (get parts 1) "mCoefficient"))
    (def strings (get (util/read-json (slurp (string root "Jayce-strings.json"))) "entries"))
    (assert (and (= patch (manifest "patch")) (= "Jayce" (record "mCharacterName"))
                 (= 125 (get-in record ["attackRangeModifiable" "baseValue"]))
                 (all |(= $ 375) increase) (= 7 (length increase))
                 (= 2 (length parts)) (= "ByCharLevelBreakpointsCalculationPart" (get (first parts) "__type"))
                 (= 5 (get (first parts) "mLevel1Value")) (= [6 11 16] (tuple ;(map |($ "mLevel") steps)))
                 (all |(= 7 ($ "mAdditionalBonusAtThisLevel")) steps)
                 (= "StatByCoefficientCalculationPart" (get (get parts 1) "__type"))
                 (= 2 (get (get parts 1) "mStat")) (= 2 (get (get parts 1) "mStatFormula"))
                 (util/finite? ratio) (< (math/abs (- ratio 0.075)) 0.0000001)
                 (string/find "is ranged" (strings "game_buff_tooltip_jaycestancegun"))
                 (string/find "is melee" (strings "game_buff_tooltip_jaycestancehammer"))
                 (string/find "@spell.JayceStanceHtG:Resists@ Armor" (strings "spell_jaycestancegth_tooltip")))
            "Jayce source differs from the reviewed form profile.")
    {"hammer" {:name "Hammer" :attack-style "melee" :attack-range (get-in record ["attackRangeModifiable" "baseValue"])
               :resist-levels [1 ;(map |($ "mLevel") steps)] :resist-base (get (first parts) "mLevel1Value")
               :resist-step (get (first steps) "mAdditionalBonusAtThisLevel") :bonus-ad-ratio ratio}
     "cannon" {:name "Cannon" :attack-style "ranged" :attack-range (+ (get-in record ["attackRangeModifiable" "baseValue"]) (first increase))}}))
(defn read-elise [patch]
  (let [root (string "data/form-fixtures/" patch "/")
        manifest (util/read-json (slurp (string root "elise-manifest.json")))]
    (eachp [path expected] (manifest "fixture_sha256")
      (assert (= expected (hash/sha256 (slurp (string root path)))) "Elise form source integrity check failed."))
    (def source (util/read-json (slurp (string root "Elise-characters.json"))))
    (def human (source "Characters/Elise/CharacterRecords/Root"))
    (def spider (get-in (util/read-json (slurp (string root "EliseSpider-characters.json"))) ["Characters/EliseSpider/CharacterRecords/Root"]))
    (def spell (get-in source ["Characters/Elise/Spells/EliseRAbility/EliseR" "mSpell"]))
    (def values (tabseq [row :in (spell "DataValues")] (row "name") (row "values")))
    (def damage (get-in spell ["mSpellCalculations" "PassiveTotalDamage" "mFormulaParts"]))
    (def healing (get-in spell ["mSpellCalculations" "PassiveTotalHealing" "mFormulaParts"]))
    (def strings (get (util/read-json (slurp (string root "Elise-strings.json"))) "entries"))
    (assert (and (= patch (manifest "patch"))
                 (= "Elise" (human "mCharacterName")) (= "EliseSpider" (spider "mCharacterName"))
                 (= "Elise" (spider "mFallbackCharacterName"))
                 (= 550 (get-in human ["attackRangeModifiable" "baseValue"]))
                 (= 125 (get-in spider ["attackRangeModifiable" "baseValue"]))
                 (= 330 (get-in human ["baseMoveSpeedModifiable" "baseValue"]))
                 (= 355 (get-in spider ["baseMoveSpeedModifiable" "baseValue"]))
                 (= [14 24 34 44] (tuple ;(take 4 (drop 1 (values "PassiveBonusDamage")))))
                 (= [6 8 10 12] (tuple ;(take 4 (drop 1 (values "PassiveHealing")))))
                 (= 1 (get-in spell ["mSpellCalculations" "PassiveTotalDamage" "DamageType"]))
                 (= 2 (length damage) (length healing))
                 (= "PassiveBonusDamage" (get (first damage) "mDataValue"))
                 (= "PassiveHealing" (get (first healing) "mDataValue"))
                 (string/find "begins the game with a point in her Ultimate" (strings "spell_elisepassive_tooltip"))
                 (string/find "becoming melee" (strings "spell_eliser_tooltip"))
                 (string/find "PassiveTotalDamage" (strings "spell_elisepassive_tooltip"))
                 (string/find "PassiveTotalHealing" (strings "spell_elisepassive_tooltip")))
            "Elise source differs from the reviewed form profile.")
    (each parts [damage healing]
      (assert (and (= "NamedDataValueCalculationPart" (get (first parts) "__type"))
                   (= "StatByCoefficientCalculationPart" (get (get parts 1) "__type"))
                   (= 0 (get (get parts 1) "mStat" 0)) (= 0 (get (get parts 1) "mStatFormula" 0)))
              "Elise passive requires a reviewed AP formula."))
    (def damage-ratio (get (get damage 1) "mCoefficient"))
    (def heal-ratio (get (get healing 1) "mCoefficient"))
    (assert (and (< (math/abs (- damage-ratio 0.15)) 0.0000001) (< (math/abs (- heal-ratio 0.08)) 0.0000001))
            "Elise passive AP ratio changed.")
    (defn field [record key] (def value (record key)) (if (dictionary? value) (value "baseValue") value))
    (each key ["baseHPModifiable" "hpPerLevelModifiable" "baseStaticHPRegenModifiable" "hpRegenPerLevelModifiable"
               "baseDamageModifiable" "damagePerLevelModifiable" "baseArmorModifiable" "armorPerLevelModifiable"
               "baseMR" "mrPerLevel" "attackSpeedModifiable" "attackSpeedRatioModifiable" "attackSpeedPerLevelModifiable"]
      (assert (and (util/finite? (field human key)) (= (field human key) (field spider key))) "Elise permanent form stats changed."))
    {"human" {:name "Human" :attack-style "ranged" :attack-range (get-in human ["attackRangeModifiable" "baseValue"])
              :move-speed (get-in human ["baseMoveSpeedModifiable" "baseValue"])}
     "spider" {:name "Spider" :attack-style "melee" :attack-range (get-in spider ["attackRangeModifiable" "baseValue"])
               :move-speed (get-in spider ["baseMoveSpeedModifiable" "baseValue"])
               :damage (values "PassiveBonusDamage") :healing (values "PassiveHealing")
               :damage-ratio damage-ratio :heal-ratio heal-ratio}}))
(defn read-gnar [patch]
  (let [root (string "data/form-fixtures/" patch "/")
        manifest (util/read-json (slurp (string root "gnar-manifest.json")))]
    (eachp [path expected] (manifest "fixture_sha256")
      (assert (= expected (hash/sha256 (slurp (string root path)))) "Gnar form source integrity check failed."))
    (def source (util/read-json (slurp (string root "Gnar-characters.json"))))
    (def mini (source "Characters/Gnar/CharacterRecords/Root"))
    (def mega (get-in (util/read-json (slurp (string root "GnarBig-characters.json"))) ["Characters/GnarBig/CharacterRecords/Root"]))
    (def spell (get-in source ["Characters/Gnar/Spells/GnarPassiveAbility/GnarPassive" "mSpell"]))
    (def calculations (spell "mSpellCalculations"))
    (def values (tabseq [row :in (spell "DataValues")] (row "name") (first (row "values"))))
    (def strings (get (util/read-json (slurp (string root "Gnar-strings.json"))) "entries"))
    (def ms (first (get-in calculations ["TotalMS" "mFormulaParts"])))
    (def range (first (get-in calculations ["TotalAttackRange" "mFormulaParts"])))
    (def hp (first (get-in calculations ["TotalMegaGnarHealth" "mFormulaParts"])))
    (defn field [record key] (get-in record [key "baseValue"]))
    (assert (and (= patch (manifest "patch")) (= "Gnar" (mini "mCharacterName"))
                 (= "GnarBig" (mega "mCharacterName")) (= "Gnar" (mega "mFallbackCharacterName"))
                 (= "Fighter,melee" (get-in mega ["characterToolData" "searchTags"]))
                 (= 175 (field mini "attackRangeModifiable") (field mega "attackRangeModifiable"))
                 (= 335 (field mini "baseMoveSpeedModifiable") (field mega "baseMoveSpeedModifiable"))
                 (= 6 (field mini "attackSpeedPerLevelModifiable")) (= 0.5 (field mega "attackSpeedPerLevelModifiable"))
                 (= 400 (get-in manifest ["reviewed_semantics" "mini_range_at_level1"]))
                 (true? (get-in manifest ["reviewed_semantics" "mini_attack_speed_already_in_growth"]))
                 (true? (get-in manifest ["reviewed_semantics" "mega_passive_increases_base_stats"]))
                 (= "ByCharLevelInterpolationCalculationPart" (range "__type")) (= 0 (get range "mStartValue" 0)) (= 100 (range "mEndValue"))
                 (not (get range "mScaleByStatProgressionMultiplier" false))
                 (= "ByCharLevelBreakpointsCalculationPart" (ms "__type")) (= 0 (get ms "mLevel1Value" 0)) (= 1 (ms "mInitialBonusPerLevel"))
                 (= 1 (length (ms "mBreakpoints"))) (= 16 (get-in ms ["mBreakpoints" 0 "mLevel"]))
                 (= 2 (get-in ms ["mBreakpoints" 0 "mBonusPerLevelAtAndAfter"]))
                 (= "{ee18a47b}" (hp "__type")) (= "MegaHealthStartingValue" (hp "StartDataValue")) (= "MegaHealthEndingValue" (hp "EndDataValue"))
                 (= 100 (values "MegaHealthStartingValue")) (= 831 (values "MegaHealthEndingValue"))
                 (string/find "Mini Gnar" (strings "spell_gnarpassive_tooltip"))
                 (string/find "Base Attack Damage" (strings "game_buff_tooltip_gnarpassive")))
            "Gnar source differs from the reviewed form profile.")
    (each key ["attackSpeedModifiable" "attackSpeedRatioModifiable"]
      (assert (= 0.625 (field mini key) (field mega key)) "Gnar attack speed base/ratio changed."))
    # GnarBig's root retains rounded defenses and an older AD growth. The named
    # passive supplies base-stat additions; adding them to Mini avoids those
    # conflicts and preserves base AD for Spellblade and bonus-AD formulas.
    (def bonuses @{:hp [(values "MegaHealthStartingValue") (/ (- (values "MegaHealthEndingValue") (values "MegaHealthStartingValue")) 17)]})
    (each [key name start end] [[:ad "TotalMegaGnarAD" 6 48.5] [:armor "TotalMegaGnarArmor" 3.5 54.5] [:mr "TotalMegaGnarMR" 3.5 63]]
      (def parts (get-in calculations [name "mFormulaParts"]))
      (def part (first parts))
      (assert (and (= 1 (length parts)) (= "ByCharLevelInterpolationCalculationPart" (part "__type"))
                   (true? (part "mScaleByStatProgressionMultiplier")) (= start (part "mStartValue")) (= end (part "mEndValue")))
              "Gnar passive stat progression changed.")
      (put bonuses key [start (/ (- end start) 17)]))
    {"mini" {:name "Mini" :attack-style "ranged" :attack-range (get-in manifest ["reviewed_semantics" "mini_range_at_level1"])
             :range-growth (range "mEndValue") :move-speed (field mini "baseMoveSpeedModifiable")
             :ms-break (get-in ms ["mBreakpoints" 0 "mLevel"]) :ms-early (ms "mInitialBonusPerLevel") :ms-late (get-in ms ["mBreakpoints" 0 "mBonusPerLevelAtAndAfter"])
             :attack-speed-growth (/ (field mini "attackSpeedPerLevelModifiable") 100)}
     "mega" {:name "Mega" :attack-style "melee" :attack-range (field mega "attackRangeModifiable")
             :move-speed (field mega "baseMoveSpeedModifiable") :stat-bonuses (table/to-struct bonuses)
             :attack-speed-growth (/ (field mega "attackSpeedPerLevelModifiable") 100)}}))
(def profiles
  (tabseq [patch :in ["16.19.1" "16.20.1" "16.21.1"]]
    patch {"Nidalee" (read-nidalee patch) "Jayce" (read-jayce patch) "Elise" (read-elise patch) "Gnar" (read-gnar patch)}))
(defn choices [champion patch]
  (if (get-in profiles [patch champion])
    (case champion
      "Nidalee" [["human" "Human · ranged"] ["cougar" "Cougar · melee"]]
      "Jayce" [["hammer" "Hammer · melee"] ["cannon" "Cannon · ranged"]]
      "Elise" [["human" "Human · ranged"] ["spider" "Spider · melee"]]
      "Gnar" [["mini" "Mini · ranged"] ["mega" "Mega · melee"]] []) []))
(defn fixed? [champion patch form]
  (not (nil? (find |(= form ($ 0)) (choices champion patch)))))
(defn known-choice? [patch form]
  (some |(fixed? $ patch form) (keys (get profiles patch {}))))
(defn apply-form [champion form &opt level ranks]
  (if (nil? form) champion
    (do
      (assert (and (string? form) (fixed? (champion :id) (champion :patch) form))
              "Choose a supported form for this champion and patch.")
      (def selected (get-in profiles [(champion :patch) (champion :id) form]))
      (when (some |(= $ (champion :id)) ["Jayce" "Gnar"])
        (assert (and (number? level) (= level (math/floor level)) (<= 1 level 18)) "This fixed form requires a valid level."))
      (def base (merge (champion :base) (if (selected :move-speed) {:move-speed (selected :move-speed)} {})))
      (def growth (merge (champion :growth)))
      (eachp [key [initial per-level]] (get selected :stat-bonuses {})
        (put base key (+ (get base key 0) initial))
        (put growth key (+ (get growth key 0) per-level)))
      (when (selected :ms-break)
        (put base :move-speed (+ (base :move-speed)
                                 (* (min (dec level) (- (selected :ms-break) 2)) (selected :ms-early))
                                 (* (max 0 (- level (dec (selected :ms-break)))) (selected :ms-late)))))
      (def spider-rank (when (and (= "Elise" (champion :id)) (= "spider" form))
                         (assert (dictionary? ranks) "Elise's Spider form requires skill point allocation.")
                         (def additional (get ranks :r 0))
                         (assert (and (number? additional) (= additional (math/floor additional)) (<= 0 additional 3)) "Invalid Spider Form allocation.")
                         (inc additional)))
      (defn passive-amount [base ratio]
        {:op :sum :children [{:op :constant :value base}
                             {:op :multiply :children [{:op :constant :value ratio} {:op :stat :stat :ap :formula 0}]}]})
      (def projected (attacks/apply-projectile champion (attacks/form-profile (champion :id) (champion :patch) form) (champion :attack-windup)))
      (def reviewed-base (and (= "16.21.1" (champion :patch))
                              (= form (get {"Gnar" "mini" "Jayce" "hammer" "Elise" "human" "Nidalee" "human"} (champion :id)))))
      (def reviewed-abilities (if reviewed-base (filter |(not= :r ($ :slot)) (get champion :abilities [])) []))
      (merge projected {:form form :form-name (selected :name) :attack-style (selected :attack-style)
                        :attack-range (+ (selected :attack-range) (if (selected :range-growth) (* (selected :range-growth) (/ (dec level) 17)) 0)) :abilities reviewed-abilities
                        :base (table/to-struct base) :growth (table/to-struct growth)
                        :attack-speed-growth (get selected :attack-speed-growth (champion :attack-speed-growth))
                        :form-triggers (if spider-rank
                                         [{:id "EliseSpiderQueen" :name "Spider Queen" :icon (champion :icon) :icon-group "champion"
                                           :on [:attack] :target-kinds [:champion :practice] :kind :damage :damage-type :magic
                                           :amount (passive-amount ((selected :damage) spider-rank) (selected :damage-ratio))}
                                          {:id "EliseSpiderQueenHeal" :name "Spider Queen healing" :icon (champion :icon) :icon-group "champion"
                                           :on [:attack] :target-kinds [:champion :practice] :kind :heal :target :self
                                           :amount (passive-amount ((selected :healing) spider-rank) (selected :heal-ratio))}] [])
                        :form-resistance (when (selected :resist-levels)
                                           {:base (+ (selected :resist-base) (* (selected :resist-step) (dec (count |(<= $ level) (selected :resist-levels)))))
                                            :bonus-ad-ratio (selected :bonus-ad-ratio)})
                        :limitations [;(filter |(not= $ "Ordinary basic attacks only; champion abilities, passives and special attack rules excluded.")
                                               (get projected :limitations []))
                                      (cond reviewed-base
                                        (string "Fixed " (selected :name) " form: reviewed base-form abilities, ordinary attacks and existing form stats included. Form switching, automatic transformations and unreviewed passives remain excluded.")
                                        (= "Gnar" (champion :id))
                                        (string "Fixed " (selected :name) " form: ordinary attacks and level-scaled form stats included. Rage, automatic transformations, transformation healing, Hyper, ability casts and form switching are excluded. The selected form persists for the full simulation, including beyond Mega Gnar's usual 15-second duration.")
                                        (= "Elise" (champion :id))
                                        (string "Fixed " (selected :name) " form: ordinary attacks and form movement speed included"
                                                (if spider-rank "; Spider Queen damage and healing included against champions/practice targets, with the free first R rank plus allocated R points" "")
                                                ". Active abilities, Spiderlings, Rappel amplification, conditional movement bonuses and form switching are excluded; Spider Queen effects against objectives are excluded.")
                                        (= "Jayce" (champion :id))
                                        (string "Fixed " (selected :name) " form: ordinary attacks" (if (= form "hammer") " and Hammer resistances" "")
                                                " included; Jayce abilities, Hextech Capacitor, transformation attack bonuses and form switching are excluded.")
                                        (string "Fixed " (selected :name) " form: ordinary attacks only; Nidalee abilities, Hunt/Prowl and form switching are excluded."))]}))))
