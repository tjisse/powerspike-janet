(import ./data-util :as util)
(import pshash :as hash)

# Resolve retained sources during import so packaged runtimes need no checkout.
(def nidalee
  (let [root "data/form-fixtures/16.19.1/"
        manifest (util/read-json (slurp (string root "manifest.json")))]
    (eachp [path expected] (manifest "fixture_sha256")
      (assert (= expected (hash/sha256 (slurp (string root path)))) "Form source integrity check failed."))
    (def human (get-in (util/read-json (slurp (string root "Nidalee-characters.json"))) ["Characters/Nidalee/CharacterRecords/Root"]))
    (def cougar (get-in (util/read-json (slurp (string root "NidaleeCougar-characters.json"))) ["Characters/NidaleeCougar/CharacterRecords/Root"]))
    (def tooltip (get-in (util/read-json (slurp (string root "strings.json"))) ["entries" "spell_aspectofthecougar_tooltip"]))
    (assert (and (= "16.19.1" (manifest "patch"))
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
(def jayce
  (let [root "data/form-fixtures/16.19.1/"
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
    (assert (and (= "16.19.1" (manifest "patch")) (= "Jayce" (record "mCharacterName"))
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
(def elise
  (let [root "data/form-fixtures/16.19.1/"
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
    (assert (and (= "16.19.1" (manifest "patch"))
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
(def profiles {"Nidalee" nidalee "Jayce" jayce "Elise" elise})
(defn choices [champion patch]
  (if (= patch "16.19.1")
    (case champion
      "Nidalee" [["human" "Human · ranged"] ["cougar" "Cougar · melee"]]
      "Jayce" [["hammer" "Hammer · melee"] ["cannon" "Cannon · ranged"]]
      "Elise" [["human" "Human · ranged"] ["spider" "Spider · melee"]] []) []))
(defn fixed? [champion patch form]
  (not (nil? (find |(= form ($ 0)) (choices champion patch)))))
(defn known-choice? [patch form]
  (some |(fixed? $ patch form) (keys profiles)))
(defn apply-form [champion form &opt level ranks]
  (if (nil? form) champion
    (do
      (assert (and (string? form) (fixed? (champion :id) (champion :patch) form))
              "Choose a supported form for this champion and patch.")
      (def selected (get-in profiles [(champion :id) form]))
      (when (= "Jayce" (champion :id))
        (assert (and (number? level) (= level (math/floor level)) (<= 1 level 18)) "Jayce's fixed form requires a valid level."))
      (def spider-rank (when (and (= "Elise" (champion :id)) (= "spider" form))
                         (assert (dictionary? ranks) "Elise's Spider form requires skill point allocation.")
                         (def additional (get ranks :r 0))
                         (assert (and (number? additional) (= additional (math/floor additional)) (<= 0 additional 3)) "Invalid Spider Form allocation.")
                         (inc additional)))
      (defn passive-amount [base ratio]
        {:op :sum :children [{:op :constant :value base}
                             {:op :multiply :children [{:op :constant :value ratio} {:op :stat :stat :ap :formula 0}]}]})
      (merge champion {:form form :form-name (selected :name) :attack-style (selected :attack-style)
                       :attack-range (selected :attack-range) :abilities []
                       :base (if (selected :move-speed) (merge (champion :base) {:move-speed (selected :move-speed)}) (champion :base))
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
                                              (get champion :limitations []))
                                     (cond (= "Elise" (champion :id))
                                       (string "Fixed " (selected :name) " form: ordinary attacks and form movement speed included"
                                               (if spider-rank "; Spider Queen damage and healing included against champions/practice targets, with the free first R rank plus allocated R points" "")
                                               ". Active abilities, Spiderlings, Rappel amplification, conditional movement bonuses and form switching are excluded; Spider Queen effects against objectives are excluded.")
                                       (= "Jayce" (champion :id))
                                       (string "Fixed " (selected :name) " form: ordinary attacks" (if (= form "hammer") " and Hammer resistances" "")
                                               " included; Jayce abilities, Hextech Capacitor, transformation attack bonuses and form switching are excluded.")
                                       (string "Fixed " (selected :name) " form: ordinary attacks only; Nidalee abilities, Hunt/Prowl and form switching are excluded."))]}))))
