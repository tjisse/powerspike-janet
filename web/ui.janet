(import janet-html :as html)
(import jayson :as json)
(import ./catalog :as catalog)
(import ./model :as model)
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
      [:strong (get job :key "Patch download")]
      [:span (string " · " (job :status) " · " (progress :message))]
      (when active
        [[:progress {:max (max 1 (progress :total)) :value (progress :completed)}]
         [:button {:type "button" :data-on:click (string "@post('/jobs/cancel?id=" (job :id) "')")} "Cancel"]])
      (when (= :failed (job :status)) [:p (job :error)])
      (when (= :done (job :status))
        [:a {:class "apply" :href (string "/?patch=" ((job :result) :patch) "&snapshot=" ((job :result) :snapshot))
             :data-init (string "const next = new URL(location.href); next.searchParams.set('patch', '" ((job :result) :patch)
                                "'); next.searchParams.set('snapshot', '" ((job :result) :snapshot) "'); location.assign(next)")}
         "Open patch"])
      [:span {:id "patch-job-signals" :data-init (string "$job = '" (job :id) "'")}]])])

(defn- icon [group id description &opt class]
  [:img {:src (string "/assets/" ((catalog/current) :patch) "/" ((catalog/current) :snapshot) "/" group "/" id (if (string/has-suffix? ".png" id) "" ".png")) :alt description
         :width "64" :height "64" :class class :loading "lazy"}])
(defn- level-options [state]
  (seq [level :range [1 19]] [:option {:value level :selected (= level (state :level))} level]))

(defn- rank-markup [champion ranks &opt settings]
  [:div {:id "ranks" :class "spells"}
   (cond (not (empty? settings))
     (map (fn [ability]
            [:span {:class "spell" :title (string (ability :name) " · " (length (ability :unresolved)) " unresolved components")}
             (when (not= "" (ability :icon)) (icon (ability :icon-group) (ability :icon) (ability :name)))
             [:b (string/ascii-upper (string (ability :slot)))] (ability :rank)
             [:small (if (number? (ability :effective-cooldown))
                       (string (number-text (ability :effective-cooldown) true) "s") "CD unknown")]]) settings)
     (and (= "Annie" (champion :id)) (get ranks :q))
     [[:span {:class "spell"} (icon "spell" "AnnieQ" "Disintegrate") "Q" (ranks :q)]
      [:span {:class "spell"} (icon "spell" "AnnieW" "Incinerate") "W" (ranks :w)]
      [:span {:class "muted"} "R" (ranks :r) " passive"]]
     [:span {:class "muted"} "Abilities excluded"])])

(defn champion-display [result]
  (def champion (result :champion))
  [:div {:id "champion-display" :class "champion-display"}
   [:div {:class "portrait"} (icon "champion" (champion :icon) (champion :name))]
   [:div {:class "champion-title"} [:h1 (champion :name)]
    [:span {:class "muted"} (cond (not (empty? (get-in result [:selected :ability-settings]))) "Estimated abilities + attacks"
                              (and (= "Annie" (champion :id)) (get-in result [:selected :ranks :q])) "Q/W + basic attacks" "Basic attacks only")]
    (rank-markup champion ((result :selected) :ranks) ((result :selected) :ability-settings))]])

(defn scenario [result]
  (def state (result :state))
  [:form {:id "scenario" :class "scenario" :method "get" :action "/"
          :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"
          :data-on:input__debounce.200ms "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"
          :data-on:submit__prevent "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
   [:div {:class "champion"} (champion-display result)
    [:button {:class "catalog-open js-only" :type "button"
              :data-on:click "document.getElementById('champion-picker').showModal()"} "Change champion"]
    [:label {:class "native-only" :for "champion"} "Champion"
     [:select {:id "champion" :name "champion" :data-bind:champion true}
      (map (fn [champion] [:option {:value (champion :id) :selected (= (champion :id) (state :champion))}
                           (champion :name)]) (catalog/champion-list))]]]
   [:label {:for "level"} "Level"
    [:select {:id "level" :name "level" :data-bind:level true} (level-options state)]]
   [:label {:for "duration"} "Combat window (seconds)"
    [:input {:id "duration" :name "duration" :type "number" :min "0.5" :max "120" :step "0.5"
             :required true :value (state :duration) :data-bind:duration true}]]
   [:label {:for "mr"} "Target magic resistance"
    [:input {:id "mr" :name "mr" :type "number" :min "0" :max "1000" :step "1"
             :required true :value (state :mr) :data-bind:mr true}]]
   [:label {:for "armor"} "Target armor"
    [:input {:id "armor" :name "armor" :type "number" :min "0" :max "1000" :step "1"
             :required true :value (state :armor) :data-bind:armor true}]]
   [:label "Target health"
    [:input {:name "targethealth" :type "number" :min "1" :max "1000000" :value (get state :target-health 10000)
             :data-bind:targethealth true}]]
   [:label "Starting distance"
    [:input {:name "distance" :type "number" :min "0" :max "10000" :value (get state :distance 300) :data-bind:distance true}]]
   [:label "Fight"
    [:select {:name "mode" :data-bind:mode true}
     [:option {:value "practice" :selected (= "practice" (get state :mode "practice"))} "Practice target"]
     [:option {:value "duel" :selected (= "duel" (state :mode))} "Champion duel"]
     (map (fn [preset]
            [:option {:value (string (preset :id)) :selected (= (string (preset :id)) (state :mode))
                      :disabled (not (some |(and (= ($ :id) (preset :id)) ($ :available)) (get (result :package) :objectives [])))}
             (preset :name)]) objectives/presets)
     [:option {:value "legacy" :selected (= "legacy" (state :mode))} "Curated reference"]]]
   [:label {:data-show "$mode === 'duel'"} "Opponent"
    [:select {:name "opponent" :data-bind:opponent true}
     (map |[:option {:value ($ :id) :selected (= ($ :id) (get state :opponent "Garen"))} ($ :name)] (catalog/champion-list))]]
   [:label {:data-show "$mode === 'duel'"} "Opponent level"
    [:input {:name "opponentlevel" :type "number" :min 1 :max 18 :value (get state :opponentlevel 18) :data-bind:opponentlevel true}]]
   [:label "Trials"
    [:select {:name "samples" :data-bind:samples true}
     (map |[:option {:value $ :selected (= $ (get state :samples 1))} $] [1 8 32 64])]]
   [:label "Rune effects"
    [:select {:name "runes" :data-bind:runes true}
     [:option {:value "" :selected (empty? (get state :runes []))} "None"]
     (map |[:option {:value (get $ "id") :selected (some (fn [id] (= id (get $ "id"))) (get state :runes []))}
            (get $ "name")] (scenarios/runes (result :package)))]]
   (seq [index :range [0 2]]
     [:label (if (= index 0) "Summoner spell D" "Summoner spell F")
      [:select {:name (string "summoner" (inc index)) :data-bind (string "summoner" (inc index))}
       [:option {:value "" :selected (= "" (get (get state :summoners []) index ""))} "None"]
       (map (fn [spell] [:option {:value (spell "id") :selected (= (spell "id") (get (get state :summoners []) index ""))}
                         (spell "name")]) (filter |(some (fn [mode] (= "CLASSIC" mode)) (get $ "modes" [])) (get (result :package) :summoners [])))]])
   [:input {:type "hidden" :name "patch" :value (get state :patch ((result :package) :patch))}]
   [:input {:type "hidden" :name "snapshot" :value ((result :package) :snapshot)}]
   [:div {:class "scenario-notes"}
    [:span {:class "validation-badge"} "Unvalidated catalog"]
    [:span "Inventory " [:strong "6 slots · no budget limit"]]
    [:span "Effects " [:strong "Coverage below"]]
    [:span {:class "update-status" :role "status" :aria-live "polite" :data-text "$busy ? 'Updating…' : ''"} ""]]
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
   [:svg {:viewBox "0 0 864 185" :role "img" :aria-label title :class "state-chart"}
    [:title title]
    (seq [index :range [0 2]]
      (do (def path (string/join (seq [[i event] :pairs trace]
                                   (string (if (= i 0) "M " " L ") (x (event :at)) " "
                                           (y (get-in event [:before index field] (get-in event [:participants index field] 0)))
                                           " V " (y (get-in event [:participants index field] 0)))) ""))
        [:path {:d path :class (if (= 0 index) "chart-line" "chart-opponent")}]))
    [:text {:x 47 :y 178} "0 s"] [:text {:x 852 :y 178 :text-anchor "end"} duration " s"]]
   [:p {:class "muted"} "Gold: player · Violet: target/opponent"]])

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
       [:button {:type "button" :class (if item "item-slot" "item-slot empty-slot")
                 :data-attr:disabled "$busy"
                 :aria-label (string "Edit slot " (inc index) (if item (string ": " (item :name)) ": empty"))
                 :title (if item (item :name) "Add item")
                 :data-on:click (string seed "$editingwho = '" (if opponent "opponent" "player") "'; $editing = " (inc index)
                                        "; document.getElementById('item-picker').showModal()")}
        (if item (icon "item" (item :icon) (item :name)) "+")
        [:span {:class "slot-label"} (inc index)]]))])

(defn- setting [caption name value minimum maximum &opt step]
  [:label caption [:input {:form "scenario" :name name :id (string "setting-" name) :type "number" :required true
                           :min minimum :max maximum :step (or step 1) :value value :data-bind name}]])
(defn tactics [result]
  (def state (result :state))
  [:details {:id "tactics" :class "tactics scope-panel"
             :data-on:change "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"
             :data-on:input__debounce.300ms "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))"}
   [:summary "Fight conditions & ability settings"]
   [:div {:class "tactics-grid"}
    (setting "Seed" "seed" (get state :seed 1) 0 2147483647)
    (setting "Objective level" "objectivelevel" (get state :objectivelevel 10) 1 30)
    (setting "Game time (minutes)" "gametime" (get state :gametime 20) 0 120 0.5)
    [:label "Objective retaliation" [:input {:form "scenario" :type "checkbox" :name "retaliation" :checked (get state :retaliation true) :data-bind:retaliation true}]]
    [:label "Minions present at turret" [:input {:form "scenario" :type "checkbox" :name "minionspresent" :checked (get state :minionspresent true) :data-bind:minionspresent true}]]]
   (map (fn [opponent]
          (def prefix (if opponent "enemy" ""))
          (def stat-prefix (if opponent "opponent" ""))
          [:section {:class "tactics-participant" :data-show (if opponent "$mode === 'duel'" "true")}
           [:h2 (if opponent "Opponent strategy" "Player strategy")]
           [:div {:class "tactics-grid"}
            [:label "Ability priority"
             [:input {:form "scenario" :name (string stat-prefix "priority") :value (string/join (map string (get state (keyword (string stat-prefix "priority")) scenarios/slots)) ",")
                      :data-bind (string stat-prefix "priority")}]]
            [:label "Movement"
             [:select {:form "scenario" :name (string stat-prefix "movement") :data-bind (string stat-prefix "movement")}
              (map |[:option {:value $ :selected (= $ (get state (keyword (string stat-prefix "movement")) "approach"))}
                     (case $ "approach" "Approach into attack range" "hold" "Hold position" "Keep preferred range")] ["approach" "hold" "hold-range"])]]
            (setting "Preferred distance" (string stat-prefix "preferredrange") (get state (keyword (string stat-prefix "preferredrange")) 500) 0 10000)
            (setting "Hit chance (0–1)" (string stat-prefix "hitchance") (get state (if opponent :opponent-hit-chance :hit-chance) 1) 0 1 0.05)
            (setting "Starting health (fraction)" (string stat-prefix "healthfraction") (get state (if opponent :opponent-health-fraction :health-fraction) 1) 0.01 1 0.05)
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
              [:label "Opponent rune effects" [:select {:form "scenario" :name "opponentrunes" :data-bind:opponentrunes true}
                                               [:option {:value ""} "None"]
                                               (map |[:option {:value (get $ "id") :selected (some (fn [id] (= id (get $ "id"))) (get state :opponentrunes []))}
                                                      (get $ "name")] (scenarios/runes (result :package)))]]
              (seq [index :range [0 2]]
                [:label (string "Opponent summoner " (if (= index 0) "D" "F"))
                 [:select {:form "scenario" :name (string "opponentsummoner" (inc index)) :data-bind (string "opponentsummoner" (inc index))}
                  [:option {:value ""} "None"]
                  (map |[:option {:value ($ "id") :selected (= ($ "id") (get (get state :opponentsummoners []) index ""))} ($ "name")]
                       (filter |(some (fn [mode] (= mode "CLASSIC")) (get $ "modes" [])) (get (result :package) :summoners [])))]])])
           [:p {:class "muted"} "Automatic ranks use a standard skill order. Exceptional leveling, forms and decision rules remain listed as omissions."]]) [false true])])

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
   [:dialog {:id "item-picker" :class "catalog-dialog" :aria-labelledby "item-picker-title"}
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
            [:button {:type "button" :class "catalog-card" :hidden (not rift)
                      :data-item-id (item :id) :title (item :description)
                      :data-rift (if rift "true" "false")
                      :data-search (string (item :name) " " (item :id) " " (item :description) " " (string/join (item :tags) " "))
                      :data-on:click (string (string/join (seq [index :range [1 7]]
                                                            (string "if ($editing === " index ") { if ($editingwho === 'opponent') $enemyslot" index " = '" (item :id) "'; else $slot" index " = '" (item :id) "'; }")) " ")
                                             " if ($editingwho !== 'opponent') $selected = 'custom'; document.getElementById('item-picker').close(); "
                                             "document.getElementById('powerspike').dispatchEvent(new Event('evaluate'))")}
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
  (cond (= :attack source) [:b "AA"]
    (and (string? source) (string/has-prefix? "item/" source)) (icon "item" ((string/split "/" source) 1) "Item effect")
    (and (string? source) (string/has-prefix? "rune/" source)) [:b "Rune"]
    (do (def ability (find |(= source ($ :id)) (get row :ability-settings [])))
      (if (and ability (not= "" (ability :icon))) (icon (ability :icon-group) (ability :icon) (ability :name))
        [:b source]))))

(defn results [result]
  (def row (result :selected))
  (def state (result :state))
  (def duration (state :duration))
  (def totals (row :stats))
  (def combat (row :combat))
  (def broad (not (empty? (get row :ability-settings []))))
  (def has-spells (or broad (and (= "Annie" ((result :champion) :id)) (get-in row [:ranks :q]))))
  (def spell-label (if broad "Modeled abilities" "Q/W"))
  (def chart-title (if has-spells (string spell-label " + attacks over time") "Basic attacks over time"))
  [:div {:id "results" :class "results" :aria-live "polite" :data-attr:aria-busy "$busy"}
   [:div {:class "workspace"}
    [:section {:class "build-panel" :aria-label "Build comparisons"}
     [:div {:class "section-header"} [:h2 "Builds"]
      [:span {:class "muted"} (if (> (length (result :rows)) 1) "Custom + 3 Annie presets" "Custom inventory")]]
     (seq [[index candidate] :pairs (result :rows)] (build-row candidate index (state :selected)))]
    [:section {:class "loadout" :aria-label "Selected build"}
     [:div {:class "section-header"} [:h2 (row :name)] [:span {:class "muted"} (number-text (row :cost)) " gold"]]
     [:p {:class "inventory-note muted"} "Select a slot to add or replace an item."]
     (inventory row state)
     [:div {:class "numbers"}
      (metric (string (if has-spells (string spell-label " + attacks / ") "Basic attacks / ") duration " seconds") (combat :damage))
      (metric "Damage per second" (combat :dps) true)]
     (when (combat :metrics)
       [:div {:class "build-stats"}
        (stat "Health remaining" (number-text (get-in combat [:metrics :health])))
        (stat "Damage taken" (number-text (get-in combat [:metrics :damage-taken])))
        (stat "Healing" (number-text (get-in combat [:metrics :healing])))
        (stat "Absorbed" (number-text (get-in combat [:metrics :absorbed])))
        (stat "Effective control" (string (number-text (get-in combat [:metrics :control]) true) " s"))
        (stat "Kill / death chance" (string (number-text (* 100 (get-in combat [:metrics :kill-rate] 0))) "% / "
                                            (number-text (* 100 (get-in combat [:metrics :death-rate] 0))) "%"))
        (stat "Kill time (successful trials)" (if (get-in combat [:metrics :mean-kill-time]) (string (number-text (get-in combat [:metrics :mean-kill-time]) true) " s") "—"))
        (stat "Death time (successful trials)" (if (get-in combat [:metrics :mean-death-time]) (string (number-text (get-in combat [:metrics :mean-death-time]) true) " s") "—"))
        (stat "Sampling interval (damage)" (if (get-in combat [:uncertainty :damage]) (string "± " (number-text (get-in combat [:uncertainty :damage]))) "Unavailable"))])
     [:div {:class "build-stats"}
      (stat "Attack damage" (number-text (totals :ad) true))
      (stat "Attack speed" (number-text (totals :attack-speed) true))
      (stat "Crit chance" (string (number-text (* 100 (totals :crit-chance))) "%"))
      (stat "Health" (number-text (totals :hp)))
      (stat "Armor / MR" (string (number-text (totals :armor)) " / " (number-text (totals :mr))))
      (stat "Ability power" (number-text (totals :ap) true))
      (stat "Magic pen" (string (number-text (* 100 (totals :magic-pen-percent))) "% + " (totals :magic-pen-flat)))
      (stat "Armor pen" (string (number-text (* 100 (totals :armor-pen-percent))) "% + " (totals :armor-pen-flat)))
      (stat "Ability haste" (totals :ability-haste))]]]
   [:section {:class "scope-panel" :aria-label "Build model coverage"}
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
    (when (combat :sampling-note) [:p {:class "muted"} (combat :sampling-note)])]
   (when (combat :damage-breakdown)
     [:section {:class "scope-panel"}
      [:div {:class "section-header"} [:h2 "Mean damage by source"]]
      [:div {:class "damage-breakdown"}
       (map (fn [[source amount]]
              [:div (event-icon row {:source (if (= source "attack") :attack source)})
               [:span source] [:strong (number-text amount)]])
            (sorted (pairs (combat :damage-breakdown)) |(> ($0 1) ($1 1))))]])
   [:section {:class "chart-panel" :aria-label "Damage timeline"}
    [:div {:class "section-header"} [:h2 chart-title]
     [:span {:class "muted"} (if has-spells (string spell-label " " (number-text (* duration (combat :ability-dps)))) "Spells: not modeled")
      " · Attacks " (number-text (* duration (combat :attack-dps)))]]
    (unless has-spells
      [:p {:class "chart-coverage muted"} "Spell damage unavailable for " ((result :champion) :name)
       "; this estimate covers basic attacks."])
    (chart row duration chart-title)
    [:div {:class "hit-list" :aria-label "Damage events"}
     (map (fn [event]
            [:span {:class "hit" :title (string (number-text (event :damage)) " damage")}
             (event-icon row event)
             [:span (number-text (event :at) true) " s"]]) (combat :events))]]
   (when (not (empty? (get combat :trace []))) [(state-chart combat duration :health "Health over time")
                                                (state-chart combat duration :resource "Resources over time")])
   (when (= "duel" (state :mode))
     [:section {:class "loadout"}
      [:div {:class "section-header"} [:h2 "Opponent · " (get state :opponent "Garen")]
       (icon "champion" (get state :opponent "Garen") "Opponent")]
      (inventory row state true)
      [:div {:class "build-stats"}
       (map (fn [[key caption]] (stat caption (number-text (get-in row [:opponent :stats key] 0))))
            [[:hp "Health"] [:ad "Attack damage"] [:ap "Ability power"] [:armor "Armor"] [:mr "Magic resistance"]])]])])

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
  (def values (merge state {:busy false :editing 1 :editingwho "player" :patchchoice (state :patch) :job ""}))
  (each key [:priority :opponentpriority :runes :opponentrunes]
    (put values key (string/join (map string (get state key [])) ",")))
  (each [source prefix] [[:summoners "summoner"] [:opponentsummoners "opponentsummoner"]]
    (for index 0 2 (put values (keyword (string prefix (inc index))) (get (get state source []) index ""))))
  values)
(defn page [result evidence &opt message]
  (def state (result :state))
  (render (html/doctype :html5)
          [:html {:lang "en"}
           [:head [:meta {:charset "utf-8"}] [:meta {:name "viewport" :content "width=device-width,initial-scale=1"}]
            [:title "PowerSpike · Build comparisons"] [:link {:rel "stylesheet" :href "/assets/app.css"}]
            [:link {:rel "icon" :href "/assets/champion/Annie.png"}]
            [:script {:type "module" :src "/assets/datastar.js"}] [:script {:defer true :src "/assets/app.js"}]]
           [:body
            [:div {:id "powerspike" :data-signals (json/encode (signals state))
                   :data-on:jobtick "@get('/patches/status')"
                   :data-on:evaluate "if(document.getElementById('scenario').reportValidity()) @get('/evaluate', {requestCancellation: 'auto', retry: 'never'})"
                   :data-indicator:busy true :data-class:is-pending "$busy"}
             [:header {:class "top"} [:span {:class "brand"} "POWER" [:span "SPIKE"]] [:span {:class "patch"} "Patch " ((result :package) :patch)]]
             [:main {:class "content"} (patch-panel result nil) (scenario result) (tactics result) (native-inventory result)
              (if message (error-result message) (results result)) (evidence-panel evidence)]
             (catalog-pickers)
             [:footer {:class "footer"} [:span (length (catalog/champion-list)) " champions · " (length (catalog/item-list)) " items"]
              [:span "Combat damage unverified"]
              [:small "PowerSpike is not endorsed by Riot Games and does not reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games and all associated properties are trademarks or registered trademarks of Riot Games, Inc."]]]]]))
