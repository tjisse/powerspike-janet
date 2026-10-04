# Explicit Q/W subset; learned R penetration is in the champion stat adapter.
# Excludes E, R casts, passive stun and Tibbers.
# Numeric values from retained source spell records; timing semantics pending in-game validation.
(def spells [{:patch "16.19.1" :id "AnnieQ" :slot :q :damage-type :magic
              :source-path "Characters/Annie/Spells/AnnieQAbility/AnnieQ"
              :base-damage [80.0 125.0 170.0 215.0 260.0] :scalings {:ap 0.8}
              :cost [60.0 65.0 70.0 75.0 80.0] :cooldown [4.0 4.0 4.0 4.0 4.0]
              :cast-time 0.25 :cooldown-start :start :missile-speed 1400.0}
             {:patch "16.19.1" :id "AnnieW" :slot :w :damage-type :magic
              :source-path "Characters/Annie/Spells/AnnieWAbility/AnnieW"
              :base-damage [70.0 110.0 150.0 190.0 230.0] :scalings {:ap 0.8}
              :cost [70.0 75.0 80.0 85.0 90.0] :cooldown [7.0 7.0 7.0 7.0 7.0]
              :cast-time 0.25 :cooldown-start :start :missile-speed 0.0}])
(def skill-order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(def ability-pool ["1052" "3089" "3135" "3158" "3020" "3133"])
