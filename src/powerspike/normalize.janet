(def parser-version "1")

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
   :limitations [(if (empty? root) "Character record unavailable; Data Dragon fallback stats." "Abilities not yet interpreted.")
                 "Attack-speed cap 2.5 and windup 30% remain estimates."]})
