(import jayson :as json)
(import ./catalog :as catalog)
(import ./model :as model)
(import ./details :as details)
(import ./champion-configs :as champion-configs)
(import ./select-options :as select-options)
(import ../src/powerspike/scenario :as scenarios)
(import ../src/powerspike/runes :as rune-data)
(import ../src/powerspike/forms :as forms)

(defn text-number [n] (string/format "%.0f" (or n 0)))
(defn icon-source [package group id]
  (when (and (string? id) (not= "" id) (string? group))
    (string "/assets/" (package :patch) "/" (package :snapshot) "/" group "/" id
            (if (string/has-suffix? ".png" id) "" ".png"))))
(defn icon [package group id name]
  [:img {:src (icon-source package group id) :alt name :width 64 :height 64 :loading "lazy"}])
(defn input [name caption value minimum maximum &opt step disabled]
  [:label caption [:input {:form "scenario" :name name :data-bind name :type "number" :value value
                           :min minimum :max maximum :step (or step 1) :required true :disabled disabled}]])
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
            (def passive (get (find |(= slot ($ :slot)) settings) :passive))
            [:article [:strong (string (string/ascii-upper (string slot)) (if passive " · Passive" ""))]
             (when (some |(= slot $) [:q :w :e :r])
               (select-field (string base "rank") (if (and (= "Elise" (champion :id)) (= slot :r)) "Additional R points (free first rank included)" "Rank") (get state (keyword (string base "rank")) -1)
                             [[-1 "Automatic"] ;(map |[$ (string $)] (range 0 (if (= slot :r) 4 6)))]))
             (input (string base "after") "Cast after (s)" (get state (keyword (string base "after")) 0) 0 120 0.1 passive)
             (input (string base "selfbelow") "Self health at most (0–1)" (get state (keyword (string base "selfbelow")) 1) 0 1 0.05 passive)
             (input (string base "targetbelow") "Target health at most (0–1)" (get state (keyword (string base "targetbelow")) 1) 0 1 0.05 passive)]) scenarios/slots)]]])
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
(defn champion-card [result opponent native-options]
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
                      (details/attrs {:name (champion :name) :stats (details/stat-rows stats) :body [] :coverage "Modeled stats; see coverage."} true)) "Details"]]]
    [:div {:class "matchup-card-tools"}
     (when (not (empty? (forms/choices (champion :id) (package :patch))))
       [:div {:class "form-control"}
        (select-field (if opponent "opponentform" "form") "Form (fixed)" (get state (if opponent :opponentform :form) "")
                      [["" "Choose form"] ;(forms/choices (champion :id) (package :patch))])])
     [:button {:type "button" :class "quiet-action champion-slots-open js-only" :data-champion-slots who} "Champion save slots"]]]
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
                                                     [:label (string "Slot " (inc index))
                                                      [:select {:form "scenario" :name (string "native" (if opponent "enemyslot" "slot") (inc index))
                                                                :data-bind (string (if opponent "enemyslot" "slot") (inc index))}
                                                       (select-options/selected native-options id)]])]]]]
    [:section {:id (string who "-panel-runes") :class "matchup-tab-panel" :role "tabpanel" :aria-labelledby (string who "-tab-runes")} (rune-fields result opponent)]
    [:section {:id (string who "-panel-abilities") :class "matchup-tab-panel" :role "tabpanel" :aria-labelledby (string who "-tab-abilities")} (ability-fields result opponent)]
    [:section {:id (string who "-panel-sequence") :class "matchup-tab-panel" :role "tabpanel" :aria-labelledby (string who "-tab-sequence")} (sequence-fields result opponent) (champion-settings result opponent)]]])
(defn loadout [result]
  (def state (result :state))
  (def native-options (select-options/prepare [["" "Empty"] ;(map |[($ :id) ($ :name)] (catalog/item-list))]))
  [:section {:id "loadout-tray" :class "matchup-tray"}
   [:span {:id "configuration-data" :hidden true
           :data-json (json/encode {:format "powerspike-scenario" :version 1
                                    :scenario (or (result :definition) (get-in result [:selected :combat :scenario]))})}]
   [:span {:id "champion-configurations" :hidden true
           :data-json (json/encode (champion-configs/documents
                                     (or (result :definition) (get-in result [:selected :combat :scenario]))
                                     (ids result false) (ids result true)))}]
   [:form {:id "scenario" :method "get" :action "/" :class "matchup-form"
           :data-on:submit__prevent "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
    (map (fn [[name value]] [:input {:type "hidden" :name name :value value :data-bind name}])
         [["patch" (state :patch)] ["snapshot" (state :snapshot)] ["snapshotlocked" (if (state :snapshotlocked) "true" "false")]
          ["mode" "duel"] ["selected" (state :selected)]
          ["championaction" ""] ["championwho" "player"] ["championjson" ""]])
    (mapcat (fn [opponent]
              (seq [[index id] :pairs (ids result opponent)]
                [:input {:type "hidden" :name (string (if opponent "enemyslot" "slot") (inc index)) :value id
                         :data-bind (string (if opponent "enemyslot" "slot") (inc index))}])) [false true])
    [:noscript [:input {:type "hidden" :name "nativeform" :value "true"}]
     [:button {:type "submit"} "Run matchup"]]]
   [:div {:class "matchup-cards"} (champion-card result false native-options)
    [:button {:type "button" :class "matchup-swap js-only" :data-swap-champions true :aria-label "Swap champions" :title "Swap champions" :data-attr:disabled "$busy"}
     [:svg {:viewBox "0 0 24 24" :width 22 :height 22 :aria-hidden "true" :fill "none" :stroke "currentColor" :stroke-width 1.5}
      [:path {:d "M4 8h15m-4-4 4 4-4 4M20 16H5m4-4-4 4 4 4"}]]]
    (champion-card result true native-options)]])
(defn fightbar [result]
  [:div {:id "matchup-fightbar" :class "matchup-fightbar"}
   (input "duration" "Duration (s)" (get-in result [:state :duration]) 0.5 120 "any")
   [:button {:type "button" :class "quiet-action matchup-jump" :data-matchup-jump true} "Results ↓"]
   [:button {:type "submit" :form "scenario" :class "matchup-run" :data-attr:disabled "$busy"} "Run matchup"]])
(defn champion-slots-dialog []
  [:dialog {:id "champion-slots-dialog" :class "champion-slots-dialog" :aria-labelledby "champion-slots-title"}
   [:header [:h2 {:id "champion-slots-title"} "Champion save slots"]
    [:button {:type "button" :data-close-champion-slots true :aria-label "Close champion save slots"} "×"]]
   [:p {:id "champion-slots-description"} "Save this champion's configuration, or load a slot onto this side."]
   [:p {:class "muted"} "Four slots shared by both sides. Saved in this browser."]
   [:div {:id "champion-slots-list"}]
   [:p {:id "champion-slots-status" :role "status"}]
   [:noscript [:p "Champion save slots require JavaScript."]]])
(defn fight-controls [result]
  (def state (result :state))
  [:details {:id "fight-settings" :class "control-group" :data-preserve-attr "open"}
   [:summary "Advanced fight settings"]
   [:div {:class "matchup-fields"}
    (input "distance" "Starting distance" (get state :distance 300) 0 10000)
    (input "samples" "Trials" (get state :samples 1) 1 64)
    (input "seed" "Random seed" (get state :seed 1) 0 2147483647)]])
(defn event-sources [package actors trace]
  (def abilities (mapcat |(get $ :abilities []) actors))
  (def triggers (mapcat |(get $ :triggers []) actors))
  (tabseq [source :in (keys (tabseq [event :in trace :when (string? (event :source))] (event :source) true))]
    source
    (let [parts (string/split "/" source)
          item (when (and (= "item" (first parts)) (>= (length parts) 2)) (get-in package [:item-map (parts 1)]))
          rune (when (= "rune" (first parts)) (find |(= (string (get $ "id")) (get parts 1)) (scenarios/runes package)))
          ability (find |(= source ($ :id)) abilities)
          trigger (find |(= source ($ :id)) triggers)]
      {:name (cond (= source "attack") "Basic attack" item (item :name) ability (ability :name) rune (get rune "name") (get trigger :name) (trigger :name) source)
       :icon (cond item (icon-source package "item" (item :icon))
               ability (icon-source package (ability :icon-group) (ability :icon))
               rune (icon-source package "rune" (get parts 1)))
       :slot (get ability :slot)
       :consumption (when (= "spellblade" (get trigger :consume-buff)) "Spellblade consumed")})))
(defn results [result]
  (def combat (get-in result [:selected :combat]))
  (def actors (get combat :actors []))
  (def state (result :state))
  (def names (map (fn [id actor]
                    (string (get-in result [:package :champion-map id :name] id)
                            (if (actor :form-name) (string " (" (actor :form-name) ")") "")))
                  [(state :champion) (state :opponent)] actors))
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
                                                                                               :statuses (get combat :statuses [])
                                                                                               :sources (event-sources (result :package) actors trace)
                                                                                               :actors (map |{:id ($ :id) :hp (get-in $ [:stats :hp] 1)
                                                                                                              :icon (icon-source (result :package) "champion"
                                                                                                                                 (get-in result [:package :champion-map ($ :champion) :icon]))} actors)})
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
   [:div {:class "matchup-legend"}
    (seq [[index name] :pairs names] [:span [:i {:class (if (= index 0) "matchup-key" "matchup-key opponent")}] name])
    (when (some |(= :parried ($ :kind)) trace)
      [:span {:class "muted matchup-parry-hint" :title "Select an event for details"} "× Parried hit"])]
   [:div {:class "matchup-visual"}
    [:div {:id "matchup-chart" :class "matchup-chart" :role "slider" :tabindex 0 :aria-label "Inspect fight time" :aria-valuemin 0 :aria-valuemax end :aria-valuenow 0}]
    [:section {:id "matchup-events" :class "matchup-events" :aria-label "Combat events"}
     [:div {:class "matchup-event-lanes"}]]
    [:div {:class "matchup-timeline-guide" :aria-hidden "true"}]]
   [:div {:class "matchup-status-legend" :aria-label "Active effect colors"}]
   [:div {:class "matchup-inspection"}
    [:output {:class "matchup-time" :aria-label "Fight time"} "0.00 s"]
    [:label "Event" [:select {:class "matchup-event-select" :aria-label "Select combat event"} [:option {:value ""} "Select event"]]]]
   [:div {:class "matchup-health" :aria-live "polite"}]
   [:div {:id "combat-event-tooltip" :class "matchup-event-detail" :role "tooltip" :popover "manual" :hidden true}]])
