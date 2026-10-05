(import ./catalog :as catalog)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/loadouts :as loadouts)
(import ../src/powerspike/scenario :as scenario)
(def defaults {:searchjob "" :searchbudget 10000 :searchslots 6 :searchseconds 5 :searchpreset "burst"
               :searchpool "" :searchexclude "" :nextpurchase false :searchrunes false :searchsummoners false :searchskills false})
(defn number [value] (if (number? value) (string/format "%.1f" value) "—"))
(defn checkbox [name caption]
  [:label [:input {:type "checkbox" :data-bind name}] caption])
(defn controls [&opt result]
  (def order (or (get-in result [:state :skillorder]) scenario/default-order))
  [:section {:id "optimizer" :class "scope-panel optimizer"}
   [:h2 "Optimize build"]
   [:div {:class "tactics-grid"}
    [:label "Gold budget" [:input {:type "number" :min 0 :max 100000 :step 50 :data-bind:searchbudget true}]]
    [:label "Inventory slots" [:input {:type "number" :min 0 :max 6 :step 1 :data-bind:searchslots true}]]
    [:label "Scoring" [:select {:data-bind:searchpreset true}
                       (map |[:option {:value (string $)} (string $)] search/presets)]]
    [:label "Compute budget" [:select {:data-bind:searchseconds true} [:option {:value 5} "5 seconds"] [:option {:value 30} "30 seconds"]]]]
   [:div {:class "tactics-grid"}
    (checkbox "nextpurchase" "Recommend one next purchase (budget is gold available now)")
    (checkbox "searchrunes" "Search rune pages") (checkbox "searchsummoners" "Search summoner spells") (checkbox "searchskills" "Search skill orders")]
   [:details [:summary "Locks & candidate items"]
    [:p {:class "muted"} "Lock owned items to retain them. Other slots may be replaced. Next-purchase search keeps runes, summoners and skills fixed."]
    [:div {:class "tactics-grid"} (seq [index :range [1 7]] (checkbox (string "lockslot" index) (string "Keep item in slot " index)))]
    [:label "Candidate items (comma-separated names or IDs; blank uses the full shop)" [:input {:type "text" :data-bind:searchpool true :placeholder "Rabadon's Deathcap, Void Staff, Sorcerer's Shoes"}]]
    [:label "Exclude items (comma-separated names or IDs)" [:input {:type "text" :data-bind:searchexclude true}]]
    [:div {:class "tactics-grid"} (seq [index :range [1 7]] (checkbox (string "lockrune" index) (string "Keep rune " index)))
     (checkbox "locksummoner1" "Keep summoner D") (checkbox "locksummoner2" "Keep summoner F")]
    [:details [:summary "Keep skill choices at specific levels"]
     [:p {:class "muted"} "Locks preserve the displayed standard order at those levels. Rank settings remain fixed when skill-order search is off."]
     [:div {:class "tactics-grid"}
      (seq [index :range [1 19]]
        [:span {:data-show (string "$level >= " index)}
         (checkbox (string "lockskill" index)
                   [:span {:data-text (string "'Level " index " · ' + ($skillorder.length > " (dec index) " ? $skillorder[" (dec index) "].toUpperCase() : '"
                                              (string/ascii-upper (string (scenario/default-order (dec index)))) "')")}
                    (string "Level " index " · " (string/ascii-upper (string (get order (dec index) :q))))])])]]]
   [:p {:class "muted"} "Your opponent and fight strategy stay fixed. Missing effects may change the ranking; recommendations include their coverage."]
   [:button {:class "apply" :type "button" :data-on:click "@post('/search')"} "Find builds"]])
(defn comparison-chart [rows field caption &opt cost]
  (def values (map |(if cost ($ :cost) (get-in $ [:metrics field])) rows))
  (def ceiling (max ;[1 ;(filter number? values)]))
  [:figure {:class "comparison-chart"}
   [:figcaption caption]
   [:svg {:viewBox "0 0 640 170" :role "img" :aria-label (string caption " across recommended builds")}
    (seq [[index value] :pairs values]
      [:g
       [:text {:x 4 :y (+ 23 (* index 30)) :class "chart-label"} (string "Build " (inc index))]
       (when (number? value) [:rect {:x 72 :y (+ 8 (* index 30)) :width (* 430 (/ value ceiling)) :height 19 :fill "#b49a5d"}])
       [:text {:x 520 :y (+ 23 (* index 30)) :class "chart-label"} (number value)]])]])
(defn panel [result job]
  (def ongoing (and job (some |(= $ (job :status)) [:queued :running :cancelling])))
  (def outcome (get job :result))
  (def progress (get job :progress {}))
  (def rows (or (get outcome :rows) (get progress :best) []))
  (def package (result :package))
  [:section {:id "search-panel" :class "scope-panel search-panel" :data-poll (if ongoing "true" "false") :aria-live "polite"}
   (when job
     [:div
      [:h2 "Recommendations · " (if (get outcome :complete) "Optimal within selected pool" "Best found")]
      [:p (string (job :status) " · " (get progress :message "Queued") " · " (get outcome :evaluated (get progress :completed 0))
                  " builds evaluated · " (number (get outcome :seconds (get progress :seconds 0))) " s")]
      [:p (or (get outcome :explanation) (get progress :explanation) "Waiting for the simulation worker.")]
      (when ongoing [:button {:type "button" :data-on:click (string "@post('/jobs/cancel?id=" (job :id) "')")} "Cancel search"])
      (when (= :failed (job :status)) [:p {:class "warning"} (job :error)])
      (when (and outcome (empty? rows)) [:p "No recommendation fits these constraints. Increase the budget, relax locks or change the item pool."])
      (when (not (empty? rows))
        [:div {:class "comparison-charts"}
         (comparison-chart rows :damage "Damage") (comparison-chart rows :health "Health remaining")
         (comparison-chart rows :control "Effective control (seconds)") (comparison-chart rows nil "Gold cost" true)])
      [:p {:class "muted"} "Alternatives include scoring leaders and cost, health or control tradeoffs found during this search. Each chart has its own scale."]
      (when outcome [:details [:summary "Search limits & coverage"] [:ul (map |[:li $] (outcome :notes))]])
      [:div {:class "search-alternatives"}
       (seq [[index row] :pairs rows]
         [:article {:class "search-alternative"}
          [:h3 (string "Build " (inc index) " · " (number (row :cost)) " gold")]
          [:div {:class "inventory"}
           (map (fn [id]
                  (def item ((package :item-map) id))
                  [:img {:src (string "/assets/" (get-in row [:definition :patch]) "/" (get-in row [:definition :snapshot]) "/item/" id ".png")
                         :alt (get item :name id) :title (get item :name id) :width 48 :height 48 :loading "lazy"}]) (row :ids))]
          (when (row :purchase) [:p (string "Next purchase: " (get ((package :item-map) (row :purchase)) :name (row :purchase))
                                            " · " (number (row :purchase-cost)) " gold now")])
          [:dl {:class "search-metrics"}
           (map (fn [[field caption]] [:div [:dt caption] [:dd (number (get (row :metrics) field))]])
                [[:damage "Damage"] [:health "Health left"] [:win-rate "Win probability"] [:control "Control (s)"] [:healing "Healing"] [:absorbed "Absorbed"]])]
          [:p {:class "muted"} (row :samples) " trials · damage interval ±" (number (get-in row [:uncertainty :damage]))]
          [:details [:summary "Runes, summoners & skill order"]
           [:p "Runes: " (string/join (map (fn [id] (def rune (find |(= id (get $ "id")) (scenario/runes package))) (get rune "name" (string id)))
                                           (get-in row [:definition :player :loadout :runes] [])) ", ")]
           [:p "Summoners: " (string/join (map (fn [id] (get (find |(= id (get $ "id")) (get package :summoners [])) "name" id))
                                               (get-in row [:definition :player :loadout :summoners] [])) ", ")]
           [:p "Skill order: " (if (get-in row [:definition :player :skill-order])
                                 (string/join (map |(string/ascii-upper (string $)) (get-in row [:definition :player :skill-order])) " → ")
                                 "Current rank settings")]]
          [:details [:summary (string (length (row :coverage)) " coverage notes")]
           [:ul (map |[:li $] (row :coverage))]]
          (unless ongoing [:button {:class "apply" :type "button" :data-on:click (string "@post('/search/apply?id=" (job :id) "&key=" (row :key) "')")}
                           "Apply & inspect"])])]
      [:span {:data-init (string "$searchjob = '" (job :id) "'")}]])])
(defn rune-editor [package state]
  [:details {:id "rune-editor" :class "scope-panel" :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
   [:summary "Rune pages"]
   [:p {:class "muted"} "A full page has a primary keystone and one rune from each primary slot, plus two different secondary slots. Leave slots empty for a partial effect estimate. Stat shards are not modeled."]
   (map (fn [opponent]
          (def prefix (if opponent "enemy" ""))
          (def chosen (get state (if opponent :opponentrunes :runes) []))
          [:section {:data-show (if opponent "$mode === 'duel'" "true")}
           [:h3 (if opponent "Opponent runes" "Player runes")]
           [:p (if (empty? chosen) "No rune effects" (if (loadouts/legal-page? package chosen) "Legal rune page" "Partial or incompatible page; effects estimated individually"))]
           [:div {:class "tactics-grid"}
            (seq [index :range [0 6]]
              [:label (get ["Primary keystone" "Primary slot 1" "Primary slot 2" "Primary slot 3" "Secondary rune 1" "Secondary rune 2"] index)
               [:select {:data-bind (string prefix "runepage" (inc index))}
                [:option {:value ""} "None"]
                (mapcat (fn [style]
                          (mapcat (fn [slot slot-index]
                                    (map (fn [rune] [:option {:value (rune "id") :selected (= (rune "id") (get chosen index))}
                                                     (string (style "name") " · slot " slot-index " · " (rune "name"))]) (slot "runes")))
                                  (get style "slots" []) (range 0 (length (get style "slots" []))))) (get package :runes []))]])]]) [false true])])
