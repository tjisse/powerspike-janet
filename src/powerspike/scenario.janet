(import ./packages :as packages)
(import ./stats :as stats)
(import ./skills :as skills)
(import ./builds :as builds)
(import ./engine :as engine)
(import ./effects :as effects)
(import ./validation :as v)
(import ./data-util :as util)
(import pshash :as hash)
(import ../../data/16.19.1/annie :as annie)

(def schema 1)
(def default-order annie/skill-order)
(def slots [:q :w :e :r :d :f])
(defn seed-abilities [package champion]
  (if (and (get-in package [:manifest "initial"]) (= "16.19.1" (package :patch)) (= "Annie" (champion :id)))
    (map (fn [spell]
           (merge spell {:name (spell :id) :icon (string (spell :id) ".png") :icon-group "spell" :available true :checked false :max-rank 5
                         :cost {:op :rank :values (spell :cost) :offset -1}
                         :cooldown {:op :rank :values (spell :cooldown) :offset -1} :range 625
                         :effects [{:kind :damage :damage-type (spell :damage-type) :target :enemy :status :estimated :trigger :cast
                                    :amount {:op :sum :children [{:op :rank :values (spell :base-damage) :offset -1}
                                                                 {:op :multiply :children [{:op :stat :stat :ap :formula 0}
                                                                                           {:op :constant :value 0.8}]}]}}]
                         :unresolved ["Initial curated Q/W subset; passive stun, E, R casts and Tibbers excluded."]})) annie/spells)
    (get champion :abilities [])))
(defn runes [package]
  (mapcat (fn [style] (mapcat |(get $ "runes" []) (get style "slots" []))) (get package :runes [])))
(defn default-ranks [champion level]
  (def ranks (skills/ranks-from-order default-order level))
  (tabseq [slot :in [:q :w :e :r]
           :let [ability (find |(= slot ($ :slot)) (get champion :abilities []))]]
    slot (min (get ranks slot 0) (get ability :max-rank (if (= :r slot) 3 5)))))
(defn strategy [input]
  (def priority (get input :priority slots))
  (assert (and (indexed? priority) (<= (length priority) 6)
               (= (length priority) (length (keys (tabseq [slot :in priority] slot true))))
               (not (some |(not (some (fn [slot] (= $ slot)) slots)) priority))) "Invalid ability priority.")
  (def movement (get input :movement :approach))
  (assert (some |(= $ movement) [:hold :approach :hold-range]) "Invalid movement strategy.")
  (def activations (get input :activation {}))
  (eachp [slot condition] activations
    (assert (some |(= $ slot) slots) "Unknown activation slot.")
    (v/nonnegative (get condition :after 0) "Activation delay")
    (each key [:self-health-below :target-health-below] (v/fraction (get condition key 1) "Activation health threshold")))
  (each key [:attacks :abilities] (assert (boolean? (get input key true)) "Strategy switches must be booleans."))
  {:priority priority :activation activations :movement movement :attacks (get input :attacks true) :abilities (get input :abilities true)
   :hit-chance (v/fraction (get input :hit-chance 1) "Hit chance")
   :preferred-range (v/nonnegative (get input :preferred-range 500) "Preferred range")})
(defn participant [package spec id position]
  (def champion ((package :champion-map) (spec :champion)))
  (assert champion "Champion unavailable on this patch.")
  (def level (v/integer-between (get spec :level 18) 1 18 "level"))
  (def loadout (get spec :loadout {}))
  (def ids (get loadout :items []))
  (assert (and (indexed? ids) (<= (length ids) 6)) "Inventory supports six slots.")
  (def items (map (fn [id] (def item ((package :item-map) id)) (assert item "Item unavailable on this patch.") item) ids))
  (def ranks (or (spec :ranks) (when (spec :skill-order) (skills/ranks-from-order (spec :skill-order) level)) (default-ranks champion level)))
  (skills/validate-ranks ranks level)
  (def abilities (seed-abilities package champion))
  (def page (get loadout :runes []))
  (assert (and (indexed? page) (<= (length page) 6)) "Rune page supports six runes.")
  (def chosen-runes (map (fn [id] (def rune (find |(= id (get $ "id")) (runes package))) (assert rune "Rune unavailable on this patch.") rune) page))
  (def summoner-ids (get loadout :summoners []))
  (assert (and (indexed? summoner-ids) (<= (length summoner-ids) 2)
               (= (length summoner-ids) (length (keys (tabseq [id :in summoner-ids] id true))))) "Choose up to two distinct summoner spells.")
  (def summoners (map (fn [summoner-id slot]
                        (def raw (find |(= summoner-id (get $ "id")) (get package :summoners [])))
                        (assert (and raw (some |(= "CLASSIC" $) (get raw "modes" []))) "Summoner spell unavailable on Summoner's Rift.")
                        (effects/summoner-ability raw slot (package :patch))) summoner-ids [:d :f]))
  (def computed (stats/apply-rank-penetration champion (stats/total-stats champion level items) ranks))
  (def ranged (> (champion :attack-range) 300))
  (def all-ranks (merge ranks (tabseq [spell :in summoners] (spell :slot) 1)))
  (def inspection (builds/inspect-build items {:champion (champion :id)}))
  {:id id :kind :champion :champion (champion :id) :level level :ranged ranged :stats computed
   :base (merge (stats/base-stats champion level) {:ap 0 :crit-chance 0 :crit-damage (champion :crit-damage)})
   :health (* (computed :hp) (v/fraction (get spec :health-fraction 1) "Starting health"))
   :resource (* (get computed :mp 0) (v/fraction (get spec :resource-fraction 1) "Starting resource"))
   :abilities [;abilities ;summoners] :ranks all-ranks :position position :attack-range (champion :attack-range)
   :strategy (strategy (get spec :strategy {}))
   :triggers [;(mapcat |(effects/item-triggers $ ranged) items) ;(mapcat |(effects/rune-triggers $ (package :patch)) chosen-runes)]
   :coverage [;(get champion :limitations []) ;(mapcat |(get $ :unresolved []) abilities)
              ;(mapcat |(map (fn [note] (string ($ :name) ": " note)) (get $ :limitations [])) items)
              ;(mapcat |(get $ :unresolved []) summoners)
              ;(map (fn [rune] (if (empty? (effects/rune-triggers rune (package :patch)))
                                 (string (rune "name") ": trigger handler unavailable.")
                                 (string (rune "name") ": interpreted trigger; unvalidated in-game."))) chosen-runes)
              ;(inspection :errors)
              ;(if (some |(= "3057" ($ :id)) items) ["Spellblade priming window is assumed to be ten seconds; unvalidated."] [])]})
(defn compile [definition]
  (assert (and (dictionary? definition) (= schema (get definition :schema schema))) "Unsupported scenario schema.")
  (def package (packages/load (definition :patch) (definition :snapshot)))
  (def duration (v/finite-number (get definition :duration 5) "duration"))
  (assert (<= 0.5 duration 120) "Duration must be from 0.5 to 120 seconds.")
  (def distance (v/nonnegative (get definition :distance 300) "distance"))
  (assert (<= distance 10000) "Starting distance exceeds the modeled range.")
  (def player (participant package (definition :player) "player" 0))
  (def target (get definition :target {:kind :practice :hp 10000 :armor 80 :mr 80}))
  (def opponent
    (case (get target :kind :practice)
      :champion (participant package target "opponent" distance)
      :practice {:id "target" :kind :practice :level 1 :position distance
                 :stats {:hp (v/nonnegative (get target :hp 10000) "Target health") :mp 0
                         :armor (v/finite-number (get target :armor 80) "armor") :mr (v/finite-number (get target :mr 80) "magic resistance")}
                 :strategy {:attacks false :abilities false :movement :hold} :coverage []}
      (error "Objective data requires an available objective preset.")))
  (def warnings [;(player :coverage) ;(opponent :coverage)
                 ;(if (and (definition :model) (not= engine/identity (definition :model)))
                    ["This scenario was saved with a different combat model. The retained data is used, but the result is recomputed with the current model."] [])])
  {:definition (merge definition {:schema schema :patch (package :patch) :snapshot (package :snapshot) :model engine/identity})
   :duration duration :seed (v/integer-between (get definition :seed 1) 0 2147483647 "seed")
   :actors [player opponent] :coverage warnings :patch (package :patch) :snapshot (package :snapshot) :model engine/identity})
(defn identity [compiled]
  (hash/sha256 (util/encode-data [(compiled :definition) (compiled :actors) engine/identity])))
(defn simulate [definition &opt cancelled]
  (def compiled (compile definition))
  (def outcome (engine/trials compiled (get definition :samples 1) cancelled))
  (merge outcome {:scenario (compiled :definition) :scenario-id (identity compiled)
                  :coverage (compiled :coverage) :unsupported [;(compiled :coverage) ;(outcome :unsupported)]}))
