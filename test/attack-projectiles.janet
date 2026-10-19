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
(assert (= 2 (length (profile :spell-paths))))
(assert (= (get-in profile [:source :sha256]) (hash/sha256 (slurp (get-in profile [:source :path])))))
(def dragon (util/read-json (slurp "data/16.19.1/catalog/sources/champions-ddragon.json")))
(assert (= 173 (length (dragon "data"))))
(eachp [id champion] (dragon "data")
  (close (get-in champion ["stats" "attackrange"]) (attacks/attack-range id "16.19.1" nil)))
(close 700 (attacks/attack-range "Ahri" "16.19.1" 700))
(assert (nil? (attacks/attack-range "Ahri" "16.20.1" nil)))
(assert (nil? (attacks/attack-range "Unknown" "16.19.1" nil)))
(each invalid [-1 0 math/inf "550"]
  (assert (not (first (protect (attacks/attack-range "Ahri" "16.19.1" invalid))))))
(each [champion patch] [["Ahri" "16.18.1"] ["Ahri" "16.20.1"] ["Annie" "16.19.1"] ["Viktor" "16.19.1"]]
  (assert (nil? (attacks/profile champion patch))))
(def repaired (normalize/semantic-kit "Ahri" "16.19.1"
                                      {:abilities [] :limitations ["Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions."]}))
(assert (= profile (repaired :attack-projectile)))
(close 550 (repaired :attack-range))
(assert (not (some |(string/find "projectile travel zero" $) (repaired :limitations))))
(assert (= (util/canonical repaired) (util/canonical (normalize/semantic-kit "Ahri" "16.19.1" repaired))))
(assert (nil? ((attacks/apply-profile "Ahri" "16.20.1" repaired) :attack-projectile)))

# Incomplete/ambiguous movement cannot quietly become a speed or zero travel.
(defn spell [speed kind &opt legacy]
  {"mSpell" {"missileSpeed" (or legacy speed) "mMissileSpec" {"movementComponent" {"__type" kind "mSpeed" speed}}}})
(each objects [{"one" (spell 1750 "AcceleratingMovement")}
               {"one" (spell -1 "FixedSpeedMovement")}
               {"one" (spell 1750 "FixedSpeedMovement" 1200)}
               {"one" (spell 1750 "FixedSpeedMovement") "two" (spell 1500 "FixedSpeedMovement")}]
  (assert (not (first (protect (attacks/fixed-projectile objects ["one" "two"]))))))
(assert (not (first (protect (attacks/fixed-projectile {} [])))))

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
(assert (not (some |(string/find "projectile travel is assumed zero" $) (player :coverage))))
(def other (scenario/compile (definition "Annie")))
(close 0 (get-in other [:actors 0 :attack-missile-speed]))
(assert (some |(string/find "projectile travel is assumed zero" $) (get-in other [:actors 0 :coverage])))
(def duel (scenario/compile (definition "Ahri" {:kind :champion :champion "Ahri" :level 1
                                                :loadout {:items []} :skill-order [:q]
                                                :strategy {:attacks true :abilities false :movement :hold}})))
(each actor (duel :actors) (close 1750 (actor :attack-missile-speed)))
(def outcome (scenario/simulate (definition "Ahri")))
(close (+ (/ 0.3 (get-in player [:stats :attack-speed])) (/ 300 1750)) (get-in outcome [:events 0 :at]))
(assert (= (outcome :metrics) ((scenario/fitness (definition "Ahri")) :metrics)))

# Travel shifts impact, never the start of the following attack. The scoring
# window stays half-open, and an in-flight attack contributes no early damage.
(def unit (merge player {:stats (merge (player :stats) {:attack-speed 1 :ad 100 :crit-chance 0})}))
(def target (get-in compiled [:actors 1]))
(defn run [distance duration]
  (engine/simulate {:duration duration :actors [unit (merge target {:position distance})]}))
(close 100 ((run 0 0.4) :damage))
(close 0 ((run 350 0.5) :damage))
(close 100 ((run 350 0.501) :damage))
(close 0 ((run 551 2) :damage))
(close 100 ((run 550 0.615) :damage))
(def long (run 350 2))
(close 200 (long :damage))
(close 0.5 (get-in long [:events 0 :at]))
(close 1.5 (get-in long [:events 1 :at]))
(assert (= source-hash (hash/sha256 (slurp (string (package :directory) "/package.jdn")))))
(util/remove-tree root)
(print "Ahri retained projectile movement, patch isolation, cached semantic repair, both participants, impact/window boundaries and fitness agreement passed.")
