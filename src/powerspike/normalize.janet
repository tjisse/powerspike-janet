(import ./tooltip :as tooltip)
(import ./expressions :as expr)
(import pshash :as hash)
(import ./data-util :as util)

(def parser-version "2")
(def semantic-rules ((util/read-data "data/semantic-overrides.jdn") :rules))
(defn patch-order [patch]
  (def parts (string/split "." (string/replace "lolpatch_" "" patch)))
  (+ (* 1000000 (or (scan-number (get parts 0 "")) 0))
     (* 1000 (or (scan-number (get parts 1 "")) 0)) (or (scan-number (get parts 2 "")) 0)))
(defn applicable-rules [id patch]
  (filter |(and (= id ($ :champion)) (<= (patch-order ($ :patch-min)) (patch-order patch) (patch-order ($ :patch-max)))) semantic-rules))

(defn plain [text]
  (def out @"")
  (var tag false)
  (each byte (string/bytes (or text ""))
    (cond (= byte 60) (set tag true)
      (= byte 62) (do (set tag false) (buffer/push-byte out 32))
      (not tag) (buffer/push-byte out byte)))
  (var value (string out))
  (each [from to] [["&nbsp;" " "] ["&amp;" "&"] ["&lt;" "<"] ["&gt;" ">"]]
    (set value (string/replace-all from to value)))
  (string/trim value))

(defn number-field [record key fallback]
  (def raw (get record key fallback))
  (def value (if (dictionary? raw) (get raw "baseValue" fallback) raw))
  (if (number? value) value fallback))

(def structured-stats {"FlatHPPoolMod" :hp "FlatMPPoolMod" :mp "FlatPhysicalDamageMod" :ad
                       "FlatMagicDamageMod" :ap "FlatArmorMod" :armor "FlatSpellBlockMod" :mr
                       "FlatMovementSpeedMod" :move-speed "PercentMovementSpeedMod" :move-speed-percent
                       "PercentAttackSpeedMod" :attack-speed-bonus "FlatCritChanceMod" :crit-chance})
(def text-stats {"Health" [:hp 1] "Mana" [:mp 1] "Attack Damage" [:ad 1] "Ability Power" [:ap 1]
                 "Armor" [:armor 1] "Magic Resist" [:mr 1] "Ability Haste" [:ability-haste 1]
                 "Lethality" [:armor-pen-flat 1] "Magic Penetration" [:magic-pen-flat 1]
                 "% Magic Penetration" [:magic-pen-percent 0.01] "% Armor Penetration" [:armor-pen-percent 0.01]
                 "% Attack Speed" [:attack-speed-bonus 0.01] "% Critical Strike Chance" [:crit-chance 0.01]
                 "% Critical Strike Damage" [:crit-damage-bonus 0.01] "Move Speed" [:move-speed 1]
                 "% Move Speed" [:move-speed-percent 0.01] "Health Regen per 5 seconds" [:hp-regen 1]
                 "Mana Regen per 5 seconds" [:mp-regen 1]})

(defn stat-block [description]
  (def begin (string/find "<stats>" description))
  (def end (string/find "</stats>" description))
  (if (and begin end (< begin end)) (string/slice description (+ begin 7) end) ""))

(defn item [patch id source]
  (def totals @{})
  (def limitations @[])
  (eachp [key value] (get source "stats" {})
    (cond (structured-stats key) (put totals (structured-stats key) value)
      (= key "FlatHPRegenMod") (put totals :hp-regen (* 5 value))
      (and (number? value) (not= 0 value))
      (array/push limitations (string "Unmodeled stat: " key))))
  (def description (get source "description" ""))
  (each raw (string/split "<br>" (string/replace-all "<br />" "<br>" (stat-block description)))
    (def text (plain raw))
    (unless (= text "")
      (def parsed (peg/match ~(* '(* (some (range "09")) (? (* "." (some (range "09")))))
                                 '(? "%") (any (set " \t")) '(any 1) -1) text))
      (def rule (when parsed (text-stats (string (if (= "%" (parsed 1)) "% " "") (parsed 2)))))
      (if rule (put totals (rule 0) (* (scan-number (parsed 0)) (rule 1)))
        (array/push limitations (string "Unmodeled stat line: " text)))))
  (unless (= description (stat-block description))
    (array/push limitations "Passive and active effects await effect parsing."))
  {:patch patch :id id :name (source "name") :icon ((source "image") "full")
   :gold ((source "gold") "total") :purchasable ((source "gold") "purchasable")
   :in-store (get source "inStore" true) :maps (seq [[map enabled] :pairs (source "maps") :when enabled] (scan-number map))
   :stats totals :status "unvalidated" :supported true :stackable false :groups []
   :required-champion (get source "requiredChampion" "") :tags (get source "tags" [])
   :description (plain description) :tooltip description :limitations limitations
   :from (get source "from" []) :into (get source "into" []) :source source})

(defn champion [patch source objects]
  (def root-path (string "Characters/" (source "id") "/CharacterRecords/Root"))
  (def root (get objects root-path {}))
  (def dd (source "stats"))
  (def base @{})
  (def growth @{})
  (each [stat field dd-field growth-field dd-growth scale]
    [[:hp "baseHPModifiable" "hp" "hpPerLevelModifiable" "hpperlevel" 1]
     [:ad "baseDamageModifiable" "attackdamage" "damagePerLevelModifiable" "attackdamageperlevel" 1]
     [:armor "baseArmorModifiable" "armor" "armorPerLevelModifiable" "armorperlevel" 1]
     [:mr "baseMR" "spellblock" "mrPerLevel" "spellblockperlevel" 1]
     [:hp-regen "baseStaticHPRegenModifiable" "hpregen" "hpRegenPerLevelModifiable" "hpregenperlevel" 5]]
    (put base stat (* scale (number-field root field (/ (get dd dd-field 0) scale))))
    (put growth stat (* scale (number-field root growth-field (/ (get dd dd-growth 0) scale)))))
  (put base :move-speed (number-field root "baseMoveSpeedModifiable" (get dd "movespeed" 0)))
  (each [stat field grow-field] [[:mp "mp" "mpperlevel"] [:mp-regen "mpregen" "mpregenperlevel"]]
    (put base stat (get dd field 0)) (put growth stat (get dd grow-field 0)))
  {:patch patch :id (source "id") :name (source "name") :title (source "title")
   :icon ((source "image") "full") :tags (source "tags") :resource (source "partype")
   :base base :growth growth :status "unvalidated" :abilities [] :root root-path
   :attack-speed-base (number-field root "attackSpeedModifiable" (get dd "attackspeed" 0.625))
   :attack-speed-ratio (number-field root "attackSpeedRatioModifiable" (get dd "attackspeed" 0.625))
   :attack-speed-growth (/ (number-field root "attackSpeedPerLevelModifiable" (get dd "attackspeedperlevel" 0)) 100)
   :attack-speed-cap 2.5 :crit-damage (number-field root "critDamageMultiplier" 1.75)
   :attack-range (get dd "attackrange" 125)
   :limitations [(if (empty? root) "Character record unavailable; Data Dragon fallback stats." "Character root supplies base stats; ability coverage is reported separately.")
                 "Special champion attack rules and transformations require handlers."
                 "Attack-speed cap 2.5 and windup 30% remain estimates."]})

(defn spell-paths [id root]
  # Current references take precedence over legacy names and old extracted spells.
  (or (get root "spells")
      (map |(if (string/has-prefix? "Characters/" $) $ (string "Characters/" id "/Spells/" $))
           (get root "spellNames" []))))

(defn ability [slot path object dd fonts &opt patch]
  (def spell (merge (get object "mSpell" {}) {"__powerspike_patch" (or patch "16.19.1")}))
  (def client (get-in spell ["mClientData" "mTooltipData"] {}))
  (def key (or (get-in client ["mLocKeys" "keyTooltip"]) (get client "keyTooltip")))
  (def text (or (when key (or (get fonts key) (get fonts (string/ascii-lower key)) (get fonts (hash/tooltip-key (string/ascii-lower key)))))
                (get dd "tooltip") (get dd "description") ""))
  (def parsed (merge @{} (tooltip/parse text spell dd)))
  (when (= slot :p)
    (put parsed :effects (map |(merge $ {:trigger :unresolved :status :unresolved}) (parsed :effects)))
    (array/push (parsed :unresolved) "Passive activation requires an explicit trigger handler."))
  (def maxrank (get dd "maxrank" (if (= slot :r) 3 (if (= slot :p) 1 5))))
  (def problems (array ;(parsed :unresolved)))
  (when (empty? object) (array/push problems "Current spell record unavailable."))
  (when (empty? text) (array/push problems "Ability tooltip unavailable."))
  (when (empty? (parsed :effects)) (array/push problems "No recognized executable effect; this does not imply zero damage."))
  (each [term note] [["recast" "Recasts/charges need explicit semantics."]
                     ["pet" "Pet behavior needs a handler."] ["tibbers" "Tibbers behavior needs a handler."]
                     ["stack" "Stack state requires explicit triggers."] ["minions" "Minion-specific rules are outside champion estimates."]]
    (when (string/find term (string/ascii-lower text)) (array/push problems note)))
  (merge parsed {:slot slot :path path :id (or (get object "ObjectName") (get dd "id") (string slot))
                 :name (get dd "name" (or (get object "ObjectName") (string slot)))
                 :icon (get-in dd ["image" "full"] "") :icon-group (if (= slot :p) "passive" "spell")
                 :max-rank maxrank :available (or (not (empty? object)) (not (empty? dd))) :checked false
                 :cooldown (if (get dd "cooldown") (expr/ranked (dd "cooldown") -1 "Data Dragon cooldown")
                             (expr/ranked (get spell "cooldownTime") 0 "CommunityDragon cooldown"))
                 :cost (if (get dd "cost") (expr/ranked (dd "cost") -1 "Data Dragon resource cost")
                         (expr/ranked (get-in spell ["manaValues" "values"]) -1 "CommunityDragon resource cost"))
                 :range (if (get dd "range") (expr/ranked (dd "range") -1 "Data Dragon range")
                          (expr/ranked (or (get spell "castRangeDisplayOverride") (get spell "castRange")) 0 "CommunityDragon range"))
                 :cast-time (get spell "mCastTime" (get spell "spellCastTime" 0.25))
                 :missile-speed (get spell "missileSpeed" 0)
                 :unresolved problems :record spell}))

(defn kit [id objects detail fonts &opt patch]
  (def root (get objects (string "Characters/" id "/CharacterRecords/Root") {}))
  (def paths (spell-paths id root))
  (def dd (get-in detail ["data" id] {}))
  (def abilities @[])
  (eachp [index slot] [:q :w :e :r]
    (def path (get paths index ""))
    (array/push abilities (ability slot path (get objects path {}) (get (get dd "spells" []) index {}) fonts (get detail "version" (or patch "unknown")))))
  (def passive-path (get root "mCharacterPassiveSpell" ""))
  (array/push abilities (ability :p passive-path (get objects passive-path {}) (get dd "passive" {}) fonts (get detail "version" (or patch "unknown"))))
  (def penetration @{})
  (each rule (applicable-rules id (get detail "version" (or patch "unknown")))
    (def chosen (find |(= ($ :slot) (rule :slot)) abilities))
    (when chosen
      (def index (find-index |(= ($ :slot) (rule :slot)) abilities))
      (def effects (when (rule :effects)
                     (map (fn [spec]
                            (def amount (expr/variable (spec :variable) (chosen :record)))
                            (merge spec {:id (string id "/" (rule :slot) "/" (spec :variable)) :amount amount
                                         :target :enemy :trigger (get spec :trigger :cast) :condition :always
                                         :duration (when (spec :duration-variable) (expr/variable (spec :duration-variable) (chosen :record)))
                                         :status (if (empty? (expr/problems amount)) :estimated :unresolved)
                                         :evidence {:tooltip (rule :note) :override true}})) (rule :effects))))
      (put abilities index (merge chosen {:effects (or effects (chosen :effects))
                                          :unresolved [;(chosen :unresolved) (rule :note)]}))
      (when (rule :rank-penetration)
        (def bonuses (tabseq [[stat name] :pairs (rule :rank-penetration)
                              :let [values (expr/lookup (expr/named-values (chosen :record)) name)]
                              :when (and (indexed? values) (not (empty? values)))] stat values))
        (unless (empty? bonuses) (put penetration (rule :slot) bonuses)))))
  {:abilities abilities
   :rank-penetration penetration
   :forms (seq [[path object] :pairs objects
                :when (and (= "SpellObject" (get object "__type"))
                           (not= path passive-path) (not (some |(= $ path) paths)))]
            {:path path :id (get object "ObjectName") :record (get object "mSpell" {}) :status :unresolved})
   :coverage {:available (count |($ :available) abilities)
              :implemented (sum (map |(count (fn [effect] (= :estimated (effect :status))) ($ :effects)) abilities))
              :checked 0 :unresolved (mapcat |($ :unresolved) abilities)}})

(defn localized [fonts key fallback]
  (or (when (string? key) (or (get fonts key) (get fonts (string/ascii-lower key)) (get fonts (hash/tooltip-key (string/ascii-lower key))))) fallback))
(defn item-effects [record objects fonts]
  (def raw (get objects (string "Items/" (record :id)) {}))
  (def key (get-in raw ["mItemDataClient" "mTooltipData" "mLocKeys" "keyTooltip"]))
  (def text (localized fonts key (record :tooltip)))
  (def spell {"mDataValues" (get raw "mDataValues" []) "mSpellCalculations" (get raw "mItemCalculations" {}) "__powerspike_patch" (record :patch)})
  (def parsed (tooltip/parse text spell))
  (def limits (tabseq [key :in (get raw "mItemGroups" [])
                       :let [limit (get-in objects [key "mMaxGroupOwnable"])] :when (number? limit)] key limit))
  (def stats (merge @{} (record :stats)))
  # This passive is numerical data plus an explicit semantic interpretation.
  (when (= "3089" (record :id))
    (def amp (expr/lookup (expr/named-values spell) "APAmp"))
    (when amp (put stats :ap-multiplier (+ 1 (amp 1)))))
  (merge record {:effects (parsed :effects) :effect-variables (parsed :variables) :record raw
                 :tooltip text :group-limits limits :groups (keys limits)
                 :stackable (not (some |(= 1 $) (values limits))) :stats stats
                 :limitations [;(record :limitations) ;(parsed :unresolved)]}))

(defn rune-effects [styles objects fonts &opt patch]
  (map (fn [style]
         (merge style {"slots" (map (fn [slot]
                                      (merge slot {"runes" (map (fn [rune]
                                                                  (def raw (find |(and (dictionary? $) (= (rune "id") (get $ "mPerkId"))) (values objects)))
                                                                  (def script (get-in raw ["mScript" "mSpellScriptData"] {}))
                                                                  (def spell {"__powerspike_patch" (or patch "unknown") "mDataValues" (seq [[name value] :pairs (get script "mEffectAmount" {})]
                                                                                                                                        {"mName" name "mValue" value})
                                                                              "mSpellCalculations" (get script "mCalculations" {})})
                                                                  (def text (localized fonts (get raw "mLongDescLocalizationKey") (get rune "longDesc" "")))
                                                                  (merge rune {:parsed (tooltip/parse text spell) :record raw :available true :checked false})) (slot "runes"))})) (style "slots"))})) styles))
