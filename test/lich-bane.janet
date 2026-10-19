(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(def root "data/combat-fixtures/16.19.1/")
(eachp [path expected] ((util/read-json (slurp (string root "manifest.json"))) "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root path)))) "Lich Bane fixture corruption."))
(def records (util/read-json (slurp (string root "items.json"))))
(def dd (get-in (util/read-json (slurp (string root "items-ddragon.json"))) ["data" "3100"]))
(def item (normalize/item-effects (normalize/item "16.19.1" "3100" dd) records {}))
(def triggers (effects/item-triggers item true))
(defn close [expected actual] (assert (< (math/abs (- expected actual)) 0.00001)))
(def ability {:id "cast" :slot :q :cost 0 :range 200 :cooldown 99 :cast-time 0.1
              :effects [{:kind :shield :target :self :status :estimated :amount 0 :duration 0.1}]})
# Base speed and ratio deliberately differ. Existing bonus speed must not be
# multiplied by 1.5; the retained 50% bonus adds 0.25 attacks/second here.
(def unit {:id "a" :kind :champion :level 18 :position 0 :attack-range 200 :ranks {:q 1}
           :attack-speed-ratio 0.5 :attack-speed-cap 2.5
           :base {:ad 100 :ap 0 :hp 10000}
           :stats {:hp 10000 :mp 1000 :ad 100 :ap 100 :armor 0 :mr 0 :crit-chance 0
                   :attack-speed 1.5 :attack-speed-uncapped 1.5 :attack-speed-bonus 1}
           :abilities [ability] :triggers triggers
           :strategy {:attacks true :abilities true :priority [:q] :movement :hold}})
(def target {:id "b" :kind :champion :position 0 :stats {:hp 10000 :armor 0 :mr 0}
             :strategy {:attacks false :abilities false}})
(defn run [duration &opt fields events opponent]
  (engine/simulate {:duration duration :actors [(merge unit (or fields {})) (or opponent target)]
                    :initial-events (or events [])}))
(defn sourced [outcome source] (filter |(= source ($ :source)) (outcome :events)))
(defn stat [outcome key] (get-in outcome [:actors 0 :stats key]))
(def no-attacks {:attacks false :abilities true :priority [:q] :movement :hold})
(def primed (run 0.15))
(close 1.75 (stat primed :attack-speed))
(close 1.5 (stat primed :attack-speed-bonus))
(assert (empty? (primed :unsupported)))
(assert (empty? (effects/item-limitations item)))
(def consumed (run 3))
(def attacks (sourced consumed "attack"))
(def starts (filter |(and (= :attack ($ :kind)) (= "a" ($ :actor))) (consumed :trace)))
(close (+ 0.1 (/ 0.3 1.75)) ((first attacks) :at))
(assert (= 1 (length (sourced consumed "item/3100/hit"))))
(close 120 ((first (sourced consumed "item/3100/hit")) :damage))
(close 1.5 (stat consumed :attack-speed))
(close 1 (stat consumed :attack-speed-bonus))
# Consumption leaves subsequent windups at ordinary speed. It does not reset
# or retroactively retime the attack period already scheduled at attack start.
(for i 1 (length attacks) (close (/ 0.3 1.5) (- ((attacks i) :at) ((starts i) :at))))
(assert (>= (- ((starts 2) :at) ((starts 1) :at)) (/ 1 1.5)))

(def expires (run 10.2 {:strategy no-attacks}))
(close 1.5 (stat expires :attack-speed))
(assert (= 0 (get-in expires [:actors 0 :buff-counts "spellblade"])))
(close 1.75 (stat (run 9.9 {:strategy no-attacks}) :attack-speed))
# A recast refreshes duration without stacking speed; the old expiry is inert.
(def refreshed (run 10.2 {:strategy no-attacks :abilities [(merge ability {:cooldown 6})]}))
(close 1.75 (stat refreshed :attack-speed))
(assert (= 1 (get-in refreshed [:actors 0 :buff-counts "spellblade"])))

(def repeated (run 5 {:abilities [(merge ability {:cooldown 0.5})]}))
(def procs (sourced repeated "item/3100/hit"))
(def primes (filter |(= "item/3100/prime" ($ :source)) (repeated :trace)))
(assert (>= (length procs) 2))
(assert (> (length (filter |(= :cast ($ :kind)) (repeated :trace))) (length primes)))
(each prime primes
  (each proc procs
    (when (< (proc :at) (prime :at)) (assert (>= (- (prime :at) (proc :at)) 1.5)))))
(for i 1 (length procs) (assert (>= (- ((procs i) :at) ((procs (dec i)) :at)) 1.5)))

(each [raw expected] [[2.4 2.5] [3 2.5]]
  (def capped (run 0.15 {:stats (merge (unit :stats) {:attack-speed (min raw 2.5) :attack-speed-uncapped raw})}))
  (close expected (stat capped :attack-speed))
  (close (+ raw 0.25) (stat capped :attack-speed-uncapped)))
(def missed (run 2 {:strategy (merge (unit :strategy) {:hit-chance 0})}))
(assert (empty? (sourced missed "item/3100/hit")))
(close 1.75 (stat missed :attack-speed))
(def interrupted (run 0.5 {} [{:at 0.15 :kind :effect :actor 1 :target 0 :source "stun" :origin "stun"
                               :effect {:kind :control :control :stun :duration 1}}]))
(assert (some |(= :interrupted ($ :kind)) (interrupted :trace)))
(close 1.75 (stat interrupted :attack-speed))
# Current Spellblade triggers run at successful impact, including projectiles.
(def flying (run 0.5 {:attack-missile-speed 100} [] (merge target {:position 100})))
(assert (empty? (sourced flying "item/3100/hit")))
(close 1.75 (stat flying :attack-speed))
(close 1.5 (stat (run 1.5 {:attack-missile-speed 100} [] (merge target {:position 100})) :attack-speed))

# Both participants own independent buff and cooldown state.
(def duel (run 3 {} [] (merge unit {:id "b"})))
(each actor (duel :actors)
  (close 1.5 (get-in actor [:stats :attack-speed]))
  (close 120 (get-in actor [:breakdown "item/3100/hit"])))
(def no-cast (run 1 {:strategy {:attacks true :abilities false}}))
(assert (empty? (sourced no-cast "item/3100/hit")))
(close 1.5 (stat no-cast :attack-speed))
# Missing fields must remain diagnostic, never an invented zero-speed bonus.
(def absent (merge item {:record {}}))
(assert (not (empty? (effects/item-limitations absent))))
(assert (empty? (effects/item-triggers (merge item {:patch "99.1.1"}) true)))
(def incomplete-record (merge (item :record)
                              {"mDataValues" (filter |(not= "SheenASBuff" (get $ "mName")) (get-in item [:record "mDataValues"]))}))
(def missing-data (merge item {:record incomplete-record}))
(assert (not (empty? (effects/item-limitations missing-data))))
(def unresolved (run 0.15 {:triggers (effects/item-triggers missing-data true)}))
(assert (some |(string/find "SheenASBuff" $) (unresolved :unsupported)))
(close 1.5 (stat unresolved :attack-speed))
(assert (= nil (get-in unresolved [:actors 0 :buff-counts "spellblade"])))
(def incomplete (merge @{} unit))
(put incomplete :attack-speed-ratio nil)
(def missing (engine/simulate {:duration 0.15 :actors [incomplete target]}))
(assert (some |(string/find "attack-speed ratio and cap" $) (missing :unsupported)))
(close 1.5 (stat missing :attack-speed))
(assert (= nil (get-in missing [:actors 0 :buff-counts "spellblade"])))
(print "Lich Bane source values, ratio/cap, windups, consumption, refresh/expiry, cooldown gating, misses, interruptions, projectiles and independent duel state passed.")
