(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)
(defn unit [id &opt settings]
  (merge {:id id :kind :champion :level 1 :base {:ad 100 :ap 0 :hp 1000}
          :stats {:hp 1000 :mp 20 :ad 100 :ap 0 :armor 0 :mr 0 :attack-speed 1 :crit-chance 0 :crit-damage 1.75}
          :position 0 :attack-range 200 :ranks {:q 1}
          :strategy {:attacks false :abilities false :movement :hold}}
         (or settings {})))
(defn battle [events &opt a b duration]
  (engine/simulate {:duration (or duration 3) :actors [(unit "a" a) (unit "b" b)] :initial-events events}))
(defn effect [at actor target data]
  {:at at :kind :effect :actor actor :target target :source "fixture" :origin (string actor "/" at) :effect data})
(defn hit [at actor target amount] (effect at actor target {:kind :damage :damage-type :true :amount amount}))
(defn close [a b] (assert (< (math/abs (- a b)) 0.000001)))
(def plain (battle [] {:strategy {:attacks true :abilities false}}))
(close 300 (plain :damage))
(each [actual expected] (map tuple (map |($ :at) (plain :events)) [0.3 1.3 2.3]) (close actual expected))
(def deaths (battle [(hit 1 0 1 1000) (hit 1 1 0 1000)]))
(assert (= [1 1] (tuple ;(map |($ :dead-at) (deaths :actors)))))
(def health-dependent {:op :multiply :children [{:op :target-stat :stat :health} {:op :constant :value 0.5}]})
(def changing (battle [(hit 1 0 1 health-dependent) (hit 2 0 1 health-dependent)]))
(close 750 (changing :damage)) (close 250 (((changing :actors) 1) :health))
(def shield (battle [(effect 0 1 1 {:kind :shield :amount 50 :duration 1}) (hit 0.5 0 1 100)]))
(close 50 (((shield :actors) 1) :absorbed)) (close 950 (((shield :actors) 1) :health))
(def expired (battle [(effect 0 1 1 {:kind :shield :amount 50 :duration 1}) (hit 1 0 1 100)]))
(close 0 (((expired :actors) 1) :absorbed)) (close 900 (((expired :actors) 1) :health))
(def healed (battle [(effect 1 0 0 {:kind :heal :amount 5000})] {:health 400}))
(close 600 (((healed :actors) 0) :healed))
(def delayed (battle [] {:attack-missile-speed 10 :strategy {:attacks true :abilities false}}
                     {:position 100} 1))
(close 0 (delayed :damage))
(def spell {:id "spell" :slot :q :cast-time 0.1 :range 500 :cost 10 :cooldown 0.2
            :effects [{:kind :damage :damage-type :magic :amount 50 :status :estimated :target :enemy}]})
(def exhausted (battle [] {:abilities [spell] :strategy {:attacks false :abilities true}}))
(assert (= 2 (count |(= :cast ($ :kind)) (exhausted :trace))))
(close 0 (exhausted :resource-left)) (close 100 (exhausted :damage))
(def directed (battle [] {:abilities [(merge spell {:cast-time -2})] :strategy {:abilities true :attacks true}}))
(assert (not (empty? (directed :unsupported))))
(close 300 (directed :damage))
(def zero-cooldown (battle [] {:abilities [(merge spell {:cost 0 :cooldown 0})]
                               :strategy {:abilities true :attacks true}}))
(close 300 (zero-cooldown :damage))
(assert (some |(string/find "Zero-cooldown activation" $) (zero-cooldown :unsupported)))
(assert (= 0 (count |(= :cast ($ :kind)) (zero-cooldown :trace))))
(def periodic (battle [] {:abilities [(merge spell {:cost 0 :cooldown 99
                                                    :effects [{:kind :damage :damage-type :true :amount 20 :hits 3 :interval 1
                                                               :status :estimated :target :enemy}]})]
                          :strategy {:abilities true :attacks false}}))
(close 60 (periodic :damage))
(def proc (battle [] {:strategy {:attacks true :abilities false}
                      :triggers [{:id "proc" :on [:damage] :kind :damage :damage-type :magic :amount 65 :cooldown 0}]}))
(close 495 (proc :damage)) (assert (= 6 (length (proc :events))))
(def interrupted (battle [(effect 0.1 1 0 {:kind :control :control :stun :duration 1})]
                         {:strategy {:attacks true :abilities false}}))
(assert (some |(= :interrupted ($ :kind)) (interrupted :trace)))
(def approach (battle [] {:stats {:hp 1000 :mp 0 :ad 100 :armor 0 :mr 0 :attack-speed 1 :move-speed 400}
                          :strategy {:attacks true :abilities false :movement :approach}}
                      {:position 1000}))
(assert (> (approach :damage) 0))
(def seeded {:duration 10 :seed 123 :actors [(unit "a" {:stats {:hp 10000 :ad 100 :armor 0 :mr 0 :attack-speed 1
                                                                :crit-chance 0.5 :crit-damage 2}
                                                        :strategy {:attacks true :abilities false :hit-chance 0.7}})
                                             (unit "b" {:stats {:hp 10000 :armor 0 :mr 0}})]})
(assert (= ((engine/simulate seeded) :metrics) ((engine/simulate seeded) :metrics)))
(assert (not= ((engine/simulate seeded) :damage) ((engine/simulate (merge seeded {:trial 1})) :damage)))
(assert (= (get ((seeded :actors) 0) :health) nil))
(assert (not (first (protect (engine/simulate (merge seeded {:event-limit 5}))))))
(assert (not (first (protect (engine/simulate seeded (fn [] true))))))
(def charged (battle [] {:abilities [(merge spell {:cost 0 :cooldown 1 :max-charges 2 :charge-delay 0.1})]
                         :strategy {:abilities true :attacks false}}))
(assert (= 4 (count |(= :cast ($ :kind)) (charged :trace))))
(assert (= 2 (count |(= :charge ($ :kind)) (charged :trace))))
(def recast (battle [] {:abilities [(merge spell {:cost 10 :cooldown 99 :recast {:window 1 :count 2 :delay 0.1}})]
                        :strategy {:abilities true :attacks false}}))
(assert (= 3 (count |(= :cast ($ :kind)) (recast :trace))))
(close 10 (recast :resource-left))
(def buffed (battle [(effect 0 0 0 {:kind :stat-buff :stat :ad :amount 100 :duration 1})]
                    {:strategy {:attacks true :abilities false}}))
(close 400 (buffed :damage))
(close 100 (get-in buffed [:actors 0 :stats :ad]))
(def slow (battle [(effect 0 1 0 {:kind :control :control :slow :strength 0.5 :duration 1})]
                  {:stats {:hp 1000 :ad 100 :move-speed 400 :attack-speed 1 :armor 0 :mr 0}
                   :strategy {:attacks true :abilities false :movement :approach}}
                  {:position 1000} 1))
(close 200 (get-in slow [:actors 0 :position]))
(close 0.5 (get-in slow [:actors 0 :control-time]))
(def immune (battle [(effect 0 0 1 {:kind :control :control :stun :duration 3})]
                    nil {:immunities [:stun] :strategy {:attacks true :abilities false}}))
(close 300 (get-in immune [:actors 1 :damage-dealt]))
(def once (battle [(effect 0 0 0 {:kind :buff :buff "mark" :duration 10})]
                  {:strategy {:attacks true :abilities false}
                   :triggers [{:id "consume" :on [:damage] :requires-buff "mark" :consume-buff "mark"
                               :kind :damage :damage-type :true :amount 20}]}))
(close 320 (once :damage))
(def bounded (battle [] {:triggers [{:id "bounded" :on [:damage] :kind :damage :damage-type :true :amount 1000
                                     :monster-cap {:op :constant :value 20}}]
                         :strategy {:attacks true :abilities false}} {:kind :objective} 1))
(close 120 (bounded :damage))
(def sampled (engine/trials seeded 16))
(def lean (engine/trials (merge seeded {:trace false}) 16))
(assert (empty? (lean :trace)))
(assert (empty? (lean :events)))
(each field [:metrics :uncertainty :damage-breakdown :unsupported]
  (assert (= (util/canonical (sampled field)) (util/canonical (lean field)))))
(assert (= (sampled :metrics) ((engine/trials seeded 16) :metrics)))
(assert (> (get-in sampled [:uncertainty :damage]) 0))
(close (sampled :damage) (get-in sampled [:metrics :damage]))
(print "Chronological health, simultaneous deaths, conditional health damage, shields/expiry, healing, travel, resources, periodic hits, proc bounds, interruption, movement and seeded trials passed.")
