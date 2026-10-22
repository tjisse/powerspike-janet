(import ./expressions :as expr)
(import ./data-util :as util)
(import ./runes :as runes)

# Semantic handlers use values from the selected snapshot. A missing expression
# is retained as unresolved and will be reported by the event engine.
(defn multiply [& children] {:op :multiply :children children})
(defn constant [value] {:op :constant :value value})
(defn ability-triggers [abilities ranks]
  (mapcat (fn [ability]
            (def rank (get ranks (ability :slot) 0))
            (if (and (ability :passive) (> rank 0))
              (map (fn [effect]
                     (merge (tabseq [[key value] :pairs effect] key
                              (if (and (dictionary? value) (value :op))
                                {:op :with-rank :rank rank :children [value]} value))
                            {:id (ability :id)}))
                   (filter |(and (= :estimated ($ :status)) (= :passive ($ :trigger))) (ability :effects))) [])) abilities))
(defn item-spell [item]
  {"mDataValues" (get-in item [:record "mDataValues"] [])
   "mSpellCalculations" (get-in item [:record "mItemCalculations"] {})
   "__powerspike_patch" (item :patch)})
(defn bork-rate [item ranged]
  (if (boolean? ranged)
    (expr/variable (if ranged "RangedValue" "MeleeValue") (item-spell item))
    (expr/unresolved "Melee/ranged attack type is unresolved.")))
(defn item-tooltip-variables [item context]
  (def variables (get item :effect-variables []))
  (if (and (= "3153" (item :id)) (dictionary? context)
           (not (empty? (get item :record {})))
           (some |(= $ (util/cdragon-version (item :patch))) ["16.17" "16.18" "16.19" "16.20" "16.21"]))
    # Resolve on presentation so retained snapshots and both duel participants
    # use the same melee/ranged rate as combat without rewriting cached data.
    [{:name "Item_Melee_Ranged_Split_Dynamic" :expression (multiply (bork-rate item (context :ranged)) (constant 100))
      :unavailable-label "a percentage"
      :suffix "%" :note (if (boolean? (context :ranged))
                          (string (if (context :ranged) "Ranged" "Melee") " attacks use this percentage of the target's current health.")
                          "Melee/ranged attack type is unresolved; this on-hit effect is excluded.")}
     ;variables]
    variables))
(def spellblade-types {"3057" :physical "3100" :magic "3078" :physical "3508" :physical "6662" :physical})
(defn item-supported? [item]
  (and (some |(= $ (util/cdragon-version (item :patch))) ["16.17" "16.18" "16.19" "16.20" "16.21"])
       (not (empty? (get item :record {})))))
(defn item-limitations [item &opt ranged]
  (case (item :id)
    "3153" (if (boolean? ranged) [] ["Blade of the Ruined King's Mist's Edge on-hit damage is excluded because melee/ranged attack type is unresolved."])
    "3100" (if (and (item-supported? item)
                    (not= :unresolved ((expr/variable "SheenASBuff" (item-spell item)) :op))
                    (not= :unresolved ((expr/variable "SpellBladeDuration" (item-spell item)) :op)))
             [] ["Lich Bane's empowered attack-speed data is unavailable on this snapshot."])
    "3078" ["Trinity Force's Quicken movement speed remains excluded."]
    "3508" ["Essence Reaver's mana restoration remains excluded."]
    "6662" ["Iceborn Gauntlet's frost field and slow remain excluded."]
    "6655" ["Luden's Echo assumes all echoes are available and hit the sole opponent; secondary targets and projectile travel are excluded."]
    []))
(defn item-triggers [item ranged]
  (def spell (item-spell item))
  (defn term [name] (expr/variable name spell))
  (def id (item :id))
  (if (not (item-supported? item)) []
    (if (spellblade-types id)
      [{:id (string "item/" id "/prime") :on [:cast] :kind :buff :target :self :buff "spellblade"
        :requires-ready (string "item/" id "/hit")
        :stat-bonuses (if (= id "3100") {:attack-speed-bonus (term "SheenASBuff")} {})
        :duration (if (= id "3100") (term "SpellBladeDuration") 10) :refresh true}
       {:id (string "item/" id "/hit") :on [:attack :parried-attack] :requires-buff "spellblade" :consume-buff "spellblade"
        :kind :damage :damage-type (spellblade-types id) :amount (term "SpellbladeDamage")
        :affects-structures true :cooldown (term "SpellbladeCooldown")}]
      (case id
        "3145" [{:id "item/3145" :on [:damage] :target-kinds [:champion] :kind :damage :damage-type :magic
                 :amount (term "DamageAmount") :cooldown (term "Cooldown")}]
        "3153" (if (boolean? ranged) [{:id "item/3153/mist" :on [:attack] :target-kinds [:champion :practice :objective]
                                       :exclude-objectives [:turret]
                                       :kind :damage :damage-type :physical
                                       :amount (multiply (bork-rate item ranged) {:op :target-stat :stat :health})
                                       :monster-cap (term "MonsterDamageCap") :cooldown 0}] [])
        "3115" [{:id "item/3115" :on [:attack] :kind :damage :damage-type :magic
                 :target-kinds [:champion :practice :objective] :exclude-objectives [:turret]
                 :amount (term "TotalOnHitDamage") :cooldown 0}]
        "6655" [{:id "item/6655" :on [:spell-hit] :kind :damage :damage-type :magic
                 :ability-slots [:p :q :w :e :r]
                 :target-kinds [:champion :practice :objective] :exclude-objectives [:turret]
                 :amount (term "SingleTargetMax") :cooldown (term "Cooldown")}]
        []))))
(defn rune-spell [rune patch]
  (runes/spell rune patch))
(defn rune-triggers [rune patch]
  (def spell (rune-spell rune patch))
  (case (get rune "id")
    8112 [{:id "rune/8112" :on [:attack :spell-hit] :target-kinds [:champion]
           :kind :damage :damage-type :adaptive :amount (expr/variable "TotalDamage" spell)
           :every 3 :window (expr/variable "WindowDuration" spell) :cooldown (expr/variable "Cooldown" spell)}]
    8237 (if (runes/supported-patch? patch) [{:id "rune/8237" :on [:spell-hit] :ability-slots [:p :q :w :e :r] :target-kinds [:champion]
                                              :kind :damage :damage-type :magic :amount (expr/variable "DamageCalc" spell)
                                              :delay (expr/variable "DotDuration" spell) :cooldown (expr/variable "BurnlockoutDuration" spell)}] [])
    []))
(defn summoner-ability [summoner slot patch]
  (def spell (merge (get summoner :record {}) {"__powerspike_patch" patch}))
  (defn term [name] (expr/variable name spell))
  (def id (get summoner "id"))
  (defn typed [kind target fields] (merge fields {:kind kind :target target :status :estimated :trigger :cast :condition :always}))
  (def effects
    (case id
      "SummonerDot" [(typed :damage :enemy {:damage-type :true :amount (term "DamagePerSecond") :hits (term "DotDuration") :interval 1})
                     (typed :stat-buff :enemy {:duration (term "DotDuration") :stat :healing-multiplier :mode :multiply
                                               :amount (multiply (constant -1) (term "GrievousAmount")) :relative true})]
      "SummonerBarrier" [(typed :shield :self {:amount (term "ShieldStrength") :duration (term "ShieldDuration")})]
      "SummonerHeal" [(typed :heal :self {:amount (term "TotalHeal")})
                      (typed :stat-buff :self {:stat :move-speed :mode :multiply :relative true :amount (term "MoveSpeed")
                                               :duration (term "MoveSpeedDuration")})]
      "SummonerExhaust" [(typed :stat-buff :enemy {:stat :outgoing-multiplier :mode :multiply :relative true
                                                   :amount (multiply (constant -0.01) (term "DamageReduction")) :duration (term "DebuffDuration")})
                         (typed :control :enemy {:control :slow :strength (multiply (constant 0.01) (term "Slow")) :duration (term "DebuffDuration")})]
      "SummonerHaste" [(typed :stat-buff :self {:stat :move-speed :mode :multiply :relative true :amount (term "MoveSpeedMod")
                                                :duration (term "Duration")})]
      "SummonerSmite" [(typed :damage :enemy {:damage-type :true :amount (term "SmiteBaseDamage") :target-kinds [:objective] :exclude-objectives [:turret]})]
      "SummonerBoost" [(typed :cleanse :self {:controls [:stun :root :charm :fear :silence :slow]})
                       (typed :stat-buff :self {:stat :tenacity :amount (term "TenacityValue") :mode :maximum :duration (term "TenacityDuration")})]
      []))
  {:id id :name (get summoner "name" id) :slot slot :max-rank 1 :icon (get-in summoner ["image" "full"] "") :icon-group "spell"
   :cooldown (expr/ranked (get spell "cooldownTime") 0 "Summoner cooldown") :unhasted true
   :range (expr/ranked (get spell "castRange") 0 "Summoner range") :cost 0 :cast-time 0 :effects effects
   :available (not (empty? spell)) :checked false :unresolved
   (case id "SummonerHeal" ["Ally healing and repeat-heal debuff are excluded in this duel."]
     "SummonerDot" ["Ignite ticks are estimated at one-second intervals; vision is excluded."]
     "SummonerSmite" ["Base Smite only; jungle pet progression and upgraded Smite are unresolved."]
     (if (empty? effects) ["Summoner spell requires a handler."] []))})
