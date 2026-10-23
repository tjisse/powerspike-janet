(import ./latest-provider :as fixtures)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/champion-abilities :as handlers)
(import ../src/powerspike/data-util :as util)
(import ../scripts/lib/ability-audit :as audit)
(import ../web/catalog :as catalog)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.0003) (string "Expected " expected ", got " actual)))
(def root "data/ability-fixtures/16.21.1/completeness/")
(def ids ["Vi" "TwistedFate" "Tristana" "Singed" "Gangplank" "Veigar" "Zac" "Zilean" "Malzahar" "Cassiopeia"])
(eachp [file expected] ((util/read-json (slurp (string root "manifest.json"))) "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root file))))))
(def scratch (string "build/completeness-tests/" (hash/sha256 (os/cryptorand 8))))
(catalog/initialize scratch "build/seed")
(def refreshed (packages/fetch "16.21.1" (string scratch "/job") (fn [progress] nil) (fn [] false)
                               (fixtures/provider "16.21.1" root ids)))
(def package (packages/load "16.21.1" (refreshed :snapshot)))
(def bytes (string (slurp (string (package :directory) "/package.jdn"))))
(def order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(def idle {:abilities false :attacks false :movement :hold})
(defn source [id &opt ranks]
  (def champion (get-in package [:champion-map id]))
  (assert (= (util/canonical champion) (util/canonical (normalize/semantic-kit id "16.21.1" champion))))
  (scenario/participant package {:champion id :level 18 :skill-order order :ranks (or ranks {})} "player" 0))
(defn actor [id slot &opt fields]
  (def original (source id))
  (def result (merge original {:health 500 :resource 10000 :attack-missile-speed 0 :attack-speed-ratio 1 :attack-speed-cap 3
                               :ranks {slot 1} :base (merge (original :base) {:ad 100})
                               :stats (merge (original :stats) {:hp 1000 :hp-regen 0 :mp 10000 :mp-regen 0 :ap 100 :ad 150 :bonus-ad 50
                                                                :armor 100 :mr 50 :move-speed 100 :attack-speed 1 :attack-speed-uncapped 1
                                                                :attack-speed-bonus 0 :crit-chance 0})
                               :strategy {:abilities true :attacks false :priority [slot] :movement :hold}} (or fields {})))
  (put result :triggers (effects/ability-triggers (result :abilities) (result :ranks)))
  result)
(def target {:id "target" :kind :champion :position 0 :level 18 :stats {:hp 2000 :armor 0 :mr 0 :attack-speed 1 :move-speed 100} :strategy idle})
(defn run [id slot &opt fields other events duration]
  (engine/simulate {:duration (or duration 1) :initial-events (or events [])
                    :actors [(actor id slot fields) (merge target (or other {}))]}))
(defn rows [result kind source]
  (filter |(and (= kind ($ :kind)) (= source ($ :source))) (result :trace)))
(defn damage [result source] (rows result :damage source))
(defn first-raw [result source] ((first (damage result source)) :raw))
(defn hit [at origin &opt slot]
  {:at at :kind :effect :actor 0 :target 1 :rank 1 :source "fixture" :origin origin
   :trigger (if slot :spell-hit :attack) :ability-slot slot :effect {:kind :damage :damage-type :physical :amount 10}})

# Independent arithmetic: .04 + .00035 * 50 bonus AD, then * 2000 HP.
(def vi (run "Vi" :w {:strategy idle} nil [(hit 0 "a") (hit 1 "b") (hit 2 "c")] 2.1))
(close 115 (first-raw vi "ViW"))
(close 1.3 (get-in vi [:actors 0 :stats :attack-speed]))
(def vi-armor (run "Vi" :w {:strategy idle} {:stats (merge (target :stats) {:armor 100})}
                   [(hit 0 "a") (hit 1 "b") (hit 2 "c") (hit 2.1 "d")] 2.2))
(close 80 (get-in vi-armor [:actors 1 :stats :armor]))
(close 57.5 ((first (damage vi-armor "ViW")) :damage))
(close (/ 10 1.8) ((last (damage vi-armor "fixture")) :damage))
(def vi-refresh (run "Vi" :w {:strategy idle} nil [(hit 0 "a") (hit 3 "b") (hit 6 "c")] 6.1))
(assert (= 1 (length (damage vi-refresh "ViW"))))
(assert (empty? (damage (run "Vi" :w {:strategy idle} nil [(hit 0 "a") (hit 4 "b") (hit 8 "c")] 8.1) "ViW")))
(assert (empty? (damage (run "Vi" :w {:strategy idle} nil [(hit 0 "a") (hit 1 "b") (hit 2 "r" :r)] 2.1) "ViW")))
(def vi-e (run "Vi" :w {:strategy idle} nil [(hit 0 "a") (hit 1 "e" :e) (hit 1 "e" :e) (hit 2 "b")] 2.1))
(assert (= 1 (length (damage vi-e "ViW"))))
(close 195 (first-raw (run "Vi" :w {:strategy idle :ranks {:w 5}} nil [(hit 0 "a") (hit 1 "b") (hit 2 "c")] 2.1) "ViW"))
(def vi-expired (run "Vi" :w {:strategy idle} {:stats (merge (target :stats) {:armor 100})} [(hit 0 "a") (hit 1 "b") (hit 2 "c")] 6.1))
(close 100 (get-in vi-expired [:actors 1 :stats :armor]))
(close 1 (get-in vi-expired [:actors 0 :stats :attack-speed]))

# Stacked Deck has no cast and no mana cost. Its learned AS is permanent.
(def four [(hit 0 "a") (hit 1 "b") (hit 2 "c") (hit 3 "d")])
(def tf (run "TwistedFate" :e {:strategy idle} nil four 3.1))
(close 115 (first-raw tf "CardmasterStack"))
(assert (empty? (rows tf :cast "CardmasterStack")))
(close 10000 (get-in tf [:actors 0 :resource]))
(close 215 (first-raw (run "TwistedFate" :e {:strategy idle :ranks {:e 5}} nil four 3.1) "CardmasterStack"))
(assert (empty? (damage (run "TwistedFate" :e {:strategy idle :ranks {:e 0}} nil four 3.1) "CardmasterStack")))
(def tf0 (source "TwistedFate" {:e 0}))
(def tf1 (source "TwistedFate" {:e 1}))
(close 0.15 (- (get-in tf1 [:stats :attack-speed-bonus]) (get-in tf0 [:stats :attack-speed-bonus])))
(close (* 0.15 (tf1 :attack-speed-ratio)) (- (get-in tf1 [:stats :attack-speed]) (get-in tf0 [:stats :attack-speed])))
(assert (some |(and (= "Stacked Deck" ($ :effect)) (= "player" ($ :actor))) (tf :statuses)))

(def rapid (run "Tristana" :q nil {:position 10000}))
(close 1.4 (get-in rapid [:actors 0 :stats :attack-speed]))
(close 0 ((first (rows rapid :buff "TristanaQ")) :at))
(close 1 (get-in (run "Tristana" :q nil nil nil 7.01) [:actors 0 :stats :attack-speed]))
(close 2.2 (get-in (run "Tristana" :q {:ranks {:q 5}}) [:actors 0 :stats :attack-speed]))
(close 1.4 (get-in (run "Tristana" :q {:strategy {:abilities true :attacks false :priority [:q] :movement :hold :hit-chance 0}}) [:actors 0 :stats :attack-speed]))

(def potion (run "Singed" :r))
(each [stat expected] [[:ap 125] [:armor 125] [:mr 75] [:move-speed 125] [:hp-regen 25] [:mp-regen 25]]
  (close expected (get-in potion [:actors 0 :stats stat])))
(close 503.75 (get-in potion [:actors 0 :health]))
(close 9903.75 (get-in potion [:actors 0 :resource]))
(close 185 (get-in (run "Singed" :r {:ranks {:r 3}}) [:actors 0 :stats :ap]))
(close 100 (get-in (run "Singed" :r nil nil nil 25.26) [:actors 0 :stats :ap]))

# Remove Scurvy can respond to modeled cast-disabling control, but does not
# erase unrelated debuffs or pretend to cancel airborne displacement.
(defn cc [control]
  {:at 0 :priority 0 :kind :effect :actor 1 :target 0 :source "fixture" :origin "cc"
   :effect {:kind :control :control control :duration 2 :strength 0.5}})
(close 700 (get-in (run "Gangplank" :w) [:actors 0 :health]))
(close 800 (get-in (run "Gangplank" :w {:ranks {:w 5}}) [:actors 0 :health]))
(each control [:stun :charm :fear :suppression :silence :root :slow :grounded]
  (def cleansed (run "Gangplank" :w nil nil [(cc control)]))
  (assert (= 1 (length (rows cleansed :cleanse "GangplankW"))))
  (close 0 ((first (rows cleansed :cast "GangplankW")) :at))
  (close 0.25 (get-in cleansed [:actors 0 :controls control])))
(assert (empty? (rows (run "Gangplank" :w nil nil [(cc :airborne)]) :cast "GangplankW")))
(assert (empty? (rows (run "Tristana" :q nil nil [(cc :silence)]) :cast "TristanaQ")))

# Veigar: 175 + .65*100 = 240; half missing health increases this by 75%.
(each [health expected] [[2000 240] [1000 420] [(/ 2000 3) 480] [200 480]]
  (close expected (first-raw (run "Veigar" :r nil {:health health}) "VeigarR")))
(close 400 (first-raw (run "Veigar" :r {:ranks {:r 3}}) "VeigarR"))
(def burst (run "Veigar" :r nil {:position 300}))
(close (+ 0.25 (/ (- (math/sqrt (+ (* 500 500) (* 2 4000 300))) 500) 4000))
       ((first (damage burst "VeigarR")) :at))
(def heal-in-flight {:at 0.4 :kind :effect :actor 1 :target 1 :source "fixture" :origin "heal"
                     :effect {:kind :heal :amount 200}})
(close 384 (first-raw (run "Veigar" :r nil {:position 300 :health 1000} [heal-in-flight]) "VeigarR"))
(def veigar-r (find |(= :r ($ :slot)) ((source "Veigar") :abilities)))
(close 1.6328125 (engine/projectile-time veigar-r 5000 0))
(def missing-record (merge @{} (veigar-r :record)))
(put missing-record "mMissileSpec" nil)
(def missing-motion (handlers/review (merge veigar-r {:record missing-record}) :veigar-r))
(assert (not (some |(= :estimated ($ :status)) (missing-motion :effects))))

# Zac: 40 + (.04 + .0003*100)*2000 = 180, costing 4% current HP.
(def zac (run "Zac" :w))
(close 180 (first-raw zac "ZacW"))
(close 480 (get-in zac [:actors 0 :health]))
(close 300 (first-raw (run "Zac" :w {:ranks {:w 5}}) "ZacW"))
(def warp (run "Zilean" :e nil {:position 500}))
(close 0.515250027179718 ((first (rows warp :control "TimeWarp")) :at))
(close 60 (get-in warp [:actors 1 :stats :move-speed]))
(close 1 (get-in (run "Zilean" :e {:ranks {:e 5}}) [:actors 1 :stats :move-speed]))
(close 100 (get-in (run "Zilean" :e nil nil nil 3.02) [:actors 1 :stats :move-speed]))

(def visions (run "Malzahar" :e nil nil nil 4.3))
(assert (= 16 (length (damage visions "MalzaharE"))))
(close 160 (sum (map |($ :raw) (damage visions "MalzaharE"))))
(close 0.5 ((first (damage visions "MalzaharE")) :at))
(close 4.25 ((last (damage visions "MalzaharE")) :at))
(close 300 (sum (map |($ :raw) (damage (run "Malzahar" :e {:ranks {:e 5}} nil nil 4.3) "MalzaharE"))))
(def poison (run "Cassiopeia" :q nil nil nil 3.3))
(assert (= 7 (length (damage poison "CassiopeiaQ"))))
(close 140 (sum (map |($ :raw) (damage poison "CassiopeiaQ"))))
(close 0.25 ((first (damage poison "CassiopeiaQ")) :at))
(close 3.25 ((last (damage poison "CassiopeiaQ")) :at))
(close 280 (sum (map |($ :raw) (damage (run "Cassiopeia" :q {:ranks {:q 5}} nil nil 3.3) "CassiopeiaQ"))))
(defn application [id slot at origin]
  {:at at :kind :effect :actor 0 :target 1 :rank 1 :source id :origin origin :ability-slot slot
   :effect (first ((find |(= slot ($ :slot)) ((source (if (= id "MalzaharE") "Malzahar" "Cassiopeia")) :abilities)) :effects))})
(def replaced (run "Malzahar" :e {:strategy idle} nil [(application "MalzaharE" :e 0 "first") (application "MalzaharE" :e 2 "second")] 6.1))
(assert (= 23 (length (damage replaced "MalzaharE"))))
(def replaced-poison (run "Cassiopeia" :q {:strategy idle} nil [(application "CassiopeiaQ" :q 0 "first") (application "CassiopeiaQ" :q 1 "second")] 4.1))
(assert (= 9 (length (damage replaced-poison "CassiopeiaQ"))))
(def parry {:at 0 :priority 0 :kind :effect :actor 1 :target 1 :source "fixture" :origin "parry"
            :effect {:kind :parry :duration 1 :source-kinds [:champion]}})
(assert (empty? (damage (run "Malzahar" :e nil nil [parry] 4.3) "MalzaharE")))
(assert (empty? (damage (run "Vi" :w {:strategy idle} nil [parry (hit 0.1 "a") (hit 0.2 "b") (hit 1.1 "c")] 1.2) "ViW")))

# Reviewed metadata does not enable passive or periodic semantics on a future patch.
(each [id slot] [["Vi" :w] ["TwistedFate" :e] ["Malzahar" :e] ["Cassiopeia" :q]]
  (def current (find |(= slot ($ :slot)) ((source id) :abilities)))
  (def fresh (normalize/ability slot "fixture" {"mSpell" (current :record)} {} {} "16.22.1"))
  (def future (normalize/semantic-kit id "16.22.1" {:abilities [fresh]}))
  (assert (not (get-in future [:abilities 0 :passive])))
  (assert (not (get-in future [:abilities 0 :rank-bonuses])))
  (assert (not (some |(= :periodic ($ :kind)) (get-in future [:abilities 0 :effects])))))

(def cases @[])
(each [id slot name kind count duration] [["Vi" :w "ViW" :damage 1 3.5] ["TwistedFate" :e "CardmasterStack" :damage 1 5]
                                          ["Tristana" :q "TristanaQ" :buff 1 1] ["Singed" :r "InsanityPotion" :stat-buff 6 1]
                                          ["Gangplank" :w "GangplankW" :heal 1 1] ["Veigar" :r "VeigarR" :damage 1 1]
                                          ["Zac" :w "ZacW" :damage 1 1] ["Zilean" :e "TimeWarp" :control 1 1]
                                          ["Malzahar" :e "MalzaharE" :damage 16 4.3] ["Cassiopeia" :q "CassiopeiaQ" :damage 7 3.3]]
  (def passive (some |(= id $) ["Vi" "TwistedFate"]))
  (def learned (find |(= slot ($ :slot)) ((source id) :abilities)))
  (assert (= :executes ((audit/inspect id learned) :status)) id)
  (each active [0 1]
    (def selected {:champion id :level 18 :skill-order order :health-fraction 0.5
                   :ranks {:q (if (= slot :q) 1 0) :w (if (= slot :w) 1 0) :e (if (= slot :e) 1 0) :r (if (= slot :r) 1 0)}
                   :strategy {:abilities (not passive) :attacks passive :priority [slot] :movement :hold}})
    (def other {:champion "Singed" :level 18 :skill-order order :strategy idle})
    (def definition {:schema 1 :patch "16.21.1" :snapshot (refreshed :snapshot) :duration duration :distance 0 :seed 1 :samples 1
                     :player (if (= active 0) selected other) :target (merge (if (= active 1) selected other) {:kind :champion})})
    (def result (scenario/simulate definition))
    (assert (= (result :metrics) ((scenario/fitness definition) :metrics)))
    (assert (= count (length (rows result kind name))) (string id " " (rows result kind name)))
    (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (result :metrics)
                       :passive-side (when passive (if (= active 0) "player" "opponent")) :passive-slot (string slot)
                       :passive-effect (if (= id "Vi") "Denting Blows" "Stacked Deck")
                       :tooltips (if passive [{:side (if (= active 0) "player" "opponent") :slot (string slot)
                                               :contains (if (= id "Vi") "4%" "15%") :stats [["Type" "Passive"]]}] [])
                       :sources (if (= kind :damage) [name] []) :trace-counts [{:kind kind :source name :count count}]})))
(when-let [export (os/getenv "PS_COMPLETENESS_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string scratch "/patches") (string export "/seed"))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(assert (= bytes (string (slurp (string (package :directory) "/package.jdn")))))
(util/remove-tree scratch)
(print "Ten ability slots: passive procs/stats, temporary buffs, disabled-state cleanse/heal, impact health scaling, accelerating travel, health costs, slows, replaceable periodic damage, both roles and optimizer parity passed.")
