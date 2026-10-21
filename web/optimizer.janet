(import ./catalog :as catalog)
(import ./details :as details)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/loadouts :as loadouts)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/runes :as rune-data)
(def defaults {:searchjob "" :searchwho "player" :searchbudget 10000 :searchslots 6 :searchseconds 5 :searchpreset "burst"
               :searchpool "" :searchexclude "" :nextpurchase false :searchrunes false :searchsummoners false :searchskills false})
(defn number [value] (if (number? value) (string/format "%.1f" value) "—"))
(defn checkbox [name caption]
  [:label [:input {:type "checkbox" :data-bind name}] caption])
(defn item-controls [result]
  [:section {:id "optimizer" :class "optimizer"}
   [:div {:class "tactics-grid"}
    [:label "Gold budget" [:input {:type "number" :min 0 :max 100000 :step 1 :name "searchbudget" :data-bind:searchbudget true}]]
    [:label "Optimize for" [:select {:name "searchpreset" :data-bind:searchpreset true}
                            [:option {:value "burst"} "Damage dealt"] [:option {:value "duel"} "Duel outcome"]
                            [:option {:value "survival"} "Survival"] [:option {:value "sustained"} "Damage per second"]
                            [:option {:value "utility"} "Control, healing & shields"]]]]
   [:h3 "Keep items"]
   [:div {:class "matchup-item-locks"}
    (seq [index :range [1 7]]
      [:label {:class "matchup-item-lock" :data-lock-slot index}
       [:span {:class "matchup-lock-icon"} "—"]
       [:span [:input {:type "checkbox" :name (string "lockslot" index) :data-bind (string "lockslot" index)}] " Keep"]])]
   [:details {:class "optimizer-advanced" :data-preserve-attr "open"} [:summary "Advanced item search options"]
    [:div {:class "tactics-grid"}
     [:label "Inventory slots" [:input {:type "number" :min 0 :max 6 :name "searchslots" :data-bind:searchslots true}]]
     [:label "Compute budget" [:select {:name "searchseconds" :data-bind:searchseconds true} [:option {:value 5} "5 seconds"] [:option {:value 30} "30 seconds"]]]
     (checkbox "nextpurchase" "Next purchase")]
    [:label "Candidate items (names or IDs; blank uses the shop)" [:input {:type "text" :name "searchpool" :data-bind:searchpool true}]]
    [:label "Exclude items (names or IDs)" [:input {:type "text" :name "searchexclude" :data-bind:searchexclude true}]]]])
(defn legacy-controls [result]
  (def order (get-in result [:state :skillorder]))
  [:section {:id "optimizer" :class "optimizer"}
   [:p {:class "muted" :data-text "'Fight: ' + $duration + ' seconds' + ($mode === 'practice' ? ' · ' + $targethealth + ' target HP · ' + $armor + ' armor / ' + $mr + ' MR' : '')"}
    "Uses the current combat window and target settings."]
   [:p {:class "muted" :data-show "$searchpreset === 'burst'"}
    "Burst scores total damage from spells, attacks and item effects during this window. Target health affects percentage-health damage."]
   [:div {:class "tactics-grid"}
    [:label "Search gold budget" [:input {:type "number" :min 0 :max 100000 :step 1 :data-bind:searchbudget true}]]
    [:label "Inventory slots" [:input {:type "number" :min 0 :max 6 :step 1 :data-bind:searchslots true}]]
    [:label "Scoring" [:select {:data-bind:searchpreset true}
                       (map |[:option {:value (string $)} (string $)] search/presets)]]
    [:label "Compute budget" [:select {:data-bind:searchseconds true} [:option {:value 5} "5 seconds"] [:option {:value 30} "30 seconds"]]]]
   [:details {:class "optimizer-advanced" :data-preserve-attr "open"} [:summary "Options, locks & candidate items"]
    [:div {:class "tactics-grid"}
     (checkbox "nextpurchase" "Recommend one next purchase (budget is gold available now)")
     (checkbox "searchrunes" "Search rune pages") (checkbox "searchsummoners" "Search summoner spells") (checkbox "searchskills" "Search skill orders")]
    [:p {:class "muted"} "Lock owned items to retain them. Other slots may be replaced. Next-purchase search keeps runes, summoners and skills fixed."]
    [:div {:class "tactics-grid"} (seq [index :range [1 7]] (checkbox (string "lockslot" index) (string "Keep item in slot " index)))]
    [:label "Candidate items (comma-separated names or IDs; blank uses the full shop)" [:input {:type "text" :data-bind:searchpool true :placeholder "Rabadon's Deathcap, Void Staff, Sorcerer's Shoes"}]]
    [:label "Exclude items (comma-separated names or IDs)" [:input {:type "text" :data-bind:searchexclude true}]]
    [:div {:class "tactics-grid"} (seq [index :range [1 7]] (checkbox (string "lockrune" index) (string "Keep rune " index)))
     (checkbox "locksummoner1" "Keep summoner D") (checkbox "locksummoner2" "Keep summoner F")]
    [:details [:summary "Keep skill choices at specific levels"]
     [:p {:class "muted"} "Locks preserve this champion's skill order at those levels. Rank settings remain fixed when skill-order search is off."]
     [:div {:class "tactics-grid"}
      (seq [index :range [1 19]]
        [:span {:data-show (string "$level >= " index)}
         (checkbox (string "lockskill" index)
                   [:span {:data-text (string "'Level " index " · ' + ($skillorder.split(',')[" (dec index) "] || '').trim().toUpperCase()")}
                    (string "Level " index " · " (string/ascii-upper (string (get order (dec index) ""))))])])]]]
   [:p {:class "muted"} "Builds are compared in the same simulated fight. Your opponent and fight strategy stay fixed."]])
(defn controls [result] (if (= "duel" (get-in result [:state :mode])) (item-controls result) (legacy-controls result)))
(defn panel-body [result job &opt applied]
  (def ongoing (and job (some |(= $ (job :status)) [:queued :running :cancelling])))
  (def outcome (get job :result))
  (def progress (get job :progress {}))
  (def rows (or (get outcome :rows) (get progress :best) []))
  (def package (result :package))
  [:section {:id "search-panel" :class "scope-panel search-panel" :data-poll (if ongoing "true" "false")
             :data-job (get job :id "") :data-status (get job :status :idle) :data-applied applied :aria-live "polite"
             :data-search-who (get job :search-who "player")}
   (unless job [:div {:class "search-empty"} [:h2 "Find your next build"] [:p "Choose a budget and run a search to compare simulated outcomes."]])
   (when job
     [:div
      [:div {:class "search-summary"}
       [:h2 "Recommendations · " (if (get outcome :complete) "Optimal within selected pool" "Best found")]
       [:p (string (job :status) " · " (get progress :message "Queued") " · " (get outcome :evaluated (get progress :completed 0))
                   " builds evaluated · " (number (get outcome :seconds (get progress :seconds 0))) " s")]
       [:p {:class "muted"} (if (job :next-purchase) "Available gold: " "Gold limit: ") (get job :gold-budget "—")
        (when (not (empty? rows)) (string " · Top " (length rows) " builds · ranked by " (get outcome :preset (get progress :preset :burst))))]
       [:p {:class "muted search-cache"}
        (when (> (get outcome :cache-hits (get progress :cache-hits 0)) 0)
          (string (get outcome :cache-hits (get progress :cache-hits 0)) " results reused · " (get outcome :simulated (get progress :simulated 0)) " new simulations"))]
       [:div {:class "search-progress-row"}
        [:progress {:class "search-time" :hidden (not ongoing) :aria-label "Search compute time" :max (get job :limit 5)
                    :value (min (get job :limit 5) (get progress :seconds 0))}]
        (when ongoing [:button {:type "button" :data-on:click (string "@post('/jobs/cancel?id=" (job :id) "')")} "Cancel search"])]]
      (when (= :failed (job :status)) [:p {:class "warning"} (job :error)])
      (when (and outcome (empty? rows)) [:p "No recommendation fits these constraints. Increase the budget, relax locks or change the item pool."])
      [:details {:class "search-method"} [:summary "Search settings & simulation details"]
       (when (job :scenario-summary) [:p {:class "muted"} (job :scenario-summary)])
       [:p (or (get outcome :explanation) (get progress :explanation) "Waiting for the simulation worker.")]
       (when (get outcome :baseline)
         [:p {:class "muted"} "Current inventory: " (number (get-in outcome [:baseline :metrics :damage])) " damage · "
          (number (get-in outcome [:baseline :metrics :health])) " health left · " (get-in outcome [:baseline :samples]) " trials"])
       (when outcome [:ul (map |[:li $] (details/simulation-notes (outcome :notes)))])]
      [:div {:class "search-alternatives" :role "list" :aria-label "Builds ranked best to worst"}
       (seq [[index row] :pairs rows]
         (def context (details/scenario-context (get row :definition {})))
         [:article {:class "search-alternative" :role "listitem"}
          [:span {:class "search-rank" :aria-label (string "Rank " (inc index))} (inc index)]
          [:div {:class "search-loadout"}
           [:h3 (if (empty? (row :ids)) "No items" (string "Build " (inc index)))
            [:span {:class "gold-number"} (number (row :cost)) " gold"]]
           [:div {:class "inventory" :aria-label (string "Build " (inc index) " items")}
            (map (fn [id]
                   (def item ((package :item-map) id))
                   [:button (merge {:type "button" :class "search-item" :aria-label (string (get item :name id) " details")}
                                   (when item (details/attrs (merge (details/item item context) {:action nil :action-label nil}) true)))
                    [:img {:src (string "/assets/" (get-in row [:definition :patch]) "/" (get-in row [:definition :snapshot]) "/item/" id ".png")
                           :alt (get item :name id) :width 40 :height 40 :loading "lazy"}]]) (row :ids))]
           (when (row :purchase) [:p {:class "muted"} (string "Next purchase: " (get ((package :item-map) (row :purchase)) :name (row :purchase))
                                                              " · " (number (row :purchase-cost)) " gold now")])]
          [:dl {:class "search-metrics"}
           (map (fn [[field caption]] [:div [:dt caption] [:dd (number (get (row :metrics) field))]])
                [[:damage "Damage"] [:health "Health left"] [:win-rate "Win probability"]])]
          [:button {:class "apply" :type "button" :disabled ongoing :data-apply-build (get job :search-who "player")
                    :data-on:click (string "@post('/search/apply?id=" (job :id) "&key=" (row :key) "')")}
           (if (= "duel" (get-in result [:state :mode])) "Apply items" "Apply & inspect")]
          [:details {:class "search-build-details"} [:summary "Build & simulation details"]
           (when (get outcome :baseline)
             [:table {:class "search-comparison"}
              [:thead [:tr [:th ""] [:th "Current"] [:th "Proposed"]]]
              [:tbody
               [:tr [:th "Gold"] [:td (number (get-in outcome [:baseline :cost]))] [:td (number (row :cost))]]
               (map (fn [[field caption]] [:tr [:th caption] [:td (number (get-in outcome [:baseline :metrics field]))] [:td (number (get-in row [:metrics field]))]])
                    [[:damage "Damage"] [:health "Health left"] [:win-rate "Win probability"]])]])

           [:dl {:class "search-metrics"}
            (map (fn [[field caption]] [:div [:dt caption] [:dd (number (get (row :metrics) field))]])
                 [[:control "Control (s)"] [:healing "Healing"] [:absorbed "Absorbed"]])]
           [:p {:class "muted"} (row :samples) " trials · damage interval ±" (number (get-in row [:uncertainty :damage]))]
           [:p "Runes: " (string/join (map (fn [id] (def rune (find |(= id (get $ "id")) (scenario/runes package))) (get rune "name" (string id)))
                                           (get-in row [:definition :player :loadout :runes] [])) ", ")]
           [:p "Summoners: " (string/join (map (fn [id] (get (find |(= id (get $ "id")) (get package :summoners [])) "name" id))
                                               (get-in row [:definition :player :loadout :summoners] [])) ", ")]
           [:p "Stat shards: " (string/join (map |(get rune-data/shard-names $ "None") (get-in row [:definition :player :loadout :shards] [])) ", ")]
           [:p "Skill order: " (if (get-in row [:definition :player :skill-order])
                                 (string/join (map |(string/ascii-upper (string $)) (get-in row [:definition :player :skill-order])) " → ")
                                 "Current rank settings")]
           (when (not (empty? (details/simulation-notes (row :coverage))))
             [:div [:p "Effects not included & inventory rules"]
              [:ul (map |[:li $] (details/simulation-notes (row :coverage)))]])]])]
      [:span {:data-init (string "$searchjob = '" (job :id) "'")}]])])
(defn panel [result job &opt applied]
  (with-dyns [:patch-package (result :package)] (panel-body result job applied)))
(defn error-panel [message]
  [:section {:id "search-panel" :class "scope-panel search-panel" :data-poll "false" :data-job "" :data-status "failed" :data-error "true"}
   [:p {:class "warning" :role "alert"} message]
   [:span {:data-init "$searchjob = ''"}]])
(defn dialog [result]
  [:dialog {:id "optimizer-dialog" :class "optimizer-dialog" :aria-labelledby "optimizer-title" :aria-describedby "optimizer-description"
            :data-on:searchtick "@get('/search/status')"}
   [:header {:class "picker-header"}
    [:div [:h2 {:id "optimizer-title" :tabindex "-1"} (if (= "duel" (get-in result [:state :mode])) "Optimize items" "Optimize build")]
     [:p {:id "optimizer-description" :class "muted"} (if (= "duel" (get-in result [:state :mode])) "Opponent build fixed" "Compare builds for your current opponent and fight strategy.")]]
    [:button {:type "button" :class "catalog-close" :data-search-close true :aria-label "Close optimization"} "Close"]]
   [:div {:class "optimizer-body"} (controls result) (panel result nil)]
   [:div {:class "optimizer-actions"}
    [:p {:id "search-request-status" :role "status" :hidden true} "Starting search…"]
    [:button {:id "search-start" :type "button" :class "optimize-primary" :data-search-start true
              :data-on:click "@post('/search', {retry: 'never'})"} "Run search"]]])
(defn rune-editor [package state]
  [:details {:id "rune-editor" :class "scope-panel" :data-preserve-attr "open" :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
   [:summary "Rune pages"]
   [:p {:class "muted"} "A full page has four primary and two secondary runes. Leave slots empty for a partial estimate. Shards stay fixed during optimization. Tenacity and slow-resist shards are not yet supported."]
   (map (fn [opponent]
          (def prefix (if opponent "enemy" ""))
          (def chosen (get state (if opponent :opponentrunes :runes) []))
          [:section {:data-show (if opponent "$mode === 'duel'" "true")}
           [:h3 (if opponent "Opponent runes" "Player runes")]
           [:p (if (empty? chosen) "No rune effects" (if (loadouts/legal-page? package chosen) "Legal rune page" "Partial or incompatible page; effects estimated individually"))]
           [:div {:class "tactics-grid"}
            (seq [index :range [0 6]]
              [:label (get ["Primary keystone" "Primary slot 1" "Primary slot 2" "Primary slot 3" "Secondary rune 1" "Secondary rune 2"] index)
               [:select {:form "scenario" :name (string prefix "runepage" (inc index))
                         :data-bind (string prefix "runepage" (inc index))}
                [:option {:value ""} "None"]
                (mapcat (fn [style]
                          (mapcat (fn [slot slot-index]
                                    (map (fn [rune] [:option {:value (rune "id") :selected (= (rune "id") (get chosen index))}
                                                     (string (style "name") " · slot " slot-index " · " (rune "name"))]) (slot "runes")))
                                  (get style "slots" []) (range 0 (length (get style "slots" []))))) (get package :runes []))]])]
           [:h4 "Stat shards"]
           [:div {:class "tactics-grid"}
            (seq [index :range [0 3]]
              [:label (get ["Offense" "Flex" "Defense"] index)
               [:select {:form "scenario" :name (string prefix "shard" (inc index)) :data-bind (string prefix "shard" (inc index))}
                [:option {:value 0} "None"]
                (seq [id :in (rune-data/shard-rows index) :when (some |(= id ($ :id)) (rune-data/shards package))]
                  [:option {:value id :selected (= id (get (get state (if opponent :opponentshards :shards) []) index 0))}
                   (rune-data/shard-names id)])]])
            [:label "Adaptive force"
             [:select {:form "scenario" :name (if opponent "opponentadaptivestat" "adaptivestat") :data-bind (if opponent "opponentadaptivestat" "adaptivestat")}
              (map (fn [[value caption]] [:option {:value value :selected (= value (get state (if opponent :opponentadaptivestat :adaptivestat) "auto"))} caption])
                   [["auto" "Automatic from build"] ["ad" "Attack damage"] ["ap" "Ability power"]])]]]]) [false true])])
