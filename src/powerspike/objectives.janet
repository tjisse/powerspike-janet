(import ./expressions :as expr)
(import ./validation :as v)
(def presets [{:id :turret :name "Outer turret" :file "turret" :character "Turret"}
              {:id :baron :name "Baron Nashor" :file "sru_baron" :character "SRU_Baron"}
              {:id :herald :name "Rift Herald" :file "sru_riftherald" :character "SRU_RiftHerald"}
              {:id :dragon-fire :name "Infernal Drake" :file "sru_dragon_fire" :character "sru_dragon_fire"}
              {:id :dragon-air :name "Cloud Drake" :file "sru_dragon_air" :character "sru_dragon_air"}
              {:id :dragon-earth :name "Mountain Drake" :file "sru_dragon_earth" :character "sru_dragon_earth"}
              {:id :dragon-water :name "Ocean Drake" :file "sru_dragon_water" :character "sru_dragon_water"}
              {:id :dragon-hextech :name "Hextech Drake" :file "sru_dragon_hextech" :character "sru_dragon_hextech"}
              {:id :dragon-chemtech :name "Chemtech Drake" :file "sru_dragon_chemtech" :character "sru_dragon_chemtech"}
              {:id :dragon-elder :name "Elder Dragon" :file "sru_dragon_elder" :character "sru_dragon_elder"}])
(def immune-controls [:stun :root :charm :fear :airborne :silence :slow :suppression])
(defn field [record name &opt fallback]
  (def value (get record name (or fallback 0)))
  (if (dictionary? value) (get value "baseValue" (or fallback 0)) value))
(defn normalize [preset objects items patch]
  (def path (string "Characters/" (preset :character) "/CharacterRecords/Root"))
  (def root (get objects (or (when (get objects path) path)
                             (find |(= (string/ascii-lower $) (string/ascii-lower path)) (keys objects))) {}))
  (def attack (merge (get root "basicAttack" {})
                     (or (find |(> (get $ "mAttackProbability" 0) 0) (get root "extraAttacks" [])) {})))
  (def attack-name (get attack "mAttackName" ""))
  (def attack-record (get-in objects [(string "Characters/" (preset :character) "/Spells/" attack-name) "mSpell"] {}))
  (defn item-values [id]
    (expr/named-values {"mDataValues" (get-in items [(string "Items/" id) "mDataValues"] [])}))
  (merge preset {:patch patch :available (not (empty? root)) :checked false :root root :record objects :attack attack
                 :attack-record attack-record :turret-values (when (= :turret (preset :id))
                                                               {:ramp (item-values "1500") :backdoor (item-values "1502") :plates (item-values "1515")})}))
(defn actor [package target position]
  (def id (target :objective))
  (def preset (find |(= id ($ :id)) (get package :objectives [])))
  (assert (and preset (preset :available)) "This snapshot has no usable records for that objective. Refresh the patch or use a practice target.")
  (def root (preset :root))
  (def level (v/integer-between (get target :level 1) 1 30 "Objective level"))
  (def time (v/nonnegative (get target :game-time 1200) "Game time"))
  (assert (<= time 7200) "Game time exceeds two hours.")
  (def stats @{:mp 0 :crit-chance 0})
  (each [key base growth] [[:hp "baseHPModifiable" "hpPerLevelModifiable"]
                           [:ad "baseDamageModifiable" "damagePerLevelModifiable"]
                           [:armor "baseArmorModifiable" "armorPerLevelModifiable"]
                           [:mr "baseMR" "mrPerLevel"]]
    (put stats key (+ (field root base) (* (dec level) (field root growth)))))
  (put stats :attack-speed (field root "attackSpeedModifiable" 0.625))
  (put stats :hp-regen (* 5 (field root "baseStaticHPRegenModifiable")))
  (def notes @[(string (preset :name) ": client base/per-level stats use linear scaling at the declared objective level; server scaling remains unvalidated.")
               "Objective special attacks, terrain, leash/reset behavior and combat geometry are unresolved."])
  (def extra @{})
  (when (= id :turret)
    (def values (preset :turret-values))
    (defn term [family name] (def row (get-in values [family name])) (when row (row 1)))
    (def step (term :ramp "HeatingUpMultiplier"))
    (def stacks (term :ramp "HeatingUpMaxStacks"))
    (def window (term :ramp "HeatingUpDuration"))
    (when (and step stacks window) (put extra :attack-ramp {:step step :maximum stacks :window window}))
    (when (term :ramp "ArmorPenetration") (put stats :armor-pen-percent (term :ramp "ArmorPenetration")))
    (def per-minute (term :plates "OuterBonusADPerMinute"))
    (def maximum (term :plates "OuterTotalBonusAD"))
    (when (and per-minute maximum) (put stats :ad (+ (stats :ad) (min maximum (* (/ time 60) per-minute)))))
    (when (and (false? (get target :minions-present true)) (term :backdoor "DamageReduction"))
      (put extra :damage-multiplier (- 1 (* 0.01 (term :backdoor "DamageReduction")))))
    (put extra :spell-immune true)
    (put extra :no-crit true)
    (array/push notes "Turret spell immunity, sourced backdoor reduction, armor penetration and attack heating are modeled; plating/bulwark, AP attack conversion and detailed time scaling remain unresolved."))
  (when (= id :baron) (array/push notes "Baron target damage reduction, corrosion, regeneration and special attack variants require further handlers."))
  (when (= id :herald) (array/push notes "Herald eye exposure/true-damage interaction and charge patterns require a handler."))
  (when (string/has-prefix? "dragon-" (string id))
    (array/push notes "Dragon vengeance stacks, element-specific damage components and exact spawn scaling require handlers."))
  (def attack (preset :attack))
  (def total-time (get attack "mAttackTotalTime" (/ 1 (stats :attack-speed))))
  (merge {:id "objective" :name (preset :name) :kind :objective :objective id :level level :position position :stats stats
          :base (table/to-struct stats) :attack-range (field root "attackRangeModifiable" 500)
          :windup-fraction (if (get attack "mAttackCastTime") (/ (attack "mAttackCastTime") total-time) 0.3)
          :attack-missile-speed (get (preset :attack-record) "missileSpeed" 0) :immunities immune-controls
          :strategy {:attacks (get target :retaliation true) :abilities false :movement :hold} :coverage notes}
         extra))
