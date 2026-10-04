# Read-only sample results for the frontend design; no browser-side combat model.
(import ../../src/powerspike/core :as core)
(import ../../src/powerspike/skills :as skills)
(import ../../data/16.19.1/snapshot :as snapshot)
(import ../../data/16.19.1/annie :as annie)

(defn encode [value]
  (cond
    (nil? value) "null"
    (or (string? value) (keyword? value)) (string/format "%q" (string value))
    (number? value) (string value)
    (indexed? value) (string "[" (string/join (map encode value) ",") "]")
    (dictionary? value) (string "{" (string/join
                                      (seq [[key item] :pairs value] (string (encode key) ":" (encode item))) ",") "}")
    (error "unsupported design-data value")))

(def builds [{:id "penetration" :name "Penetration" :ids ["3089" "3135" "3020"]}
             {:id "ability-power" :name "More ability power" :ids ["3089" "3135" "1052"]}
             {:id "haste" :name "More haste" :ids ["3089" "3135" "3158"]}])
(def samples @[])
(each level [6 18]
  (each mr [40 80 120]
    (each duration [3 5 8]
      (each build builds
        (def result (core/evaluate-rotation (snapshot/champions "Annie") level
                                            (map |(snapshot/items $) (build :ids)) {:armor 80 :mr mr}
                                            {:duration duration :windup-fraction 0.3 :distance 300
                                             :attack-travel-time 0 :include-attacks true}
                                            {:slots 6 :budget 10000 :map 11} annie/spells
                                            (skills/ranks-from-order annie/skill-order level)))
        (array/push samples
                    {:level level :mr mr :duration duration :id (build :id)
                     :name (build :name) :ids (build :ids) :cost (result :cost)
                     :ranks (skills/ranks-from-order annie/skill-order level)
                     :stats (result :stats) :damage ((result :combat) :damage)
                     :dps ((result :combat) :dps)
                     :events ((result :combat) :events)
                     :ability-damage (* duration ((result :combat) :ability-dps))
                     :attack-damage (* duration ((result :combat) :attack-dps))})))))
(print (encode samples))
