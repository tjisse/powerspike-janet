(import ./data-util :as util)
(import ./attack-limits :as attack-limits)
(import pshash :as hash)

# Keep ordinary attack movement separate from spell cast timing and empowered
# attacks. Extend this list only after reviewing every ordinary attack variant.
(def fixtures "data/combat-fixtures/16.19.1/")
(def manifest (util/read-json (slurp (string fixtures "manifest.json"))))
(def reviewed-timing (util/read-data "data/attack-fixtures/16.19.1/reviewed-timing.jdn"))
(assert (= "16.19.1" (reviewed-timing :patch)) "Unsupported reviewed timing patch.")
(def latest-timing (util/read-data "data/attack-fixtures/latest-mage-timing.jdn"))
(assert (= 1 (latest-timing :schema)) "Unsupported latest attack timing review.")
(def timing-reviews
  (merge {"16.19.1" reviewed-timing}
         (tabseq [[patch champions] :pairs (latest-timing :patches)]
           patch (merge reviewed-timing {:patch patch :reference (latest-timing :reference)
                                         :champions (tabseq [[id receipt] :pairs champions]
                                                      id (merge (get-in reviewed-timing [:champions id]) receipt))}))))
(def retained @{})
(def retained-windups @{})
(def reviewed-forms (util/read-data "data/attack-fixtures/16.19.1/reviewed-form-projectiles.jdn"))
(assert (= "16.19.1" (reviewed-forms :patch)) "Unsupported reviewed form projectile patch.")
(def latest-forms (util/read-data "data/attack-fixtures/latest-form-projectiles.jdn"))
(assert (= 1 (latest-forms :schema)) "Unsupported latest form projectile review.")
(def form-reviews (merge {"16.19.1" reviewed-forms} (latest-forms :patches)))
(def retained-forms @{})
(def styles @{})
(defn style-from-identities [identities]
  (if (indexed? identities)
    (let [melee (some |(= $ "Melee") identities)
          ranged (some |(= $ "Ranged") identities)]
      (cond (and melee ranged) "form-dependent" melee "melee" ranged "ranged" "unknown"))
    "unknown"))
(defn attack-style [champion patch configured]
  (if (not= configured nil)
    (do (assert (some |(= configured $) ["melee" "ranged" "form-dependent" "unknown"]) "Invalid champion attack style.") configured)
    (if (= patch "16.19.1")
      (do
        (when (empty? styles)
          (def root "data/16.19.1/catalog/")
          (def manifest (util/read-json (slurp (string root "manifest.json"))))
          (each receipt (manifest "retained")
            (def path (receipt "path"))
            (when (string/has-prefix? "sources/characters/" path)
              (def bytes (slurp (string root path)))
              (assert (= (receipt "sha256") (hash/sha256 bytes)) "Attack-style source integrity check failed.")
              (def source (util/read-json bytes))
              (def file (last (string/split "/" path)))
              (def id (string/slice file 0 (- (length file) 5)))
              (put styles id (style-from-identities (get-in source ["record" "purchaseIdentities"] []))))))
        (get styles champion "unknown"))
      "unknown")))
(defn ranged? [style]
  (case style "ranged" true "melee" false nil))

# A reviewed fixed-level projection, separate from immutable snapshot metadata.
# Retain and validate it during import for the relocated executable as well.
(defn read-kayle [patch]
  (let [root (string "data/attack-fixtures/" patch "/")
        receipt (util/read-json (slurp (string root "kayle-manifest.json")))]
    (eachp [path expected] (receipt "fixture_sha256")
      (assert (= expected (hash/sha256 (slurp (string root path)))) "Kayle attack-transition source integrity check failed."))
    (def source (util/read-json (slurp (string root "Kayle-characters.json"))))
    (def record (source "Characters/Kayle/CharacterRecords/Root"))
    (def spell (get-in source ["Characters/Kayle/Spells/KaylePassiveAbility/KaylePassive" "mSpell"]))
    (def values (tabseq [value :in (spell "DataValues")]
                  (value "name")
                  (do (assert (all |(= $ (first (value "values"))) (value "values")) "Kayle transition value varies by rank.")
                    (first (value "values")))))
    (def tooltip (get-in (util/read-json (slurp (string root "Kayle-strings.json"))) ["entries" "spell_kaylepassive_tooltip"]))
    (assert (and (= patch (receipt "patch")) (= "Kayle" (record "mCharacterName"))
                 (= "form-dependent" (style-from-identities (record "purchaseIdentities")))
                 (= 175 (get-in record ["attackRangeModifiable" "baseValue"]))
                 (= 6 (values "LevelForPassiveRank1")) (= 16 (values "LevelForPassiveRank3"))
                 (= 525 (values "UpgradedAttackRange")) (= 625 (values "FinalAttackRange"))
                 (string/find "spends skill points" tooltip)
                 (string/find "@LevelForPassiveRank1@ - Arisen" tooltip)
                 (string/find "@UpgradedAttackRange@" tooltip)
                 (string/find "@LevelForPassiveRank3@ - Transcendent" tooltip)
                 (string/find "@FinalAttackRange@" tooltip))
            "Kayle source differs from the reviewed transition profile.")
    {:ranged-level (values "LevelForPassiveRank1") :final-level (values "LevelForPassiveRank3")
     :melee-range (get-in record ["attackRangeModifiable" "baseValue"])
     :ranged-range (values "UpgradedAttackRange") :final-range (values "FinalAttackRange")}))
(def kayle-profiles (tabseq [patch :in ["16.19.1" "16.20.1" "16.21.1"]] patch (read-kayle patch)))
(defn at-level [champion level ranks]
  (def kayle (get kayle-profiles (champion :patch)))
  (if (and (= "Kayle" (champion :id)) kayle)
    (do
      (assert (or (< level (kayle :ranged-level)) (= level (sum (values ranks))))
              "Assign all of Kayle's skill points to simulate her ascension at this level.")
      (merge champion
             {:attack-style (if (< level (kayle :ranged-level)) "melee" "ranged")
              :attack-range (cond (>= level (kayle :final-level)) (kayle :final-range)
                              (>= level (kayle :ranged-level)) (kayle :ranged-range)
                              (kayle :melee-range))
              :limitations [;(map |(if (= $ "Ordinary basic attacks only; champion abilities, passives and special attack rules excluded.")
                                     "Ordinary basic attacks and Divine Ascent attack type/range included; other champion abilities and passive effects excluded." $)
                                  (get champion :limitations []))
                            "Kayle's Divine Ascent attack-speed stacks, movement bonus and fire waves are not included."]}))
    champion))
(var ranges nil)
(defn attack-range [champion patch configured]
  (if (not= configured nil)
    (do (assert (and (util/finite? configured) (> configured 0)) "Invalid champion attack range.") configured)
    (when (= patch "16.19.1")
      (unless ranges
        (def path "data/16.19.1/catalog/sources/champions-ddragon.json")
        (def source-manifest (util/read-json (slurp "data/16.19.1/catalog/manifest.json")))
        (def receipt (find |(= "sources/champions-ddragon.json" (get $ "path")) (source-manifest "retained")))
        (def bytes (slurp path))
        (assert (and receipt (= (receipt "sha256") (hash/sha256 bytes))) "Attack-range source integrity check failed.")
        (def data (util/read-json bytes))
        (assert (= patch (get data "version")) "Attack-range source patch mismatch.")
        (set ranges (tabseq [[id record] :pairs (data "data")] id (get-in record ["stats" "attackrange"]))))
      (def value (get ranges champion))
      (when value (assert (and (util/finite? value) (> value 0)) "Invalid retained champion attack range."))
      value)))
(defn fixed-movement [objects paths]
  (assert (and (indexed? paths) (not (empty? paths))) "Ordinary attack paths are required.")
  (def speeds
    (map (fn [path]
           (def spell (get-in objects [path "mSpell"]))
           (def movement (get-in spell ["mMissileSpec" "movementComponent"]))
           (def speed (get movement "mSpeed"))
           (assert (and (= "FixedSpeedMovement" (get movement "__type"))
                        (util/finite? speed) (> speed 0))
                   "Ordinary attack projectile movement is missing or unsupported.")
           speed) paths))
  (assert (all |(= $ (first speeds)) speeds) "Ordinary attack variants have different projectile speeds.")
  {:kind :fixed-projectile :missile-speed (first speeds) :spell-paths paths})
(defn fixed-projectile [objects paths]
  (def movement (fixed-movement objects paths))
  (assert (all |(= (movement :missile-speed) (get-in objects [$ "mSpell" "missileSpeed"])) paths)
          "Ordinary attack legacy and movement speeds conflict.")
  movement)
(defn source-records [champion &opt patch]
  (def version (or patch "16.19.1"))
  (def review (get-in timing-reviews [version :champions champion]))
  (def name (string champion "-characters.json"))
  (def path (get review :source-path (string fixtures name)))
  (def receipt (if (review :manifest-path) (util/read-json (slurp (review :manifest-path))) manifest))
  (def bytes (slurp path))
  (def expected (get-in receipt ["fixture_sha256" name]))
  (assert (and (= version (receipt "patch")) (= expected (hash/sha256 bytes) (review :source-sha256)))
          "Ordinary attack source differs from its reviewed profile.")
  {:objects (util/read-json bytes) :source {:patch version :path path :sha256 expected}})
(defn attack-paths [champion names]
  (map |(string "Characters/" champion "/Spells/" $) names))
(defn reviewed-projectile [champion objects review &opt reference]
  (def paths (attack-paths champion [;(review :ordinary-variants) ;(review :critical-variants)]))
  (def movement (fixed-movement objects paths))
  (assert (and (= (movement :missile-speed) (review :movement-speed))
               (all |(= (review :legacy-speed) (get-in objects [$ "mSpell" "missileSpeed"])) paths))
          "Reviewed projectile conflict no longer matches the retained source.")
  (merge movement {:legacy-speed (review :legacy-speed) :reference (or reference (reviewed-timing :reference))}))
(defn windup-profile [champion patch]
  (def review (get-in timing-reviews [patch :champions champion]))
  (when (get review :windup-fraction)
    (def key [champion patch])
    (or (retained-windups key)
        (do
          (def data (source-records champion patch))
          (def root (get-in data [:objects (string "Characters/" champion "/CharacterRecords/Root")]))
          (assert (and (util/finite? (review :windup-fraction)) (< 0 (review :windup-fraction) 1))
                  "Reviewed windup fraction must be finite and between zero and one.")
          (def primary (root "basicAttack"))
          (assert (and (= (review :cast-offset) (get primary "mAttackDelayCastOffsetPercent"))
                       (not (has-key? primary "mAttackTotalTime")) (not (has-key? primary "mAttackCastTime"))
                       (not (has-key? primary "mOverrideAutoattackCastTime"))
                       (not (has-key? primary "mAttackDelayCastOffsetPercentAttackSpeedRatio"))
                       (all |(= (review :cast-offset) (get $ "mAttackDelayCastOffsetPercent")) (root "critAttacks")))
                  "Reviewed windup no longer matches the retained source.")
          (def result {:fraction (review :windup-fraction) :source (data :source) :reference (get-in timing-reviews [patch :reference])})
          (put retained-windups key result)
          result))))

(defn reviewed-form-projectile [champion objects review]
  (assert (= champion (get-in objects [(string "Characters/" champion "/CharacterRecords/Root") "mCharacterName"]))
          "Form projectile character mismatch.")
  (def paths (attack-paths champion [;(review :ordinary-variants) ;(review :critical-variants)]))
  (assert (not (some |(some (fn [path] (= path $)) paths)
                     (attack-paths champion (get review :excluded-variants []))))
          "Special attack cannot enter the ordinary form projectile profile.")
  (def movement (fixed-projectile objects paths))
  (assert (= (review :missile-speed) (movement :missile-speed)) "Reviewed form projectile speed changed.")
  movement)

(defn form-profile [champion patch form]
  (def review (get-in form-reviews [patch :forms champion form]))
  (when review
    (def key [champion patch form])
    (or (retained-forms key)
        (do
          (def bytes (slurp (review :source-path)))
          (assert (= (review :source-sha256) (hash/sha256 bytes)) "Form projectile source differs from its reviewed profile.")
          (def objects (util/read-json bytes))
          (def movement (reviewed-form-projectile champion objects review))
          (def result (merge movement {:source {:patch patch :path (review :source-path) :sha256 (review :source-sha256)} :form form}))
          (put retained-forms key result)
          result))))

(defn profile [champion patch]
  (def review (get-in timing-reviews [patch :champions champion]))
  (when review
    (def key [champion patch])
    (or (retained key)
        (do
          (def data (source-records champion patch))
          (def paths (attack-paths champion [;(review :ordinary-variants) ;(review :critical-variants)]))
          (when (= champion "Viktor")
            (def empowered (review :empowered))
            (def spell (get-in data [:objects (first (attack-paths champion [(empowered :spell)])) "mSpell"]))
            (assert (and spell (not (has-key? spell "mMissileSpec"))
                         (= (empowered :legacy-speed) (spell "missileSpeed"))
                         (= :release (empowered :delivery)))
                    "Reviewed empowered attack record changed; delivery needs review."))
          (def result (merge (if (= champion "Annie") (reviewed-projectile champion (data :objects) review (get-in timing-reviews [patch :reference]))
                               (fixed-projectile (data :objects) paths))
                             {:source (data :source)}))
          (put retained key result)
          result))))

# JPM serializes these values. Resolve bundled sources during module import so
# relocated executables never need source-tree files when loading a snapshot.
(attack-range "Ahri" "16.19.1" nil)
(attack-style "Ahri" "16.19.1" nil)
(eachp [patch review] timing-reviews
  (each champion (keys (review :champions))
    (profile champion patch)
    (windup-profile champion patch)))
(each patch (keys form-reviews)
  (form-profile "Nidalee" patch "human")
  (form-profile "Elise" patch "human")
  (form-profile "Jayce" patch "cannon"))

(defn apply-projectile [kit movement &opt windup]
  (if movement
    (merge kit {:attack-projectile movement
                :limitations [;(filter |(not (some (fn [note] (= $ note))
                                                   ["Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions."
                                                    "Attack-speed cap 2.5 and windup 30% remain estimates."
                                                    "Attack-speed cap 2.5 remains an estimate."
                                                    "Windup 30% and projectile travel zero are assumptions."
                                                    "Windup 30% remains an estimate."]))
                                       (get kit :limitations []))
                              ;(attack-limits/notes (kit :patch)
                                                    [(if windup "Attack-speed cap 2.5 remains an estimate."
                                                       "Attack-speed cap 2.5 and windup 30% remain estimates.")])]})
    (tabseq [[key value] :pairs kit :when (not= key :attack-projectile)] key value)))

(defn apply-profile [champion patch kit]
  (def movement (profile champion patch))
  (def windup (windup-profile champion patch))
  (def corrected (merge (tabseq [[key value] :pairs kit :when (not= key :attack-windup)] key value)
                        {:patch patch :attack-style (attack-style champion patch (kit :attack-style))}
                        (if-let [cap (attack-limits/cap (merge kit {:patch patch}))] {:attack-speed-cap cap} {})
                        (if windup {:attack-windup windup} {})
                        (if-let [range (attack-range champion patch (kit :attack-range))] {:attack-range range} {})))
  (def projected (apply-projectile corrected movement windup))
  (merge projected {:limitations (attack-limits/notes patch (get projected :limitations []))}))
