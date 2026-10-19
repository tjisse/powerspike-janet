(import ../src/powerspike/attacks :as attacks)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual] (assert (< (math/abs (- expected actual)) 0.000001)))
(def profile (attacks/profile "Ahri" "16.19.1"))
(close 1750 (profile :missile-speed))
(assert (= 3 (length (profile :spell-paths))))
(assert (= (get-in profile [:source :sha256]) (hash/sha256 (slurp (get-in profile [:source :path])))))
(def annie-profile (attacks/profile "Annie" "16.19.1"))
(close 1500 (annie-profile :missile-speed))
(close 1200 (annie-profile :legacy-speed))
(assert (= 3 (length (annie-profile :spell-paths))))
(close 0.2 ((attacks/windup-profile "Ahri" "16.19.1") :fraction))
(each [champion patch] [["Ahri" "16.18.1"] ["Ahri" "16.20.1"] ["Annie" "16.19.1"] ["Garen" "16.19.1"]]
  (assert (nil? (attacks/windup-profile champion patch))))
(def dragon (util/read-json (slurp "data/16.19.1/catalog/sources/champions-ddragon.json")))
(assert (= 173 (length (dragon "data"))))
(eachp [id champion] (dragon "data")
  (close (get-in champion ["stats" "attackrange"]) (attacks/attack-range id "16.19.1" nil)))
(close 700 (attacks/attack-range "Ahri" "16.19.1" 700))
(assert (nil? (attacks/attack-range "Ahri" "16.20.1" nil)))
(assert (nil? (attacks/attack-range "Unknown" "16.19.1" nil)))
(each invalid [-1 0 math/inf "550"]
  (assert (not (first (protect (attacks/attack-range "Ahri" "16.19.1" invalid))))))
(each [champion patch] [["Ahri" "16.18.1"] ["Ahri" "16.20.1"] ["Annie" "16.18.1"] ["Annie" "16.20.1"] ["Viktor" "16.18.1"] ["Viktor" "16.20.1"]]
  (assert (nil? (attacks/profile champion patch))))
(def repaired (normalize/semantic-kit "Ahri" "16.19.1"
                                      {:abilities [] :limitations ["Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions."]}))
(assert (= profile (repaired :attack-projectile)))
(close 0.2 (get-in repaired [:attack-windup :fraction]))
(close 550 (repaired :attack-range))
(assert (not (some |(string/find "projectile travel zero" $) (repaired :limitations))))
(assert (not (some |(string/find "windup 30%" $) (repaired :limitations))))
(assert (= (util/canonical repaired) (util/canonical (normalize/semantic-kit "Ahri" "16.19.1" repaired))))
(assert (nil? ((attacks/apply-profile "Ahri" "16.20.1" repaired) :attack-projectile)))
(assert (nil? ((attacks/apply-profile "Ahri" "16.20.1" repaired) :attack-windup)))

# Incomplete/ambiguous movement cannot quietly become a speed or zero travel.
(defn spell [speed kind &opt legacy]
  {"mSpell" {"missileSpeed" (or legacy speed) "mMissileSpec" {"movementComponent" {"__type" kind "mSpeed" speed}}}})
(each objects [{"one" (spell 1750 "AcceleratingMovement")}
               {"one" (spell -1 "FixedSpeedMovement")}
               {"one" (spell 1750 "FixedSpeedMovement" 1200)}
               {"one" (spell 1750 "FixedSpeedMovement") "two" (spell 1500 "FixedSpeedMovement")}]
  (assert (not (first (protect (attacks/fixed-projectile objects ["one" "two"]))))))
(assert (not (first (protect (attacks/fixed-projectile {} [])))))
(def conflict {"Characters/Fixture/Spells/one" (spell 1500 "FixedSpeedMovement" 1200)})
(def review {:ordinary-variants ["one"] :critical-variants [] :movement-speed 1500 :legacy-speed 1200})
(assert (not (first (protect (attacks/fixed-projectile conflict ["Characters/Fixture/Spells/one"])))))
(close 1500 ((attacks/reviewed-projectile "Fixture" conflict review) :missile-speed))
(assert (not (first (protect (attacks/reviewed-projectile "Fixture" conflict (merge review {:legacy-speed 1300}))))))

# Existing seed snapshots acquire current semantics without altering bytes.
(def root (string "build/attack-projectile-tests/" (hash/sha256 (os/cryptorand 8))))
(def package (packages/initialize root "build/seed"))
(def source-hash (hash/sha256 (slurp (string (package :directory) "/package.jdn"))))
(defn definition [champion &opt target]
  {:schema 1 :patch "16.19.1" :snapshot (package :snapshot) :duration 2 :distance 300 :seed 1
   :player {:champion champion :level 1 :loadout {:items []} :skill-order [:q]
            :strategy {:attacks true :abilities false :movement :hold}}
   :target (or target {:kind :practice :hp 10000 :armor 0 :mr 0})})
(def compiled (scenario/compile (definition "Ahri")))
(def player (get-in compiled [:actors 0]))
(close 550 (player :attack-range))
(close 1750 (player :attack-missile-speed))
(close 0.2 (player :windup-fraction))
(assert (not (some |(string/find "projectile travel is assumed zero" $) (player :coverage))))
(def other (scenario/compile (definition "Annie")))
(close 1500 (get-in other [:actors 0 :attack-missile-speed]))
(close 0.3 (get-in other [:actors 0 :windup-fraction]))
(assert (not (some |(string/find "projectile travel is assumed zero" $) (get-in other [:actors 0 :coverage]))))
(def viktor-profile (attacks/profile "Viktor" "16.19.1"))
(close 2300 (viktor-profile :missile-speed))
(assert (= 3 (length (viktor-profile :spell-paths))))
(assert (= (get-in viktor-profile [:source :sha256]) (hash/sha256 (slurp (get-in viktor-profile [:source :path])))))
(def viktor (scenario/compile (definition "Viktor")))
(close 2300 (get-in viktor [:actors 0 :attack-missile-speed]))
(close 0.3 (get-in viktor [:actors 0 :windup-fraction]))
(assert (not (some |(string/find "projectile travel is assumed zero" $) (get-in viktor [:actors 0 :coverage]))))
(def viktor-hit (scenario/simulate (definition "Viktor")))
(close (+ (/ 0.3 (get-in viktor [:actors 0 :stats :attack-speed])) (/ 300 2300)) (get-in viktor-hit [:events 0 :at]))
(def unsupported (scenario/compile (definition "Garen")))
(close 0 (get-in unsupported [:actors 0 :attack-missile-speed]))
(assert (nil? (attacks/profile "Garen" "16.19.1")))
(def duel (scenario/compile (definition "Ahri" {:kind :champion :champion "Ahri" :level 1
                                                :loadout {:items []} :skill-order [:q]
                                                :strategy {:attacks true :abilities false :movement :hold}})))
(each actor (duel :actors) (close 1750 (actor :attack-missile-speed)))
(def outcome (scenario/simulate (definition "Ahri")))
(close (+ (/ 0.2 (get-in player [:stats :attack-speed])) (/ 300 1750)) (get-in outcome [:events 0 :at]))
(assert (= (outcome :metrics) ((scenario/fitness (definition "Ahri")) :metrics)))

# Travel shifts impact, never the start of the following attack. The scoring
# window stays half-open, and an in-flight attack contributes no early damage.
(def unit (merge player {:stats (merge (player :stats) {:attack-speed 1 :ad 100 :crit-chance 0})}))
(def target (get-in compiled [:actors 1]))
(defn run [distance duration]
  (engine/simulate {:duration duration :actors [unit (merge target {:position distance})]}))
(close 100 ((run 0 0.4) :damage))
(close 0 ((run 350 0.4) :damage))
(close 100 ((run 350 0.401) :damage))
(close 0 ((run 551 2) :damage))
(close 100 ((run 550 0.515) :damage))
(def long (run 350 2))
(close 200 (long :damage))
(close 0.4 (get-in long [:events 0 :at]))
(close 1.4 (get-in long [:events 1 :at]))
(def critical (engine/simulate {:duration 0.401 :actors [(merge unit {:stats (merge (unit :stats) {:crit-chance 1})})
                                                         (merge target {:position 350})]}))
(assert (get-in critical [:events 0 :critical]))
(close 0.4 (get-in critical [:events 0 :at]))
(each speed [0.5 1 2]
  (def scaled (engine/simulate {:duration 1 :actors [(merge unit {:stats (merge (unit :stats) {:attack-speed speed})})
                                                     (merge target {:position 0})]}))
  (close (/ 0.2 speed) (get-in scaled [:events 0 :at])))
(def annie (merge (get-in other [:actors 0]) {:stats (merge (get-in other [:actors 0 :stats]) {:attack-speed 1 :ad 100 :crit-chance 0})}))
(def annie-hit (engine/simulate {:duration 0.501 :actors [annie (merge target {:position 300})]}))
(close 0.5 (get-in annie-hit [:events 0 :at]))
(def mixed (engine/simulate {:duration 1 :actors [unit (merge annie {:id "opponent" :position 300})]}))
(close (+ 0.2 (/ 300 1750)) (get-in mixed [:events 0 :at]))
(close 0.5 ((first (filter |(and (= :damage ($ :kind)) (= "opponent" ($ :actor))) (mixed :trace))) :at))
(assert (= source-hash (hash/sha256 (slurp (string (package :directory) "/package.jdn")))))
(util/remove-tree root)
(print "Reviewed Ahri windup, Annie/Ahri/Viktor projectile movement, conflict guards, patch isolation, cached repair, both participants and impact boundaries passed.")
