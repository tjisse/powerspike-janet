(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/stats :as stats)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(def root "data/combat-fixtures/16.19.1/")
(def manifest (util/read-json (slurp (string root "manifest.json"))))
(eachp [path expected] (manifest "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root path)))) "Item upgrade fixture corruption."))
(def records (util/read-json (slurp (string root "items.json"))))
(def dd ((util/read-json (slurp (string root "items-ddragon.json"))) "data"))
(def items (map (fn [id] (normalize/item-effects (normalize/item "16.19.1" id (dd id)) records {})) (keys dd)))
(def pack {:patch "16.19.1" :snapshot "item-upgrade-fixture" :items items
           :item-map (tabseq [item :in items] (item :id) item)})
(defn triggers [id] (effects/item-triggers ((pack :item-map) id) true))
(defn close [a b] (assert (< (math/abs (- a b)) 0.00001)))
(def ability {:id "fixture" :slot :q :cost 0 :range 200 :cooldown 99 :cast-time 0.1
              :effects [{:kind :damage :target :enemy :status :estimated :damage-type :true :amount 10}]})
(def unit {:id "a" :kind :champion :level 18 :position 0 :attack-range 200 :ranks {:q 1}
           :base {:ad 100 :ap 0 :hp 1000} :stats {:hp 1000 :mp 1000 :ad 250 :bonus-ad 150 :ap 100
                                                  :crit-chance 0.25 :crit-damage 2 :armor 0 :mr 0 :attack-speed 1}
           :strategy {:attacks true :abilities true :priority [:q] :movement :hold}})
(def target {:id "b" :kind :practice :tags [:practice :champion] :level 1 :position 0
             :stats {:hp 100000 :armor 0 :mr 0} :strategy {:attacks false :abilities false}})
(defn run [fields &opt duration]
  (engine/simulate {:duration (or duration 3) :actors [(merge unit fields) target]}))
(defn hits [outcome source] (filter |(= source ($ :source)) (outcome :events)))

# Different bonus AD and AP verify that source formulas use base AD correctly.
(each [id expected] [["3057" 100] ["3100" 120] ["3078" 200] ["3508" 137.5] ["6662" 150]]
  (def outcome (run {:abilities [ability] :triggers (triggers id)}))
  (def proc (hits outcome (string "item/" id "/hit")))
  (assert (= 1 (length proc)))
  (close expected ((first proc) :damage))
  (assert (empty? (outcome :unsupported))))
(assert (= :magic (((triggers "3100") 1) :damage-type)))
(each id ["3057" "3100" "3078" "3508" "6662"]
  (def outcome (run {:abilities [(merge ability {:cooldown 0.5})] :triggers (triggers id)} 5))
  (def proc (hits outcome (string "item/" id "/hit")))
  (assert (>= (length proc) 2))
  (for index 1 (length proc)
    (assert (>= (- ((proc index) :at) ((proc (dec index)) :at)) 1.5))))

(def nashor (run {:triggers (triggers "3115")}))
(assert (= 3 (length (hits nashor "item/3115"))))
(each hit (hits nashor "item/3115") (close 30 (hit :damage)))
(def echo (run {:abilities [(merge ability {:effects [(merge (first (ability :effects)) {:hits 3 :interval 0.05})]})]
                :triggers (triggers "6655")}))
(assert (= 1 (length (hits echo "item/6655"))))
(close 160 ((first (hits echo "item/6655")) :damage))
(assert (empty? (hits (run {:triggers (triggers "6655")}) "item/6655")))
(assert (empty? (hits (run {:abilities [(merge ability {:slot :d})] :ranks {:d 1}
                            :strategy {:attacks false :abilities true :priority [:d] :movement :hold}
                            :triggers (triggers "6655")}) "item/6655")))
(def repeated (run {:abilities [(merge ability {:cooldown 1})] :triggers (triggers "6655")
                    :strategy {:attacks false :abilities true :priority [:q] :movement :hold}} 13))
(def echo-hits (hits repeated "item/6655"))
(assert (= 2 (length echo-hits)))
(assert (>= (- ((echo-hits 1) :at) ((echo-hits 0) :at)) 12))

# Searches still score the same engine. No item tier or completion bonus enters
# the score; larger caps make the source-derived upgrades affordable.
(def champion {:base {:hp 1000 :mp 1000 :ad 100} :growth {} :crit-damage 2
               :attack-speed-base 1 :attack-speed-ratio 1 :attack-speed-growth 0 :attack-speed-cap 2.5})
(def definition {:schema 1 :patch "16.19.1" :snapshot (pack :snapshot) :duration 3 :seed 1 :samples 1
                 :player {:champion "Test" :level 18 :loadout {:items []}} :target {:kind :practice}})
(defn evaluate [candidate cancelled]
  (def inventory (map |((pack :item-map) $) (get-in candidate [:player :loadout :items])))
  (def outcome (run {:abilities [ability] :stats (stats/total-stats champion 18 inventory)
                     :triggers (mapcat |(effects/item-triggers $ true) inventory)}))
  {:metrics {:damage (outcome :damage)}})
(each [component upgrade] [["3057" "3100"] ["3145" "6655"]]
  (defn search-with [budget]
    (search/run pack definition {:pool [component upgrade] :budget budget :slots 1 :seconds 5 :final-samples 1}
                (fn [progress] nil) (fn [] false) evaluate))
  (def low-budget (((pack :item-map) component) :gold))
  (def high-budget (((pack :item-map) upgrade) :gold))
  (def low (search-with low-budget))
  (def high (search-with high-budget))
  (assert (= [component] (get-in low [:rows 0 :ids])))
  (assert (= [upgrade] (get-in high [:rows 0 :ids])))
  (assert (> (get-in high [:rows 0 :metrics :damage]) (get-in low [:rows 0 :metrics :damage])))
  (each row (low :rows) (assert (<= (row :cost) low-budget)))
  (each row (high :rows) (assert (<= (row :cost) high-budget))))
(print "Source-derived upgraded Spellblade, Nashor on-hit, Luden echo/cooldown and engine-scored gold caps passed.")
