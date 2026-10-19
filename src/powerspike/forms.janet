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
(defn choices [champion patch]
  (if (and (= champion "Nidalee") (= patch "16.19.1"))
    [["human" "Human · ranged"] ["cougar" "Cougar · melee"]] []))
(defn fixed? [champion patch form]
  (not (nil? (find |(= form ($ 0)) (choices champion patch)))))
(defn apply-form [champion form]
  (if (nil? form) champion
    (do
      (assert (and (string? form) (fixed? (champion :id) (champion :patch) form))
              "Choose a supported form for this champion and patch.")
      (def selected (nidalee form))
      (merge champion {:form form :form-name (selected :name) :attack-style (selected :attack-style)
                       :attack-range (selected :attack-range) :abilities []
                       :limitations [;(filter |(not= $ "Ordinary basic attacks only; champion abilities, passives and special attack rules excluded.")
                                              (get champion :limitations []))
                                     (string "Fixed " (selected :name) " form: ordinary attacks only; Nidalee abilities, Hunt/Prowl and form switching are excluded.")]}))))
