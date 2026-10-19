(import ./data-util :as util)
(import pshash :as hash)

# Keep ordinary attack movement separate from spell cast timing and empowered
# attacks. Extend this list only after reviewing every ordinary attack variant.
(def fixtures "data/combat-fixtures/16.19.1/")
(def manifest (util/read-json (slurp (string fixtures "manifest.json"))))
(def retained @{})
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
(defn fixed-projectile [objects paths]
  (assert (and (indexed? paths) (not (empty? paths))) "Ordinary attack paths are required.")
  (def speeds
    (map (fn [path]
           (def spell (get-in objects [path "mSpell"]))
           (def movement (get-in spell ["mMissileSpec" "movementComponent"]))
           (def speed (get movement "mSpeed"))
           (assert (and (= "FixedSpeedMovement" (get movement "__type"))
                        (util/finite? speed) (> speed 0)
                        (= speed (get spell "missileSpeed")))
                   "Ordinary attack projectile movement is missing, conflicting or unsupported.")
           speed) paths))
  (assert (all |(= $ (first speeds)) speeds) "Ordinary attack variants have different projectile speeds.")
  {:kind :fixed-projectile :missile-speed (first speeds) :spell-paths paths})

(defn profile [champion patch]
  (when (and (= patch "16.19.1") (= champion "Ahri"))
    (or (retained champion)
        (do
          (def name "Ahri-characters.json")
          (def bytes (slurp (string fixtures name)))
          (def expected (get-in manifest ["fixture_sha256" name]))
          (assert (= expected (hash/sha256 bytes)) "Ordinary attack source integrity check failed.")
          (def result (merge (fixed-projectile (util/read-json bytes)
                                               ["Characters/Ahri/Spells/AhriBasicAttack"
                                                "Characters/Ahri/Spells/AhriBasicAttack2"
                                                "Characters/Ahri/Spells/AhriCritAttack"])
                             {:source {:patch patch :path (string fixtures name) :sha256 expected}}))
          (put retained champion result)
          result))))

# JPM serializes these values. Resolve bundled sources during module import so
# relocated executables never need source-tree files when loading a snapshot.
(attack-range "Ahri" "16.19.1" nil)
(profile "Ahri" "16.19.1")

(defn apply-profile [champion patch kit]
  (def movement (profile champion patch))
  (def corrected (merge kit (if-let [range (attack-range champion patch (kit :attack-range))] {:attack-range range} {})))
  (if movement
    (merge corrected {:attack-projectile movement
                      :limitations [;(filter |(not= $ "Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions.")
                                             (get kit :limitations []))
                                    ;(if (some |(= $ "Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions.")
                                               (get kit :limitations []))
                                       ["Attack-speed cap 2.5 and windup 30% remain estimates."] [])]})
    (tabseq [[key value] :pairs corrected :when (not= key :attack-projectile)] key value)))
