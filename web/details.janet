(import ./catalog :as catalog)
(import jayson :as json)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/tooltip :as parser)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/runes :as rune-data)
(import ./tooltip :as tooltip)

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
  (tooltip/lines description))
(defn scenario-context [definition &opt opponent]
  (when (get definition :player)
    (def actors ((scenario/compile definition) :actors))
    (def index (if opponent 1 0))
    (engine/context (engine/state (actors index) index) (engine/state (actors (- 1 index)) (- 1 index)) 1)))
(defn attrs [payload &opt pinnable]
  {:data-details (json/encode payload) :data-detail-pin (if pinnable "true" "false") :aria-haspopup "dialog"})
(defn amount [value]
  (if (number? value) (string/format "%.2f" value) (string value)))

(defn simulation-notes [notes]
  # Keep omissions and numerical assumptions; verification-only annotations stay
  # in the developer view. Never change the underlying engine diagnostics.
  (distinct
    (map (fn [note]
           (var text note)
           (each [from to] [["; unvalidated." "."]
                            ["; server scaling remains unvalidated." "; server-specific scaling is not included."]
                            ["trigger handler unavailable" "effect not included"]
                            ["require handlers" "are not included"]
                            ["requires a handler" "is not included"]
                            ["requires an explicit trigger handler" "is not included"]]
             (set text (string/replace-all from to text)))
           text)
         (filter |(and (not (string/has-prefix? "Character root supplies base stats;" $))
                       (not (string/has-suffix? ": patch-derived estimate; unvalidated in-game." $))) (or notes [])))))

(def stat-labels
  [[:hp "Health"] [:mp "Mana"] [:ad "Attack damage"] [:ap "Ability power"] [:armor "Armor"] [:mr "Magic resist"]
   [:ability-haste "Ability haste"] [:attack-speed "Attack speed"] [:attack-speed-bonus "Bonus attack speed"]
   [:crit-chance "Critical strike chance"] [:attack-range "Attack range"] [:move-speed "Move speed"] [:hp-regen "Health regeneration / 5 s"]
   [:mp-regen "Mana regeneration / 5 s"] [:magic-pen-flat "Flat magic penetration"] [:magic-pen-percent "Magic penetration"]
   [:armor-pen-flat "Lethality"] [:armor-pen-percent "Armor penetration"]])
(defn stat-rows [stats]
  (seq [[key caption] :in stat-labels :when (and (number? (get stats key)) (not= 0 (stats key)))]
    [caption (if (some |(= key $) [:attack-speed-bonus :crit-chance :magic-pen-percent :armor-pen-percent])
               (string (amount (* 100 (stats key))) "%") (amount (stats key)))]))
(defn champion [champion level totals]
  {:name (champion :name) :icon (asset "champion" (champion :icon)) :subtitle (string "Level " level " · champion")
   :stats (stat-rows totals) :body (lines (get champion :description ""))
   :coverage "Champion stats with this build at the selected level." :action "champion-picker" :action-label "Change champion"})
(defn item [item &opt context]
  (def tooltip (get item :tooltip (item :description)))
  (def start (string/find "<stats>" tooltip))
  (def end (string/find "</stats>" tooltip))
  (def body (if (and start end) (string (string/slice tooltip 0 start) (string/slice tooltip (+ end 8))) tooltip))
  {:name (item :name) :icon (asset "item" (item :icon)) :subtitle (string (item :gold) " gold · item")
   :stats (stat-rows (get item :stats {})) :body (lines body)
   :body-rich (tooltip/body body (effects/item-tooltip-variables item context) (when context (merge context {:hide-rank true})))
   :coverage "Item description for this patch. See Simulation details for effects not included in the fight."
   :action "item-picker" :action-label "Change item"})
(defn ability [ability]
  {:name (ability :name) :icon (asset (ability :icon-group) (ability :icon))
   :subtitle (string (string/ascii-upper (string (ability :slot))) (if (> (ability :rank) 0) (string " · rank " (ability :rank)) " · Locked (not learned)"))
   :stats [["Cooldown" (cond (= 0 (ability :rank)) "Not learned"
                         (number? (ability :effective-cooldown)) (string (amount (ability :effective-cooldown)) " s")
                         "Not available")]]
   :body (lines (get ability :tooltip ""))
   :body-rich (tooltip/body (get ability :tooltip "") (get ability :variables []) (when (> (ability :rank) 0) (ability :tooltip-context)))
   :coverage "Calculated values use this build at the start of the fight. See Simulation details for effects not included."
   :action "ability-settings" :action-label "Ability settings"})
(defn rune [rune &opt context]
  (def interpreted (when context (rune-data/compile [rune] (get context :patch "unknown") (context :level))))
  {:name (rune "name") :icon (asset "rune" (string (rune "id"))) :subtitle "Rune"
   :stats (when interpreted
            [;(mapcat stat-rows (interpreted :stats))
             ;(if (not (empty? (interpreted :rules)))
                [["Damage bonus at fight start"
                  (string (tooltip/number (* 100 (- (rune-data/damage-multiplier (interpreted :rules)
                                                                                 (get-in context [:stats :health-percent] 1)
                                                                                 (/ (get-in context [:target :health] 1) (get-in context [:target :hp] 1)) :magic (context :champion-target)) 1))) "%")]] [])])
   :body (lines (get rune "longDesc" (get rune "shortDesc" "")))
   :body-rich (tooltip/body (get-in rune [:parsed :tooltip] (get rune "longDesc" (get rune "shortDesc" "")))
                            (get-in rune [:parsed :variables] []) (when context (merge context {:hide-rank true})))
   :coverage "Rune description for this patch. See Simulation details for effects not included."
   :action "rune-editor" :action-label "Edit rune page"})
(defn summoner [spell &opt context]
  (def text (get spell "tooltip" (get spell "description" "")))
  (def parsed (parser/parse text (get spell :record {}) spell))
  {:name (spell "name") :icon (asset "spell" (get-in spell ["image" "full"])) :subtitle "Summoner spell"
   :stats [["Cooldown" (string (get-in spell ["cooldown" 0] "Unknown") " s")]]
   :body (lines text) :body-rich (tooltip/body text (parsed :variables) (when context (merge context {:hide-rank true})))
   :coverage "Spell description for this patch. Activation follows your fight strategy."
   :action "ability-settings" :action-label "Spell settings"})
(defn loadout-effects [package state &opt context]
  [;(map (fn [id modifier]
           {:kind "shard" :id id :short (case id 5005 "AS" 5007 "AH" 5010 "MS" 5008 (if (modifier :ap) "AP" "AD") "HP")
            :details {:name (rune-data/shard-names id) :subtitle (string "Stat shard · level " (context :level))
                      :stats (stat-rows modifier) :body [] :coverage "Selected patch's numerical values. Included in this build and combat simulation."}})
         (filter |(not= $ 0) (get context :shards [])) (get context :shard-bonuses []))
   ;(map (fn [id] (def record (find |(= id (get $ "id")) (scenario/runes package)))
           (when record {:kind "rune" :id id :details (rune record context)})) (get state :runes []))
   ;(map (fn [id] (def record (find |(= id (get $ "id")) (get package :summoners [])))
           (when record {:kind "summoner" :id id :details (summoner record context)})) (get state :summoners []))])
