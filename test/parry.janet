(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(def root "data/parry-fixtures/16.19.1/")
(def manifest (util/read-json (slurp (string root "manifest.json"))))
(eachp [file expected] (manifest "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root file)))) "Parry fixture corruption."))
(def objects (util/read-json (slurp (string root "Fiora-characters.json"))))
(def detail (util/read-json (slurp (string root "Fiora-abilities.json"))))
(def fonts (util/read-json (slurp (string root "strings.json"))))
(def path "Characters/Fiora/Spells/FioraWAbility/FioraW")
(def raw (normalize/ability :w path (objects path) (get-in detail ["data" "Fiora" "spells" 1]) fonts "16.19.1"))
(def kit (normalize/semantic-kit "Fiora" "16.19.1" {:abilities [raw]}))
(def ability (get-in kit [:abilities 0]))
(defn close [a b] (assert (< (math/abs (- a b)) 0.000001) (string "Expected " a ", got " b)))
(assert (= :parry (get-in ability [:effects 0 :kind])))
(assert (= :self (get-in ability [:effects 0 :target])))
(assert (= :cast-start (get-in ability [:effects 0 :trigger])))
(assert (= 1 (length (ability :effects))))
(assert (= (util/canonical kit) (util/canonical (normalize/semantic-kit "Fiora" "16.19.1" kit))))
(each patch ["16.18.1" "16.20.1"]
  (def unsupported (normalize/semantic-kit "Fiora" patch {:abilities [raw]}))
  (assert (not (some |(= :parry ($ :kind)) (get-in unsupported [:abilities 0 :effects])))))
(def items-root "data/combat-fixtures/16.19.1/")
(def records (util/read-json (slurp (string items-root "items.json"))))
(defn item-triggers [id]
  (effects/item-triggers {:id id :patch "16.19.1" :record (records (string "Items/" id))} true))
(def prime {:id "prime" :slot :q :cost 0 :range 200 :cooldown 99 :cast-time 0.1
            :effects [{:kind :shield :target :self :status :estimated :amount 0 :duration 0.1}]})
(def attacker {:id "attacker" :kind :champion :level 1 :position 0 :attack-range 200 :ranks {:q 1}
               :attack-speed-ratio 0.5 :attack-speed-cap 2.5 :attack-missile-speed 500
               :base {:ad 100 :hp 10000 :ap 0}
               :stats {:hp 10000 :mp 1000 :ad 100 :ap 100 :armor 0 :mr 0 :attack-speed 1.5
                       :attack-speed-uncapped 1.5 :attack-speed-bonus 1 :crit-chance 0}
               :abilities [prime] :triggers (item-triggers "3100")
               :strategy {:attacks true :abilities true :priority [:q] :movement :hold}})
(def defender {:id "defender" :kind :champion :level 1 :position 100 :attack-range 150 :ranks {:w 1}
               :base {:ad 100 :hp 10000 :ap 0}
               :stats {:hp 10000 :mp 1000 :ad 100 :ap 0 :armor 0 :mr 0 :attack-speed 1 :move-speed 400}
               :abilities [ability] :strategy {:attacks false :abilities true :priority [:w] :movement :hold}})
(defn run [&opt duration a b events]
  (engine/simulate {:duration (or duration 0.7) :actors [(merge attacker (or a {})) (merge defender (or b {}))]
                    :initial-events (or events [])}))
(defn initial [at kind &opt fields]
  {:at at :kind :effect :actor 0 :target 1 :source "fixture" :origin (string "fixture/" at "/" kind)
   :effect (merge {:kind kind :damage-type :true :amount 100 :duration 1} (or fields {}))})
(def blocked (run))
(close 0 (blocked :damage))
(close 950 (get-in blocked [:actors 1 :resource]))
(close 0 (get-in blocked [:actors 0 :buff-counts "spellblade"]))
(close 1.5 (get-in blocked [:actors 0 :stats :attack-speed]))
(assert (empty? (blocked :events)))
(assert (= 1 (count |(and (= :parried ($ :kind)) (= "item/3100/hit" ($ :source))) (blocked :trace))))
(close (+ 0.1 (/ 0.3 1.75) (/ 100 500))
       ((first (filter |(and (= :parried ($ :kind)) (= "attack" ($ :source))) (blocked :trace))) :at))
# Parry starts before the record's 10ms cast time, blocks all damage types and
# hostile debuffs, and ends at the half-open source duration boundary.
(def during (run 0.74 {:strategy {:attacks false :abilities false}}
                 {} [(initial 0.005 :damage) (initial 0.2 :damage {:damage-type :physical})
                     (initial 0.3 :damage {:damage-type :magic}) (initial 0.4 :control {:control :stun})
                     (initial 0.5 :stat-buff {:stat :outgoing-multiplier :mode :multiply :amount 0.5})
                     (initial 0.6 :buff {:buff "debuff"})]))
(close 0 (during :damage))
(close 0 (get-in during [:actors 1 :controls :stun] 0))
(close 0 (get-in during [:actors 1 :buff-counts "debuff"] 0))
(close 1 (get-in during [:actors 1 :stats :outgoing-multiplier] 1))
# Public JSON output must survive temporary buff and stat-effect state. Lich
# Bane previously left tuple map keys that broke the standalone encoder.
(assert (= 0 (get-in (util/read-json (util/encode-json blocked)) ["metrics" "damage"])))
(def boundary (run 0.751 {:strategy {:attacks false :abilities false}} {} [(initial 0.75 :damage)]))
(close 100 (boundary :damage))
# Defense and its action lock do not cleanse prior effects or prevent self-healing.
(def prior (run 0.5 {:strategy {:attacks false :abilities false}}
                {:health 9000}
                [(initial 0 :stat-buff {:stat :ad :amount -10})
                 {:at 0.1 :kind :effect :actor 1 :target 1 :source "self" :effect {:kind :heal :amount 50}}]))
(close 90 (get-in prior [:actors 1 :stats :ad]))
(close 9050 (get-in prior [:actors 1 :health]))
(close 90 (get-in (util/read-json (util/encode-json prior)) ["actors" 1 "stats" "ad"]))
(def held (run 0.749 {:strategy {:attacks false :abilities false}}
               {:position 500 :strategy {:attacks true :abilities true :priority [:w] :movement :approach}}))
(close 500 (get-in held [:actors 1 :position]))
(assert (not (some |(and (= :attack ($ :kind)) (= "defender" ($ :actor))) (held :trace))))
# Activate defense after launch but before impact; expiry in flight instead
# allows damage and consumes Spellblade normally at impact.
(def in-flight (run 0.7 {} {:strategy {:attacks false :abilities true :priority [:w] :movement :hold
                                       :activation {:w {:after 0.35}}}}))
(close 0 (in-flight :damage))
(close 0 (get-in in-flight [:actors 0 :buff-counts "spellblade"]))
(def expired (run 1.5 {:attack-missile-speed 100}))
(assert (> (expired :damage) 0))
(assert (not (some |(= :parried ($ :kind)) (expired :trace))))
(close 0 (get-in expired [:actors 0 :buff-counts "spellblade"]))
# Misses and windup interruptions retain the primed item. A parried attack must
# not count as an ordinary on-hit, damage proc or defender damage-taken proc.
(def missed (run 0.7 {:strategy (merge (attacker :strategy) {:hit-chance 0})}))
(close 1 (get-in missed [:actors 0 :buff-counts "spellblade"]))
(def interrupted (run 0.7 {} {} [{:at 0.15 :kind :effect :actor 1 :target 0 :source "stun"
                                  :effect {:kind :control :control :stun :duration 1}}]))
(close 1 (get-in interrupted [:actors 0 :buff-counts "spellblade"]))
(def clean-procs (run 0.7 {:triggers [;(attacker :triggers)
                                      {:id "other-on-hit" :on [:attack] :kind :damage :damage-type :true :amount 20}
                                      {:id "other-damage" :on [:damage] :kind :damage :damage-type :true :amount 20}]}
                      {:triggers [{:id "reactive" :on [:damage-taken] :kind :damage :damage-type :true :amount 20}]}))
(each id ["other-on-hit" "other-damage"] (assert (nil? (get-in clean-procs [:actors 0 :proc-counts id]))))
(assert (nil? (get-in clean-procs [:actors 1 :proc-counts "reactive"])))
(each id ["3057" "3100" "3078" "3508" "6662"]
  (def result (run 0.7 {:triggers (item-triggers id)}))
  (close 0 (result :damage))
  (close 0 (get-in result [:actors 0 :buff-counts "spellblade"]))
  (assert (= 1 (count |(and (= :parried ($ :kind)) (= (string "item/" id "/hit") ($ :source))) (result :trace)))))
# Defensive casts work out of range and use independent participant state.
(def reversed (engine/simulate {:duration 0.7 :actors [defender attacker]}))
(close 0 (get-in reversed [:actors 1 :damage-dealt]))
(close 0 (get-in reversed [:actors 1 :buff-counts "spellblade"]))
(close 0.75 (get-in reversed [:actors 0 :parry-until]))
(assert (= (blocked :metrics) ((engine/simulate {:duration 0.7 :trace false :actors [attacker defender]}) :metrics)))
# Consumption starts the source cooldown once even when one attack has a
# separate bonus component. A dead target does not consume an in-flight item.
(close (+ 0.1 (/ 0.3 1.75) (/ 100 500) 1.5) (get-in blocked [:actors 0 :proc-ready "item/3100/hit"]))
(def bonus (run 0.7 {:abilities [(merge prime {:effects [;(prime :effects)
                                                         {:id "bonus" :kind :damage :damage-type :magic :amount 30 :target :enemy
                                                          :trigger :attack :attack-mode :bonus :duration 4 :status :estimated}]})]}))
(close 0 (bonus :damage))
(assert (= 1 (count |(and (= :parried ($ :kind)) (= "item/3100/hit" ($ :source))) (bonus :trace))))
(def dead-target (run 0.7 {} {} [{:at 0.4 :kind :effect :actor 1 :target 1 :source "self-execute"
                                  :effect {:kind :damage :damage-type :true :amount 10000}}]))
(close 1 (get-in dead-target [:actors 0 :buff-counts "spellblade"]))
# The declared shield-ordering assumption is intentional and visible: shields
# remain intact for blocked damage, then absorb ordinary damage after expiry.
(def shielded (run 0.81 {:strategy {:attacks false :abilities false}} {}
                   [{:at 0.1 :kind :effect :actor 1 :target 1 :source "self-shield"
                     :effect {:kind :shield :amount 50 :duration 2}}
                    (initial 0.2 :damage) (initial 0.8 :damage)]))
(close 50 (shielded :damage))
(close 50 (get-in shielded [:actors 1 :absorbed]))
(each invalid [-1 math/inf]
  (def rejected (run 0.2 {:strategy {:attacks false :abilities false}}
                     {:abilities [(merge ability {:cast-lock invalid})]}))
  (close 1000 (get-in rejected [:actors 1 :resource]))
  (close 0 (get-in rejected [:actors 1 :parry-until]))
  (assert (some |(string/find "action-lock duration" $) (rejected :unsupported))))
# Objective defense is deliberately outside this champion-only handler.
(def objective-hit (run 0.7 {:kind :objective :objective :turret :strategy {:attacks false :abilities false}}
                        {} [(initial 0.2 :damage)]))
(close 100 (objective-hit :damage))
# A version-4 cached package acquires the defensive semantics without changing
# its snapshot. Both participant compilation and optimizer fitness use them.
(def package-root (string "build/parry-tests/" (hash/sha256 (os/cryptorand 8))))
(def fiora (merge (normalize/champion "16.19.1" (get-in detail ["data" "Fiora"]) objects)
                  {:abilities [raw]}))
(def ahri-objects (util/read-json (slurp (string items-root "Ahri-characters.json"))))
(def ahri-detail (util/read-json (slurp (string items-root "Ahri-abilities.json"))))
(def ahri-fonts (util/read-json (slurp (string items-root "champion-strings.json"))))
(def ahri-raw (normalize/ability :q "Characters/Ahri/Spells/AhriQAbility/AhriQ"
                                 (ahri-objects "Characters/Ahri/Spells/AhriQAbility/AhriQ")
                                 (get-in ahri-detail ["data" "Ahri" "spells" 0]) ahri-fonts "16.19.1"))
(def ahri (merge (normalize/champion "16.19.1" (get-in ahri-detail ["data" "Ahri"]) ahri-objects)
                 {:abilities [ahri-raw]}))
(def item-dd (get-in (util/read-json (slurp (string items-root "items-ddragon.json"))) ["data" "3100"]))
(def lich (normalize/item-effects (normalize/item "16.19.1" "3100" item-dd) records {}))
(def bytes (util/encode-data (util/canonical {:schema 1 :parser "4" :patch "16.19.1" :champions [fiora ahri] :items [lich]})))
(def snapshot (hash/sha256 bytes))
(def directory (string package-root "/patches/16.19.1/" snapshot))
(util/write (string directory "/package.jdn") bytes)
(util/write (string directory "/manifest.json") (util/encode-json {"initial" false "package_sha256" snapshot}))
(util/write (string package-root "/patches/16.19.1/current") snapshot)
(packages/initialize package-root nil)
(def definition {:schema 1 :patch "16.19.1" :snapshot snapshot :duration 0.74 :distance 100 :seed 1
                 :player {:champion "Ahri" :level 1 :loadout {:items ["3100"]} :skill-order [:q]
                          :strategy {:attacks true :abilities true :priority [:q] :movement :hold}}
                 :target {:kind :champion :champion "Fiora" :level 1 :loadout {:items []} :skill-order [:w]
                          :strategy {:attacks false :abilities true :priority [:w] :movement :hold}}})
(def compiled (scenario/compile definition))
(close 0.75 (get-in (scenario/simulate definition) [:actors 1 :parry-until]))
(close 0 ((scenario/simulate definition) :damage))
(close 0 (get-in (scenario/simulate definition) [:actors 0 :buff-counts "spellblade"]))
(assert (= ((scenario/simulate definition) :metrics) ((scenario/fitness definition) :metrics)))
(assert (= snapshot (hash/sha256 (slurp (string directory "/package.jdn")))))
# Reversing champion roles must preserve the same handler and model scoring.
(def swapped (merge definition {:player (merge (definition :target) {:strategy {:attacks false :abilities true :priority [:w] :movement :hold}})
                                :target (merge (definition :player) {:kind :champion})}))
(close 0 (get-in (scenario/simulate swapped) [:actors 1 :damage-dealt]))
(assert (= ((scenario/simulate swapped) :metrics) ((scenario/fitness swapped) :metrics)))
(when-let [export (os/getenv "PS_PARRY_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string package-root "/patches") (string export "/seed"))
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario (compiled :definition)})))
(util/remove-tree package-root)
(print "Sourced Riposte: cast-start defense, action lock, all damage/control/debuff blocking, boundaries, in-flight hits, parried Spellblade consumption and participant isolation passed.")
