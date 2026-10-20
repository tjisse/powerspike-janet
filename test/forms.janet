(import ../src/powerspike/forms :as forms)
(import ../src/powerspike/attacks :as attacks)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/data-util :as util)
(import ../web/catalog :as catalog)
(import ../web/model :as model)
(import ../web/details :as details)
(import ../web/matchup :as matchup)
(import ../web/ui :as ui)
(import pshash :as hash)

(defn close [expected actual] (assert (< (math/abs (- expected actual)) 0.0001)))
(def original (util/read-data "data/16.19.1/catalog/catalog.jdn"))
# An old cached catalog and real item calculation, independent of new metadata.
(def champions (map |(tabseq [[key value] :pairs $ :when (not= key :attack-style)] key value) (original :champions)))
(def records (util/read-json (slurp "data/combat-fixtures/16.19.1/items.json")))
(def dd (get-in (util/read-json (slurp "data/combat-fixtures/16.19.1/items-ddragon.json")) ["data" "3153"]))
(def item (merge (normalize/item-effects (normalize/item "16.19.1" "3153" dd) records {})
                 {:tooltip "Attacks deal {{ Item_Melee_Ranged_Split_Dynamic }} of current Health as bonus damage."}))
(def sheen (normalize/item-effects (normalize/item "16.19.1" "3057" (get-in (util/read-json (slurp "data/combat-fixtures/16.19.1/items-ddragon.json")) ["data" "3057"])) records {}))
(def root (string "build/form-tests/" (hash/sha256 (os/cryptorand 8))))
(def bytes (util/encode-data {:schema 1 :patch "16.19.1" :champions champions :items [item sheen]}))
(def snapshot (hash/sha256 bytes))
(def directory (string root "/patches/16.19.1/" snapshot))
(util/write (string directory "/package.jdn") bytes)
(util/write (string directory "/manifest.json") (util/encode-json {"initial" false "package_sha256" snapshot}))
(util/write (string root "/patches/16.19.1/current") snapshot)
(def package (catalog/initialize root nil))
(def order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(defn spec [form level &opt champion]
  {:champion (or champion "Nidalee") :level level :form form :skill-order order :loadout {:items ["3153"]}
   :strategy {:attacks true :abilities true :movement :hold}})
(defn definition [form level &opt champion]
  {:schema 1 :patch "16.19.1" :snapshot snapshot :duration 0.7 :distance 0 :seed 1
   :player (spec form level champion) :target {:kind :practice :hp 1000 :armor 0 :mr 0}})
(each [champion form ranged range rate] [["Nidalee" "human" true 525 0.06] ["Nidalee" "cougar" false 125 0.09]
                                         ["Jayce" "hammer" false 125 0.09] ["Jayce" "cannon" true 500 0.06]
                                         ["Elise" "human" true 550 0.06] ["Elise" "spider" false 125 0.09]
                                         ["Gnar" "mini" true 400 0.06] ["Gnar" "mega" false 175 0.09]]
  (each level (if (= champion "Jayce") [1 5 6 10 11 15 16 18] [1 6 18])
    (def range (if (and (= champion "Gnar") (= form "mini")) (+ range (* 100 (/ (dec level) 17))) range))
    (def definition (definition form level champion))
    (def compiled (scenario/compile definition))
    (def actor (get-in compiled [:actors 0]))
    (assert (= form (actor :form)))
    (assert (= ranged (actor :ranged)))
    (each path [[:attack-range] [:stats :attack-range] [:base :attack-range]] (close range (get-in actor path)))
    (assert (empty? (actor :abilities)))
    (assert (not (some |(string/find "effects requiring an attack type are excluded" $) (compiled :coverage))))
    (assert (some |(string/find "form switching are excluded" $) (compiled :coverage)))
    (def target (get-in compiled [:actors 1]))
    (def context (engine/context (engine/state actor 0) (engine/state target 1) 1))
    (assert (some |(= (if ranged "6%" "9%") ($ :text)) (mapcat identity ((details/item item context) :body-rich))))
    (each side [0 1]
      (def attacker (merge actor {:stats (merge (actor :stats) {:ad 100 :attack-speed 1 :crit-chance 0})}))
      (def outcome (engine/simulate (merge compiled {:actors (if (= side 0) [attacker target] [target attacker])})))
      (def proc (find |(= "item/3153/mist" ($ :source)) (outcome :trace)))
      (close (* 900 rate) (proc :damage)))
    (assert (some |(= "attack" ($ :source)) ((scenario/simulate (merge definition {:distance range :duration 1})) :events)))
    (assert (empty? ((scenario/simulate (merge definition {:distance (+ range 0.01)})) :events)))
    (assert (= ((scenario/simulate definition) :metrics) ((scenario/fitness definition) :metrics)))))

# These projectiles belong only to the explicit reviewed form. All
# ordinary/critical variants agree; both source receipts and the cached package
# stay pinned while form selection supplies current timing semantics.
(each [champion ranged-form melee speed variants] [["Nidalee" "human" "cougar" 2500 3] ["Elise" "human" "spider" 1600 4]
                                                   ["Jayce" "cannon" "hammer" 2000 3]]
  (def profile (attacks/form-profile champion "16.19.1" ranged-form))
  (close speed (profile :missile-speed))
  (assert (= variants (length (profile :spell-paths))))
  (assert (= (get-in profile [:source :sha256]) (hash/sha256 (slurp (get-in profile [:source :path])))))
  (each [patch form] [["16.18.1" ranged-form] ["16.20.1" ranged-form] ["16.19.1" melee] ["16.19.1" nil]]
    (assert (nil? (attacks/form-profile champion patch form))))
  (def definition (merge (definition ranged-form 1 champion) {:distance 300 :duration 2
                                                              :player (merge (spec ranged-form 1 champion) {:loadout {:items []}})}))
  (def compiled (scenario/compile definition))
  (def actor (get-in compiled [:actors 0]))
  (def target (get-in compiled [:actors 1]))
  (close speed (actor :attack-missile-speed))
  (assert (not (some |(or (string/find "projectile travel is assumed zero" $) (string/find "projectile travel zero" $)) (actor :coverage))))
  (assert (= ((scenario/simulate definition) :metrics) ((scenario/fitness definition) :metrics)))
  (def reversed (merge definition {:player (merge (definition :player) {:strategy {:attacks false :abilities false :movement :hold}})
                                   :target (merge (definition :player) {:kind :champion})}))
  (close speed (get-in (scenario/compile reversed) [:actors 1 :attack-missile-speed]))
  (assert (= ((scenario/simulate reversed) :metrics) ((scenario/fitness reversed) :metrics)))
  (each as [0.5 1 2]
    (each crit [0 1]
      (each side [0 1]
        (def attacker (merge actor {:stats (merge (actor :stats) {:attack-speed as :ad 100 :crit-chance crit})}))
        (def actors (if (= side 0) [attacker target] [target attacker]))
        (def impact (+ (/ 0.3 as) (/ 300 speed)))
        (defn run [duration] (engine/simulate {:duration duration :actors actors}))
        (assert (empty? (filter |(= :damage ($ :kind)) ((run impact) :trace))))
        (def duration (+ impact (/ 1 as) 0.101))
        (def outcome (run duration))
        (def hits (filter |(and (= :damage ($ :kind)) (= "attack" ($ :source))) (outcome :trace)))
        (assert (= 2 (length hits)))
        (close impact ((hits 0) :at))
        # Decisions retain the existing 50ms polling policy. Travel must not
        # alter attack starts, even when a ready time falls between polls.
        (def instant (engine/simulate {:duration duration :actors (map |(merge $ {:attack-missile-speed 0}) actors)}))
        (def starts (map |($ :at) (filter |(= :attack ($ :kind)) (outcome :trace))))
        (assert (= (tuple ;starts) (tuple ;(map |($ :at) (filter |(= :attack ($ :kind)) (instant :trace))))))
        (close (+ (starts 1) impact) ((hits 1) :at))
        (close (if (= crit 1) (* 100 (get-in actor [:stats :crit-damage])) 100) ((hits 0) :damage)))))
  # Form changes must clear an already projected ranged projectile. A melee
  # form's missing missile record is not converted into a projectile profile.
  (def projected (forms/apply-form ((package :champion-map) champion) ranged-form 1 {:q 1}))
  (assert (projected :attack-projectile))
  (assert (nil? ((forms/apply-form projected melee 1 {:q 1}) :attack-projectile)))
  (close 0 (get-in (scenario/compile (merge definition {:player (spec melee 1 champion)})) [:actors 0 :attack-missile-speed]))
  (assert (nil? (get-in (scenario/compile (merge definition {:player (spec nil 1 champion)})) [:actors 0 :ranged])))
  # Primed Sheen stays available while the ordinary projectile is in flight.
  (def armed (get-in (scenario/compile (merge definition {:player (merge (definition :player) {:loadout {:items ["3057"]}})})) [:actors 0]))
  (def priming {:at 0 :kind :effect :actor 0 :target 0 :source "fixture" :origin "prime"
                :effect {:kind :buff :buff "spellblade" :duration 1}})
  (def release (/ 0.3 (get-in armed [:stats :attack-speed])))
  (def impact (+ release (/ 300 speed)))
  (def in-flight (engine/simulate {:duration (+ release 0.0001) :actors [armed target] :initial-events [priming]}))
  (close 0 (in-flight :damage))
  (close 1 (get-in in-flight [:actors 0 :buff-counts "spellblade"]))
  (def landed (engine/simulate {:duration (+ impact 0.0001) :actors [armed target] :initial-events [priming]}))
  (close 0 (get-in landed [:actors 0 :buff-counts "spellblade"]))
  (def proc (find |(and (= :damage ($ :kind)) (not= "attack" ($ :source))) (landed :trace)))
  (close impact (proc :at))
  (close (get-in armed [:base :ad]) (proc :damage)))

# Cannon's ordinary variants must not acquire the post-transformation attack,
# even though its speed also equals 2000. Hyper Charge and Hammer/root slots
# likewise remain distinct from the selected Cannon profile.
(def jayce-source (util/read-json (slurp "data/form-fixtures/16.19.1/Jayce-characters.json")))
(def cannon-review (get-in attacks/reviewed-forms [:forms "Jayce" "cannon"]))
(each [name animation] [["JayceRangedAttack" "ranged_attack1"] ["JayceRangedAttack2" "ranged_attack2"] ["JayceRangedCritAttack" "ranged_crit"]]
  (def spell (get-in jayce-source [(string "Characters/Jayce/Spells/" name) "mSpell"]))
  (assert (= true (spell "mApplyAttackDamage")))
  (assert (= animation (spell "mAnimationName"))))
(each name (cannon-review :excluded-variants)
  (def invalid (merge cannon-review {:ordinary-variants [;(cannon-review :ordinary-variants) name]}))
  (assert (not (first (protect (attacks/reviewed-form-projectile "Jayce" jayce-source invalid))))))
(close 1800 (get-in jayce-source ["Characters/Jayce/Spells/JayceHyperChargeAbility/JayceHyperChargeRangedAttack" "mSpell" "mMissileSpec" "movementComponent" "mSpeed"]))
(close 2500 (get-in jayce-source ["Characters/Jayce/Spells/JayceCritAttack" "mSpell" "missileSpeed"]))
(assert (empty? (get-in (scenario/compile (definition "cannon" 1 "Jayce")) [:actors 0 :abilities])))
(assert (some |(string/find "transformation attack bonuses" $)
              ((scenario/compile (definition "cannon" 1 "Jayce")) :coverage)))

# Hammer's passive is bonus armor/MR, independent of R allocation. Check all
# level breakpoints against a separate arithmetic reference and Cannon's stats.
(each level [1 5 6 10 11 15 16 18]
  (def hammer (get-in (scenario/compile (definition "hammer" level "Jayce")) [:actors 0]))
  (def cannon (get-in (scenario/compile (definition "cannon" level "Jayce")) [:actors 0]))
  (def expected (+ 5 (* 7 (math/floor (/ (dec level) 5))) (* 0.075 (- (get-in hammer [:stats :ad]) (get-in hammer [:base :ad])))))
  (each key [:armor :mr]
    (close expected (- (get-in hammer [:stats key]) (get-in cannon [:stats key])))
    (close (get-in hammer [:base key]) (get-in cannon [:base key]))))

# Temporary AD changes must update the passive before armor/MR modifiers,
# without stacking the passive on repeated refreshes or retaining it at expiry.
(def hammer (get-in (scenario/compile (definition "hammer" 1 "Jayce")) [:actors 0]))
(def resting (merge hammer {:strategy {:attacks false :abilities false :movement :hold}}))
(def target (get-in (scenario/compile (definition "cannon" 1 "Jayce")) [:actors 1]))
(defn event [at effect] {:at at :kind :effect :actor 1 :target 0 :source "fixture" :origin (string at) :effect effect})
(def simulated (engine/simulate {:duration 1.4 :actors [resting target]
                                 :initial-events [(event 0 {:kind :stat-buff :stat :ad :amount 100 :duration 1})
                                                  (event 0 {:kind :stat-buff :stat :armor :mode :multiply :amount 0.5 :duration 1})
                                                  (event 0 {:kind :stat-buff :stat :mr :mode :multiply :amount 0.5 :duration 1})
                                                  (event 0.2 {:kind :damage :damage-type :physical :amount 100})
                                                  (event 0.4 {:kind :damage :damage-type :magic :amount 100})
                                                  (event 1.1 {:kind :damage :damage-type :physical :amount 100})]}))
(def hits (filter |(= :damage ($ :kind)) (simulated :trace)))
(close (/ 10000 (+ 100 (* 0.5 (+ (get-in hammer [:stats :armor]) 7.5)))) ((hits 0) :damage))
(close (/ 10000 (+ 100 (* 0.5 (+ (get-in hammer [:stats :mr]) 7.5)))) ((hits 1) :damage))
(close (/ 10000 (+ 100 (get-in hammer [:stats :armor]))) ((hits 2) :damage))
(each key [:armor :mr :ad] (close (get-in hammer [:stats key]) (get-in simulated [:actors 0 :stats key])))
(def duel (merge (definition "human" 6) {:distance 200 :target (merge (spec "cougar" 18) {:kind :champion})}))
(def compiled (scenario/compile duel))
(assert (true? (get-in compiled [:actors 0 :ranged])))
(assert (false? (get-in compiled [:actors 1 :ranged])))
(def decoded (wire/decode (wire/encode (compiled :definition))))
(assert (= (util/encode-data (compiled :definition)) (util/encode-data decoded)))
(def restored (model/state-from-definition decoded))
(assert (= "human" (restored :form)))
(assert (= "cougar" (restored :opponentform)))
(assert (= ((scenario/simulate duel) :metrics) ((scenario/simulate (model/definition restored ["3153"])) :metrics)))
(def compared (model/compare restored))
(def html (ui/render (matchup/loadout compared) (matchup/results compared)))
(each text ["name=\"form\"" "name=\"opponentform\"" "Nidalee (Human)" "Nidalee (Cougar)"] (assert (string/find text html)))
(each definition [duel (merge duel {:player (duel :target) :target (merge (duel :player) {:kind :champion})})]
  (def result (search/run package definition {:pool ["3153"] :slots 1 :budget 4000 :seconds 5 :final-samples 1}
                          (fn [progress] nil) (fn [] false)))
  (assert (result :complete))
  (each row (result :rows)
    (assert (= (get-in definition [:player :form]) (get-in row [:definition :player :form])))
    (assert (= (get-in definition [:target :form]) (get-in row [:definition :target :form])))
    (assert (= (row :metrics) ((scenario/fitness (row :definition)) :metrics)))))
# Legacy scenarios remain unknown until a form is explicitly selected.
(assert (nil? (get-in (scenario/compile (definition nil 1)) [:actors 0 :ranged])))
(def raw (get-in package [:champion-map "Nidalee"]))
(assert (= "form-dependent" (raw :attack-style)))
(close 525 (raw :attack-range))
(assert (empty? (forms/choices "Nidalee" "16.18.1")))
(each form ["" "dragon" :cougar 42]
  (assert (not (first (protect (scenario/compile (definition form 1)))))))
(assert (not (first (protect (forms/apply-form (merge raw {:patch "16.18.1"}) "cougar")))))
(assert (not (first (protect (forms/apply-form (merge raw {:id "Ahri"}) "human")))))
(def human-kit (merge raw {:abilities [{:id "HumanOnlySpell" :slot :q}]}))
(assert (empty? ((forms/apply-form human-kit "cougar") :abilities)))
(assert (= (human-kit :abilities) ((forms/apply-form human-kit nil) :abilities)))
(assert (= "" ((model/parse-state {"champion" "Ahri" "form" "cougar"}) :form)))
(assert (= "" ((model/parse-state {"champion" "Jayce" "form" "human"}) :form)))
(assert (= "" ((model/parse-state {"champion" "Nidalee" "form" "hammer"}) :form)))
(assert (not (first (protect (model/parse-state {"champion" "Jayce" "form" "dragon"})))))
(def jayce-duel (merge (definition "cannon" 6 "Jayce") {:target (merge (spec "hammer" 18 "Jayce") {:kind :champion})}))
(def jayce-decoded (wire/decode (wire/encode ((scenario/compile jayce-duel) :definition))))
(def jayce-restored (model/state-from-definition jayce-decoded))
(assert (= "cannon" (jayce-restored :form)))
(assert (= "hammer" (jayce-restored :opponentform)))
(assert (= ((scenario/simulate jayce-duel) :metrics) ((scenario/simulate (model/definition jayce-restored ["3153"])) :metrics)))
(each definition [jayce-duel (merge jayce-duel {:player (jayce-duel :target) :target (merge (jayce-duel :player) {:kind :champion})})]
  (def result (search/run package definition {:pool ["3153"] :slots 1 :budget 4000 :seconds 5 :final-samples 1}
                          (fn [progress] nil) (fn [] false)))
  (assert (result :complete))
  (each row (result :rows)
    (assert (= (get-in definition [:player :form]) (get-in row [:definition :player :form])))
    (assert (= (get-in definition [:target :form]) (get-in row [:definition :target :form])))
    (assert (= (row :metrics) ((scenario/fitness (row :definition)) :metrics)))))
(assert (nil? (get-in (scenario/compile (definition nil 1 "Jayce")) [:actors 0 :ranged])))
(def no-r (merge jayce-duel {:player (merge (spec "hammer" 18 "Jayce") {:ranks {:r 0}})}))
(close (get-in (scenario/compile (definition "hammer" 18 "Jayce")) [:actors 0 :stats :armor])
       (get-in (scenario/compile no-r) [:actors 0 :stats :armor]))
(assert (not (first (protect (scenario/compile (definition "human" 1 "Jayce"))))))
(assert (not (first (protect (scenario/compile (definition "hammer" 1 "Nidalee"))))))

# Elise gets one free R rank. Independent expected values use the reviewed
# patch notes (14/24/34/44), not the stale alternate tooltip's 12/22/32/42.
(defn elise-actor [form level &opt allocated]
  (def spec (merge (spec form level "Elise") {:loadout {:items []}}))
  (def spec (if (nil? allocated) spec (merge spec {:ranks {:r allocated}})))
  (def actor (scenario/participant package spec "player" 0))
  (merge actor {:health 100 :stats (merge (actor :stats) {:ap 100 :hp-regen 0 :ad 100 :attack-speed 1 :crit-chance 1 :crit-damage 2})}))
(def dummy {:id "target" :kind :practice :tags [:practice :champion] :position 0
            :stats {:hp 10000 :armor 0 :mr 100} :strategy {:attacks false :abilities false :movement :hold}})
(defn passive-events [outcome source] (filter |(= source ($ :source)) (outcome :trace)))
(each [level base heal] [[1 14 6] [6 24 8] [11 34 10] [16 44 12] [18 44 12]]
  (each side [0 1]
    (def actor (elise-actor "spider" level))
    (def result (engine/simulate {:duration 0.7 :actors (if (= side 0) [actor dummy] [dummy actor])}))
    (def proc (passive-events result "EliseSpiderQueen"))
    (assert (= 1 (length proc)))
    (close (/ (+ base 15) 2) ((first proc) :damage))
    (assert (false? ((first proc) :critical)))
    (close (+ heal 8) ((first (passive-events result "EliseSpiderQueenHeal")) :amount))
    (close 200 ((first (filter |(and (= "attack" ($ :source)) (= :damage ($ :kind))) (result :trace))) :damage))))
(def spider (elise-actor "spider" 1))
(def human (elise-actor "human" 1))
(each [actor speed] [[human 330] [spider 355]]
  (close speed (get-in actor [:base :move-speed]))
  (close speed (get-in actor [:stats :move-speed]))
  (def mover (merge actor {:strategy {:attacks false :abilities false :movement :approach}}))
  (def moved (engine/simulate {:duration 0.5 :actors [mover (merge dummy {:position 1000})]}))
  (close (* speed 0.5) (get-in moved [:actors 0 :position])))
(def withheld (engine/simulate {:duration 0.7 :actors [(elise-actor "spider" 18 0) dummy]}))
(close 14.5 ((first (passive-events withheld "EliseSpiderQueen")) :damage))
(assert (empty? (passive-events (engine/simulate {:duration 0.7 :actors [human dummy]}) "EliseSpiderQueen")))
(def capped (engine/simulate {:duration 0.7 :actors [(merge spider {:health (dec (get-in spider [:stats :hp]))}) dummy]}))
(close 1 ((first (passive-events capped "EliseSpiderQueenHeal")) :amount))

# The amounts follow live AP and expire with its modifier; generated damage
# never recursively generates Spider Queen. Misses, interrupted windups,
# parried attacks and objectives must produce neither passive damage nor heal.
(def buffed (engine/simulate {:duration 1.7 :actors [spider dummy]
                              :initial-events [(event 0 {:kind :stat-buff :stat :ap :amount 100 :duration 1})]}))
(def procs (passive-events buffed "EliseSpiderQueen"))
(def heals (passive-events buffed "EliseSpiderQueenHeal"))
(assert (= 2 (length procs) (length heals)))
(close 22 ((procs 0) :damage)) (close 14.5 ((procs 1) :damage))
(close 22 ((heals 0) :amount)) (close 14 ((heals 1) :amount))
(def parry {:at 0 :kind :effect :actor 1 :target 1 :source "fixture" :origin "parry"
            :effect {:kind :parry :duration 1 :source-kinds [:champion]}})
(each compiled [{:actors [(merge spider {:strategy {:attacks true :abilities false :movement :hold :hit-chance 0}}) dummy]}
                {:actors [spider dummy] :initial-events [(event 0.1 {:kind :control :control :stun :duration 1})]}
                {:actors [spider dummy] :initial-events [parry]}
                {:actors [spider (merge dummy {:kind :objective :tags [:monster]})]}]
  (def outcome (engine/simulate (merge compiled {:duration 0.7})))
  (assert (empty? (passive-events outcome "EliseSpiderQueen")))
  (assert (empty? (passive-events outcome "EliseSpiderQueenHeal"))))

(def elise-duel (merge (definition "spider" 6 "Elise") {:target (merge (spec "human" 18 "Elise") {:kind :champion})}))
(def elise-decoded (wire/decode (wire/encode ((scenario/compile elise-duel) :definition))))
(def elise-restored (model/state-from-definition elise-decoded))
(assert (= "spider" (elise-restored :form)))
(assert (= "human" (elise-restored :opponentform)))
(assert (= ((scenario/simulate elise-duel) :metrics) ((scenario/simulate (model/definition elise-restored ["3153"])) :metrics)))
(def compared (model/compare elise-restored))
(def html (ui/render (matchup/loadout compared) (matchup/results compared)))
(each text ["Elise (Spider)" "Elise (Human)" "Spider Queen" "Additional R points (free first rank included)"] (assert (string/find text html)))
(def metadata (matchup/event-sources package [(elise-actor "spider" 1)] [{:source "EliseSpiderQueen"} {:source "EliseSpiderQueenHeal"}]))
(assert (= "Spider Queen" (get-in metadata ["EliseSpiderQueen" :name])))
(assert (= "Spider Queen healing" (get-in metadata ["EliseSpiderQueenHeal" :name])))
(each definition [elise-duel (merge elise-duel {:player (elise-duel :target) :target (merge (elise-duel :player) {:kind :champion})})]
  (def result (search/run package definition {:pool ["3153"] :slots 1 :budget 4000 :seconds 5 :final-samples 1}
                          (fn [progress] nil) (fn [] false)))
  (assert (result :complete))
  (each row (result :rows)
    (assert (= (get-in definition [:player :form]) (get-in row [:definition :player :form])))
    (assert (= (get-in definition [:target :form]) (get-in row [:definition :target :form])))
    (assert (= (row :metrics) ((scenario/fitness (row :definition)) :metrics)))))
(assert (nil? (get-in (scenario/compile (definition nil 1 "Elise")) [:actors 0 :ranged])))
(assert (not (first (protect (scenario/compile (definition "cougar" 1 "Elise"))))))
(assert (= "form-dependent" (get-in package [:champion-map "Elise" :attack-style])))
(assert (empty? (forms/choices "Elise" "16.18.1")))

# Independent complete stat table: passive additions are BASE stats, not item
# bonuses. GnarBig's conflicting rounded defenses/old AD growth must not win.
(each level (range 1 19)
  (def n (dec level))
  (def factor (+ (* 0.7025 n) (* 0.0175 n n)))
  (each form ["mini" "mega"]
    (def spec (merge (spec form level "Gnar") {:loadout {:items []} :health-fraction 0.5}))
    (def actor (scenario/participant package spec "player" 0))
    (def mega (= form "mega"))
    (each [key base growth] (if mega [[:hp 640 122] [:ad 66 5.7] [:armor 35.5 6.7] [:mr 33.5 4.8] [:hp-regen 4.5 1.25]]
                              [[:hp 540 79] [:ad 60 3.2] [:armor 32 3.7] [:mr 30 1.3] [:hp-regen 4.5 1.25]])
      (close (+ base (* growth factor)) (get-in actor [:stats key]))
      (close (+ base (* growth factor)) (get-in actor [:base key])))
    (close 0 (get-in actor [:stats :bonus-ad]))
    (close (get-in actor [:base :ad]) (get-in actor [:stats :base-ad]))
    (close (* 0.625 (+ 1 (* (if mega 0.005 0.06) factor))) (get-in actor [:stats :attack-speed]))
    (close (+ 335 (if mega 0 ([0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 16 18 20] n))) (get-in actor [:stats :move-speed]))
    (close (* 0.5 (get-in actor [:stats :hp])) (actor :health))
    (close (if mega 175 (+ 400 (/ (* 100 n) 17))) (actor :attack-range))
    # Item AD is bonus AD; form AD must instead feed source-backed Sheen.
    (def armed (scenario/participant package (merge spec {:loadout {:items ["3057"]}}) "player" 0))
    (def priming {:at 0 :kind :effect :actor 0 :target 0 :source "fixture" :origin "prime"
                  :effect {:kind :buff :buff "spellblade" :duration 1}})
    (def target (merge dummy {:stats {:hp 10000 :armor 0 :mr 0}}))
    (def result (engine/simulate {:duration 0.7 :actors [armed target] :initial-events [priming]}))
    (def hit (find |(and (= :damage ($ :kind)) (not= "attack" ($ :source))) (result :trace)))
    (assert hit)
    (close (get-in actor [:base :ad]) (hit :damage))
    (assert (empty? (get-in result [:actors 0 :abilities])))))

(def gnar-duel (merge (definition "mini" 15 "Gnar") {:distance 200 :target (merge (spec "mega" 18 "Gnar") {:kind :champion})}))
(def gnar-decoded (wire/decode (wire/encode ((scenario/compile gnar-duel) :definition))))
(def gnar-restored (model/state-from-definition gnar-decoded))
(assert (= "mini" (gnar-restored :form))) (assert (= "mega" (gnar-restored :opponentform)))
(assert (= ((scenario/simulate gnar-duel) :metrics) ((scenario/simulate (model/definition gnar-restored ["3153"])) :metrics)))
(def compared (model/compare gnar-restored))
(def html (ui/render (matchup/loadout compared) (matchup/results compared)))
(each text ["Gnar (Mini)" "Gnar (Mega)" "Mini · ranged" "Mega · melee"] (assert (string/find text html) text))
(assert (string/find "Rage, automatic transformations" (ui/render (ui/coverage compared))))
(each definition [gnar-duel (merge gnar-duel {:player (gnar-duel :target) :target (merge (gnar-duel :player) {:kind :champion})})]
  (def result (search/run package definition {:pool ["3153"] :slots 1 :budget 4000 :seconds 5 :final-samples 1}
                          (fn [progress] nil) (fn [] false)))
  (assert (result :complete))
  (each row (result :rows)
    (assert (= (get-in definition [:player :form]) (get-in row [:definition :player :form])))
    (assert (= (get-in definition [:target :form]) (get-in row [:definition :target :form])))
    (assert (= (row :metrics) ((scenario/fitness (row :definition)) :metrics)))))
(assert (nil? (get-in (scenario/compile (definition nil 1 "Gnar")) [:actors 0 :ranged])))
(assert (not (first (protect (scenario/compile (definition "cannon" 1 "Gnar"))))))
(assert (not (first (protect (scenario/compile (definition "mini" 1 "Jayce"))))))
(assert (= "" ((model/parse-state {"champion" "Gnar" "form" "spider"}) :form)))
(assert (= "" ((model/parse-state {"champion" "Elise" "form" "mega"}) :form)))
(assert (empty? (forms/choices "Gnar" "16.18.1")))
(assert (= "form-dependent" (get-in package [:champion-map "Gnar" :attack-style])))
(assert (= snapshot (hash/sha256 (slurp (string directory "/package.jdn")))))
(util/remove-tree root)
(print "Sourced Nidalee/Jayce/Elise/Gnar forms: both roles, ranges, item scaling, form stats, base-AD Spellblade, passive effects, cached repair, scenario/UI round trips and optimizer preservation passed.")
