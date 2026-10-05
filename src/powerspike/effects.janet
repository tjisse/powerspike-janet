(import ./expressions :as expr)
(import ./data-util :as util)

# Semantic handlers use values from the selected snapshot. A missing expression
# is retained as unresolved and will be reported by the event engine.
(defn multiply [& children] {:op :multiply :children children})
(defn constant [value] {:op :constant :value value})
(defn item-spell [item]
  {"mDataValues" (get-in item [:record "mDataValues"] [])
   "mSpellCalculations" (get-in item [:record "mItemCalculations"] {})
   "__powerspike_patch" (item :patch)})
(defn item-triggers [item ranged]
  (def spell (item-spell item))
  (defn term [name] (expr/variable name spell))
  (def id (item :id))
  (def family (some |(= $ (util/cdragon-version (item :patch))) ["16.17" "16.18" "16.19"]))
  (if (or (not family) (empty? (get item :record {}))) []
    (case id
      "3145" [{:id "item/3145" :on [:damage] :target-kinds [:champion] :kind :damage :damage-type :magic
               :amount (term "DamageAmount") :cooldown (term "Cooldown")}]
      "3153" [{:id "item/3153/mist" :on [:attack] :target-kinds [:champion :practice :objective]
               :exclude-objectives [:turret]
               :kind :damage :damage-type :physical
               :amount (multiply (term (if ranged "RangedValue" "MeleeValue")) {:op :target-stat :stat :health})
               :monster-cap (term "MonsterDamageCap") :cooldown 0}]
      "3057" [{:id "item/3057/prime" :on [:cast] :kind :buff :target :self :buff "spellblade" :duration 10 :refresh true}
              {:id "item/3057/hit" :on [:attack] :requires-buff "spellblade" :consume-buff "spellblade"
               :kind :damage :damage-type :physical :amount (term "SpellbladeDamage")
               :affects-structures true
               :cooldown (term "SpellbladeCooldown")}]
      [])))
(defn rune-spell [rune patch]
  (def script (get-in rune [:record "mScript" "mSpellScriptData"] {}))
  {"__powerspike_patch" patch
   "mDataValues" (seq [[name value] :pairs (get script "mEffectAmount" {})] {"mName" name "mValue" value})
   "mSpellCalculations" (get script "mCalculations" {})})
(defn rune-triggers [rune patch]
  (def spell (rune-spell rune patch))
  (case (get rune "id")
    8112 [{:id "rune/8112" :on [:attack :spell-hit] :target-kinds [:champion]
           :kind :damage :damage-type :adaptive :amount (expr/variable "TotalDamage" spell)
           :every 3 :window (expr/variable "WindowDuration" spell) :cooldown (expr/variable "Cooldown" spell)}]
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
