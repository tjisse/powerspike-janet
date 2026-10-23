(import ./expressions :as expr)

# Matching-snapshot combat semantics. Auxiliary references are resolved only
# within the selected kit, never from an unrelated patch or downloaded default.
(defn constant [n] {:op :constant :value n})
(defn add [& xs] {:op :sum :children xs})
(defn mul [& xs] {:op :multiply :children xs})
(defn divide [x y] {:op :divide :children [x y]})
(defn self-stat [key] {:op :stat :stat key :formula 0})
(defn enemy-stat [key] {:op :target-stat :stat key})
(defn problems [value]
  (cond (and (dictionary? value) (value :op)) (expr/problems value)
    (dictionary? value) (mapcat problems (values value))
    (indexed? value) (mapcat problems value) []))
(defn review [ability handler forms]
  (def spell (ability :record))
  (defn term [name] (expr/variable name spell))
  (defn pct [name] (mul (constant 0.01) (term name)))
  (defn other [suffix name]
    (def found (find |(string/has-suffix? (string/ascii-lower suffix) (string/ascii-lower ($ :path))) forms))
    (if found (expr/variable name (merge (found :record) {"__powerspike_patch" "16.21.1" "__powerspike_stat_scope" (get spell "__powerspike_stat_scope" [])}))
      (expr/unresolved (string "Selected auxiliary spell missing: " suffix))))
  (defn record [suffix] (get (find |(string/has-suffix? (string/ascii-lower suffix) (string/ascii-lower ($ :path))) forms) :record {}))
  (defn damage [amount &opt type] {:kind :damage :target :enemy :damage-type (or type :magic) :amount amount})
  (defn stat [key amount duration &opt mode] {:kind :stat-buff :target :self :stat key :amount amount :duration duration :mode (or mode :add)})
  (defn speed [amount duration] (stat :move-speed (add (constant 1) amount) duration :multiply))
  (defn slow [strength duration] {:kind :control :target :enemy :control :slow :strength strength :duration duration})
  (defn field [duration interval radius effects &opt extra]
    (merge {:kind :field :target :self :duration duration :interval interval :radius radius :effects effects} (or extra {})))
  (defn advance [distance] {:kind :advance :target :self :distance distance})
  (defn refund [amount slot] {:kind :cooldown-refund :target :self :amount amount :slots [slot]})
  (defn health-damage [base ratio &opt type] (damage (add base (mul ratio (enemy-stat :hp))) type))
  (defn empower [duration effects &opt extra]
    (merge {:kind :empower :target :self :count (constant 1) :duration duration :effects effects} (or extra {})))
  (def config
    (case handler
      :monkeyking-w
      {:self-cast true :missile-speed 0 :effects [(advance (term "RangeClamp")) {:kind :conceal :target :self :buff "Warrior Trickster" :duration (term "StealthDuration")}]
       :note "Warrior Trickster dashes toward the opponent and grants source invisibility. The stationary clone, mimic attacks/ultimate, collision and alternate dash directions remain excluded; no clone damage is invented."}
      :fiora-r
      {:effects [{:kind :field :target :self :radius (term "MSRingRadius") :duration (term "MarkDuration") :interval 0.25 :immediate true
                  :effects [(speed (term "PercentMS") (constant 0.25))]}]
       :note "Grand Challenge grants source movement while the marked opponent is within the source radius, sampled every quarter second. The one-dimensional duel has no facing or four vital directions: vital strikes, true damage and the completion/death healing field remain excluded."}
      :locke-w
      {:self-cast true :cost 0 :cost-resource :mana :active-buff "Soul Ignition" :missile-speed 0
       :effects [{:kind :buff :target :self :buff "Soul Ignition" :duration (term "BaseDuration") :refresh true}
                 (stat :attack-speed-bonus (term "AttackSpeed") (term "BaseDuration"))
                 (merge (speed (term "MoveSpeed") (term "BaseDuration")) {:decay-steps 20 :decay-duration (term "DecayTime") :decay-floor (add (constant 1) (term "MinMoveSpeed"))})
                 {:kind :field :target :self :duration (term "BaseDuration") :interval 0.25 :radius 1e9 :effects
                  [{:kind :health-payment :target :self :amount (mul (constant 0.25) (term "HealthCost") (self-stat :health))}]}]
       :note "Soul Ignition grants source AS and decaying movement, paying quarter-second source current-health costs for its full duration. Its recent-damage restoration, missing-health recovery and manual early termination need additional temporal rules and remain excluded."}
      :naafiri-q
      {:recast {:count 1 :delay (term "RecastLockout") :window (term "RecastWindow") :cost 0}
       :effects [{:kind :bleeding-blade :target :enemy :amount (term "TotalDamageFirstCast") :bleed (term "TotalBleedDamage") :minimum (term "TotalMinDamageSecondCast")
                  :maximum (term "TotalMaxDamageSecondCast") :heal (term "TotalHealSecondCast") :duration (term "BleedDuration") :interval (term "BleedInterval")}]
       :note "Darkin Daggers applies initial physical damage and source half-second bleed ticks. A second applied dagger cashes out remaining bleed, scales source second damage with missing health, and heals on a bleeding champion. Misses/spell shields cannot create or cash out bleed. Packmates and multi-target geometry remain excluded."}
      :mel-r
      {:stack-requirement {:target :enemy :buff "Overwhelm" :count 1}
       :effects [{:kind :stack :target :enemy :trigger :passive :on [:attack :spell-hit] :spell-slots [:q :w :e] :allow-same-time true :buff "Overwhelm" :maximum 100000 :duration 6}
                 {:kind :stack-detonate :target :enemy :buff "Overwhelm" :amount (term "UltFlatDamage") :per-stack (term "UltStackDamage") :damage-type :magic :delay (term "DisintegrateDelay")}]
       :note "Golden Eclipse requires actual prior hits to build six-second Overwhelm stacks, then deals source flat plus per-stack ultimate damage after its source delay. Passive bonus attack projectiles, the passive execute and per-projectile stack counts for multi-missile spells remain excluded; this handler does not claim those passive effects."}
      :tahmkench-e
      {:audit-context {:kind :needs-incoming-damage :only-if-no-effect true :reason "Thick Skin needs real health damage before a shield or recovery can occur."} :self-cast true :store-requirement true :cast-time 0 :missile-speed 0
       :effects [{:kind :damage-store :target :self :trigger :combat-start :taken (term "GreyHealthRatio") :cap 3 :delay (term "OOCTimer") :grey-heal (term "GreyHealthHealingRatio") :heal-rate (term "MaxHPHealRatio")}
                 {:kind :store-shield :target :self :amount 1 :duration (term "ShieldDuration") :shield-key "Thick Skin"}]
       :note "Thick Skin stores source post-mitigation health damage at the single-enemy ratio, capped at three maximum-health bars. Its active requires stored grey health, consumes it into the source-duration shield, and otherwise heals after four damage-free seconds at the selected maximum-health rate. The two-enemy ratio and allied contexts remain excluded."}
      :tahmkench-r
      {:cost (term "DataManaCost") :cooldown (term "DataCooldown") :range 250 :missile-speed 0 :cast-time-expression (term "CastTime")
       :stack-requirement {:target :enemy :buff "Acquired Taste" :count 3}
       :effects [{:kind :stack :target :enemy :trigger :passive :on [:attack] :allow-same-time true :buff "Acquired Taste" :duration 5 :maximum 3}
                 {:kind :sequence :target :enemy :effects [{:kind :consume-stacks :buff "Acquired Taste"}
                                                           {:kind :control :control :suppression :duration (term "EnemyDuration")}
                                                           {:kind :protection :buff "Devoured" :duration (term "EnemyDuration") :untargetable true}]}
                 (merge (slow (term "SlowAmount") (term "EnemyDuration")) {:target :self})
                 (merge (health-damage (term "BaseDamage") (term "PercentHPDamage")) {:delay (term "EnemyDuration")})]
       :note "Enemy Devour requires three actual attack-applied Acquired Taste marks, consumes them, suppresses/hides the victim and slows Tahm for the source full duration before source maximum-health damage. Allied swallowing/shields, Q application of passive marks, grounding, spit positioning and manual early release remain excluded."}
      :varus-w
      {:self-cast true :effects [(merge (damage (term "OnHitDamage")) {:trigger :passive :on [:attack] :allow-same-time true})
                                 {:kind :stack :target :enemy :trigger :passive :on [:attack] :allow-same-time true :buff "Blight" :maximum (term "MaxStacks") :duration (term "DebuffDuration")}
                                 {:kind :blight-detonate :target :enemy :trigger :passive :on [:spell-hit] :spell-slots [:q :e :r] :allow-same-time true :buff "Blight" :amount (term "PercentHPPerStack") :refund (term "CDRPerBlightStack")}
                                 {:kind :buff :target :self :buff "Blighted Quiver" :duration 10 :refresh true}
                                 {:kind :quiver-hit :target :enemy :trigger :passive :on [:spell-hit] :spell-slots [:q] :requires-buff "Blighted Quiver" :consume-buff "Blighted Quiver" :amount (term "MaxQEmpowerPercentHP")}]
       :note "Blighted Quiver grants source on-hit damage and six-second capped Blight stacks. Applied Q/E/R hits consume stacks for source maximum-health magic damage and per-stack basic cooldown refunds. Active empowers the next applied full-charge Q with source missing-health damage; lower charges, detonation charge amplification and R's spreading stacks remain excluded."}
      :zeri-e
      {:self-cast true :missile-speed 0 :effects [(advance (term "MaxDistance"))
                                                  {:kind :buff :target :self :buff "Spark Surge" :duration (term "BuffDuration") :refresh true}
                                                  (merge (damage (term "BonusDamageTotal")) {:trigger :passive :on [:attack] :ability-slots [:q] :requires-buff "Spark Surge" :allow-same-time true})
                                                  {:kind :cooldown-refund :target :self :trigger :passive :on [:attack] :allow-same-time true :slots [:e] :amount (term "CDReductionPerHit")}]
       :note "Spark Surge dashes up to the source open-ground range, empowers Q shots during its source duration, and refunds E cooldown on attacks. Terrain vaulting, critical refund scaling, shot piercing and charged ordinary-attack interactions remain excluded."}
      :zeri-q
      {:projectile true :cost 0 :cost-resource :mana :unhasted true :attack-spell true :cast-time 0.15
       :cooldown {:op :maximum :children [(term "MinCooldown") (divide (constant 1.5) (self-stat :attack-speed))]}
       :effects [(merge (damage (term "ActiveDamageThatCanCrit") :physical)
                        {:critical-amount (mul (term "ActiveDamageThatCanCrit") (self-stat :crit-damage)) :inherit-critical true})]
       :note "Burst Fire sends one aggregate seven-round attack at the sole target with source total damage, normal critical multiplier, one on-hit application and AS-scaled cooldown down to the selected floor. Ability haste does not shorten it. Cast windup uses a fixed 0.15-second model. Per-round collision, excess AS-to-AD conversion, charge generation and Zeri's charged ordinary attack remain excluded."}
      :warwick-w
      {:self-cast true :active-buff "Blood Hunt" :combat-lockout 3 :effects [{:kind :buff :target :self :buff "Blood Hunt" :duration (term "Duration") :refresh true}
                                                                             {:kind :blood-hunt-hit :target :self :trigger :passive :on [:attack :spell-hit] :allow-same-time true :duration (term "PassiveASDuration")
                                                                              :amount (pct "PassiveASBonus") :first-threshold (term "FirstHPThreshold") :second-threshold (term "SecondHPThreshold")}
                                                                             {:kind :field :target :self :trigger :combat-start :duration 180 :interval 0.25 :radius 1e9 :immediate true :effects
                                                                              [{:kind :blood-hunt-move :target :self :amount (pct "PassiveMSBonus") :first-threshold (term "FirstHPThreshold") :second-threshold (term "SecondHPThreshold")}]}]
       :note "Blood Hunt marks the sole champion for eight seconds and cannot activate within three seconds of champion damage. Actual hits grant source AS for 1.25 seconds against a hunted/low-health target, tripled below the second threshold. Quarter-second movement sensing uses source chase speed out of combat. Map trails, shared ally detection, windup re-evaluation and gradual movement recovery remain excluded."}
      :quinn-w
      {:passive true :audit-context {:kind :needs-harrier :only-if-no-effect true :reason "Heightened Senses combat buffs require a Harrier mark from Q/E; this isolated-slot probe has neither."}
       :effects [{:kind :stack :target :enemy :trigger :passive :on [:spell-hit] :spell-slots [:q :e] :allow-same-time true :buff "Harrier" :maximum 1 :duration (other "/QuinnPassive" "RevealDuration")}
                 {:kind :sequence :target :enemy :trigger :passive :on [:attack] :requires-target-buff "Harrier" :allow-same-time true :effects
                  [(damage (other "/QuinnPassive" "BonusDamage") :physical) {:kind :consume-stacks :buff "Harrier"}
                   (stat :attack-speed-bonus (term "AttackSpeedBonus") (term "BuffDuration")) (speed (term "MovespeedAmount") (term "BuffDuration"))]}]
       :note "Heightened Senses grants source AS/movement only after an actual attack consumes a Q/E-created Harrier mark, alongside selected passive damage. Automatic periodic Harrier assignment, enemy-facing reveal and map vision remain excluded. W does not invent a mark or grant unconditional combat stats."}
      :yasuo-w
      {:self-cast true :cast-time 0 :missile-speed 0 :effects [{:kind :windwall :target :self :duration (term "WallLife") :distance (term "Thickness")}]
       :note "Wind Wall is projected 100 source units toward the foe in one dimension for the source four seconds. Reviewed incoming projectile paths are rejected if they crossed its fixed plane while it existed, even when impact follows expiry. Blocking is recorded at the scheduled impact. Ranged attacks with retained missile speed and explicitly reviewed Gnar Q, Zeri Q, Zoe Q, Hwei QQ, Elise W and Vex R missiles are covered; wall drift/width, other missiles and special non-projectile attack exceptions remain excluded."}
      :xayah-e
      {:self-cast true :cast-time 0 :missile-speed 0 :feather-requirement true
       :audit-context {:kind :needs-feathers :only-if-no-effect true :reason "Bladecaller requires planted feathers from other casts/empowered attacks; the isolated slot has none."}
       :effects [{:kind :feather-cast :target :self :trigger :passive :on [:cast] :allow-same-time true :duration (other "/XayahPassive" "PFeatherDuration")
                  :stack-duration (other "/XayahPassive" "PEmpoweredDuration") :charges (other "/XayahPassive" "PStacksPerCast") :maximum (other "/XayahPassive" "PStackMax")}
                 {:kind :feather-attack :target :self :trigger :passive :on [:attack] :allow-same-time true :duration (other "/XayahPassive" "PFeatherDuration")}
                 {:kind :feather-recall :target :self :amount (term "FeatherDamage") :falloff (term "FeatherFalloff") :count (term "FeatherThreshold") :duration (term "RootDuration") :return-delay (term "FeatherReturnDelay")}]
       :note "Bladecaller recalls actual six-second feathers from Q's two blades, R's five blades and Clean Cuts attacks, applying source crit-scaled damage with five-percent per-feather falloff (ten-percent floor) and root on three applied hits. Casts grant capped source passive charges. Feather positions project one-dimensional cast direction/range; lateral spread, moving return paths, miss-created attack feathers and individual outgoing blade collision remain excluded. Return speed uses the reviewed 4000-unit flight profile."}
      :zed-w
      {:self-cast true :cast-time 0 :missile-speed 0 :recast {:count 1 :delay 0.25 :window (term "SwapTimeLimit") :cost 0}
       :effects [{:kind :shadow-place :target :self :distance (ability :range) :duration (term "ShadowDuration") :cast-phase :initial}
                 {:kind :shadow-swap :target :self :distance (term "RecastRange") :cast-phase :recast}]
       :note "Living Shadow projects a stationary shadow toward the opponent within the selected cast range, then automatically swaps positions on its single modeled recast inside the source range/window. Q/E mimics, double-hit energy returns, cast-overlap swaps and R shadows remain excluded; no duplicated spell damage is invented."}
      :ryze-r
      {:self-cast true :minimum-distance (term "MinimumCastRange") :cast-range-required true :missile-speed 0 :cast-time 0
       :audit-context {:kind :needs-distance :only-if-no-effect true :reason "Realm Warp's selected destination is the opponent and must be at least 1000 units away."}
       :effects [{:kind :realm-warp :target :self :duration (term "ChargeTime") :radius (expr/ranked (get spell "castRadius") 0 "Realm Warp portal radius")}]
       :note "Realm Warp opens at the caster and schedules source-charge teleport to the opponent's cast-time position, only for destinations beyond the source minimum range. Leaving its source portal radius or receiving immobilizing/silencing control cancels it. Allies, arrival presentation, Flux damage/healing upgrades and arbitrary map destinations remain excluded."}
      :taliyah-r
      {:self-cast true :minimum-distance (term "MinJumpRange") :cast-range-required true :range (term "WallLength") :cost (term "ManaCost") :combat-lockout 3 :missile-speed 0
       :cast-time-expression (divide (self-stat :distance) (term "MissileSpeed")) :interruptible-channel true :channel true
       :channel-interrupts [:stun :charm :fear :airborne :suppression :root] :effects [(advance (term "WallLength"))]
       :audit-context {:kind :needs-distance :only-if-no-effect true :reason "The automatic ride needs a destination at least 150 units away; this isolated probe starts at zero."}
       :note "Weaver's Wall automatically rides toward the opponent's initial position using source wall length/speed, with source champion-damage lockout. Immobilization cancels the modeled travel. Position changes at completion; the growing terrain wall, continuous rider path, arbitrary wall direction, voluntary dismount and wall collisions remain excluded."}
      :reksai-w
      {:self-cast true :cost 0 :cost-resource :mana :missile-speed 0 :cast-time 0
       :recast {:count 1 :delay (term "LockoutTime") :window 180 :cost 0}
       :effects [{:kind :burrow :target :self :amount (term "BurrowedMoveSpeed") :cast-phase :initial}
                 {:kind :unburrow :target :self :amount (term "UnburrowDamage") :radius (term "KnockupRange") :duration (term "KnockupDuration") :immunity (term "KnockupImmunity") :cast-phase :recast}]
       :note "Burrow grants source movement and disables attacks/unburrowed Q/E until the automatic Unburrow recast. Unburrow removes its movement, deals source magic damage inside source radius and knocks up subject to the per-target source immunity window. Burrowed Q/tunnels, Fury healing, tremor vision and manual stance retention remain excluded."}
      :renata-w
      {:self-cast true :effects [(merge (stat :attack-speed-bonus (term "ASCalc") (term "Duration")) {:decay-steps 20 :decay-floor (term "FinalASCalc")})
                                 (merge (speed (term "MSCalc") (term "Duration")) {:chase-only true :decay-steps 20 :decay-floor (add (constant 1) (term "FinalMSCalc"))})
                                 {:kind :bailout :target :self :ticks (term "TicksBeforeDeath") :interval (divide (constant 1) (term "TicksPerSecond")) :duration (term "Duration") :amount (pct "TriumphPercent")}]
       :note "Self-cast Bailout ramps source AS/chase movement. One lethal hit during its duration restores full health, then drains one maximum-health bar over the selected ten quarter-second ticks (2.5 seconds; the prose tooltip says three); healing can delay the second death. A takedown ends the drain at source recovery health and refreshes owned buffs. Allies and measured ramp/decay phases remain excluded."}
      :renata-r
      {:effects [{:kind :sequence :target :enemy :effects [{:kind :control :control :berserk :duration (term "BerserkDuration")}
                                                           {:kind :stat-buff :target-kinds [:champion] :stat :attack-speed-bonus :amount (term "BonusAttackSpeed") :duration (term "BerserkDuration")}
                                                           {:kind :force-attacks :duration (term "BerserkDuration") :reset false}]}]
       :note "Hostile Takeover berserks the sole opponent, disables its spells and forces attacks with source bonus AS. With no allied/neutral targets in this duel, it attacks the caster. Forced pursuit outside normal movement strategy, team target priority and wave geometry remain excluded."}
      :ally-only
      {:effects [] :audit-context {:kind :requires-ally :reason "The duel has one opposing champion and no allied champion or Oathsworn."}
       :note "This ability requires a different allied champion or Oathsworn. The duel supplies no such target; it cannot cast here and its allied effects are excluded."}
      :vision-only
      {:effects [] :audit-context {:kind :vision-only :reason "Map vision is outside this duel's known-position model."}
       :note "Hawkshot grants map vision rather than duel damage or combat stats. Map exploration and sight areas remain outside this known-position model; Hawkshot does not grant True Sight through invisibility."}
      :terrain-only
      {:effects [] :audit-context {:kind :requires-terrain :reason "This ability requires an existing traversable terrain anchor, which this duel does not supply."}
       :note "This ability needs existing terrain for its traversal. The one-dimensional duel supplies no terrain anchor; no dash or portal is invented. Terrain-aware paths and collisions remain outside this model."}
      :informational-slot
      {:effects [] :audit-context {:kind :informational-slot :reason "Aphelios E displays the weapon queue and is not an active ability."}
       :note "Aphelios has no third active ability. E displays the next weapon in his queue; this slot has no cast or independent damage effect."}
      :anivia-w
      {:missile-speed 0 :effects [{:kind :displace :target :enemy :mode :away :distance (term "ChampPushDistance")}]
       :note "Crystallize is placed under the sole opponent and applies the selected champion push, interrupting interruptible channels. Wall width/lifetime, path blocking, walking around terrain and repeated collisions remain excluded."}
      :yunara-r
      {:self-cast true :cast-time 0 :missile-speed 0 :effects [{:kind :buff :target :self :buff "Transcendence" :refresh true :duration (term "Buff_Duration")}
                                                               {:kind :activate-slot :target :self :slot :q :duration (term "Buff_Duration")}
                                                               {:kind :cooldown-scale :target :self :slots [:w] :amount (add (constant 1) (mul (constant -1) (term "RW_CDR"))) :duration (term "Buff_Duration")}]
       :note "Transcendence refreshes learned Q's active state for the selected duration, upgrades W to source laser damage/slow and E to a modeled dash, and reduces subsequent W cooldowns. Existing cooldown deadlines, spread attacks, aiming and animation timing remain excluded."}
      :akshan-w
      {:self-cast true :cast-time 0 :missile-speed 0 :effects [{:kind :conceal :target :self :buff "Going Rogue" :duration (term "WallGracePeriod") :detection (term "StealthDetectionRange")}]
       :note "Going Rogue grants source camouflage for its open-ground grace period, broken by offensive actions and detected inside the selected radius. Terrain persistence, Scoundrel pursuit/mana regeneration, gold and ally resurrection require additional context and remain excluded."}
      :twitch-q
      {:self-cast true :cast-time 0 :missile-speed 0 :effects [{:kind :ambush :target :self :fade-delay (term "MaxFadeTime") :duration (term "StealthDuration") :detection (term "StealthDetectionRange") :speed (pct "MoveSpeedMod")
                                                                :attack-speed (term "AttackSpeedMod") :attack-speed-duration (term "AttackSpeedDuration")}]
       :note "Ambush fades for the source second, then grants source camouflage/movement. An offensive action ends it and grants source AS; attacks during fade request that transition at fade completion. Enemy-proximity bonus movement, damage-delayed fade, Venom and takedown resets remain excluded."}
      :jinx-q
      {:passive true :effects [{:kind :stack :target :self :trigger :passive :on [:attack] :allow-same-time true :buff "Rev'd Up" :duration (term "MinigunAttackSpeedDuration") :maximum (term "MinigunAttackSpeedStacks")
                                :stat-bonuses {:attack-speed-bonus (mul (constant 0.25) (pct "MinigunAttackSpeedMax"))}
                                :initial-bonuses {:attack-speed-bonus (mul (constant 0.25) (pct "MinigunAttackSpeedMax"))}}]
       :note "Switcheroo currently keeps Pow-Pow selected. Actual attacks build source minigun AS in 50/75/100-percent increments of the maximum. Expiry uses a refreshed full window; gradual stack falloff, rocket selection, splash and rocket mana costs remain excluded."}
      :urgot-w
      (let [lifetime {:op :minimum :children [(constant 180) (expr/ranked (get-in spell ["mEffectAmount" 2 "value"]) 0 "Purge duration")]}]
        {:self-cast true :cast-time 0 :missile-speed 0 :active-buff "Purge"
         :effects [{:kind :buff :target :self :buff "Purge" :duration lifetime :refresh true}
                   (stat :attack-speed (term "WAttacksPerSecond") lifetime :maximum)
                   (stat :attack-range (term "RangeCheck") lifetime :maximum)
                   (stat :move-speed (mul (constant -1) (term "MoveSpeedMod")) lifetime)
                   {:kind :force-attacks :target :self :duration lifetime :can-move true}
                   {:kind :damage :target :enemy :trigger :attack :attack-mode :replace :attack-count :all :attack-delivery :release :damage-type :physical :amount (term "DamagePerShot") :duration lifetime :no-critical true :on-hit-scale 0.5}]
         :note "Purge replaces attacks with three source-damage shots per second, half-damage supported item on-hits, no critical damage and source movement penalty/range. It fires even with ordinary attacks disabled and allows movement during firing. Rank five remains active for the fight. Slow resistance, leg shotguns, mark target selection and manual toggle cycles remain excluded."})
      :aurelionsol-w
      {:self-cast true :cast-time-expression (term "FakeCastTime") :missile-speed 0
       :effects [{:kind :flight :target :self :duration (divide (ability :range) (term "DashSpeed")) :speed (term "DashSpeed") :amplification (term "TrueDamageBonus")}
                 (refund (constant 999) :q)]
       :note "Astral Flight grants source cruise speed, allows movement during Breath of Light, resets Q and removes its channel cooldown while flying. Q's flat damage receives the selected W amplification. Control ends flight and Q. Flight follows the configured one-dimensional movement strategy; fixed direction, terrain, Stardust range extension and takedown resets remain excluded."}
      :ksante-q
      {:cast-time 0.35 :missile-speed 0
       :range (add (constant 450) (mul (constant 250) {:op :floor :children [(divide {:op :buff-count :name "Ntofo Strikes"} (constant 2))]}))
       :cooldown (add (term "BaseCD") (mul (constant -1) (add (term "BaseCD") (mul (constant -1) (term "MinCD")))
                                           {:op :minimum :children [(constant 1) (divide (add {:op :stat :stat :armor :formula 2} {:op :stat :stat :mr :formula 2}) (term "DefenseCapforCooldown"))]}))
       :effects [{:kind :combo-strike :target :enemy :amount (term "BaseDamage") :buff "Ntofo Strikes" :duration (term "RecastWindow")
                  :slow (term "SlowPercent") :slow-duration (term "SlowDuration") :control-duration (term "StunDuration") :distance (term "PullDistance")}]
       :note "Base Ntofo Strikes uses source bonus-resistance damage and cooldown reduction. Applied hits build a refreshed two-stack window; the third hit stuns/pulls and consumes it, with extended range. Cast time uses the selected fixed directive; health scaling, wave flight and All Out remain excluded."}
      :hwei-q
      {:projectile true :range (expr/ranked (get (record "/HweiQQ") "castRange") 0 "Devastating Fire range") :cast-time 0.25
       :effects [(health-damage (other "/HweiQQ" "Damage") (mul (constant 0.01) (other "/HweiQQ" "BonusDamage")))]
       :note "Subject: Disaster currently selects Devastating Fire (QQ), using selected base/AP plus target maximum-health damage. QW/QE selection, missile collision, expanding area and other subjects remain excluded."}
      :rell-w
      {:self-cast true :missile-speed 0 :recast-update-cooldown true :recast {:count 1 :delay (ability :cooldown) :window 180 :cost (ability :cost)}
       :effects [{:kind :stat-buff :target :self :trigger :combat-start :stat :move-speed :amount (other "/RellW_Dismount" "MountedMoveSpeed") :duration 180}
                 (merge {:kind :clear-source-stats :target :self} {:cast-phase :initial})
                 (merge (advance (ability :range)) {:cast-phase :initial})
                 (merge (damage (other "/RellW_Dismount" "DismountDamage")) {:cast-phase :initial :range-at-impact 200})
                 {:kind :control :target :enemy :control :airborne :duration (other "/RellW_Dismount" "CrashDownKnockupDuration") :cast-phase :initial :range-at-impact 200}
                 {:kind :control :target :enemy :control :stun :duration (other "/RellW_Dismount" "CrashDownStunDuration") :cast-phase :initial :range-at-impact 200}
                 {:kind :shield :target :self :amount (other "/RellW_Dismount" "Shield") :duration 180 :shield-key "Crash Down" :cast-phase :initial}
                 (merge (stat :armor (add (constant 1) (other "/RellW_Dismount" "ResistanceIncrease")) (constant 180) :multiply) {:cast-phase :initial})
                 (merge (stat :mr (add (constant 1) (other "/RellW_Dismount" "ResistanceIncrease")) (constant 180) :multiply) {:cast-phase :initial})
                 (merge (stat :attack-speed-bonus (other "/RellW_Dismount" "DismountedASBoost") (constant 180)) {:cast-phase :initial})
                 (merge (stat :attack-range (other "/RellW_Dismount" "DismountedRangeBoost") (constant 180)) {:cast-phase :initial})
                 {:kind :clear-source-stats :target :self :shield-key "Crash Down" :cast-phase :recast}
                 (merge (stat :move-speed (other "/RellW_Dismount" "MountedMoveSpeed") (constant 180)) {:cast-phase :recast})
                 (merge (speed (other "/RellW_Dismount" "MountUpSpeed") (other "/RellW_Dismount" "MountUpSpeedDuration")) {:cast-phase :recast :buff "Mount Up haste"})
                 (merge (empower (other "/RellW_Dismount" "MountUpSpeedDuration") [(damage (other "/RellW_Dismount" "FlipDamage"))
                                                                                   {:kind :control :target :enemy :control :airborne :duration (other "/RellW_Dismount" "FlipKnockupDuration")}
                                                                                   {:kind :control :target :enemy :control :stun :duration (other "/RellW_Dismount" "FlipStunDuration")}]) {:cast-phase :recast})]
       :note "Ferromancy alternates source Crash Down and Mount Up at the source cooldown, preserving dismounted shield/resists/AS/range until remounting. Remount removes that shield and grants mounted movement plus one empowered control attack. Terrain, slide/flip geometry, native form selection and passive shred remain excluded."}
      :kayn-r
      {:range (term "BaseCastRange") :cast-time-expression (term "InfestDuration") :cast-lock (term "InfestDuration") :missile-speed 0
       :stack-requirement {:target :enemy :buff "Umbral prey" :count (constant 1)}
       :effects [{:kind :stack :target :enemy :trigger :passive :on [:damage] :allow-same-time true :buff "Umbral prey" :duration 3.15 :maximum 1}
                 {:kind :protection :target :self :trigger :cast-start :buff "Umbral Trespass" :duration (term "InfestDuration") :untargetable true}
                 (advance (constant 100000)) (damage (term "Damage") :physical)]
       :note "Base Umbral Trespass requires a recently damaged champion, becomes untargetable for the full source infest duration, then emerges at the sole target and applies source damage. Entry spell-shield cancellation, evolved forms, manual emergence, detailed flight and persistent control interactions remain excluded."}
      :reksai-r
      {:cast-time-expression (term "CastBuffDuration") :missile-speed 0 :stack-requirement {:target :enemy :buff "Prey" :count (constant 1)}
       :effects [{:kind :stack :target :enemy :trigger :passive :on [:damage] :allow-same-time true :buff "Prey" :duration (term "PreyMarkDuration") :maximum 1}
                 {:kind :protection :target :self :trigger :cast-start :buff "Void Rush" :duration (term "CastBuffDuration") :untargetable true :controls [:stun :charm :fear :airborne :suppression :silence :root :polymorph]}
                 (advance (constant 100000)) (health-damage (term "RBaseDamageCalc") (pct "PercentHealthDamage") :physical) (refund (constant 999) :w)]
       :note "Void Rush requires damage within the selected prey window, becomes untargetable during the modeled source delay, lands source base plus maximum-health damage and resets W. Leap trajectory, Fury generation and cancellation exceptions remain excluded."}
      :yone-e
      {:self-cast true :cast-time 0 :missile-speed 0
       :effects [{:kind :soul-unbound :target :self :duration (term "ReturnTimer") :amount (term "DeathmarkPercent")}
                 (advance (term "EDashRange")) (merge (speed (term "StartingMS") (term "ReturnTimer")) {:decay-steps 20 :decay-floor (add (constant 1) (term "MovementSpeed"))})]
       :note "Soul Unbound records post-mitigation physical/magic health damage from owned attacks/spells, excluding shields, items, runes and summoners. At return it repeats the selected fraction as true damage and returns to the modeled starting body position. Control/action locks defer return; death returns immediately. Manual early return, detailed body displacement and realm restrictions remain excluded."}
      :twistedfate-r
      {:self-cast true :cast-time 1.5 :interruptible-channel true :channel true :finish-channel-on-release true :missile-speed 0
       :effects [(advance (term "Effect4Amount"))]
       :note "Destiny's automatic duel strategy immediately channels Gate toward the sole opponent within source range. Control cancels the channel. Global vision, selecting a different destination and waiting before recasting remain excluded."}
      :graves-e
      {:self-cast true :missile-speed 0 :effects [(advance (term "DashMaxDistance"))
                                                  {:kind :stack :target :self :buff "True Grit" :amount 2 :maximum (term "MaxStacks") :duration (term "BuffDuration") :stat-bonuses {:armor (term "ArmorPerStack") :mr (term "MRGrant")}}
                                                  (merge (refund (term "CooldownPerHit") :e) {:trigger :passive :on [:attack] :allow-same-time true})]
       :note "Quickdraw dashes toward the sole champion and grants two source True Grit stacks, capped at eight, with source armor/MR and expiry. Each modeled attack refunds one source hit's cooldown. Shell/reload state, pellet hit counts and combat refresh remain excluded."}
      :ashe-q
      {:self-cast true :cast-time 0 :cost (constant 0) :cooldown (constant 0) :stack-requirement {:target :self :buff "Focus" :count (term "MaxStacks")}
       :effects [{:kind :stack :target :self :trigger :passive :on [:attack] :allow-same-time true :unless-buff "Ranger's Focus" :buff "Focus" :maximum (term "MaxStacks") :duration (term "StackDuration")}
                 {:kind :consume-stacks :target :self :buff "Focus"}
                 {:kind :buff :target :self :buff "Ranger's Focus" :duration (term "BuffDuration") :refresh true :stat-bonuses {:attack-speed-bonus (pct "BonusAS")}}
                 {:kind :damage :target :enemy :trigger :attack :attack-mode :replace :attack-count :all :damage-type :physical :amount (term "EmpoweredDamage") :duration (term "BuffDuration")}]
       :note "Ranger's Focus requires four real attacks before activation, consumes Focus and grants source AS/replacement attack damage. Attacks do not rebuild Focus during the buff. Stack expiry is modeled as a refreshed full window; gradual falloff, five-arrow presentation and Frost Shot remain excluded."}
      :kalista-e
      {:cast-time 0 :cooldown (term "FakedCooldown") :stack-requirement {:target :enemy :buff "Rend spears" :count (constant 1)}
       :effects [{:kind :stack :target :enemy :trigger :passive :on [:attack :spell-hit] :spell-slots [:q] :allow-same-time true :buff "Rend spears" :duration 4 :maximum (term "MaxSpears")}
                 {:kind :rend :target :enemy :buff "Rend spears" :amount (term "NormalDamage") :additional (term "AdditionalDamage") :slow (term "TotalSlowAmount") :duration (term "SlowDuration") :refund (term "ManaRefund")}]
       :note "Rend requires actual attack/Pierce spears, consumes them for source base/additional damage and slow, and refunds source mana/cooldown on its own kill. Spears refresh a four-second window; target switching, Pierce transfer and minion/monster rules remain excluded."}
      :yunara-q
      {:self-cast true :cast-time 0 :active-buff "Cultivation of Spirit" :cooldown (constant 0) :cost (constant 0) :stack-requirement {:target :self :buff "Unleash" :count (term "Resource_Max")}
       :effects [(merge (damage (term "Calc_Passive_Damage")) {:trigger :passive :on [:attack] :allow-same-time true})
                 {:kind :stack :target :self :trigger :passive :on [:attack] :allow-same-time true :unless-buff "Cultivation of Spirit" :buff "Unleash" :amount (term "Resource_Champion") :maximum (term "Resource_Max") :duration (term "Resource_Duration")}
                 {:kind :consume-stacks :target :self :buff "Unleash"}
                 {:kind :buff :target :self :buff "Cultivation of Spirit" :on-activation true :duration (term "Buff_Duration") :refresh true :stat-bonuses {:attack-speed-bonus (term "Calc_Attack_Speed")}}
                 (merge (damage (term "Calc_Damage")) {:trigger :passive :on [:attack] :requires-buff "Cultivation of Spirit" :allow-same-time true})]
       :note "Cultivation supplies source passive on-hit magic damage, gains Unleash on real champion attacks and spends eight for source AS/additional on-hit damage. Unleash uses a refreshed expiry window; gradual decay, spreading and Transcendence remain excluded."}
      :viego-q
      {:effects [(damage (term "TotalDamage") :physical)
                 (merge (damage {:op :maximum :children [(term "MinDamageOnHit") (mul (term "TotalPercentHealthOnHit") (enemy-stat :health))]} :physical) {:trigger :passive :on [:attack] :allow-same-time true})
                 {:kind :stack :target :enemy :trigger :passive :on [:spell-hit] :allow-same-time true :buff "Sovereign mark" :maximum 1 :duration (term "MarkDuration")}
                 {:kind :sequence :target :enemy :trigger :passive :on [:attack] :allow-same-time true :requires-target-buff "Sovereign mark"
                  :effects [{:kind :consume-stacks :buff "Sovereign mark"} (merge (damage (term "SecondAttackDamage") :physical) {:heal-dealt-ratio (term "HealModVsChamps")})]}]
       :note "Blade of the Ruined King stabs with source critical-stat scaling, adds live current-health on-hit damage and consumes a spell-applied mark for a second hit/heal. Possession, current-health critical modifiers and second-hit item procs remain excluded."}
      :smolder-q
      {:effects [(merge (damage (term "TotalDamage") :physical) {:kill-resource-refund (term "ManaRestore")})
                 (merge (damage (other "/SmolderP" "Passive_QDamageIncrease")) {:kill-resource-refund (term "ManaRestore")})
                 {:kind :stack :target :self :trigger :passive :on [:spell-hit] :buff "{32bcea5d}" :duration 180 :amount 1}]
       :note "Base Super Scorcher Breath deals selected critical-stat-scaled physical damage plus configured Dragon Practice magic damage, collecting a stack on a distinct champion spell hit. Its own kill refunds mana once per cast. Starting stacks default to zero. Evolution splash, burn/execute and non-champions remain excluded."}
      :gnar-q
      {:projectile true :range (expr/ranked (get spell "castRangeDisplayOverride") 0 "Boomerang range") :missile-speed (get (record "/GnarQMissile") "missileSpeed" 0)
       :projectile-motion (get-in (record "/GnarQMissile") ["mMissileSpec" "movementComponent"])
       :effects [(damage (term "MiniTotalDamage") :physical) (slow (term "SlowAmount") (term "SlowDuration"))]
       :note "Mini Boomerang Throw uses source damage, slow and the selected decelerating missile. The sole opponent is hit once. Return path, catching, cooldown refund and subsequent targets remain excluded."}
      :gnar-w
      {:passive true :effects [{:kind :sequence :target :enemy :trigger :passive :on [:attack :spell-hit] :every 3 :window (term "MiniMarkDuration") :refresh-window true :allow-same-time true :counter-buff "Hyper"
                                :effects [(health-damage (term "MiniTotalDamage") (term "MiniPercentHPDamage"))
                                          (merge (speed (mul (constant 0.01) {:op :spell-rank-value :slot :r :values (expr/lookup (expr/named-values (record "/GnarR")) "RHyperMovementSpeedPercent")}) (term "MiniHasteDuration")) {:decay-steps 16})]}]
       :note "Mini Hyper triggers on three distinct attacks/abilities against the sole opponent, with source magic damage, maximum-health ratio and R-rank-based decaying movement. Rage and form transitions remain excluded."}
      :gnar-e
      {:range (term "MiniRange") :cast-time-expression (term "TravelTime") :blink-to-target true :missile-speed 0
       :effects [(stat :attack-speed-bonus (term "MinibAS") (term "MiniASDuration")) (damage (term "MiniTotalDamage") :physical) (slow (mul (constant -1) (term "MoveSpeedMod")) (term "SlowDuration"))]
       :note "Mini Hop lands on the sole opponent after the source travel time, applies source damage/slow and attack speed. The bounce's second destination, terrain and additional targets remain excluded."}
      :jayce-q
      {:missile-speed 0 :blink-to-target true :effects [(damage (term "Damage") :physical) (slow (mul (constant -1) (term "Slow")) (term "SlowDuration"))]
       :note "Hammer To the Skies lands on the sole opponent, deals selected damage and slows. Leap flight, additional targets and transformations remain excluded."}
      :jayce-w
      {:self-cast true :missile-speed 0 :effects [(field (term "Duration") (constant 0.5) (ability :range) [(damage (divide (term "Damage") (mul (term "Duration") (constant 2))))])
                                                  {:kind :resource :target :self :trigger :passive :on [:attack] :allow-same-time true :amount (term "ManaGain")}]
       :note "Hammer Lightning Field supplies source total damage as half-second nearby pulses; Hammer attacks restore source mana. Transformation bonuses and other targets remain excluded."}
      :jayce-e
      {:missile-speed 0 :effects [(health-damage (term "FlatDamage") (term "PercHPDamage"))
                                  {:kind :control :target :enemy :control :airborne :duration (term "KnockbackDuration")}
                                  {:kind :displace :target :enemy :mode :away :distance (term "KnockbackDistance")}]
       :note "Hammer Thundering Blow deals source bonus-AD plus target maximum-health magic damage and knocks back the opponent. Terrain and Cannon Gate remain excluded."}
      :akshan-r
      {:cast-time-expression (term "ChannelDuration") :cast-lock (add (term "ChannelDuration") (mul (term "NumberOfBullets") (term "CastTimePerBullet"))) :interruptible-channel true :channel true
       :effects [(merge (damage (mul (term "DamagePerBulletWithCrit") (add (constant 1) (mul (add (term "MaxIncrease") (constant -1)) (enemy-stat :missing-health-percent)))) :physical)
                        {:hits (term "NumberOfBullets") :interval (term "CastTimePerBullet") :requires-channel true})]
       :note "Comeuppance fully charges, then fires the source bullet count at source intervals with live missing-health amplification and critical-stat scaling. Control cancels the channel and unreleased shots. Collision, manual early release and measured bullet flight remain excluded."}
      :aurelionsol-q
      {:cast-time-expression {:op :minimum :children [(constant 180) (term "MaxChannelDuration")]} :interruptible-channel true :channel true :finish-channel-on-release true :cooldown-start :end :cooldown-after-channel true :no-cooldown-while-flight true :cost-resource :resource :cost (constant 0) :minimum-resource (mul (constant 0.25) (term "ManaCostPerSecond")) :range (term "LevelBasedRangeScaling") :targeted-area true
       :effects [(merge (field {:op :minimum :children [(constant 180) (term "MaxChannelDuration")]} (constant 0.25) (term "LevelBasedRangeScaling")
                               [(damage (mul (constant 0.25) (term "DamagePerSecond") (add (constant 1) (self-stat :flight-amplification))))]
                               {:requires-channel true :end-channel-on-empty true :mana-per-second (term "ManaCostPerSecond") :every-pulses 4
                                :extra-effects [(health-damage (mul (term "BurstDamage") (add (constant 1) (self-stat :flight-amplification))) (term "BurstBonusTrueDamageToChamps"))]}) {:trigger :cast-start})]
       :note "Breath of Light channels source DPS, pays continuous mana, checks range every quarter second and bursts each full second on the sole target. Stardust defaults to configured stacks; flight, collecting Stardust, rotation and other targets remain excluded."}
      :briar-w
      {:self-cast true :cost-resource :health :cost (mul (other "/BriarP" "CurrentHealthPercentCost") (self-stat :health))
       :recast {:count 1 :delay 0.5 :window (term "BerserkDuration") :cost 0}
       :effects [(merge (advance (term "MaxDashDistance")) {:cast-phase :initial})
                 (merge (stat :attack-speed-bonus (term "BerserkAS") (term "BerserkDuration")) {:cast-phase :initial})
                 (merge (speed (term "BerserkMS") (term "BerserkDuration")) {:cast-phase :initial})
                 (merge (empower (term "BerserkDuration") [(merge (damage (add (term "TotalAttackBonusDamage") (mul (pct "TotalAttackPercentMissingHealth") (enemy-stat :missing-health))) :physical) {:heal-dealt-ratio (term "AttackHealPercent")})
                                                           {:kind :heal :target :self :amount (term "AttackMaxHPHeal")}
                                                           {:kind :clear-source-stats :target :self}]) {:cast-phase :recast})]
       :note "Blood Frenzy pays current health, leaps and grants source AS/movement; one Snack Attack recast empowers a hit with source live missing-health damage and healing, then ends Frenzy buffs. Forced pursuit, attack cleave, bleed and passive healing amplification remain excluded."}
      :corki-w
      {:missile-speed 0 :cast-time 0 :range (term "MaximumRange") :targeted-area true :effects [(advance (term "MaximumRange"))
                                                                                                (field (term "TrailDuration") (divide (constant 1) (term "TicksPerSecond")) (term "DamageRadius")
                                                                                                       [(damage (divide (term "MaximumDamage") (term "MaximumTicks")))] {:fixed true})]
       :note "Valkyrie advances within source range and leaves its source-rate five damage pulses in the landing area. The full path, flight and terrain geometry remain excluded."}
      :rammus-w
      {:self-cast true :effects [(stat :armor (term "BonusArmorTooltip") (term "BuffDuration")) (stat :mr (term "BonusMRTooltip") (term "BuffDuration"))
                                 {:kind :buff :target :self :buff "Defensive Ball Curl" :amount (constant 1) :duration (term "BuffDuration") :refresh true}
                                 (merge (damage (term "ReturnDamageCalc")) {:trigger :passive :on [:attack-taken] :requires-buff "Defensive Ball Curl" :allow-same-time true :suppress-procs true})]
       :note "Defensive Ball Curl grants selected flat/total resistance bonuses and reflects source magic damage once per received modeled ordinary attack while active. Retaliation is not added for spells or independent on-hit packets. Manual ending/recast damage and passive Spiked Shell remain excluded."}
      :nilah-r
      {:cast-time 1 :can-move true :self-cast true :effects [(merge (field (constant 1) (term "TickDelay") (constant 450)
                                                                           [(merge (damage (term "DamagePerTickCalc") :physical) {:heal-dealt-ratio (term "ChampHealingPercent") :overheal-duration (term "Duration")})]
                                                                           {:immediate true}) {:trigger :cast-start})
                                                             (merge (damage (term "DamageCalc") :physical) {:range-at-impact (constant 450) :heal-dealt-ratio (term "ChampHealingPercent") :overheal-duration (term "Duration")})
                                                             {:kind :displace :target :enemy :mode :toward :distance 450 :range-at-impact (constant 450)}]
       :note "Apotheosis applies six source-interval whirl hits and the final source burst/pull, healing from post-mitigation champion damage and shielding overheal. Movement remains possible. Allies, exact geometry and concurrent spell casts remain excluded."}
      :mordekaiser-r
      {:missile-speed 0 :effects [{:kind :stat-steal :target :enemy :duration (term "SpiritRealmDuration") :amount (term "StatStealPercentScalar")}]
       :note "Realm of Death snapshots and steals source fractions of the sole target's AD, AP, armor, MR, AS and maximum/current health for seven seconds. Health removal is nonlethal and bypasses shields. The arena, realm isolation, target cancellation, projectile destruction and post-kill persistence remain excluded."}
      :bard-r
      {:effects [{:kind :stasis-zone :target :enemy :duration (term "RStasisDuration") :radius (constant 350)}]
       :note "Tempered Fate places both actors inside the fixed impact area into untargetable invulnerable stasis for the source duration, disabling their actions and movement. Other units, terrain and measured projectile travel remain excluded."}
      :teemo-r
      {:effects [{:kind :trap :target :enemy :duration (mul (constant 60) (term "MushroomDuration")) :arm (term "ArmTime") :radius (term "TriggerRadius")
                  :effects [{:kind :periodic :target :enemy :damage-type :magic :amount (term "TotalDamage") :duration (term "DebuffDuration") :pulse-count 4 :pulse-interval 1 :first-delay 1 :buff "Noxious Trap"}
                            (slow (pct "SlowAmount") (term "DebuffDuration"))]}]
       :note "Noxious Trap arms after one second at the target's cast position, triggers once on nearby enemy occupancy and applies four source poison ticks plus slow. Traps retain separate state and source charge recovery; poison refreshes rather than stacking. Bounce, trap destruction, vision and measured toss flight remain excluded."}
      :akali-w
      {:self-cast true :effects [(merge (speed (pct "MovementSpeed") (term "MovementSpeedDuration")) {:decay-steps 16})
                                 {:kind :temporary-resource :target :self :amount (term "EnergyRestore") :duration (term "BaseDuration")}
                                 {:kind :conceal :target :self :buff "Twilight Shroud" :duration (term "BaseDuration")}]
       :note "Twilight Shroud restores energy and temporarily increases its maximum; movement decays over its source duration. Shroud geometry, repeated concealment and True Sight remain excluded."}
      :aurora-w
      {:self-cast true :effects [(advance (term "JumpDistance")) (speed (pct "MoveSpeedBonus") (term "InvisDuration")) {:kind :conceal :target :self :buff "Across the Veil" :duration (term "InvisDuration")}]
       :note "Across the Veil advances toward the sole opponent and grants source movement. Passive spirits, terrain, True Sight and takedown reset remain excluded."}
      :ambessa-q
      {:cast-time 0.225 :hit-gated-recast true :recast {:count 1 :delay (term "Swap_Static_Cooldown") :window (term "Swap_Duration") :cost 0}
       :effects [(merge (health-damage (term "Calc_Damage_1_Max") (term "Calc_Damage_1_Percent_Max") :physical) {:cast-phase :initial :enables-recast true})
                 (merge (health-damage (term "Calc_Damage_2_Max") (term "Calc_Damage_2_Percent_Max") :physical) {:cast-phase :recast})]
       :note "Cunning Sweep then one Sundering Slam use source damage and target maximum health. The sole opponent is assumed at the edge/first-hit position. Recast is granted only after an applied initial hit. Drakehound dashes and passive attacks remain excluded."}
      :fiora-q
      {:cast-time 0 :effects [(advance (constant 400)) (merge (damage (term "TotalDamage") :physical) {:applies-on-hit true :refund-own-ratio (term "CDRefundPercent")})]
       :note "Lunge advances up to 400 units, deals selected physical damage, applies supported on-hits and refunds half the maximum cooldown on an applied hit. Vitals, aiming and measured dash flight remain excluded."}
      :elise-q
      {:effects [(damage (add (term "BaseDamage") (mul (term "HumanPercentHealth") (enemy-stat :health))))]
       :note "Human Neurotoxin deals source base/AP plus live current-health damage. Spider Venomous Bite and Spiderlings require separate form handling."}
      :elise-w
      {:projectile true :effects [(damage (term "TotalDamage"))]
       :note "Human Volatile Spiderling uses the selected damage calculation and modeled projectile delivery. Autonomous pathfinding, three-second roaming and Spiderlings remain excluded."}
      :illaoi-q
      {:effects [(damage (term "TentacleDamageTotal") :physical)]
       :note "Tentacle Smash uses selected level/AD/AP damage and learned Q amplification. Tentacle geometry, healing and autonomous passive slams remain excluded."}
      :shyvana-e
      {:effects [(health-damage (term "Damage") (term "Calc_Max_Health_Damage")) (slow (term "Calc_Slow") (term "SlowDuration"))]
       :note "Human Molten Burst deals source base/AP plus target maximum-health damage and slow. Dragon fireball/trail, collision and transformation interactions remain excluded."}
      :zaahen-r
      {:cast-time 0.5 :rank-bonuses {:armor-pen-percent (term "ArmorPen")}
       :effects [{:kind :protection :target :self :trigger :cast-start :buff "Grim Deliverance" :duration (constant 0.5) :damage-types [:physical :magic] :reduction (term "DamageReduction")}
                 (advance (term "DashMaxDistance")) (merge (damage (term "DamageEndCalc") :physical) {:heal-dealt-ratio (term "HealPercent")})]
       :note "Grim Deliverance grants learned-rank armor penetration, halves non-true damage during modeled casting, advances and heals from post-mitigation champion damage. Revival, terrain and multi-target effects remain excluded."}
      :reksai-e
      {:effects [{:kind :resource-strike :target :enemy :amount (term "BaseDamageCalculation") :maximum (term "EmpoweredDamageCalculation") :threshold 100}]
       :note "Unburrowed Furious Bite deals selected physical damage, or source-amplified true damage at 100 Fury and consumes Fury. Fury generation, Burrow and tunnels remain excluded."}
      :kayn-e
      {:self-cast true :effects [(speed (pct "MS") (term "MaxInCombatTime"))]
       :note "Base Shadow Step grants its source movement for the combat-limited duration. No terrain is supplied, so wall entry, wall healing, extended duration and evolved-form behavior remain excluded."}
      :khazix-r
      {:self-cast true :cast-time 0 :recast {:count 1 :delay (term "RecastCD") :window (term "RecastWindow") :cost 0}
       :effects [(speed (term "BonusMovementSpeedPercent") (term "StealthDuration")) {:kind :conceal :target :self :buff "Void Assault" :duration (term "StealthDuration")}]
       :note "Unevolved Void Assault grants source movement on each of two activations. Passive reset, True Sight and evolution remain excluded."}
      :hwei-r
      {:effects [{:kind :despair :target :enemy :amount (term "DamageOverTime") :burst (term "Damage") :duration (term "Duration") :slow (pct "SlowPercentPerStack")}]
       :note "Spiraling Despair attaches to the sole opponent, deals quarter-second source DPS pulses and a final explosion, with stacking slow capped at 90%. Expanding area and other enemies remain excluded."}
      :sion-q
      {:cast-time 2 :interruptible-channel true :channel true :cancel-cooldown 2
       :effects [(damage (term "MaxDamageTotal") :physical) {:kind :control :target :enemy :control :airborne :duration 2.25}]
       :note "Decimating Smash fully charges for two seconds, deals source maximum physical damage and applies its 2.25-second control. Caster control cancels damage and applies the short cancellation cooldown; manual early releases and geometry remain excluded."}
      :ksante-w
      {:cast-time-expression (term "MaxDuration") :interruptible-channel true :channel true :channel-interrupts [] :uninterruptible true :blink-to-target true :range (term "MaxDashBase")
       :effects [{:kind :protection :target :self :trigger :cast-start :buff "Path Maker" :duration (term "MaxDuration") :damage-types [:physical :magic] :reduction (term "DamageReduction") :controls [:stun :charm :fear :airborne :suppression :silence :root :polymorph] :direct-displacement-immune true}
                 (health-damage (term "BaseDamage") (term "TotalMaxHealthDamage") :physical)
                 {:kind :control :target :enemy :control :stun :duration (term "MaxKnockbackDuration")}
                 {:kind :displace :target :enemy :mode :away :distance (term "KnockbackDist")}]
       :note "Base Path Maker fully charges with source damage reduction and control/displacement immunity, then deals base plus maximum-health physical damage and pushes/stuns. All Out, manual early release and dash flight remain excluded."}
      :yunara-e
      {:self-cast true :effects [(merge (speed (term "Calc_Move_Speed") (term "Buff_Duration")) {:chase-amount (add (constant 1) (term "Calc_Move_Speed_Enhanced")) :unless-owner-buff "Transcendence"})
                                 (merge (advance (constant 300)) {:requires-owner-buff "Transcendence"})]
       :note "Base Kanmei's Steps grants source movement with its enhanced amount while approaching the sole opponent. Transcendent dash remains excluded."}
      :yunara-w
      {:cast-time-expression (term "Cast_Time_Base")
       :effects [(merge (damage (term "Calc_Damage_Initial")) {:unless-owner-buff "Transcendence"})
                 (merge (slow (term "Calc_Slow") (term "Slow_Duration")) {:decay-steps 16 :unless-owner-buff "Transcendence"})
                 (merge (field (term "Linger_Duration") (constant 0.25) (constant 100) [(damage (mul (constant 0.25) (term "Calc_Damage_Per_Second")))] {:fixed true}) {:unless-owner-buff "Transcendence"})
                 (merge (damage {:op :spell-expression :slot :r :children [(other "/YunaraR" "Calc_RW_Damage")]}) {:requires-owner-buff "Transcendence"})
                 (merge (slow (other "/YunaraR" "RW_Slow_Amount") (other "/YunaraR" "RW_Slow_Duration")) {:decay-steps 16 :requires-owner-buff "Transcendence"})]
       :note "Base Arc of Judgment lands source damage and decaying slow, leaving a one-second quarter-second sampled damage area at the impact position. Projectile width, return flight and Transcendent laser remain excluded."}
      :vex-r
      {:projectile true :hit-gated-recast true :recast {:count 1 :delay 0.1 :window (term "R2Duration") :cost 0}
       :effects [(merge (damage (term "RDamageCalc")) {:cast-phase :initial :enables-recast true})
                 (merge (advance (ability :range)) {:cast-phase :recast})
                 (merge (damage (term "RecastDamageCalc")) {:cast-phase :recast})]
       :note "Shadow Surge marks on an applied missile hit; one automatic recast lands on the marked champion and deals source second-hit damage. Recast cannot precede the first impact. Doom, takedown resets and measured dash flight remain excluded."}
      :shaco-q
      {:self-cast true :cast-time-expression (term "PseudoCastTime") :effects [(advance (constant 400)) (empower (term "StealthDuration") [(damage (term "TotalDamage") :physical)])
                                                                               {:kind :conceal :target :self :buff "Deceive" :duration (term "StealthDuration") :except-sources ["JackInTheBox" "HallucinateFull"]}]
       :note "Deceive advances up to 400 units and adds source damage to one attack within the stealth window. Backstab position/critical, True Sight and exceptional spell interactions remain excluded."}
      :zoe-q
      {:projectile true :range 800 :effects [{:kind :distance-damage :target :enemy :damage-type :magic :amount (term "TotalDamageTooltip") :maximum (term "MaxDamageTooltip") :ramp-distance 1500}]
       :note "Paddle Star uses a direct shot toward the sole opponent, with source base/maximum damage interpolated over 1500 traveled units. Backward redirects, arbitrary recast aiming and flight path changes remain excluded."}
      nil))
  (assert config (string "Unknown remaining ability handler: " handler))
  (def note (config :note))
  (def unresolved (problems config))
  (def compiled (map (fn [effect index]
                       (merge {:id (string (ability :id) "/reviewed/" index) :proc-key (string (ability :id) "/reviewed/" index)
                               :trigger :cast :condition :always :target-kinds [:champion :practice]
                               :status (if (empty? unresolved) :estimated :unresolved) :evidence {:override true :tooltip note}} effect))
                     (config :effects) (range 0 (length (config :effects)))))
  (merge ability (tabseq [[key value] :pairs config :when (not (some |(= key $) [:effects :note]))] key value) {:effects compiled :unresolved [;unresolved note]}))
