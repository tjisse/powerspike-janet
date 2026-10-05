(import ../src/powerspike/search :as search)
(import ../src/powerspike/optimization :as reference)
(import ../src/powerspike/builds :as builds)
(import ../src/powerspike/loadouts :as loadouts)
(import ../src/powerspike/skills :as skills)
(import ../src/powerspike/packages :as packages)
(defn item [id cost power &opt fields]
  (merge {:id id :gold cost :power power :supported true :purchasable true :maps [11] :stackable false :groups []} (or fields {})))
(def items [(item "a" 100 10) (item "b" 150 18) (item "c" 300 50)
            (item "boot1" 100 20 {:groups [:boots] :group-limits {:boots 1}})
            (item "boot2" 100 30 {:groups [:boots] :group-limits {:boots 1}})
            (item "away" 10 999 {:maps [12]}) (item "only" 10 999 {:required-champion "Other"})
            (item "upgrade" 400 80 {:from ["a" "b"]}) (item "earned" 500 90 {:purchasable false :in-store false})])
(def pack {:patch "16.18.1" :snapshot "fixture" :items items :item-map (tabseq [i :in items] (i :id) i)})
(def definition {:schema 1 :patch "16.18.1" :snapshot "fixture" :duration 5 :seed 7 :samples 1
                 :player {:champion "Test" :level 6 :loadout {:items []}} :target {:kind :practice}})
(defn fake [candidate cancelled]
  (assert (not (cancelled)))
  {:metrics {:damage (sum (map |(((pack :item-map) $) :power) (get-in candidate [:player :loadout :items])))
             :health 100 :win-rate 0 :kill-rate 0 :death-rate 0 :control 0 :healing 0 :absorbed 0}
   :unsupported ["Synthetic search fixture; no claim about game damage."]})
(defn run [options &opt candidate cancel]
  (search/run pack (or candidate definition) (merge {:seconds 5 :final-samples 1} options) (fn [p] nil) (or cancel (fn [] false)) fake))
(def options {:pool ["a" "b" "c"] :budget 300 :slots 2})
(def ranked-fixture (seq [index :range [0 13]] {:key (string index) :score [index] :cost (- 13 index)
                                                :metrics {:health (- 13 index) :control (- 13 index)}}))
(def ranked-ten (search/alternatives [;ranked-fixture ;ranked-fixture]))
(assert (= 10 (length ranked-ten)))
(for index 0 10
  (assert (= (- 12 index) (first ((ranked-ten index) :score)))))
(def result (run options))
(def exact (reference/exact-search (map |((pack :item-map) $) (options :pool)) options (fn [items] (sum (map |($ :power) items)))))
(assert (result :complete))
(assert (= ((exact :best) :score) (get-in result [:rows 0 :metrics :damage])))
(assert (= "c" (get-in result [:rows 0 :ids 0])))
(assert (= (get-in result [:rows 0 :key]) (get-in (run options) [:rows 0 :key])))
(def boots (run {:pool ["boot1" "boot2" "away" "only"] :slots 2 :budget 300}))
(assert (= ["boot2"] (get-in boots [:rows 0 :ids])))
(def owned (search/replace-items definition ["a" "b"]))
(def purchase (run {:pool ["upgrade"] :budget 150 :slots 6 :next-purchase true} owned))
(assert (= 150 (get-in purchase [:rows 0 :purchase-cost])))
(assert (= ["upgrade"] (get-in purchase [:rows 0 :ids])))
(def locked (run {:pool ["a" "b" "c"] :budget 300 :slots 2 :locked ["a"]} (search/replace-items definition ["a"])))
(assert (some |(= $ "a") (get-in locked [:rows 0 :ids])))
(assert (not (first (protect (run {:pool ["a"] :locked ["c"]} owned)))))
(assert ((builds/inspect-build [((pack :item-map) "earned")] {:owned ["earned"]}) :legal))
(assert (not ((builds/inspect-build [((pack :item-map) "earned")] {}) :legal)))
(def excluded (run {:pool ["a" "c"] :exclusions ["c"] :budget 1000 :slots 1}))
(assert (= ["a"] (get-in excluded [:rows 0 :ids])))
(var polls 0)
(def cancelled (run {:pool ["a" "b" "c"] :slots 2 :budget 1000} nil (fn [] (++ polls) (> polls 7))))
(assert (= :best-found (cancelled :guarantee)))
(assert (cancelled :cancelled))
(assert (not (cancelled :complete)))
(def limited (search/run pack definition {:pool ["a" "b" "c"] :slots 2 :budget 1000 :seconds 0.01}
                         (fn [p] nil) (fn [] false) (fn [c stop] (os/sleep 0.02) (fake c (fn [] false)))))
(assert (not (limited :complete)))
(assert (= :best-found (limited :guarantee)))
(def utility (search/score {:control 1 :healing 100 :absorbed 200} :utility 5))
(assert (= [1 100 200] utility))
# Complete-build search must escape misleading standalone scores. Compare its
# result with exact enumeration of the same synergy fixture and scoring rule.
(def synergy-items [(item "link-a" 100 0) (item "link-b" 100 0)
                    ;(map |(item (string "decoy-" $) 100 100) (range 0 8))])
(def synergy-pack (merge pack {:items synergy-items :item-map (tabseq [i :in synergy-items] (i :id) i)}))
(defn synergy-score [items]
  (+ (sum (map |($ :power) items))
     (if (and (some |(= "link-a" ($ :id)) items) (some |(= "link-b" ($ :id)) items)) 1000 0)))
(def synergy-reference (reference/exact-search synergy-items {:budget 400 :slots 4} synergy-score))
(def synergy-result
  (search/run synergy-pack definition {:budget 400 :slots 4 :seconds 2 :samples 1 :final-samples 1}
              (fn [p] nil) (fn [] false)
              (fn [candidate stop]
                (merge (fake definition (fn [] false))
                       {:metrics {:damage (synergy-score (search/inventory synergy-pack (get-in candidate [:player :loadout :items])))}}))))
(assert (= :heuristic (synergy-result :search)))
(assert (= (get-in synergy-reference [:best :score]) (get-in synergy-result [:rows 0 :metrics :damage])))
(each row (synergy-result :rows)
  (assert ((search/legal synergy-pack (row :ids) {:budget 400 :slots 4} "Test") :legal))
  (assert (= (tuple ;(sorted (row :ids))) (row :ids))))
# Retained shop metadata may require a buff/Feat, and trinkets have a separate
# slot. Neither may silently become an ordinary six-slot purchase.
(def unlocked (item "feat" 100 999 {:record {"mRequiredBuffCurrencyName" "PurchaseUnlock"}}))
(assert (not ((builds/inspect-build [unlocked] {}) :legal)))
(assert ((builds/inspect-build [unlocked] {:owned ["feat"]}) :legal))
(assert (not ((builds/inspect-build [(item "trinket" 0 0 {:tags ["Trinket"]})] {}) :legal)))
(assert (not ((builds/inspect-build [(item "hidden" 100 999 {:record {"mItemDataAvailability" {"mInStore" false}}})] {}) :legal)))
(def rune-pack {:runes (map (fn [style] {"id" style "slots" (map (fn [slot] {"runes" [{"id" (+ (* style 100) slot)} {"id" (+ (* style 100) slot 10)}]}) (range 0 4))}) [1 2 3])})
(each page (loadouts/initial-pages rune-pack) (assert (loadouts/legal-page? rune-pack page)))
(assert (not (loadouts/legal-page? rune-pack [100 101 102 103 201 201])))
(each page (loadouts/page-neighbors rune-pack [100 101 102 103 201 202] [0])
  (assert (= 100 (page 0))) (assert (loadouts/legal-page? rune-pack page)))
(each level [1 6 11 18]
  (assert (= 6 (length (loadouts/skill-orders level {}))))
  (each order (loadouts/skill-orders level {}) (skills/ranks-from-order order level)))
(def choices-pack (merge pack rune-pack
                         {:summoners [{"id" "a" "modes" ["CLASSIC"] "summonerLevel" 1}
                                      {"id" "b" "modes" ["CLASSIC"] "summonerLevel" 1}
                                      {"id" "other-map" "modes" ["ARAM"] "summonerLevel" 1}]}))
(var saw-order false)
(def choices (search/run choices-pack definition {:pool ["a"] :slots 1 :budget 100 :seconds 1 :runes true :summoners true :skills true :final-samples 1}
                         (fn [p] nil) (fn [] false)
                         (fn [candidate stop]
                           (assert (= (definition :target) (candidate :target)))
                           (assert (= (definition :seed) (candidate :seed)))
                           (assert (loadouts/legal-page? choices-pack (get-in candidate [:player :loadout :runes])))
                           (assert (some |(= $ (get-in candidate [:player :loadout :summoners])) [["a" "b"] ["b" "a"]]))
                           (when (get-in candidate [:player :skill-order]) (set saw-order true))
                           (fake candidate stop))))
(assert saw-order)
(each row (choices :rows) (assert (loadouts/legal-page? choices-pack (get-in row [:definition :player :loadout :runes]))))
# One real-engine reference verifies that this search does not have its own
# damage arithmetic. Reuse the external seed in an isolated data directory.
(packages/initialize "build/search-tests" "build/seed")
(def real (packages/load "16.19.1"))
(def actual (merge definition {:patch "16.19.1" :snapshot (real :snapshot)
                               :player {:champion "Annie" :level 1 :loadout {:items []}} :target {:kind :practice :hp 10000 :armor 80 :mr 80}}))
(def found (search/run real actual {:pool ["1052" "1036"] :slots 1 :budget 1000 :samples 1 :final-samples 1 :seconds 5}
                       (fn [p] nil) (fn [] false)))
(assert (found :complete))
(assert (= ["1052"] (get-in found [:rows 0 :ids])))
(print "Scenario searches match exhaustive scores; legality, locks, recipes, independent metrics, common seeds, cancellation, deadlines and legal loadout choices passed.")
