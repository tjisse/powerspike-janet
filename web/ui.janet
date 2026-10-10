(import janet-html :as html)
(import jayson :as json)
(import ./catalog :as catalog)
(import ./model :as model)
(import ./optimizer :as optimizer)
(import ./workspace :as workspace)
(import ./details :as details)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/scenario :as scenarios)
(import ../src/powerspike/objectives :as objectives)

(defn- safe-tree [node]
  (if (indexed? node)
    (if (and (keyword? (first node)) (dictionary? (get node 1)))
      [(first node)
       (tabseq [[k v] :pairs (node 1) :when v] k (if (true? v) "" (html/escape v)))
       ;(map safe-tree (drop 2 node))]
      (map safe-tree node)) node))
(defn render [& nodes] (apply html/encode (map safe-tree nodes)))

(defn number-text [value &opt decimals]
  (if decimals (string/format "%.2f" value)
    (do (def text (string/format "%.0f" value)) (def out @"")
      (loop [i :range [0 (length text)]]
        (when (and (> i 0) (= 0 (% (- (length text) i) 3))) (buffer/push-string out ","))
        (buffer/push-string out (string/slice text i (inc i)))) (string out))))

(defn patch-panel [result job &opt message]
  (def patch (or (get job :key) (get (result :state) :patch ((result :package) :patch))))
  (def progress (get job :progress {:message "" :completed 0 :total 1}))
  (def active (and job (some |(= $ (job :status)) [:queued :running :cancelling])))
  [:section {:id "patch-panel" :class "patch-panel" :data-poll (if (or active (not catalog/versions-ready)) "true" "false")}
   [:label "Patch"
    [:select {:name "patchchoice" :data-bind:patchchoice true :data-on:change "@post('/patches')"}
     (map |[:option {:value $ :selected (= $ patch)} $] catalog/patch-list)]]
   [:span {:class "muted"} "Cached patches work offline"]
   [:button {:type "button" :data-on:click "@post('/patches?refresh=true')"} "Refresh patch data"]
   (when message [:p {:class "measurement-error"} message])
   (when job
     [:div {:class "patch-progress" :role "status"}
      [:div {:class "patch-progress-controls"}
       [:strong (get job :key "Patch download")]
       [:span (string " · " (job :status))]
       (when active
         [[:progress {:max (max 1 (progress :total)) :value (progress :completed)}]
          [:button {:type "button" :data-on:click (string "@post('/jobs/cancel?id=" (job :id) "')")} "Cancel"]])
       (when (= :done (job :status))
         [:a {:class "apply" :href (string "/?patch=" ((job :result) :patch) "&snapshot=" ((job :result) :snapshot))
              :data-init (string "const next = new URL('/', location.href); const form = document.getElementById('scenario'); "
                                 "if (form) for (const [key, value] of new FormData(form)) next.searchParams.set(key, value); "
                                 "if (form) for (const field of form.elements) if (field.type === 'checkbox') next.searchParams.set(field.name, field.checked ? 'true' : 'false'); "
                                 "for (const [prefix, selector] of [['slot', '#loadout-tray .tray-items .item-slot'], ['enemyslot', '#fight-settings .loadout .item-slot']]) "
                                 "document.querySelectorAll(selector).forEach((slot, index) => next.searchParams.set(prefix + (index + 1), slot.dataset.itemId || '')); "
                                 "next.searchParams.set('selected', $selected); next.searchParams.set('patch', '" ((job :result) :patch)
                                 "'); next.searchParams.set('snapshot', '" ((job :result) :snapshot) "'); location.assign(next)")}
          "Open patch"])]
      [:span {:class "patch-progress-message" :title (progress :message)} (progress :message)]
      (when (= :failed (job :status)) [:p {:class "patch-progress-error"} (job :error)])
      [:span {:id "patch-job-signals" :data-init (string "$job = '" (job :id) "'")}]])])

(defn- icon [group id description &opt class]
  [:img {:src (string "/assets/" ((catalog/current) :patch) "/" ((catalog/current) :snapshot) "/" group "/" id (if (string/has-suffix? ".png" id) "" ".png")) :alt description
         :width "64" :height "64" :class class :loading "lazy"}])
(defn- level-options [state]
  (seq [level :range [1 19]] [:option {:value level :selected (= level (state :level))} level]))

(defn- spell-visual [slot rank maximum group id name]
  [[:span {:class "spell-icon" :aria-hidden "true"}
    (when (not= "" id) (icon group id name))
    [:span {:class "spell-key"} (string/ascii-upper (string slot))]]
   [:span {:class "spell-ranks" :aria-hidden "true"}
    (when (some |(= $ slot) [:q :w :e :r])
      (seq [index :range [0 maximum]]
        [:span {:class (if (< index rank) "spell-rank spell-rank-learned" "spell-rank")}]))]])

(defn- rank-markup [champion ranks &opt settings]
  [:div {:id "ranks" :class "spells"}
   (cond (not (empty? settings))
     (map (fn [ability]
            (def learned (> (ability :rank) 0))
            [:button (merge {:type "button" :class (if learned "spell" "spell spell-locked")
                             :data-ability-slot (ability :slot) :data-rank (ability :rank) :data-unlocked (if learned "true" "false")
                             :title (if learned (string (ability :name) " · rank " (ability :rank)) (string (ability :name) " · not learned at this level"))
                             :aria-label (string (ability :name) (if learned (string " rank " (ability :rank)) " locked") " details")}
                            (details/attrs (details/ability ability) true))
             (spell-visual (ability :slot) (ability :rank) (get ability :max-rank (if (= :r (ability :slot)) 3 5))
                           (ability :icon-group) (ability :icon) (ability :name))]) settings)
     (and (= "Annie" (champion :id)) (get ranks :q))
     (map (fn [[slot name id maximum]]
            (def rank (get ranks slot 0))
            [:span {:class (if (> rank 0) "spell" "spell spell-locked")
                    :aria-label (string name (if (> rank 0) (string " rank " rank) " locked"))}
             (spell-visual slot rank maximum "spell" id name)])
          [[:q "Disintegrate" "AnnieQ" 5] [:w "Incinerate" "AnnieW" 5] [:r "R passive" "" 3]])
     [:span {:class "muted"} "Ability model unavailable"])])

(defn champion-display [result]
  (def champion (result :champion))
  [:div {:id "champion-display" :class "champion-display"}
   [:button (merge {:type "button" :class "portrait" :aria-label (string (champion :name) " details")
                    :data-on:click "document.getElementById('champion-picker').showModal()"}
                   (details/attrs (details/champion champion (get-in result [:state :level]) (get-in result [:selected :stats]))))
    (icon "champion" (champion :icon) (champion :name))]
   [:div {:class "champion-title"} [:span {:class "muted"} "Champion"]
    [:h1 (champion :name)]
    [:button {:class "catalog-open js-only" :type "button"
              :data-on:click "document.getElementById('champion-picker').showModal()"} "Change champion"]]])

(defn scenario [result]
  (def state (result :state))
  [:form {:id "scenario" :class "scenario" :method "get" :action "/"
          :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"
          :data-on:input__debounce.200ms "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"
          :data-on:submit__prevent "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
   [:div {:class "champion-identity"} (champion-display result)
    [:label {:class "native-only" :for "champion"} "Champion"
     [:select {:id "champion" :name "champion" :data-bind:champion true}
      (map (fn [champion] [:option {:value (champion :id) :selected (= (champion :id) (state :champion))}
                           (champion :name)]) (catalog/champion-list))]]
    [:label {:for "level" :class "champion-level"} "Level"
     [:select {:id "level" :name "level" :data-bind:level true} (level-options state)]]]
   [:div {:class "champion-vitals"}
    (map (fn [[key caption]] [:div [:span caption] [:strong (number-text (get-in result [:selected :stats key] 0))]]) [[:hp "Health"] [:mp "Resource"]])]
   (rank-markup (result :champion) ((result :selected) :ranks) ((result :selected) :ability-settings))
   [:input {:type "hidden" :name "patch" :value (get state :patch ((result :package) :patch))}]
   [:input {:type "hidden" :name "snapshot" :value ((result :package) :snapshot)}]
   [:input {:type "hidden" :name "snapshotlocked" :value (if (get state :snapshotlocked) "true" "false")}]
   [:span {:class "update-status" :role "status" :aria-live "polite" :data-text "$busy ? 'Updating…' : ''"} ""]
   [:noscript [:button {:type "submit" :name "selected" :value (state :selected) :class "apply"} "Update comparison"]]])

(defn ranks-fragment [result]
  (rank-markup (result :champion) ((result :selected) :ranks) ((result :selected) :ability-settings)))

(defn- build-row [row index selected]
  [:button {:type "submit" :form "scenario" :name "selected" :value (row :id)
            :class "build-row" :aria-pressed (if (= (row :id) selected) "true" "false")
            :data-on:click__prevent (string "$selected = '" (row :id)
                                            "'; document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))")}
   [:span [:span {:class "row-title"} [:span {:class "row-rank"} (inc index)] (row :name)]
    [:span {:class "row-icons"} (if (empty? (row :items)) [:span {:class "muted"} "Empty inventory"]
                                  (map |(icon "item" ($ :icon) ($ :name)) (row :items)))]]
   [:span {:class "numeric gold-number"} (number-text (row :cost)) [:small "gold"]]
   [:span {:class "numeric"} (number-text ((row :combat) :damage))
    [:small (number-text ((row :combat) :dps)) " DPS"]]])

(defn- metric [description value &opt secondary]
  [:div {:class (if secondary "metric metric-secondary" "metric")}
   [:span {:class "metric-label"} description] [:strong {:class "metric-value"} (number-text value)]])

(defn- stat [description value]
  [:div [:span description] [:strong value]])

(defn- state-chart [combat duration field title]
  (def trace (get combat :trace []))
  (def ceiling (max 1 (max ;(mapcat |(map (fn [actor] (get actor field 0)) ($ :participants)) trace))))
  (defn x [time] (+ 47 (* (/ time duration) 805)))
  (defn y [value] (- 157 (* (/ value ceiling) 145)))
  [:section {:class "chart-panel"}
   [:div {:class "section-header"} [:h2 title] [:span {:class "muted"} "Seeded trial 0"]]
   [:div {:class "state-chart-box" :data-state-chart (string field) :data-duration duration :data-label title}
    [:svg {:viewBox "0 0 864 185" :role "img" :aria-label title :class "state-chart"}
     [:title title]
     (seq [index :range [0 2]]
       (do (def path (string/join (seq [[i event] :pairs trace]
                                    (string (if (= i 0) "M " " L ") (x (event :at)) " "
                                            (y (get-in event [:before index field] (get-in event [:participants index field] 0)))
                                            " V " (y (get-in event [:participants index field] 0)))) ""))
         [:path {:d path :class (if (= 0 index) "chart-line" "chart-opponent")}]))
     [:text {:x 47 :y 178} "0 s"] [:text {:x 852 :y 178 :text-anchor "end"} duration " s"]]]
   [:p {:class "muted chart-legend"} "Player · solid cyan / Target · dashed violet"]])

(defn- inventory-ids [row state]
  (if (= "custom" (row :id)) (map |(get state $ "") model/slot-keys)
    (seq [index :range [0 6]] (get (row :ids) index ""))))

(defn- inventory [row state &opt opponent]
  (def ids (if opponent (map |(get state $ "") model/enemy-slot-keys) (inventory-ids row state)))
  (def prefix (if opponent "enemyslot" "slot"))
  (def seed (string/join (seq [index :range [0 6]]
                           (string "$" prefix (inc index) " = '" (ids index) "'; ")) ""))
  [:div {:class "inventory" :aria-label "Six editable inventory slots"}
   (seq [index :range [0 6]]
     (do (def item (catalog/items (ids index)))
       [:button (merge (if item (details/attrs (details/item item (get row (if opponent :opponent-tooltip-context :tooltip-context)))) {}) {:type "button" :class (if item "item-slot" "item-slot empty-slot")
                                                                                                                                            :data-item-id (ids index)
                                                                                                                                            :data-attr:disabled "$busy"
                                                                                                                                            :aria-label (string "Edit slot " (inc index) (if item (string ": " (item :name)) ": empty"))

                                                                                                                                            :data-on:click (string seed "$editingwho = '" (if opponent "opponent" "player") "'; $editing = " (inc index)
                                                                                                                                                                   "; document.getElementById('item-picker').showModal()")})
        (if item (icon "item" (item :icon) (item :name)) "+")
        [:span {:class "slot-label"} (inc index)]]))])

(defn fight-controls [result]
  (def state (result :state))
  (def row (result :selected))
  [:details {:id "fight-settings" :class "control-group" :data-preserve-attr "open"
             :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"
             :data-on:input__debounce.200ms "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
   [:summary [:span "Opponent & fight"] [:span {:class "muted"} (state :mode) " · " (state :duration) " s"]]
   [:div {:class "tactics-grid"}
    [:label {:for "duration"} "Combat window (seconds)"
     [:input {:form "scenario" :id "duration" :name "duration" :type "number" :min "0.5" :max "120" :step "0.5"
              :required true :value (state :duration) :data-bind:duration true}]]
    [:label {:for "mr"} "Target magic resistance"
     [:input {:form "scenario" :id "mr" :name "mr" :type "number" :min "0" :max "1000" :step "1"
              :required true :value (state :mr) :data-bind:mr true}]]
    [:label {:for "armor"} "Target armor"
     [:input {:form "scenario" :id "armor" :name "armor" :type "number" :min "0" :max "1000" :step "1"
              :required true :value (state :armor) :data-bind:armor true}]]
    [:label "Target health"
     [:input {:form "scenario" :name "targethealth" :type "number" :min "1" :max "1000000" :value (get state :target-health (model/default-state :target-health))
              :data-bind:targethealth true}]]
    [:label "Starting distance"
     [:input {:form "scenario" :name "distance" :type "number" :min "0" :max "10000" :value (get state :distance 300) :data-bind:distance true}]]
    [:label "Fight"
     [:select {:form "scenario" :name "mode" :data-bind:mode true}
      [:option {:value "practice" :selected (= "practice" (get state :mode "practice"))} "Practice target"]
      [:option {:value "duel" :selected (= "duel" (state :mode))} "Champion duel"]
      (map (fn [preset]
             [:option {:value (string (preset :id)) :selected (= (string (preset :id)) (state :mode))
                       :disabled (not (some |(and (= ($ :id) (preset :id)) ($ :available)) (get (result :package) :objectives [])))}
              (preset :name)]) objectives/presets)
      [:option {:value "legacy" :selected (= "legacy" (state :mode))} "Curated reference"]]]
    [:label {:data-show "$mode === 'duel'"} "Opponent"
     [:select {:form "scenario" :name "opponent" :data-bind:opponent true}
      (map |[:option {:value ($ :id) :selected (= ($ :id) (get state :opponent "Garen"))} ($ :name)] (catalog/champion-list))]]
    [:label {:data-show "$mode === 'duel'"} "Opponent level"
     [:input {:form "scenario" :name "opponentlevel" :type "number" :min 1 :max 18 :value (get state :opponentlevel 18) :data-bind:opponentlevel true}]]
    [:label "Trials"
     [:input {:form "scenario" :name "samples" :type "number" :min 1 :max 64 :step 1 :required true
              :value (get state :samples 1) :data-bind:samples true}]]

    [:label "Objective level" [:input {:form "scenario" :name "objectivelevel" :type "number" :min 1 :max 30 :value (get state :objectivelevel 10) :data-bind:objectivelevel true}]]
    [:label "Game time (minutes)" [:input {:form "scenario" :name "gametime" :type "number" :min 0 :max 120 :step 0.5 :value (get state :gametime 20) :data-bind:gametime true}]]
    [:label "Objective retaliation" [:input {:form "scenario" :type "checkbox" :name "retaliation" :checked (get state :retaliation true) :data-bind:retaliation true}]]
    [:label "Minions present at turret" [:input {:form "scenario" :type "checkbox" :name "minionspresent" :checked (get state :minionspresent true) :data-bind:minionspresent true}]]]
   (when (= "duel" (state :mode))
     [:section {:class "loadout"}
      [:div {:class "section-header"} [:h2 "Opponent · " (get state :opponent "Garen")]
       (icon "champion" (get state :opponent "Garen") "Opponent")]
      (inventory row state true)
      [:div {:class "build-stats"}
       (map (fn [[key caption]] (stat caption (number-text (get-in row [:opponent :stats key] 0))))
            [[:hp "Health"] [:ad "Attack damage"] [:ap "Ability power"] [:armor "Armor"] [:mr "Magic resistance"]])]])])

(defn- setting [caption name value minimum maximum &opt step]
  [:label caption [:input {:form "scenario" :name name :id (string "setting-" name) :type "number" :required true
                           :min minimum :max maximum :step (or step 1) :value value :data-bind name}]])
(defn tactics [result]
  (def state (result :state))
  [:details {:id "tactics" :class "tactics scope-panel" :data-preserve-attr "open"
             :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"
             :data-on:input__debounce.300ms "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
   [:summary "Strategies, ranks & activation rules"]
   [:div {:class "tactics-grid"} (setting "Seed" "seed" (get state :seed 1) 0 2147483647)]
   (map (fn [opponent]
          (def prefix (if opponent "enemy" ""))
          (def stat-prefix (if opponent "opponent" ""))
          [:section {:class "tactics-participant" :data-show (if opponent "$mode === 'duel'" "true")}
           [:h2 (if opponent "Opponent strategy" "Player strategy")]
           [:div {:class "tactics-grid"}
            [:label "Ability priority"
             [:input {:form "scenario" :name (string stat-prefix "priority") :value (string/join (map string (get state (keyword (string stat-prefix "priority")) scenarios/slots)) ",")
                      :data-bind (string stat-prefix "priority")}]
             [:span {:class "muted"} "Casting order for learned abilities."]]
            [:label (string (get-in result [:package :champion-map (state (if opponent :opponent :champion)) :name]) " skill order")
             [:input {:form "scenario" :name (string stat-prefix "skillorder") :required true
                      :value (string/join (map string (state (keyword (string stat-prefix "skillorder")))) ",")
                      :data-bind (string stat-prefix "skillorder") :aria-label (if opponent "Opponent skill order" "Player skill order")}]
             [:span {:class "muted"} "One Q/W/E/R per level, separated by commas. Determines unlocked abilities and ranks."]]
            [:label "Movement"
             [:select {:form "scenario" :name (string stat-prefix "movement") :data-bind (string stat-prefix "movement")}
              (map |[:option {:value $ :selected (= $ (get state (keyword (string stat-prefix "movement")) "approach"))}
                     (case $ "approach" "Approach into attack range" "hold" "Hold position" "Keep preferred range")] ["approach" "hold" "hold-range"])]]
            (setting "Preferred distance" (string stat-prefix "preferredrange") (get state (keyword (string stat-prefix "preferredrange")) 500) 0 10000)
            (setting "Hit chance (0–1)" (string stat-prefix "hitchance") (get state (if opponent :opponent-hit-chance :hit-chance) 1) 0 1 0.05)
            (setting "Starting health (fraction)" (string stat-prefix "healthfraction") (get state (if opponent :opponent-health-fraction :health-fraction) 1) 0.01 1 0.01)
            (setting "Starting resource (fraction)" (string stat-prefix "resourcefraction") (get state (if opponent :opponent-resource-fraction :resource-fraction) 1) 0 1 0.05)
            (map (fn [[suffix title]] [:label title [:input {:form "scenario" :type "checkbox" :name (string stat-prefix suffix)
                                                             :checked (get state (keyword (string stat-prefix suffix)) true) :data-bind (string stat-prefix suffix)}]])
                 [["attacks" "Basic attacks"] ["abilities" "Abilities"]])]
           [:div {:class "ability-controls"}
            (map (fn [slot]
                   (def base (string prefix slot))
                   [:article
                    [:strong (string/ascii-upper (string slot))]
                    (when (some |(= $ slot) [:q :w :e :r])
                      [:label "Rank"
                       [:select {:form "scenario" :name (string base "rank") :data-bind (string base "rank")}
                        [:option {:value -1 :selected (= -1 (get state (keyword (string base "rank")) -1))} "Automatic"]
                        (seq [rank :range [0 (if (= slot :r) 4 6)]]
                          [:option {:value rank :selected (= rank (get state (keyword (string base "rank")) -1))} rank])]])
                    (setting "Cast after (seconds)" (string base "after") (get state (keyword (string base "after")) 0) 0 120 0.1)
                    (setting "Self health at most (fraction)" (string base "selfbelow") (get state (keyword (string base "selfbelow")) 1) 0 1 0.05)
                    (setting "Target health at most (fraction)" (string base "targetbelow") (get state (keyword (string base "targetbelow")) 1) 0 1 0.05)]) scenarios/slots)]
           (when opponent
             [:div {:class "tactics-grid"}
              (seq [index :range [0 2]]
                [:label (string "Opponent summoner " (if (= index 0) "D" "F"))
                 [:select {:form "scenario" :name (string "opponentsummoner" (inc index)) :data-bind (string "opponentsummoner" (inc index))}
                  [:option {:value ""} "None"]
                  (map |[:option {:value ($ "id") :selected (= ($ "id") (get (get state :opponentsummoners []) index ""))} ($ "name")]
                       (filter |(some (fn [mode] (= mode "CLASSIC")) (get $ "modes" [])) (get (result :package) :summoners [])))]])])
           [:p {:class "muted"} "Automatic ranks follow this champion's skill order. Manual rank settings override it. Exceptional leveling and forms still require handlers."]]) [false true])])

(defn loadout [result]
  (def row (result :selected))
  (def state (result :state))
  (def totals (row :stats))
  [:section {:id "loadout-tray" :class "loadout-tray" :aria-label "Champion, stats and items"}
   (when (and (state :savedmodel) (not= workspace/model-identity (state :savedmodel)))
     [:p {:class "model-notice warning"} "Saved model differs. This result uses the current model. "
      [:button {:type "button" :class "quiet-action" :data-ui-toggle "scenario-tools"} "Reproduction details"]])
   [:div {:class "tray-champion"} (scenario result)
    [:div {:class "loadout-effects" :aria-label "Selected runes and summoner spells"}
     (map (fn [effect]
            (when effect
              [:button (merge {:type "button" :class (string "effect-icon " (effect :kind)) :aria-label (string (get-in effect [:details :name]) " details")}
                              (details/attrs (effect :details) true))
               [:img {:src (get-in effect [:details :icon]) :alt (get-in effect [:details :name]) :width 32 :height 32}]]))
          (details/loadout-effects (result :package) state (row :tooltip-context)))
     [:button {:type "button" :class "quiet-action" :data-ui-toggle "ability-settings"} "Runes & spells"]]]
   [:section {:class "tray-stats" :aria-label "Build stats"}
    [:div {:class "section-header"} [:h2 "Stats"]
     [:button (merge {:type "button" :class "quiet-action"}
                     (details/attrs {:name "Build stats" :subtitle (row :name) :stats (details/stat-rows totals) :body []
                                     :coverage "Source stats and modeled item bonuses. Combat exclusions remain in coverage."} true)) "Details"]]
    [:div {:class "build-stats"}
     (map (fn [[key caption]] (stat caption (number-text (get totals key 0) (some |(= key $) [:attack-speed]))))
          [[:ap "Ability power"] [:ad "Attack damage"] [:ability-haste "Ability haste"]
           [:attack-speed "Attack speed"] [:armor "Armor"] [:mr "Magic resist"]])]]
   [:section {:class "tray-items" :aria-label "Selected build"}
    [:div {:class "section-header"} [:h2 "Items"] [:span {:class "muted"} (number-text (row :cost)) " gold"]]
    (inventory row state)
    [:button {:type "button" :class "optimize-primary" :data-search-open true} "Optimize build"]]])

(defn ability-group [result]
  (def state (result :state))
  [:details {:id "ability-settings" :class "control-group"}
   [:summary [:span "Abilities, runes & spells"] [:span {:class "muted"} "Ranks · activation · loadout"]]
   [:div {:class "tactics-grid" :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
    (seq [index :range [0 2]]
      [:label (if (= index 0) "Summoner spell D" "Summoner spell F")
       [:select {:form "scenario" :name (string "summoner" (inc index)) :data-bind (string "summoner" (inc index))}
        [:option {:value "" :selected (= "" (get (get state :summoners []) index ""))} "None"]
        (map (fn [spell] [:option {:value (spell "id") :selected (= (spell "id") (get (get state :summoners []) index ""))}
                          (spell "name")]) (filter |(some (fn [mode] (= "CLASSIC" mode)) (get $ "modes" [])) (get (result :package) :summoners [])))]])]
   (tactics result) (optimizer/rune-editor (result :package) state)])

(defn native-inventory [result]
  (def ids (inventory-ids (result :selected) (result :state)))
  [:noscript
   [:details {:class "native-editor"} [:summary "Edit inventory"]
    [:div {:class "native-slots"}
     (seq [index :range [0 6]]
       [:label (string "Slot " (inc index))
        [:select {:form "scenario" :name (string "slot" (inc index))}
         [:option {:value "" :selected (= "" (ids index))} "Empty"]
         (map (fn [item] [:option {:value (item :id) :selected (= (item :id) (ids index))}
                          (item :name) " · " (item :id) " · " (item :gold) " gold"]) (catalog/item-list))]])]
    [:button {:class "apply" :type "submit" :form "scenario" :name "selected" :value "custom"} "Apply inventory"]]])

(defn catalog-pickers []
  [[:dialog {:id "champion-picker" :class "catalog-dialog" :aria-labelledby "champion-picker-title"}
    [:div {:class "picker-header"} [:h2 {:id "champion-picker-title"} "Choose champion"]
     [:button {:type "button" :class "catalog-close" :data-on:click "document.getElementById('champion-picker').close()"} "Close"]]
    [:div {:class "picker-toolbar"}
     [:label "Search champions" [:input {:type "search" :class "catalog-search" :placeholder "Name or role" :autocomplete "off" :autofocus true}]]
     [:span {:class "muted catalog-count"} (length (catalog/champion-list)) " champions"]]
    [:div {:class "catalog-grid champion-grid"}
     (map (fn [champion]
            [:button {:type "button" :class "catalog-card"
                      :data-champion-id (champion :id)
                      :data-search (string (champion :name) " " (string/join (champion :tags) " "))
                      :data-on:click (string "$champion = '" (champion :id) "'; $selected = 'custom'; "
                                             "document.getElementById('champion-picker').close(); "
                                             "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))")}
             (icon "champion" (champion :icon) (champion :name))
             [:span (champion :name)] [:small "Unvalidated"]]) (catalog/champion-list))]
    [:p {:class "picker-empty" :hidden true} "No champions match your search."]]
   [:dialog {:id "item-picker" :class "catalog-dialog" :aria-labelledby "item-picker-title" :data-attr:data-who "$editingwho"}
    [:div {:class "picker-header"} [:h2 {:id "item-picker-title"} "Choose item"]
     [:button {:type "button" :class "catalog-close" :data-on:click "document.getElementById('item-picker').close()"} "Close"]]
    [:div {:class "picker-toolbar"}
     [:label "Search items" [:input {:type "search" :class "catalog-search" :placeholder "Name, stat or item ID" :autocomplete "off" :autofocus true}]]
     [:label "Catalog" [:select {:class "catalog-scope"}
                        [:option {:value "rift"} "Summoner's Rift shop"] [:option {:value "all"} "All modes & special items"]]]
     [:button {:type "button" :class "clear-slot"
               :data-on:click (string (string/join (seq [index :range [1 7]]
                                                     (string "if ($editing === " index ") { if ($editingwho === 'opponent') $enemyslot" index " = ''; else $slot" index " = ''; }")) " ")
                                      " if ($editingwho !== 'opponent') $selected = 'custom'; document.getElementById('item-picker').close(); "
                                      "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))")} "Empty slot"]]
    [:p {:class "muted picker-note"} [:span {:class "catalog-count"} (length (catalog/item-list)) " items"]
     " · Unvalidated. Permanent stats only; effect exclusions appear below the build."]
    [:div {:class "catalog-grid item-grid"}
     (map (fn [item]
            (def rift (and (item :purchasable) (item :in-store) (some |(= 11 $) (item :maps))))
            [:button (merge (details/attrs (details/item item)) {:type "button" :class "catalog-card" :hidden (not rift) :data-detail-item (item :id)
                                                                 :data-item-id (item :id)
                                                                 :data-rift (if rift "true" "false")
                                                                 :data-search (string (item :name) " " (item :id) " " (item :description) " " (string/join (item :tags) " "))
                                                                 :data-on:click (string (string/join (seq [index :range [1 7]]
                                                                                                       (string "if ($editing === " index ") { if ($editingwho === 'opponent') $enemyslot" index " = '" (item :id) "'; else $slot" index " = '" (item :id) "'; }")) " ")
                                                                                        " if ($editingwho !== 'opponent') $selected = 'custom'; document.getElementById('item-picker').close(); "
                                                                                        "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))")})
             (icon "item" (item :icon) (item :name))
             [:span (item :name)] [:small (item :gold) " gold · " (item :id)]
             [:small {:class "validation-badge"} "Unvalidated"]
             [:span {:class "item-description"} (item :description)]]) (catalog/item-list))]
    [:p {:class "picker-empty" :hidden true} "No items match your search."]]])

(defn- chart [row duration title]
  (def events ((row :combat) :events))
  (def total ((row :combat) :damage))
  # The browser sizes this same event chart responsively. This SVG is the no-JS fallback.
  (def ymax (max 1 (* total 1.15)))
  (defn x [t] (+ 47 (* (/ t duration) 805)))
  (defn y [damage] (- 157 (* (/ damage ymax) 145)))
  (def path @[(string "M " (x 0) " " (y 0))])
  (var cumulative 0)
  (each event events
    (+= cumulative (event :damage))
    (array/push path (string " H " (x (event :at)) " V " (y cumulative))))
  (array/push path (string " H " (x duration)))
  [:div {:id "timeline" :class "chart" :data-events (json/encode events)
         :data-duration duration :data-total total :data-label title}
   [:svg {:viewBox "0 0 864 185" :role "img" :aria-label title}
    [:title title]
    (map (fn [fraction]
           (def value (* fraction ymax))
           [[:line {:x1 "47" :x2 "852" :y1 (y value) :y2 (y value) :class "chart-grid"}]
            [:text {:x "39" :y (+ 4 (y value)) :text-anchor "end"} (number-text value)]]) [0 0.5 1])
    [:path {:d (string/join path "") :class "chart-line"}]
    [:text {:x "47" :y "178"} "0 s"]
    [:text {:x "852" :y "178" :text-anchor "end"} duration " s"]]])

(defn- event-icon [row event]
  (def source (event :source))
  (cond (= :attack source) (icon "champion" (get-in row [:champion :icon] (get row :champion-id "Annie")) "Basic attack")
    (and (string? source) (string/has-prefix? "item/" source)) (icon "item" ((string/split "/" source) 1) "Item effect")
    (and (string? source) (string/has-prefix? "rune/" source)) (icon "rune" ((string/split "/" source) 1) "Rune effect")
    (do (def ability (find |(= source ($ :id)) (get row :ability-settings [])))
      (if (and ability (not= "" (ability :icon))) (icon (ability :icon-group) (ability :icon) (ability :name))
        [:b source]))))

(defn- event-label [row event]
  (def source (event :source))
  (cond (= :attack source) "Basic attack"
    (and (string? source) (string/has-prefix? "item/" source)) (get (catalog/items ((string/split "/" source) 1)) :name source)
    (and (string? source) (string/has-prefix? "rune/" source))
    (get (find |(= (scan-number ((string/split "/" source) 1)) (get $ "id")) (scenarios/runes (catalog/current))) "name" source)
    (get (find |(= source ($ :id)) (get row :ability-settings [])) :name source)))

(defn- champion-ability? [ability]
  (some |(= (ability :slot) $) [:p :q :w :e :r]))
(defn- damage-ability? [ability]
  (some |(and (= :damage ($ :kind)) (= :estimated ($ :status))) (get ability :effects [])))

(defn coverage [result]
  (def row (result :selected))
  (def combat (row :combat))
  (def broad (some champion-ability? (get row :ability-settings [])))
  (def has-spells (or broad (and (= "Annie" ((result :champion) :id)) (get-in row [:ranks :q]))))
  [:details {:id "coverage" :class "scope-panel coverage-details" :data-preserve-attr "open" :aria-label "Build model coverage"}
   [:summary "Coverage & assumptions"]
   [:div {:class "section-header"} [:h2 "Unvalidated estimate"] [:span {:class "validation-badge"} "Patch data · not tested in-game"]]
   [:p (cond broad "Recognized tooltip effects use the selected patch's calculations. Your declared priority, activation conditions and movement drive this run. Unresolved conditions, alternate forms, pets and passive triggers remain explicit omissions."
         has-spells
         "Annie Q/W, learned-R penetration and ordinary attacks. E, R casts, Tibbers and stun excluded."
         "Ordinary basic attacks using base stats and item stats. Champion abilities, passives and special attack rules are excluded.")]
   [:p "Available data, implemented handlers and in-game checks remain separate. Item and rune effects contribute only where a handler exists; inventory restrictions and missing effects appear below."]
   (when (not (empty? (row :limitations)))
     [:details [:summary "Excluded effects & inventory notes (" (length (row :limitations)) ")"]
      [:ul (map |[:li $] (row :limitations))]])
   (when broad
     [:details {:class "ability-evidence"} [:summary "Ability descriptions and coverage"]
      (map (fn [ability]
             [:article [:strong (string/ascii-upper (string (ability :slot))) " · " (ability :name)]
              [:p "Data " (if (ability :available) "available" "unavailable") " · "
               (length (ability :effects)) " interpreted effects · " (length (ability :unresolved)) " unresolved · No in-game check"]
              [:p (normalize/plain (ability :tooltip))]]) (row :ability-settings))])
   (when (combat :assumptions) [:details [:summary "Simulation assumptions"] [:ul (map |[:li $] (combat :assumptions))]])
   (when (combat :sampling-note) [:p {:class "muted"} (combat :sampling-note)])])

(defn results [result]
  (def row (merge (result :selected) {:champion-id ((result :champion) :icon)}))
  (def state (result :state))
  (def duration (state :duration))
  (def totals (row :stats))
  (def combat (row :combat))
  (def spell-job (get result :spell-data-job))
  (def spell-champion (if (and (= "Annie" ((result :champion) :id)) (= "duel" (state :mode)))
                        (get-in result [:package :champion-map (state :opponent) :name] (state :opponent))
                        ((result :champion) :name)))
  (def broad (some champion-ability? (get row :ability-settings [])))
  (def damage-model (some damage-ability? (get row :ability-settings [])))
  (def has-spells (or damage-model (and (= "Annie" ((result :champion) :id)) (get-in row [:ranks :q]))))
  (def spell-label (if damage-model "Modeled abilities" "Q/W"))
  (def chart-title (if has-spells (string spell-label " + attacks over time") "Basic attacks over time"))
  [:div {:id "results" :class "results" :aria-live "polite" :data-attr:aria-busy "$busy"}
   [:div {:class "fight-strip"}
    [:button {:type "button" :class "quiet-action" :data-ui-toggle "fight-settings"} (if (= "practice" (state :mode)) "Practice target" (state :mode)) " ▾"]
    [:button {:type "button" :class "quiet-action" :data-ui-toggle "fight-settings"} duration " seconds"]
    [:button {:type "button" :class "quiet-action" :data-ui-toggle "optimizer" :data-text "'Goal: ' + $searchpreset"} "Goal: burst"]
    [:span {:class "validation-badge"} "Unvalidated estimate"]]
   [:div {:class "numbers outcome-summary"}
    (metric "Mean damage dealt" (combat :damage)) (metric "Damage per second" (combat :dps) true)
    [:span {:class "muted"} (get combat :samples 1) " trial(s) · graphs show trial 0"]]
   [:div {:id "combat-graphs" :class "combat-graphs"}
    [:span {:id "combat-trace" :hidden true :data-trace (json/encode (get combat :trace []))
            :data-scenario (get combat :scenario-id (string ((result :package) :snapshot) "/" (json/encode state)))}]
    [:section {:class "chart-panel" :aria-label "Damage timeline"}
     [:div {:class "section-header"} [:h2 chart-title] [:span {:class "muted"} "Cumulative damage"]]
     (when (or (not has-spells) spell-job)
       [:p {:class "chart-coverage muted"}
        (cond
          (and spell-job (some |(= $ (spell-job :status)) [:queued :running :cancelling]))
          (string "Downloading ability data for " spell-champion " and the rest of this patch. Current estimate shown until the download completes.")
          (and spell-job (= :failed (spell-job :status)))
          (string "Ability data download failed for " spell-champion ". Current estimate shown. Open Patch & evidence to retry.")
          (and spell-job (= :cancelled (spell-job :status)))
          (string "Ability data download cancelled for " spell-champion ". Current estimate shown. Open Patch & evidence to retry.")
          (and spell-job (= :done (spell-job :status))) "Ability data ready. Opening the completed patch…"
          broad
          (string "No supported spell damage for " ((result :champion) :name) " in this patch. Other ability effects may be modeled; see coverage.")
          (string "Spell damage unavailable for " ((result :champion) :name)
                  "; this estimate covers basic attacks. Spells: not modeled."))])
     (chart row duration chart-title)]
    [:div {:id "event-detail" :class "event-detail" :aria-label "Selected attack details"}
     [:span {:class "muted"} "Hover or select an attack to inspect its damage and state changes."]]
    (when (not (empty? (get combat :trace [])))
      [:div {:class "state-plots"} (state-chart combat duration :health "Health over time")
       (state-chart combat duration :resource "Resources over time")])
    [:div {:class "attack-header"} [:h2 "Attacks & effects"] [:span {:class "muted"} "Trial 0"]]
    [:div {:id "attack-events" :class "hit-list" :aria-label "Damage events"}
     (seq [[index event] :pairs (combat :events)]
       [:button {:type "button" :class "hit" :data-event index :data-label (event-label row event) :aria-pressed "false"
                 :aria-label (string (event :source) " at " (number-text (event :at) true) " seconds, " (number-text (event :damage)) " damage")}
        (event-icon row event) [:span (number-text (event :at) true) " s"]])]]
   (when (combat :metrics)
     [:details {:class "combat-outcomes"} [:summary "Outcome details"] [:div {:class "build-stats"}
                                                                        (stat "Health remaining" (number-text (get-in combat [:metrics :health])))
                                                                        (stat "Damage taken" (number-text (get-in combat [:metrics :damage-taken])))
                                                                        (stat "Healing" (number-text (get-in combat [:metrics :healing])))
                                                                        (stat "Absorbed" (number-text (get-in combat [:metrics :absorbed])))
                                                                        (stat "Effective control" (string (number-text (get-in combat [:metrics :control]) true) " s"))
                                                                        (stat "Kill / death chance" (string (number-text (* 100 (get-in combat [:metrics :kill-rate] 0))) "% / "
                                                                                                            (number-text (* 100 (get-in combat [:metrics :death-rate] 0))) "%"))
                                                                        (stat "Kill time (successful trials)" (if (get-in combat [:metrics :mean-kill-time]) (string (number-text (get-in combat [:metrics :mean-kill-time]) true) " s") "—"))
                                                                        (stat "Death time (successful trials)" (if (get-in combat [:metrics :mean-death-time]) (string (number-text (get-in combat [:metrics :mean-death-time]) true) " s") "—"))
                                                                        (stat "Sampling interval (damage)" (if (get-in combat [:uncertainty :damage]) (string "± " (number-text (get-in combat [:uncertainty :damage]))) "Unavailable"))]])
   (when (> (length (result :rows)) 1) [:details {:class "build-comparisons"} [:summary "Build comparisons"]
                                        [:section {:class "build-panel" :aria-label "Build comparisons"}
                                         [:div {:class "section-header"} [:h2 "Builds"]
                                          [:span {:class "muted"} (if (> (length (result :rows)) 1) "Custom + 3 Annie presets" "Custom inventory")]]
                                         (seq [[index candidate] :pairs (result :rows)] (build-row candidate index (state :selected)))]])
   (when (combat :damage-breakdown)
     [:details {:class "source-breakdown"}
      [:summary "Damage breakdown"]
      [:div {:class "damage-breakdown"}
       (map (fn [[source amount]]
              [:div (event-icon row {:source (if (= source "attack") :attack source)})
               [:span (event-label row {:source (if (= source "attack") :attack source)})] [:strong (number-text amount)]])
            (sorted (pairs (combat :damage-breakdown)) |(> ($0 1) ($1 1))))]])])

(defn error-result [message]
  [:div {:id "results" :class "results" :role "alert"}
   [:section {:class "error-panel"} [:h2 "Check the scenario"] [:p message]]])

(defn evidence-panel [evidence]
  [:details {:id "evidence" :class "evidence"}
   [:summary [:span "Model & evidence"] [:span {:class "muted"} (length evidence) " stat captures"]]
   [:div {:class "evidence-body"}
    [:div {:class "evidence-row"} [:span {:class "evidence-kind checked"} "✓ Checked in-game"]
     [:span "Annie stats at levels 1 and 6: baseline, Cloak, Void Staff and rank-one R penetration. Movement speed is excluded. These measurements do not verify combat damage."]]
    [:div {:class "measurement-list"}
     (map (fn [record]
            [:div [:span "Level " (record :level) " · "
                   (if (empty? (record :items)) "No items"
                     (if (= "1018" ((record :items) 0)) "Cloak" "Void Staff"))
                   " · R" (record :r-rank)]
             [:span {:class (if (= :consistent (record :status)) "checked" "measurement-error")}
              (if (= :consistent (record :status)) "✓ " "! ") (record :checked) " checked"]]) evidence)]
    [:div {:class "evidence-row"} [:span {:class "evidence-kind"} "◇ Patch data"]
     [:span (length (catalog/champion-list)) " champions and " (length (catalog/item-list))
      " items from the selected patch. All catalog entries are unvalidated. Character records supply base/growth and attack-speed values; permanent item stats come from structured fields and stat blocks. The five Annie captures verify only the stated conditions."]]
    [:div {:class "evidence-row"} [:span {:class "evidence-kind"} "~ Assumptions"]
     [:span "The initial Annie subset uses Q before W. Fetched kits use the declared priority and changing health/resources; see each result's assumptions. The five captures above belong to patch 26.19. Damage and timing remain unverified."]]]])

(defn signals [state]
  (def values (merge optimizer/defaults state {:savedmodel workspace/model-identity :scenariojson "" :busy false :editing 1 :editingwho "player" :patchchoice (state :patch) :job ""}))
  (each key [:priority :opponentpriority :skillorder :opponentskillorder :runes :opponentrunes]
    (put values key (string/join (map string (get state key [])) ",")))
  (each [source prefix] [[:summoners "summoner"] [:opponentsummoners "opponentsummoner"]]
    (for index 0 2 (put values (keyword (string prefix (inc index))) (get (get state source []) index ""))))
  (each [source prefix] [[:runes ""] [:opponentrunes "enemy"]]
    (for index 0 6 (put values (keyword (string prefix "runepage" (inc index))) (get (get state source []) index ""))))
  (each [prefix count] [["lockslot" 6] ["lockrune" 6] ["locksummoner" 2] ["lockskill" 18]]
    (for index 1 (inc count) (put values (keyword (string prefix index)) false)))
  values)
(defn page [result evidence &opt message]
  (def state (result :state))
  (render (html/doctype :html5)
          [:html {:lang "en"}
           [:head [:meta {:charset "utf-8"}] [:meta {:name "viewport" :content "width=device-width,initial-scale=1"}]
            [:title "PowerSpike · Build comparisons"] [:link {:rel "stylesheet" :href "/assets/app.css"}]
            [:link {:rel "icon" :href "/assets/champion/Annie.png"}]
            [:script {:type "module" :src "/assets/datastar.js"}] [:script {:defer true :src "/assets/app.js"}] [:script {:defer true :src "/assets/hud.js"}]]
           [:body
            [:div {:id "powerspike" :data-signals (json/encode (signals state))
                   :data-on:evaluate "if(document.getElementById('scenario').reportValidity()) @get('/evaluate', {requestCancellation: 'auto', retry: 'never'})"
                   :data-indicator:busy true :data-class:is-pending "$busy"}
             [:header {:class "top"} [:span {:class "brand"} "POWER" [:span "SPIKE"]]
              [:div {:class "top-meta"} [:button {:type "button" :class "quiet-action" :data-ui-toggle "patch-settings" :data-text "'Patch ' + $patch + ' ▾'"} "Patch " ((result :package) :patch) " ▾"]]]
             [:main {:class "content"} (loadout result) (native-inventory result)
              (if message (error-result message) (results result))
              [:div {:class "secondary-controls"} (fight-controls result) (ability-group result)
               [:button {:type "button" :class "optimizer-settings-open" :data-search-open true} "Optimization & restrictions"]
               (workspace/tools result)
               [:details {:id "patch-settings" :class "control-group" :data-on:jobtick "@get('/patches/status')"}
                [:summary [:span "Patch & evidence"] [:span {:class "muted"} "Sources · calibration"]]
                (patch-panel result (get result :patch-job)) (coverage result) (workspace/evidence result) (evidence-panel evidence)]]]
             [:aside {:id "detail-popover" :class "detail-popover" :popover "manual" :role "dialog" :aria-label "Element details"}]
             (optimizer/dialog result)
             (catalog-pickers)
             [:footer {:class "footer"} [:span (length (catalog/champion-list)) " champions · " (length (catalog/item-list)) " items"]
              [:span "Combat damage unverified"]
              [:small "PowerSpike is not endorsed by Riot Games and does not reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games and all associated properties are trademarks or registered trademarks of Riot Games, Inc."]]]]]))
