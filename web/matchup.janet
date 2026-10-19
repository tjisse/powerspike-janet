(import jayson :as json)
(import ./catalog :as catalog)
(import ./model :as model)
(import ./details :as details)
(import ../src/powerspike/scenario :as scenarios)
(import ../src/powerspike/runes :as rune-data)

(defn text-number [n] (string/format "%.0f" (or n 0)))
(defn icon [package group id name]
  [:img {:src (string "/assets/" (package :patch) "/" (package :snapshot) "/" group "/" id
                      (if (string/has-suffix? ".png" id) "" ".png")) :alt name :width 64 :height 64 :loading "lazy"}])
(defn input [name caption value minimum maximum &opt step]
  [:label caption [:input {:form "scenario" :name name :data-bind name :type "number" :value value
                           :min minimum :max maximum :step (or step 1) :required true}]])
(defn select-field [name caption value choices &opt native-name]
  [:label caption [:select {:form "scenario" :name (or native-name name) :data-bind name}
                   (map (fn [[id caption]] [:option {:value id :selected (= (string id) (string value))} caption]) choices)]])
(defn checkbox [name caption value]
  [:label {:class "matchup-check"} [:input {:form "scenario" :name name :data-bind name :type "checkbox" :checked value}] caption])
(defn ids [result opponent]
  (if opponent (map |(get (result :state) $ "") model/enemy-slot-keys)
    (if (= "custom" (get-in result [:selected :id])) (map |(get (result :state) $ "") model/slot-keys)
      (seq [index :range [0 6]] (get-in result [:selected :ids index] "")))))
(defn inventory [result opponent]
  (def package (result :package))
  (def state (result :state))
  (def chosen (ids result opponent))
  (def who (if opponent "opponent" "player"))
  [:div {:class "inventory" :aria-label "Six editable inventory slots"}
   (seq [[index id] :pairs chosen]
     (def item ((package :item-map) id))
     [:button (merge {:type "button" :class (if item "item-slot" "item-slot empty-slot") :data-item-id id
                      :aria-label (string "Edit slot " (inc index) ": " (if item (item :name) "empty"))
                      :data-on:click (string "$editingwho = '" who "'; $editing = " (inc index) "; document.getElementById('item-picker').showModal()")}
                     (if item (details/attrs (details/item item (get-in result [:selected (if opponent :opponent-tooltip-context :tooltip-context)]))) {}))
      (if item (icon package "item" (item :icon) (item :name)) "+")])])
(defn rune-fields [result opponent]
  (def state (result :state))
  (def package (result :package))
  (def prefix (if opponent "enemy" ""))
  (def chosen (get state (if opponent :opponentrunes :runes) []))
  [:div {:class "matchup-fields"}
   (seq [index :range [0 6]]
     (select-field (string prefix "runepage" (inc index))
                   (get ["Keystone" "Primary slot 1" "Primary slot 2" "Primary slot 3" "Secondary rune 1" "Secondary rune 2"] index)
                   (get chosen index "")
                   [["" "None"] ;(map |[(get $ "id") (get $ "name")] (scenarios/runes package))]))
   (seq [index :range [0 3]]
     (select-field (string prefix "shard" (inc index)) (get ["Offense shard" "Flex shard" "Defense shard"] index)
                   (get (get state (if opponent :opponentshards :shards) []) index 0)
                   [[0 "None"] ;(seq [id :in (rune-data/shard-rows index) :when (some |(= id ($ :id)) (rune-data/shards package))]
                                  [id (rune-data/shard-names id)])]))
   (select-field (if opponent "opponentadaptivestat" "adaptivestat") "Adaptive force"
                 (get state (if opponent :opponentadaptivestat :adaptivestat) "auto")
                 [["auto" "Automatic"] ["ad" "Attack damage"] ["ap" "Ability power"]])
   (seq [index :range [0 2]]
     (select-field (string (if opponent "opponentsummoner" "summoner") (inc index)) (if (= index 0) "Summoner D" "Summoner F")
                   (get (get state (if opponent :opponentsummoners :summoners) []) index "")
                   [["" "None"] ;(map |[(get $ "id") (get $ "name")]
                                      (filter |(some (fn [mode] (= mode "CLASSIC")) (get $ "modes" [])) (get package :summoners [])))]))])
(defn ability-fields [result opponent]
  (def state (result :state))
  (def prefix (if opponent "enemy" ""))
  (def stat-prefix (if opponent "opponent" ""))
  (def actor (when opponent (get-in result [:selected :opponent])))
  (def champion (if opponent (get-in result [:package :champion-map (state :opponent)]) (result :champion)))
  (def settings (if opponent (model/ability-settings champion (actor :stats) (actor :level) (actor :ranks)
                                                     (get-in result [:selected :opponent-tooltip-context]))
                  (get-in result [:selected :ability-settings])))
  [:div
   [:label "Skill order" [:input {:type "text" :form "scenario" :name (string stat-prefix "skillorder") :data-bind (string stat-prefix "skillorder")
                                  :required true :value (string/join (map string (state (keyword (string stat-prefix "skillorder")))) ",")
                                  :aria-label (if opponent "Opponent skill order" "Player skill order")}]]
   [:div {:class "matchup-abilities" :id (if opponent "opponent-ranks" "ranks")}
    (map (fn [ability]
           [:button (merge {:type "button" :class "spell" :data-ability-slot (ability :slot) :data-rank (ability :rank)
                            :data-unlocked (if (> (ability :rank) 0) "true" "false")}
                           (details/attrs (details/ability ability) true))
            (icon (result :package) (ability :icon-group) (ability :icon) (ability :name))
            [:span (string/ascii-upper (string (ability :slot))) " · " (ability :rank)]]) settings)]
   [:details {:class "matchup-activation"} [:summary "Ranks & activation rules"]
    [:div {:class "ability-controls"}
     (map (fn [slot]
            (def base (string prefix slot))
            [:article [:strong (string/ascii-upper (string slot))]
             (when (some |(= slot $) [:q :w :e :r])
               (select-field (string base "rank") "Rank" (get state (keyword (string base "rank")) -1)
                             [[-1 "Automatic"] ;(map |[$ (string $)] (range 0 (if (= slot :r) 4 6)))]))
             (input (string base "after") "Cast after (s)" (get state (keyword (string base "after")) 0) 0 120 0.1)
             (input (string base "selfbelow") "Self health below (0–1)" (get state (keyword (string base "selfbelow")) 1) 0 1 0.05)
             (input (string base "targetbelow") "Target health below (0–1)" (get state (keyword (string base "targetbelow")) 1) 0 1 0.05)]) scenarios/slots)]]])
(defn sequence-fields [result opponent]
  (def state (result :state))
  (def prefix (if opponent "opponent" ""))
  [:div
   [:label "Ability priority" [:input {:type "text" :form "scenario" :name (string prefix "priority") :data-bind (string prefix "priority")
                                       :value (string/join (map string (get state (keyword (string prefix "priority")) scenarios/slots)) ",")}]]
   [:div {:class "matchup-fields"}
    (checkbox (string prefix "attacks") "Basic attacks" (get state (keyword (string prefix "attacks")) true))
    (checkbox (string prefix "abilities") "Abilities" (get state (keyword (string prefix "abilities")) true))]])
(defn champion-settings [result opponent]
  (def state (result :state))
  (def prefix (if opponent "opponent" ""))
  [:details {:class "matchup-champion-settings" :id (if opponent "opponent-advanced" "player-advanced") :data-preserve-attr "open"}
   [:summary "Advanced champion settings"]
   [:div {:class "matchup-fields"}
    (input (string prefix "healthfraction") "Starting health (0–1)" (get state (if opponent :opponent-health-fraction :health-fraction) 1) 0.01 1 0.01)
    (input (string prefix "resourcefraction") "Starting resource (0–1)" (get state (if opponent :opponent-resource-fraction :resource-fraction) 1) 0 1 0.05)
    (select-field (string prefix "movement") "Movement" (get state (keyword (string prefix "movement")) "approach")
                  [["approach" "Approach into range"] ["hold" "Hold position"] ["hold-range" "Keep preferred range"]])
    (input (string prefix "preferredrange") "Preferred distance" (get state (keyword (string prefix "preferredrange")) 500) 0 10000)
    (input (string prefix "hitchance") "Hit chance (0–1)" (get state (if opponent :opponent-hit-chance :hit-chance) 1) 0 1 0.05)]])
(defn champion-card [result opponent]
  (def state (result :state))
  (def package (result :package))
  (def who (if opponent "opponent" "player"))
  (def champion (if opponent ((package :champion-map) (state :opponent)) (result :champion)))
  (def totals (get-in result [:selected (if opponent :opponent :stats)]))
  (def stats (if opponent (totals :stats) totals))
  (def chosen (ids result opponent))
  (def cost (sum (map |(get-in package [:item-map $ :gold] 0) chosen)))
  [:article {:id (string who "-card") :class "matchup-card" :data-who who :data-name (champion :name) :data-items (json/encode chosen)}
   [:header {:class "matchup-card-header"}
    [:span {:class "matchup-role"} [:i {:class (string "matchup-dot " who)}] (if opponent "Opponent" "Your champion")]
    [:div {:class "matchup-identity"}
     [:button {:type "button" :class "matchup-champion" :aria-label (if opponent "Select opponent" "Select champion")
               :data-on:click (string "$editingwho = '" who "'; document.getElementById('champion-picker').showModal()")}
      (icon package "champion" (champion :icon) (champion :name)) [:h1 (champion :name)] [:span {:class "matchup-caret"} "⌄"]]
     (select-field (if opponent "opponentlevel" "level") "Level" (state (if opponent :opponentlevel :level)) (map |[$ (string $)] (range 1 19)))]
    [:label {:class "native-only"} (if opponent "Opponent" "Champion")
     [:select {:form "scenario" :name (if opponent "opponent" "champion") :data-bind (if opponent "opponent" "champion")}
      (map |[:option {:value ($ :id) :selected (= ($ :id) (champion :id))} ($ :name)] (catalog/champion-list))]]
    [:div {:class "matchup-card-summary"}
     [:div {:class "matchup-stats"}
      (map (fn [[key caption]] [:span caption " " [:strong (text-number (get stats key 0))]]) [[:hp "HP"] [:armor "Armor"] [:mr "MR"]])
      [:button (merge {:type "button" :class "quiet-action" :aria-label (string (champion :name) " stats")}
                      (details/attrs {:name (champion :name) :stats (details/stat-rows stats) :body [] :coverage "Modeled stats; see coverage."} true)) "Details"]]
     [:button {:type "button" :class "matchup-collapse js-only" :data-collapse who :aria-controls (string who "-loadout") :aria-expanded "true"} "Collapse −"]]
    [:div {:class "matchup-mini" :aria-label "Inventory summary"}
     (map (fn [id] (if (= id "") [:span {:class "mini-empty"}] (icon package "item" id (get-in package [:item-map id :name] id)))) chosen)
     [:span {:class "muted"} (text-number cost) " gold"]]]
   [:div {:id (string who "-loadout") :class "matchup-loadout"}
    [:div {:class "matchup-tabs" :role "tablist" :aria-label (string (champion :name) " customization")}
     (map (fn [[tab caption]] [:button {:type "button" :role "tab" :id (string who "-tab-" tab) :aria-controls (string who "-panel-" tab)
                                        :aria-selected (if (= tab "items") "true" "false") :data-tab tab :data-who who} caption])
          [["items" "Items"] ["runes" "Runes & spells"] ["abilities" "Abilities"] ["sequence" "Sequence"]])]
    [:section {:id (string who "-panel-items") :class "matchup-tab-panel" :role "tabpanel" :aria-labelledby (string who "-tab-items")}
     [:div {:class "section-header"} [:span {:class "muted"} (length (filter |(not= "" $) chosen)) " / 6 items · " (text-number cost) " gold"]
      [:button {:type "button" :class "matchup-optimize" :data-search-open who :data-on:click (string "$searchwho = '" who "'")} "Optimize items"]]
     (inventory result opponent)
     [:div {:class "loadout-effects"}
      (map (fn [effect]
             [:button (merge {:type "button" :class (string "effect-icon " (effect :kind)) :aria-label (get-in effect [:details :name])}
                             (details/attrs (effect :details) true))
              (if (= "shard" (effect :kind)) [:span (effect :short)] [:img {:src (get-in effect [:details :icon]) :alt (get-in effect [:details :name]) :width 28 :height 28}])])
           (details/loadout-effects package (if opponent (merge state {:runes (state :opponentrunes) :shards (state :opponentshards) :summoners (state :opponentsummoners)}) state)
                                    (get-in result [:selected (if opponent :opponent-tooltip-context :tooltip-context)])))]
     [:div {:class "matchup-undo" :data-undo-row who :hidden true} [:span "Items updated"] [:button {:type "button" :class "quiet-action" :data-undo who} "Undo"]]
     [:noscript [:details [:summary "Edit items"] [:div {:class "matchup-fields"}
                                                   (seq [[index id] :pairs chosen]
                                                     (select-field (string (if opponent "enemyslot" "slot") (inc index)) (string "Slot " (inc index)) id
                                                                   [["" "Empty"] ;(map |[($ :id) ($ :name)] (catalog/item-list))]
                                                                   (string "native" (if opponent "enemyslot" "slot") (inc index))))]]]]
    [:section {:id (string who "-panel-runes") :class "matchup-tab-panel" :role "tabpanel" :aria-labelledby (string who "-tab-runes")} (rune-fields result opponent)]
    [:section {:id (string who "-panel-abilities") :class "matchup-tab-panel" :role "tabpanel" :aria-labelledby (string who "-tab-abilities")} (ability-fields result opponent)]
    [:section {:id (string who "-panel-sequence") :class "matchup-tab-panel" :role "tabpanel" :aria-labelledby (string who "-tab-sequence")} (sequence-fields result opponent)]
    (champion-settings result opponent)]])
(defn loadout [result]
  (def state (result :state))
  [:section {:id "loadout-tray" :class "matchup-tray"}
   [:span {:id "configuration-data" :hidden true
           :data-json (json/encode {:format "powerspike-scenario" :version 1
                                    :scenario (or (result :definition) (get-in result [:selected :combat :scenario]))})}]
   [:form {:id "scenario" :method "get" :action "/" :class "matchup-form"
           :data-on:submit__prevent "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
    [:input {:type "hidden" :name "nativeform" :value "true"}]
    (map (fn [[name value]] [:input {:type "hidden" :name name :value value :data-bind name}])
         [["patch" (state :patch)] ["snapshot" (state :snapshot)] ["snapshotlocked" (if (state :snapshotlocked) "true" "false")]
          ["mode" "duel"] ["selected" (state :selected)]])
    (mapcat (fn [opponent]
              (seq [[index id] :pairs (ids result opponent)]
                [:input {:type "hidden" :name (string (if opponent "enemyslot" "slot") (inc index)) :value id
                         :data-bind (string (if opponent "enemyslot" "slot") (inc index))}])) [false true])
    [:noscript [:button {:type "submit"} "Run matchup"]]]
   [:p {:id "config-status" :class "measurement-error" :role "alert"}]
   [:div {:class "matchup-cards"} (champion-card result false) (champion-card result true)]])
(defn fightbar [result]
  [:div {:id "matchup-fightbar" :class "matchup-fightbar"}
   (input "duration" "Duration (s)" (get-in result [:state :duration]) 0.5 120 0.5)
   [:button {:type "button" :class "quiet-action matchup-jump" :data-matchup-jump true} "Results ↓"]
   [:button {:type "submit" :form "scenario" :class "matchup-run" :data-attr:disabled "$busy"} "Run matchup"]])
(defn fight-controls [result]
  (def state (result :state))
  [:details {:id "fight-settings" :class "control-group" :data-preserve-attr "open"}
   [:summary "Advanced fight settings"]
   [:div {:class "matchup-fields"}
    (input "distance" "Starting distance" (get state :distance 300) 0 10000)
    (input "samples" "Trials" (get state :samples 1) 1 64)
    (input "seed" "Random seed" (get state :seed 1) 0 2147483647)]])
(defn results [result]
  (def combat (get-in result [:selected :combat]))
  (def actors (get combat :actors []))
  (def state (result :state))
  (def names (map |(get-in result [:package :champion-map $ :name] $) [(state :champion) (state :opponent)]))
  (def deaths (map |(get $ :dead-at) actors))
  (def simultaneous (and (get deaths 0) (get deaths 1) (= (deaths 0) (deaths 1))))
  (def loser (cond simultaneous nil
               (and (get deaths 0) (get deaths 1)) (if (< (deaths 0) (deaths 1)) 0 1)
               (get deaths 0) 0 (get deaths 1) 1 nil))
  (def end (if loser (deaths loser) (if simultaneous (deaths 0) (state :duration))))
  (def winner (when loser (- 1 loser)))
  (def trace (get combat :trace []))
  (def endpoint (or (find |(<= ($ :at) end) (reverse trace)) (last trace)))
  (def hp (when winner (get-in endpoint [:participants winner :health] (get-in actors [winner :health] 0))))
  [:section {:id "results" :class "results matchup-results" :data-matchup-result (json/encode {:trace trace :duration (state :duration) :end end :names names
                                                                                               :actors (map |{:id ($ :id) :hp (get-in $ [:stats :hp] 1)} actors)})
             :data-run-id (string (os/clock :monotonic)) :aria-busy "false"}
   [:div {:class "matchup-result-header"}
    [:div [:h2 (cond simultaneous (string "Both die at " (string/format "%.2f" end) " s")
                 loser (string (names winner) " wins at " (string/format "%.2f" end) " s") "Both survive")]
     [:p {:class "muted"} (if winner (string (text-number hp) " HP remaining (" (text-number (* 100 (/ hp (max 1 (get-in actors [winner :stats :hp] 1))))) "%)")
                            (string (state :duration) " s duration"))
      (when (> (get combat :samples 1) 1) (string " · Trial 0 of " (combat :samples)))]]
    [:div {:class "matchup-metric" :aria-label "Chart metric"}
     [:button {:type "button" :data-matchup-metric "health" :aria-pressed "true"} "Health remaining"]
     [:button {:type "button" :data-matchup-metric "damage" :aria-pressed "false"} "Damage dealt"]]]
   [:div {:class "matchup-stale" :hidden true :role "status"} [:span "Configuration changed. Previous result shown."]
    [:button {:type "submit" :form "scenario" :data-attr:disabled "$busy"} "Rerun matchup"]]
   [:button {:type "button" :class "validation-badge coverage-link" :data-ui-toggle "coverage"} "Simulated fight · details ▾"]
   (when (result :spell-data-job)
     [:p {:class "muted"}
      (case (get-in result [:spell-data-job :status])
        :failed "Ability data unavailable. Refresh patch data to retry."
        :cancelled "Ability data download cancelled."
        :done "Ability data ready."
        (string "Downloading ability data for " (if (= "Annie" (state :champion)) (names 1) (names 0)) "."))])
   [:div {:class "matchup-legend"}
    (seq [[index name] :pairs names] [:span [:i {:class (if (= index 0) "matchup-key" "matchup-key opponent")}] name])]
   [:div {:id "matchup-chart" :class "matchup-chart" :role "img" :aria-label "Both champions over time"}]
   [:div {:class "matchup-health" :aria-live "polite"}]
   [:label {:class "matchup-scrubber"} "Time" [:input {:type "range" :min 0 :max end :step 0.01 :value 0 :aria-label "Inspect fight time"}] [:output "0.00 s"]]
   [:p {:class "muted matchup-advantage"}]
   [:details {:id "matchup-events" :class "matchup-events" :data-preserve-attr "open" :open true} [:summary "Combat events"]
    [:div {:class "matchup-event-lanes"}]
    [:label "Event" [:select {:class "matchup-event-select" :aria-label "Select combat event"} [:option {:value ""} "Select event"]]]
    [:div {:class "matchup-event-detail" :hidden true :aria-live "polite"}]]])
