(import ./src/powerspike/core :as core)
(import ./src/powerspike/skills :as skills)
(import ./data/16.19.1/snapshot :as snapshot)
(import ./data/16.19.1/annie :as annie-model)

(def args (array/slice (dyn :args) 1))
(def command (get args 0 "demo"))
(def rotation? (some (fn [x] (= command x)) ["rotation" "optimize-abilities" "optimize-total"]))
(def champion-id (get args 1 (if rotation? "Annie" "Garen")))
(def champion (get snapshot/champions champion-id))
(assert champion "supported champions: Garen, Annie")
(when rotation? (assert (= champion-id "Annie") "the ability model currently supports Annie Q/W only"))
(def level (if (> (length args) 2) (scan-number (args 2)) 18))
(def target {:armor 80 :mr 80})
(def scenario {:duration 5 :windup-fraction 0.3 :travel-time 0})
(def rotation-scenario {:duration 5 :windup-fraction 0.3 :distance 300
                        :attack-travel-time 0 :include-attacks (not= command "optimize-abilities")})
(def options {:slots 6 :budget 10000 :map 11 :max-evaluations 100000})
(print "PowerSpike — patch " snapshot/patch " — " champion-id " level " level)
(print "Static 80 armor / 80 MR target; 5 second window; 10,000 gold budget.")
(print "Expected critical damage; assumed 30% attack windup and instant basic-attack hit.")
(when rotation? (print "Annie Q/W subset; Q then W priority; 300 distance. Learned R penetration included; E/R casts/stun/Tibbers excluded."))
(defn print-best [result]
  (def best (result :best))
  (assert best "no legal build found")
  (pp {:items (map (fn [x] (x :name)) (best :items))
       :gold (best :cost) :dps (best :score)
       :evaluated (result :evaluated) :complete (result :complete)
       :guarantee (result :guarantee)}))
(case command
  "demo"
  (pp (core/evaluate-build champion level
                           [(snapshot/items "3031") (snapshot/items "3006")]
                           target scenario options))
  "optimize"
  (print-best (core/optimize-attacks champion level
                                     (map (fn [id] (snapshot/items id)) snapshot/attack-pool)
                                     target scenario options))
  "rotation"
  (pp (core/evaluate-rotation champion level
                              [(snapshot/items "3089") (snapshot/items "3135") (snapshot/items "3020")]
                              target rotation-scenario options annie-model/spells
                              (skills/ranks-from-order annie-model/skill-order level)))
  "optimize-abilities"
  (print-best (core/optimize-rotation champion level
                                      (map (fn [id] (snapshot/items id)) annie-model/ability-pool)
                                      target rotation-scenario options annie-model/spells
                                      (skills/ranks-from-order annie-model/skill-order level) :ability))
  "optimize-total"
  (print-best (core/optimize-rotation champion level
                                      (map (fn [id] (snapshot/items id)) ["1018" "1036" "1038" "1042" "1052" "3006" "3031" "3086" "3089" "3133" "3134" "3135" "3158" "3020"])
                                      target rotation-scenario options annie-model/spells
                                      (skills/ranks-from-order annie-model/skill-order level) :total))
  (error "usage: janet main.janet [demo|optimize|rotation|optimize-abilities|optimize-total] [Garen|Annie] [level]"))
