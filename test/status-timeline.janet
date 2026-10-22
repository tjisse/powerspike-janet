(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(defn unit [id &opt fields]
  (merge {:id id :kind :champion :level 1 :position 0 :attack-range 200
          :base {:ad 10 :ap 0 :hp 1000}
          :stats {:hp 1000 :ad 10 :ap 0 :armor 0 :mr 0 :attack-speed 1 :tenacity 0.25}
          :strategy {:attacks false :abilities false :movement :hold}} (or fields {})))
(defn effect [at side data]
  {:at at :kind :effect :actor side :target side :source "fixture" :origin (string "fixture/" at) :effect data})
(defn run [events &opt fields duration]
  (engine/simulate (merge {:duration (or duration 1) :actors [(unit "player") (unit "opponent")]
                           :initial-events events} (or fields {}))))
(defn window [result effect start end &opt actor]
  (def matches (filter |(and (= effect ($ :effect)) (= (or actor "player") ($ :actor))) (result :statuses)))
  (assert (= 1 (length matches)) (string "Expected one " effect " interval: " (util/encode-json matches)))
  (close start ((first matches) :start))
  (close end ((first matches) :end)))

# Tenacity, overlapping types, same-type refresh and selective cleanse use
# applied state, without guessing from an ability's unmodified duration.
(def controls (run [(effect 0.1 0 {:kind :control :control :stun :duration 0.6})
                    (effect 0.2 0 {:kind :control :control :silence :duration 0.2})
                    (effect 0.3 0 {:kind :control :control :stun :duration 0.8})
                    (effect 0.5 0 {:kind :cleanse :controls [:stun]})
                    (effect 0.8 1 {:kind :control :control :root :duration 2})]))
(window controls :stun 0.1 0.5)
(window controls :silence 0.2 0.35)
(window controls :root 0.8 1 "opponent")
(def boundary (run [(effect 0.1 0 {:kind :control :control :stun :duration 0.4})
                    (effect 0.4 0 {:kind :control :control :stun :duration 0.4})]))
(window boundary :stun 0.1 0.7)

# Shield depletion, named buff consumption and stat-buff expiry end exactly at
# the state change. Consuming a buff on an attack also removes its stat bonus.
(def consumed (run [(effect 0.1 0 {:kind :shield :amount 50 :duration 0.8})
                    (effect 0.12 0 {:kind :buff :buff "spellblade" :duration 0.5 :refresh true})
                    (effect 0.2 0 {:kind :buff :buff "spellblade" :duration 0.5 :refresh true})
                    (effect 0.15 0 {:kind :stat-buff :stat :outgoing-multiplier :amount 0.6 :mode :multiply :duration 0.55})
                    (merge (effect 0.25 0 {:kind :damage :damage-type :true :amount 10}) {:target 1 :trigger :attack})
                    (merge (effect 0.4 1 {:kind :damage :damage-type :true :amount 60}) {:target 0})
                    (effect 0.6 1 {:kind :parry :duration 0.3 :source-kinds [:champion]})]
                   {:actors [(unit "player" {:triggers [{:id "consume" :on [:attack] :requires-buff "spellblade" :consume-buff "spellblade"
                                                         :kind :damage :damage-type :true :amount 1}]}) (unit "opponent")]}))
(window consumed :shield 0.1 0.4)
(window consumed "spellblade" 0.12 0.25)
(window consumed :outgoing-multiplier 0.15 0.7)
(window consumed :parry 0.6 0.9 "opponent")
(def shields (run [(effect 0.1 0 {:kind :shield :amount 50 :duration 0.2})
                   (effect 0.2 0 {:kind :shield :amount 100 :duration 0.6})
                   (merge (effect 0.25 1 {:kind :damage :damage-type :true :amount 75}) {:target 0})
                   (merge (effect 0.6 1 {:kind :damage :damage-type :true :amount 75}) {:target 0})]))
(window shields :shield 0.1 0.6)
(def separated (run [(effect 0.11 0 {:kind :parry :duration 0.02 :source-kinds [:champion]})
                     (effect 0.14 0 {:kind :parry :duration 0.02 :source-kinds [:champion]})]))
(assert (= 2 (length (separated :statuses))))
(each [row start end] (map tuple (separated :statuses) [0.11 0.14] [0.13 0.16])
  (close start (row :start)) (close end (row :end)))
(def stacked (run [(effect 0.1 0 {:kind :buff :buff "stack" :duration 0.3})
                   (effect 0.2 0 {:kind :buff :buff "stack" :duration 0.5})]))
(window stacked "stack" 0.1 0.7)
(def zero (run [(effect 0.1 0 {:kind :control :control :stun :duration 0})]))
(assert (empty? (zero :statuses)))
(def immune (run [(effect 0.1 0 {:kind :control :control :stun :duration 1})]
                 {:actors [(unit "player" {:immunities [:stun]}) (unit "opponent")]}))
(assert (empty? (immune :statuses)))
(def parried (run [(effect 0 0 {:kind :parry :duration 0.5 :source-kinds [:champion]})
                   (merge (effect 0.1 1 {:kind :control :control :stun :duration 1}) {:target 0})]))
(assert (not (some |(= :stun ($ :effect)) (parried :statuses))))
(def death (run [(effect 0.1 0 {:kind :control :control :stun :duration 2})
                 (merge (effect 0.45 1 {:kind :damage :damage-type :true :amount 1500}) {:target 0})]))
(window death :stun 0.1 0.45)

# Ready empowered attacks remain active until release consumes their count,
# or their declared window expires even if no expiry event is scheduled.
(def empowerment {:id "empower" :slot :q :cost 0 :cooldown 99 :cast-time 0 :range 200
                  :effects [{:kind :damage :damage-type :true :amount 20 :trigger :attack :target :enemy :status :estimated
                             :attack-mode :bonus :attack-count 1 :duration 0.2}]})
(def empowered (run [] {:actors [(unit "player" {:abilities [empowerment] :ranks {:q 1}
                                                 :strategy {:attacks false :abilities true :movement :hold}}) (unit "opponent")]}))
(window empowered "empower" 0 0.2)
(def released (run [] {:actors [(unit "player" {:abilities [(merge empowerment {:effects [(merge (first (empowerment :effects)) {:duration 1})]})]
                                                :ranks {:q 1} :strategy {:attacks true :abilities true :movement :hold}}) (unit "opponent")]}))
(window released "empower" 0 0.31)
(def inputs {:duration 1 :actors [(unit "player") (unit "opponent")]
             :initial-events [(effect 0.1 0 {:kind :shield :amount 10 :duration 0.2})]})
(def lean (engine/simulate (merge inputs {:trace false})))
(assert (empty? (lean :statuses)))
(each field [:metrics :damage-breakdown :unsupported]
  (assert (= (util/canonical ((engine/simulate inputs) field)) (util/canonical (lean field)))))
(when-let [path (os/getenv "PS_STATUS_FIXTURE")]
  (util/write path (util/encode-json
                     (tabseq [[name result] :in [["controls" controls] ["buffs" consumed] ["cutoff" controls] ["empty" (run [])]]]
                       name {:trace (result :trace) :statuses (result :statuses) :duration 1 :end (if (= name "cutoff") 0.4 1)}))))
(print "Status intervals: applied tenacity, overlap/refresh, cleanse, buff consumption/stacks, shields, parry, death, empowerment expiry/release and trace-free scoring parity passed.")
