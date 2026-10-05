(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)
(def root "data/combat-fixtures/16.18.1/")
(def manifest (util/read-json (slurp (string root "manifest.json"))))
(eachp [path expected] (manifest "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root path)))) "Combat fixture corruption."))
(def records (util/read-json (slurp (string root "items.json"))))
(def shared (util/read-json (slurp (string root "summoners.json"))))
(def perks (util/read-json (slurp (string root "runes.json"))))
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :position 0 :attack-range 200 :ranks {:q 1 :d 1}
          :base {:ad 100 :ap 0 :hp 1000} :stats {:hp 1000 :mp 100 :ad 100 :ap 0 :bonus-ad 0 :armor 0 :mr 0 :attack-speed 1}
          :strategy {:attacks true :abilities true :priority [:q :d] :movement :hold}}
         (or fields {})))
(defn run [a &opt b seconds]
  (engine/simulate {:duration (or seconds 3) :actors [(unit "a" a) (unit "b" (merge {:strategy {:attacks false :abilities false}} (or b {})))]}))
(defn close [a b] (assert (< (math/abs (- a b)) 0.00001)))
(defn triggers [id &opt ranged]
  (effects/item-triggers {:patch "16.18.1" :id id :record (records (string "Items/" id))} ranged))
(def alternator (run {:triggers (triggers "3145")}))
(close 365 (alternator :damage))
(def bork (run {:triggers (triggers "3153")}))
(close 81 ((find |(= "item/3153/mist" ($ :source)) (bork :events)) :damage))
(def monster (run {:triggers (triggers "3153")} {:kind :objective :stats {:hp 100000 :armor 0 :mr 0}}))
(close 600 (monster :damage))
(def ability {:id "fixture" :slot :q :cost 0 :range 200 :cooldown 99 :cast-time 0.1
              :effects [{:kind :damage :target :enemy :status :estimated :damage-type :true :amount 10}]})
(def sheen (run {:abilities [ability] :triggers (triggers "3057")}))
(close 410 (sheen :damage))
(assert (= 1 (count |(= "item/3057/hit" ($ :source)) (sheen :events))))
(def electro (effects/rune-triggers {"id" 8112 :record (first (values perks))} "16.18.1"))
(close 370 ((run {:triggers electro}) :damage))
(close 300 ((run {:triggers electro} {:kind :practice}) :damage))
(defn summoner [id]
  (effects/summoner-ability {"id" id :record (get-in shared [(string "Shared/Spells/" id) "mSpell"] {})} :d "16.18.1"))
(def ignite (run {:abilities [(summoner "SummonerDot")] :strategy {:attacks false :abilities true :priority [:d]}} nil 6))
(close 70 (ignite :damage))
(close 0.6 (get-in (run {:abilities [(summoner "SummonerDot")] :strategy {:attacks false :abilities true :priority [:d]}}) [:actors 1 :stats :healing-multiplier]))
(def barrier (run {:abilities [(summoner "SummonerBarrier")] :strategy {:attacks false :abilities true :priority [:d]}}
                  {:strategy {:attacks true :abilities false}}))
(close 100 (get-in barrier [:actors 0 :absorbed]))
(def exhaust (run {:abilities [(summoner "SummonerExhaust")] :strategy {:attacks false :abilities true :priority [:d]}}
                  {:strategy {:attacks true :abilities false}}))
(close 195 (get-in exhaust [:actors 1 :damage-dealt]))
(assert (not (first (protect (engine/simulate {:duration 5 :pending-limit 2 :actors [(unit "a") (unit "b")]})))))
(print "Retained item/rune/summoner records: cooldowns, on-hit health scaling, objective caps, Spellblade consumption, distinct-action Electrocute, Ignite, shields, Exhaust and bounded pending events passed.")
