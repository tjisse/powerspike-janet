(import ../web/model :as model)
(import ../web/matchup :as matchup)
(import ../web/ui :as ui)
(import ../web/catalog :as catalog)
(import ../src/powerspike/jobs :as jobs)
(import pshash :as hash)

(catalog/initialize (string "build/matchup-tests/" (hash/sha256 (os/cryptorand 8))) "build/seed")
(def input {"mode" "duel" "selected" "custom" "champion" "Annie" "opponent" "Garen"
            "slot1" "1052" "enemyslot2" "1036" "duration" "5" "opponentlevel" "6"
            "enemyshard1" "5005" "opponentpriority" "e,q,r,w"})
(def state (model/parse-state input))
(def preview (model/preview state))
(assert (nil? (get-in preview [:selected :combat])) "Editing loadouts must not run combat.")
(assert (= 20 (get-in preview [:selected :stats :ap])))
(assert (> (get-in preview [:selected :opponent :stats :ad]) 80))
(def fields (ui/render (matchup/loadout preview) (matchup/fight-controls preview)))
(each name ["runepage1" "enemyrunepage1" "shard1" "enemyshard1" "summoner1" "opponentsummoner1"
            "skillorder" "opponentskillorder" "priority" "opponentpriority" "qrank" "enemyqrank"]
  (assert (string/find (string "name=\"" name "\"") fields) (string "Missing independent control: " name)))
(assert (not (string/find "Target armor" fields)))
(assert (not (string/find "Target magic resistance" fields)))
(assert (= ["" "1036" "" "" "" ""] (tuple ;(matchup/ids preview true))))
(def result (model/compare state))
(def graph (ui/render (matchup/results result)))
(each caption ["data-matchup-result=" "Combat events" "Both survive" "Health remaining" "Damage dealt"]
  (assert (string/find caption graph)))
(print "ok paired configuration previews and shared server traces")

(each who ["player" "opponent"]
  (def job (model/optimize (merge input {"searchwho" who "searchpool" "1036,1052" "searchslots" "2" "searchbudget" "2000"
                                         "lockslot2" (= who "opponent") "searchseconds" "0.1"})))
  (def definition (get-in job [:input :definition]))
  (assert (= (if (= who "opponent") "Garen" "Annie") (get-in definition [:player :champion])))
  (assert (= (if (= who "opponent") "Annie" "Garen") (get-in definition [:target :champion])))
  (when (= who "opponent")
    (assert (= ["1036"] (tuple ;(get-in job [:input :options :locked]))) "Locks must refer to the opponent's physical slots, including holes.")
    (assert (= 6 (get-in definition [:player :level])))
    (assert (= [5005 0 0] (tuple ;(get-in definition [:player :loadout :shards]))))
    (assert (= [:e :q :r :w] (tuple ;(get-in definition [:player :strategy :priority]))))
    (assert (= ["1052"] (tuple ;(get-in definition [:target :loadout :items])))))
  (jobs/cancel (job :id))
  (while (not (jobs/terminal? job)) (ev/sleep 0.01)))
(print "ok both optimization perspectives preserve the fixed opponent and slot locks")

(def search-input {:definition (get-in result [:selected :combat :scenario])
                   :options {:pool ["1036"] :slots 1 :budget 350 :seconds 1 :samples 1 :final-samples 1}})
(def comparison (model/search-task search-input (fn [progress] nil) (fn [] false)))
(assert (= 400 (get-in comparison [:baseline :cost])) "Compare the current build even when it exceeds the search budget.")
(assert (> (get-in comparison [:baseline :metrics :damage]) 0))
(assert (all |(not (some (fn [id] (= id "1052")) ($ :ids))) (comparison :rows)) "The reference build must not enter the candidate pool.")
(def repeated (model/search-task search-input (fn [progress] nil) (fn [] false)))
(assert (= 0 (repeated :simulated)) "Reference and candidate evaluations must share the bounded fitness cache.")
(print "ok measured current-build comparison, pool constraints and cache reuse")

# Outcome headlines must describe the first knockout in the representative
# trace, independently of later projectiles, healing and sampled means.
(def fake (merge result {:selected (merge (result :selected)
                                          {:combat {:actors [{:id "player" :dead-at 4 :stats {:hp 1000} :health 0}
                                                             {:id "opponent" :dead-at 2 :stats {:hp 1000} :health 0}]
                                                    :trace [{:at 2 :participants [{:health 400} {:health 0}]}
                                                            {:at 4 :participants [{:health 0} {:health 0}]}]}})}))
(def text (ui/render (matchup/results fake)))
(assert (string/find "Annie wins at 2.00 s" text))
(assert (string/find "400 HP remaining (40&#37;)" text))
(print "ok outcome headlines use the first knockout and its health state")

# Event labels come from the completed snapshot and actual trigger metadata.
(def sources (matchup/event-sources (result :package)
                                    [{:abilities [{:id "FioraW" :name "Riposte"}]
                                      :triggers [{:id "item/3100/hit" :consume-buff "spellblade"}]}]
                                    [{:source "attack"} {:source "FioraW"} {:source "item/3100/hit"}]))
(assert (= "Basic attack" (get-in sources ["attack" :name])))
(assert (= "Riposte" (get-in sources ["FioraW" :name])))
(assert (= "Lich Bane" (get-in sources ["item/3100/hit" :name])))
(assert (= "Spellblade consumed" (get-in sources ["item/3100/hit" :consumption])))
(assert (nil? (get-in sources ["attack" :consumption])))
(print "ok completed-snapshot event names and empowerment consumption labels")
