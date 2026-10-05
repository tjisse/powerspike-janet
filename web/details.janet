(import ./catalog :as catalog)
(import jayson :as json)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/data-util :as util)

(defn rune-source [package file]
  (def id (scan-number (string/slice file 0 -4)))
  (def record (find |(= id (get $ "id")) (scenario/runes package)))
  (assert record "Rune image unavailable on this patch.")
  (def path (get record "icon" ""))
  (assert (and (string/has-prefix? "perk-images/" path) (string/has-suffix? ".png" path)
               (all (fn [part] (and (util/safe-id? part) (not= "." part) (not= ".." part))) (string/split "/" path)))
          "Invalid rune image reference.")
  (string "https://ddragon.leagueoflegends.com/cdn/img/" path))

(defn asset [group id]
  (when (and id (not= "" id))
    (string "/assets/" ((catalog/current) :patch) "/" ((catalog/current) :snapshot) "/" group "/" id
            (if (string/has-suffix? ".png" id) "" ".png"))))
(defn lines [description]
  (var text (or description ""))
  (each tag ["<br>" "<br/>" "<br />" "</p>"] (set text (string/replace-all tag "\n" text)))
  (take 20 (filter |(not= "" $) (map string/trim (string/split "\n" (normalize/plain text))))))
(defn attrs [payload &opt pinnable]
  {:data-details (json/encode payload) :data-detail-pin (if pinnable "true" "false") :aria-haspopup "dialog"})
(defn amount [value]
  (if (number? value) (string/format "%.2f" value) (string value)))
(def stat-labels
  [[:hp "Health"] [:mp "Mana"] [:ad "Attack damage"] [:ap "Ability power"] [:armor "Armor"] [:mr "Magic resist"]
   [:ability-haste "Ability haste"] [:attack-speed "Attack speed"] [:attack-speed-bonus "Bonus attack speed"]
   [:crit-chance "Critical strike chance"] [:move-speed "Move speed"] [:hp-regen "Health regeneration / 5 s"]
   [:mp-regen "Mana regeneration / 5 s"] [:magic-pen-flat "Flat magic penetration"] [:magic-pen-percent "Magic penetration"]
   [:armor-pen-flat "Lethality"] [:armor-pen-percent "Armor penetration"]])
(defn stat-rows [stats]
  (seq [[key caption] :in stat-labels :when (and (number? (get stats key)) (not= 0 (stats key)))]
    [caption (if (some |(= key $) [:attack-speed-bonus :crit-chance :magic-pen-percent :armor-pen-percent])
               (string (amount (* 100 (stats key))) "%") (amount (stats key)))]))
(defn champion [champion level totals]
  {:name (champion :name) :icon (asset "champion" (champion :icon)) :subtitle (string "Level " level " · champion")
   :stats (stat-rows totals) :body (lines (get champion :description ""))
   :coverage "Source stats and modeled bonuses. In-game checks remain in the evidence view." :action "champion-picker" :action-label "Change champion"})
(defn item [item]
  (def tooltip (get item :tooltip (item :description)))
  (def start (string/find "<stats>" tooltip))
  (def end (string/find "</stats>" tooltip))
  (def body (if (and start end) (string (string/slice tooltip 0 start) (string/slice tooltip (+ end 8))) tooltip))
  {:name (item :name) :icon (asset "item" (item :icon)) :subtitle (string (item :gold) " gold · item")
   :stats (stat-rows (get item :stats {})) :body (lines body)
   :coverage "Patch description. Effects contribute only where the engine has a handler; see coverage for exclusions."
   :action "item-picker" :action-label "Change item"})
(defn ability [ability]
  {:name (ability :name) :icon (asset (ability :icon-group) (ability :icon))
   :subtitle (string (string/ascii-upper (string (ability :slot))) " · rank " (ability :rank))
   :stats [["Cooldown" (if (number? (ability :effective-cooldown)) (string (amount (ability :effective-cooldown)) " s") "Unresolved")]
           ["Interpreted effects" (length (get ability :effects []))] ["Unresolved components" (length (get ability :unresolved []))]]
   :body (lines (get ability :tooltip "")) :coverage "Parsed ability · no in-game damage check. Unresolved tooltip variables remain visible."
   :action "ability-settings" :action-label "Ability settings"})
(defn rune [rune]
  {:name (rune "name") :icon (asset "rune" (string (rune "id"))) :subtitle "Rune"
   :stats [] :body (lines (get rune "longDesc" (get rune "shortDesc" "")))
   :coverage "Patch description · no in-game check. Missing rune handlers are reported in coverage."
   :action "rune-editor" :action-label "Edit rune page"})
(defn summoner [spell]
  {:name (spell "name") :icon (asset "spell" (get-in spell ["image" "full"])) :subtitle "Summoner spell"
   :stats [["Cooldown" (string (get-in spell ["cooldown" 0] "Unknown") " s")]]
   :body (lines (get spell "tooltip" (get spell "description" "")))
   :coverage "Source description · unvalidated estimate. Activation rules belong to the fight strategy."
   :action "ability-settings" :action-label "Spell settings"})
(defn loadout-effects [package state]
  [;(map (fn [id] (def record (find |(= id (get $ "id")) (scenario/runes package)))
           (when record {:kind "rune" :id id :details (rune record)})) (get state :runes []))
   ;(map (fn [id] (def record (find |(= id (get $ "id")) (get package :summoners [])))
           (when record {:kind "summoner" :id id :details (summoner record)})) (get state :summoners []))])
