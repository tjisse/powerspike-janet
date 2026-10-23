(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/position-timeline :as timeline)
(import ../src/powerspike/data-util :as util)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(defn unit [id position &opt fields]
  (merge {:id id :kind :champion :level 1 :position position :attack-range 100
          :base {:ad 10 :hp 1000 :move-speed 100}
          :stats {:ad 10 :hp 1000 :armor 0 :mr 0 :move-speed 100 :attack-speed 1}
          :strategy {:attacks false :abilities false :movement :hold}} (or fields {})))
(defn run [&opt fields]
  (def definition (merge {:duration 5 :actors [(unit "player" 0 {:strategy {:attacks false :abilities false :movement :approach}}) (unit "opponent" 500)]} (or fields {})))
  (def result (engine/simulate definition))
  (def lean (engine/simulate (merge definition {:trace false})))
  (assert (empty? (lean :positions)))
  (each key [:metrics :damage-breakdown :unsupported]
    (assert (= (util/canonical (result key)) (util/canonical (lean key)))))
  result)
(defn positions-at [result t]
  (def frames (result :positions))
  (def previous (or (find |(<= ($ :at) t) (reverse frames)) (first frames)))
  (def next (find |(> ($ :at) t) frames))
  (if next
    (map (fn [a b] (+ a (* (/ (- t (previous :at)) (- (next :at) (previous :at))) (- b a)))) (previous :positions) (next :positions))
    (previous :positions)))
(defn distance-at [result t]
  (def positions (positions-at result t))
  (math/abs (- (positions 1) (positions 0))))
(defn effect [at data]
  {:at at :kind :effect :actor 0 :target 0 :rank 1 :source "fixture" :origin (string "fixture/" at) :effect data})

# Compact keyframes preserve linear segments, turns and same-time jumps.
(def frames @[])
(each [at positions] [[0 [0 500]] [1 [100 500]] [2 [200 500]] [2 [300 500]] [3 [400 500]]]
  (timeline/capture frames at positions))
(assert (= 4 (length frames)))
(assert (= 2 ((frames 1) :at) ((frames 2) :at)))
(def chase (run))
(close 500 (distance-at chase 0))
(close 375 (distance-at chase 1.25))
(close 100 (distance-at chase 4.5))
(assert (<= (length (chase :positions)) 4) "Polling must not inflate the presentation payload.")
(def both (run {:actors [(unit "player" 0 {:strategy {:movement :approach :attacks false :abilities false}})
                         (unit "opponent" 500 {:stats {:ad 10 :hp 1000 :armor 0 :mr 0 :move-speed 50 :attack-speed 1}
                                               :strategy {:movement :approach :attacks false :abilities false}})]}))
(close 350 (distance-at both 1))
(close 100 (distance-at both 3))
(def retreat (run {:actors [(unit "player" 0 {:strategy {:movement :hold-range :preferred-range 500 :attacks false :abilities false}}) (unit "opponent" 200)]}))
(close 325 (distance-at retreat 1.25))
(close 500 (distance-at retreat 4))
(def rooted (run {:duration 6 :initial-events [(effect 1 {:kind :control :control :root :duration 1})]}))
(close 400 (distance-at rooted 1.5))
(close 350 (distance-at rooted 2.5))
(close 200 (distance-at rooted 4))
(def slowed (run {:initial-events [(effect 1 {:kind :control :control :slow :strength 0.5 :duration 1})]}))
(close 375 (distance-at slowed 1.5))
(close 250 (distance-at slowed 3))
(def faster (run {:initial-events [(effect 1 {:kind :stat-buff :stat :move-speed :amount 100 :duration 1})]}))
(close 300 (distance-at faster 1.5))
(close 100 (distance-at faster 3))
(def windup (run {:duration 1.2 :actors [(unit "player" 0 {:attack-range 600 :strategy {:movement :hold-range :preferred-range 600 :attacks true :abilities false}}) (unit "opponent" 500)]}))
(close 500 (distance-at windup 0.15))
(close 535 (distance-at windup 0.65))
(close 570 (distance-at windup 1.1))
(def jumped (run {:actors [(unit "player" 0) (unit "opponent" 500)]
                  :initial-events [(effect 1 {:kind :advance :distance 125})]}))
(close 500 (distance-at jumped 0.9999))
(close 375 (distance-at jumped 1))
(assert (= 2 (length (filter |(= 1 ($ :at)) (jumped :positions)))))
(def still (run {:actors [(unit "player" 0) (unit "opponent" 0)]}))
(close 0 (distance-at still 2))
(assert (= 2 (length (still :positions))))
# A coalesced move can meet between events; retain that exact contact point.
(def contact (run {:duration 1 :actors [(unit "player" 0 {:attack-range 0 :strategy {:movement :approach :attacks false :abilities false}})
                                        (unit "opponent" 1 {:attack-range 0 :strategy {:movement :approach :attacks false :abilities false}})]}))
(close 0.6 (distance-at contact 0.002))
(close 0 (distance-at contact 0.006))
# Mirroring both coordinates cannot change separation.
(def mirrored (run {:actors [(unit "player" 0 {:strategy {:movement :approach :attacks false :abilities false}}) (unit "opponent" -500)]}))
(each t [0 0.1 1.25 3.99 4.2 5] (close (distance-at chase t) (distance-at mirrored t)))
(when-let [path (os/getenv "PS_DISTANCE_FIXTURE")]
  (util/write path (util/encode-json
                     (tabseq [[name result] :in [["chase" chase] ["rooted" rooted] ["jumped" jumped] ["still" still] ["windup" windup]]]
                       name {:positions (result :positions) :trace (result :trace) :statuses (result :statuses)
                             :duration (case name "rooted" 6 "windup" 1.2 5) :end (case name "rooted" 6 "windup" 1.2 5)}))))
(print "Position keyframes: exact chase/retreat, both movers, roots/slows/speed, windup pauses, jumps/contact, compact payload and trace-free parity passed.")
