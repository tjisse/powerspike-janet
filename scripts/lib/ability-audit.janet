# Developer-only coverage probes. A successful probe is partial execution,
# not champion-wide support or validation against a live game.
(import ../../src/powerspike/engine :as engine)
(import ../../src/powerspike/expressions :as expr)
(import ../../src/powerspike/scenario :as scenario)
(import ../../src/powerspike/effects :as effects)

(defn inspect [id ability]
  (def estimated (filter |(= :estimated ($ :status)) (ability :effects)))
  (def ranks {(ability :slot) (min (get ability :max-rank 5) (if (= :r (ability :slot)) 3 5))})
  (def bonus-as (sum (map |(get $ :attack-speed-bonus 0) (effects/ability-bonuses [ability] ranks))))
  (defn simulate []
    (engine/simulate {:duration 8 :actors
                      [{:id "player" :kind :champion :champion id :level 18 :position 0 :attack-range 200
                        :attack-speed-ratio 1 :attack-speed-cap 3
                        :base {:ad 100 :hp 100000 :mp 100000 :armor 50 :mr 50 :ap 0 :move-speed 350 :attack-range 200}
                        :stats {:ad 150 :bonus-ad 50 :hp 100000 :mp 100000 :armor 50 :mr 50 :ap 100 :move-speed 350 :crit-chance 0 :crit-damage 2
                                :attack-speed (+ 1 bonus-as) :attack-speed-uncapped (+ 1 bonus-as) :attack-speed-bonus bonus-as :attack-speed-item-growth 0 :ability-haste 0 :armor-pen-flat 0}
                        :health 50000 :resource 100000 :abilities [ability] :ranks ranks :triggers (effects/ability-triggers [ability] ranks)
                        :strategy {:attacks true :abilities true :priority [(ability :slot)] :movement :hold}}
                       {:id "target" :kind :champion :level 18 :position 0 :attack-speed-ratio 1 :attack-speed-cap 3 :base {:hp 1000000 :ad 100} :stats {:hp 1000000 :ad 100 :armor 50 :mr 50 :attack-speed 1 :attack-speed-uncapped 1 :attack-speed-bonus 0}
                        :strategy {:attacks false :abilities false :movement :hold}}]}))
  (def result (when (not (empty? estimated)) (protect (simulate))))
  (def outcome (when (and result (first result)) (result 1)))
  (def casts (when outcome (filter |(and (= :cast ($ :kind)) (= "player" ($ :actor)) (= (ability :id) ($ :source))) (outcome :trace))))
  (def applied (when outcome (filter |(and (= (ability :id) ($ :source)) (some (fn [kind] (= kind ($ :kind))) [:damage :shield :heal :control :stat-buff :buff :parry-start :cleanse :cooldown-refund :resource :displacement :blink])) (outcome :trace))))
  (def context (ability :audit-context))
  (def status (cond (and context (or (not (context :only-if-no-effect)) (and outcome (empty? applied)))) (context :kind)
                (empty? estimated) :no-executable-effect
                (and result (not (first result))) :probe-error
                (and (empty? casts) (not (ability :passive))) :not-cast
                (and (ability :passive) (empty? applied)) :passive-without-effect
                (empty? applied) :cast-without-effect :executes))
  {:champion id :slot (ability :slot) :ability (ability :id) :name (ability :name) :status status
   :estimated (length estimated) :unresolved-effects (count |(= :unresolved ($ :status)) (ability :effects))
   :cast-count (length (or casts [])) :effect-count (length (or applied []))
   :inputs (mapcat |(if (dictionary? $) (expr/problems $) []) [(ability :cost) (ability :cooldown) (ability :range)])
   :context context :notes (ability :unresolved) :runtime (when outcome (outcome :unsupported))
   :error (when (and result (not (first result))) (string (result 1)))})

(defn run [package]
  (def rows @[])
  (def counts @{})
  (each champion (sorted (package :champions) |(< (compare ($0 :id) ($1 :id)) 0))
    (def abilities (scenario/seed-abilities package champion))
    (each slot [:q :w :e :r]
      (def ability (find |(= slot ($ :slot)) abilities))
      (def row (if ability (inspect (champion :id) ability)
                 {:champion (champion :id) :slot slot :status :missing-definition :estimated 0
                  :cast-count 0 :effect-count 0 :notes ["Active ability definition unavailable in this snapshot."]}))
      (put counts (row :status) (inc (get counts (row :status) 0)))
      (array/push rows row)))
  {:patch (package :patch) :snapshot (package :snapshot) :model engine/identity :parser (package :parser)
   :champions (length (package :champions)) :summary counts :abilities rows
   :scope "Q/W/E/R from the selected snapshot, with current semantic handlers. Isolated level-18 learned slot at zero distance, ample resource, 50% self health, 100 AP/150 AD, enabled ordinary attacks, no enemy actions, eight seconds. Explicitly modeled passive slot effects run from hits without casts. A recorded effect is partial execution, not complete-kit or in-game validation. Other champion passives and automatic form behavior are outside this probe."})
