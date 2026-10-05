(import ../src/powerspike/objectives :as objectives)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)
(def root "data/objective-fixtures/16.18.1/")
(def manifest (util/read-json (slurp (string root "manifest.json"))))
(eachp [file expected] (manifest "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root file)))) "Objective fixture corruption."))
(def items (util/read-json (slurp (string root "items.json"))))
(def records (map |(objectives/normalize $ (util/read-json (slurp (string root ($ :file) ".json"))) items "16.18.1") objectives/presets))
(assert (= 10 (count |($ :available) records)))
(def package {:patch "16.18.1" :objectives records})
(defn close [a b] (assert (< (math/abs (- a b)) 0.00001)))
(defn target [id &opt settings]
  (objectives/actor package (merge {:objective id :level 1 :game-time 0 :retaliation false} (or settings {})) 0))
(defn battle [target &opt fields]
  (engine/simulate {:duration 3 :actors [(merge {:id "a" :kind :champion :level 1 :position 0 :attack-range 200 :ranks {:q 1}
                                                 :base {:ad 100 :ap 0} :stats {:hp 10000 :mp 100 :ad 100 :armor 0 :mr 0 :attack-speed 1
                                                                               :crit-chance 1 :crit-damage 2}
                                                 :strategy {:abilities true :attacks true :priority [:q] :movement :hold}}
                                                (or fields {})) target]}))
(def turret (target :turret))
(def spell {:id "q" :slot :q :cost 0 :range 200 :cooldown 99 :cast-time 0.1
            :effects [{:kind :damage :damage-type :magic :amount 900 :target :enemy :status :estimated}]})
(def plain (battle turret))
(def immune (battle turret {:abilities [spell]}))
(close (plain :damage) (immune :damage))
(assert (not (empty? (immune :unsupported))))
(def backdoor (battle (target :turret {:minions-present false})))
(close (* 0.2 (plain :damage)) (backdoor :damage))
(assert (= 0 (count |($ :critical) (plain :events))))
(close 100 ((first (plain :events)) :raw))
(def retaliation (battle (target :turret {:retaliation true})))
(assert (> (get-in retaliation [:metrics :damage-taken]) 0))
(def hits (filter |(= "objective" ($ :actor)) (filter |(= :damage ($ :kind)) (retaliation :trace))))
(assert (> ((hits 1) :damage) ((hits 0) :damage)))
(each preset records
  (def actor (target (preset :id)))
  (assert (> (get-in actor [:stats :hp]) 0))
  (assert (not (empty? (actor :coverage))))
  (def controlled (engine/simulate {:duration 1 :actors [((plain :actors) 0) actor]
                                    :initial-events [{:at 0 :kind :effect :actor 0 :target 1 :source "cc"
                                                      :effect {:kind :control :control :stun :duration 5}}]}))
  (assert (empty? (get-in controlled [:actors 1 :controls]))))
(assert (> (get-in (target :baron {:level 10}) [:stats :hp]) (get-in (target :baron) [:stats :hp])))
(assert (not (first (protect (objectives/actor {:objectives []} {:objective :baron} 0)))))
(print "Retained objective records, patch availability, declared-level scaling, structure targeting/crit immunity, backdoor reduction, heating retaliation and control immunities passed; exceptional server mechanics remain explicit.")
