(import ./data-util :as util)
(import pshash :as hash)

# Keep ordinary attack movement separate from spell cast timing and empowered
# attacks. Extend this list only after reviewing every ordinary attack variant.
(def fixtures "data/combat-fixtures/16.19.1/")
(def manifest (util/read-json (slurp (string fixtures "manifest.json"))))
(def reviewed-timing (util/read-data "data/attack-fixtures/16.19.1/reviewed-timing.jdn"))
(assert (= "16.19.1" (reviewed-timing :patch)) "Unsupported reviewed timing patch.")
(def retained @{})
(def retained-windups @{})
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
(defn source-records [champion]
  (def name (string champion "-characters.json"))
  (def bytes (slurp (string fixtures name)))
  (def expected (get-in manifest ["fixture_sha256" name]))
  (assert (= expected (hash/sha256 bytes) (get-in reviewed-timing [:champions champion :source-sha256]))
          "Ordinary attack source differs from its reviewed profile.")
  {:objects (util/read-json bytes) :source {:patch "16.19.1" :path (string fixtures name) :sha256 expected}})
(defn attack-paths [champion names]
  (map |(string "Characters/" champion "/Spells/" $) names))
(defn reviewed-projectile [champion objects review]
  (def paths (attack-paths champion [;(review :ordinary-variants) ;(review :critical-variants)]))
  (def movement (fixed-movement objects paths))
  (assert (and (= (movement :missile-speed) (review :movement-speed))
               (all |(= (review :legacy-speed) (get-in objects [$ "mSpell" "missileSpeed"])) paths))
          "Reviewed projectile conflict no longer matches the retained source.")
  (merge movement {:legacy-speed (review :legacy-speed) :reference (reviewed-timing :reference)}))
(defn windup-profile [champion patch]
  (when (and (= patch (reviewed-timing :patch)) (= champion "Ahri"))
    (or (retained-windups champion)
        (do
          (def data (source-records champion))
          (def root (get-in data [:objects (string "Characters/" champion "/CharacterRecords/Root")]))
          (def review (get-in reviewed-timing [:champions champion]))
          (assert (and (util/finite? (review :windup-fraction)) (< 0 (review :windup-fraction) 1))
                  "Reviewed windup fraction must be finite and between zero and one.")
          (def primary (root "basicAttack"))
          (assert (and (= (review :cast-offset) (get primary "mAttackDelayCastOffsetPercent"))
                       (not (has-key? primary "mAttackTotalTime")) (not (has-key? primary "mAttackCastTime"))
                       (not (has-key? primary "mOverrideAutoattackCastTime"))
                       (not (has-key? primary "mAttackDelayCastOffsetPercentAttackSpeedRatio"))
                       (all |(= (review :cast-offset) (get $ "mAttackDelayCastOffsetPercent")) (root "critAttacks")))
                  "Reviewed windup no longer matches the retained source.")
          (def result {:fraction (review :windup-fraction) :source (data :source) :reference (reviewed-timing :reference)})
          (put retained-windups champion result)
          result))))

(defn profile [champion patch]
  (when (and (= patch "16.19.1") (some |(= champion $) ["Ahri" "Annie" "Viktor"]))
    (or (retained champion)
        (do
          (def data (source-records champion))
          (def review (get-in reviewed-timing [:champions champion]))
          (def paths (attack-paths champion [;(review :ordinary-variants) ;(review :critical-variants)]))
          (when (= champion "Viktor")
            (def empowered (review :empowered))
            (def spell (get-in data [:objects (first (attack-paths champion [(empowered :spell)])) "mSpell"]))
            (assert (and spell (not (has-key? spell "mMissileSpec"))
                         (= (empowered :legacy-speed) (spell "missileSpeed"))
                         (= :release (empowered :delivery)))
                    "Reviewed empowered attack record changed; delivery needs review."))
          (def result (merge (if (= champion "Annie") (reviewed-projectile champion (data :objects) review)
                               (fixed-projectile (data :objects) paths))
                             {:source (data :source)}))
          (put retained champion result)
          result))))

# JPM serializes these values. Resolve bundled sources during module import so
# relocated executables never need source-tree files when loading a snapshot.
(attack-range "Ahri" "16.19.1" nil)
(attack-style "Ahri" "16.19.1" nil)
(profile "Ahri" "16.19.1")
(profile "Annie" "16.19.1")
(profile "Viktor" "16.19.1")
(windup-profile "Ahri" "16.19.1")

(defn apply-profile [champion patch kit]
  (def movement (profile champion patch))
  (def windup (windup-profile champion patch))
  (def corrected (merge (tabseq [[key value] :pairs kit :when (not= key :attack-windup)] key value)
                        {:attack-style (attack-style champion patch (kit :attack-style))}
                        (if windup {:attack-windup windup} {})
                        (if-let [range (attack-range champion patch (kit :attack-range))] {:attack-range range} {})))
  (if movement
    (merge corrected {:attack-projectile movement
                      :limitations [;(filter |(not (some (fn [note] (= $ note))
                                                         ["Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions."
                                                          "Attack-speed cap 2.5 and windup 30% remain estimates."
                                                          "Attack-speed cap 2.5 remains an estimate."]))
                                             (get kit :limitations []))
                                    (if windup "Attack-speed cap 2.5 remains an estimate."
                                      "Attack-speed cap 2.5 and windup 30% remain estimates.")]})
    (tabseq [[key value] :pairs corrected :when (not= key :attack-projectile)] key value)))
