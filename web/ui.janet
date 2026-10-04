(import janet-html :as html)
(import jayson :as json)
(import ./catalog :as catalog)
(import ./model :as model)

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

(defn- rank-markup [champion ranks]
  [:div {:id "ranks" :class "spells"}
   (if (get ranks :q)
     [[:span {:class "spell"} (icon "spell" "AnnieQ" "Disintegrate") "Q" (ranks :q)]
      [:span {:class "spell"} (icon "spell" "AnnieW" "Incinerate") "W" (ranks :w)]
      [:span {:class "muted"} "R" (ranks :r) " passive"]]
     [:span {:class "muted"} "Abilities excluded"])])

(defn champion-display [result]
  (def champion (result :champion))
  [:div {:id "champion-display" :class "champion-display"}
   [:div {:class "portrait"} (icon "champion" (champion :icon) (champion :name))]
   [:div {:class "champion-title"} [:h1 (champion :name)]
    [:span {:class "muted"} (if (get-in result [:selected :ranks :q]) "Q/W + basic attacks" "Basic attacks only")]
    (rank-markup champion ((result :selected) :ranks))]])

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
    [:input {:id "duration" :name "duration" :type "number" :min "0.5" :max "30" :step "0.5"
             :required true :value (state :duration) :data-bind:duration true}]]
   [:label {:for "mr"} "Target magic resistance"
    [:input {:id "mr" :name "mr" :type "number" :min "0" :max "1000" :step "1"
             :required true :value (state :mr) :data-bind:mr true}]]
   [:label {:for "armor"} "Target armor"
    [:input {:id "armor" :name "armor" :type "number" :min "0" :max "1000" :step "1"
             :required true :value (state :armor) :data-bind:armor true}]]
   [:div {:class "scenario-notes"}
    [:span {:class "validation-badge"} "Unvalidated catalog"]
    [:span "Inventory " [:strong "6 slots · no budget limit"]]
    [:span "Distance " [:strong "300"]] [:span "Runes " [:strong "Excluded"]]
    [:span {:class "update-status" :role "status" :aria-live "polite" :data-text "$busy ? 'Updating…' : ''"} ""]]
   [:noscript [:button {:type "submit" :name "selected" :value (state :selected) :class "apply"} "Update comparison"]]])

(defn ranks-fragment [result]
  (rank-markup (result :champion) ((result :selected) :ranks)))

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

(defn- inventory-ids [row state]
  (if (= "custom" (row :id)) (map |(get state $ "") model/slot-keys)
    (seq [index :range [0 6]] (get (row :ids) index ""))))

(defn- inventory [row state]
  (def ids (inventory-ids row state))
  (def seed (string/join (seq [index :range [0 6]]
                           (string "$slot" (inc index) " = '" (ids index) "'; ")) ""))
  [:div {:class "inventory" :aria-label "Six editable inventory slots"}
   (seq [index :range [0 6]]
     (do (def item (catalog/items (ids index)))
       [:button {:type "button" :class (if item "item-slot" "item-slot empty-slot")
                 :data-attr:disabled "$busy"
                 :aria-label (string "Edit slot " (inc index) (if item (string ": " (item :name)) ": empty"))
                 :title (if item (item :name) "Add item")
                 :data-on:click (string seed "$editing = " (inc index)
                                        "; document.getElementById('item-picker').showModal()")}
        (if item (icon "item" (item :icon) (item :name)) "+")
        [:span {:class "slot-label"} (inc index)]]))])

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
                                                     (string "if ($editing === " index ") $slot" index " = '';")) " ")
                                      " $selected = 'custom'; document.getElementById('item-picker').close(); "
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
                                                            (string "if ($editing === " index ") $slot" index " = '" (item :id) "';")) " ")
                                             " $selected = 'custom'; document.getElementById('item-picker').close(); "
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

(defn results [result]
  (def row (result :selected))
  (def state (result :state))
  (def duration (state :duration))
  (def totals (row :stats))
  (def combat (row :combat))
  (def has-spells (get-in row [:ranks :q]))
  (def chart-title (if has-spells "Q/W + attacks over time" "Basic attacks over time"))
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
      (metric (string (if has-spells "Q/W + attacks / " "Basic attacks / ") duration " seconds") (combat :damage))
      (metric "Damage per second" (combat :dps) true)]
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
    [:p (if has-spells
          "Annie Q/W, learned-R penetration and ordinary attacks. E, R casts, Tibbers and stun excluded."
          "Ordinary basic attacks using base stats and item stats. Champion abilities, passives and special attack rules are excluded.")]
    [:p "Inventory legality and item interactions are unvalidated. Runes, stacks, on-hit damage and conditional effects are excluded."]
    (when (not (empty? (row :limitations)))
      [:details [:summary "Excluded effects & inventory notes (" (length (row :limitations)) ")"]
       [:ul (map |[:li $] (row :limitations))]])]
   [:section {:class "chart-panel" :aria-label "Damage timeline"}
    [:div {:class "section-header"} [:h2 chart-title]
     [:span {:class "muted"} (if has-spells (string "Q/W " (number-text (* duration (combat :ability-dps)))) "Spells: not modeled")
      " · Attacks " (number-text (* duration (combat :attack-dps)))]]
    (unless has-spells
      [:p {:class "chart-coverage muted"} "Spell damage unavailable for " ((result :champion) :name)
       "; this estimate covers basic attacks."])
    (chart row duration chart-title)
    [:div {:class "hit-list" :aria-label "Damage events"}
     (map (fn [event]
            [:span {:class "hit" :title (string (number-text (event :damage)) " damage")}
             (if (= :attack (event :source)) [:b "AA"] (icon "spell" (event :source) (event :source)))
             [:span (number-text (event :at) true) " s"]]) (combat :events))]]])

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
     [:span "Attack windup 30%; basic-attack travel zero. Q before W; fixed target armor, resistance and health. Rune effects excluded. Damage and timing remain unverified."]]]])

(defn page [result evidence &opt message]
  (def state (result :state))
  (render (html/doctype :html5)
          [:html {:lang "en"}
           [:head [:meta {:charset "utf-8"}] [:meta {:name "viewport" :content "width=device-width,initial-scale=1"}]
            [:title "PowerSpike · Build comparisons"] [:link {:rel "stylesheet" :href "/assets/app.css"}]
            [:link {:rel "icon" :href "/assets/champion/Annie.png"}]
            [:script {:type "module" :src "/assets/datastar.js"}] [:script {:defer true :src "/assets/app.js"}]]
           [:body
            [:div {:id "powerspike" :data-signals (json/encode (merge state {:busy false :editing 1 :patchchoice (state :patch) :job ""}))
                   :data-on:jobtick "@get('/patches/status')"
                   :data-on:evaluate "if(document.getElementById('scenario').reportValidity()) @get('/evaluate', {requestCancellation: 'auto', retry: 'never'})"
                   :data-indicator:busy true :data-class:is-pending "$busy"}
             [:header {:class "top"} [:span {:class "brand"} "POWER" [:span "SPIKE"]] [:span {:class "patch"} "Patch " ((result :package) :patch)]]
             [:main {:class "content"} (patch-panel result nil) (scenario result) (native-inventory result)
              (if message (error-result message) (results result)) (evidence-panel evidence)]
             (catalog-pickers)
             [:footer {:class "footer"} [:span (length (catalog/champion-list)) " champions · " (length (catalog/item-list)) " items"]
              [:span "Combat damage unverified"]
              [:small "PowerSpike is not endorsed by Riot Games and does not reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games and all associated properties are trademarks or registered trademarks of Riot Games, Inc."]]]]]))
