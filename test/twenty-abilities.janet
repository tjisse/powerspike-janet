(import ./latest-provider :as fixtures)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/effects :as effects)
(import ../src/powerspike/champion-abilities :as handlers)
(import ../src/powerspike/data-util :as util)
(import ../web/catalog :as catalog)
(import pshash :as hash)

(defn close [expected actual]
  (assert (and (number? actual) (< (math/abs (- expected actual)) 0.0004)) (string "Expected " expected ", got " actual)))
(def root "data/ability-fixtures/16.21.1/twenty/")
(def ids ["Warwick" "Singed" "Katarina" "XinZhao" "Yone" "Lulu" "Velkoz" "Trundle" "Draven" "Twitch" "Sivir" "Zilean" "Teemo" "Karthus" "Nocturne" "Kassadin" "Olaf"])
(eachp [file expected] ((util/read-json (slurp (string root "manifest.json"))) "fixture_sha256")
  (assert (= expected (hash/sha256 (slurp (string root file))))))
(def scratch (string "build/twenty-tests/" (hash/sha256 (os/cryptorand 8))))
(catalog/initialize scratch "build/seed")
(def refreshed (packages/fetch "16.21.1" (string scratch "/job") (fn [progress] nil) (fn [] false) (fixtures/provider "16.21.1" root ids)))
(def package (packages/load "16.21.1" (refreshed :snapshot)))
(def bytes (string (slurp (string (package :directory) "/package.jdn"))))
(def order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(def idle {:abilities false :attacks false :movement :hold})
(defn source [id &opt ranks]
  (def champion (get-in package [:champion-map id]))
  (assert (= (util/canonical champion) (util/canonical (normalize/semantic-kit id "16.21.1" champion))))
  (scenario/participant package {:champion id :level 18 :skill-order order :ranks (or ranks {})} "player" 0))
(defn learned [id slot] (find |(= slot ($ :slot)) ((source id) :abilities)))
(defn actor [id slot &opt fields]
  (def original (source id))
  (def ranks (get fields :ranks {slot 1}))
  (def as-bonus (sum (map |(get $ :attack-speed-bonus 0) (effects/ability-bonuses (original :abilities) ranks))))
  (def totals (merge (original :stats) {:hp 1000 :hp-regen 0 :mp 1000 :mp-regen 0 :ap 100 :ad 150 :bonus-ad 50 :armor 100 :mr 50
                                        :move-speed 100 :attack-speed (+ 1 as-bonus) :attack-speed-uncapped (+ 1 as-bonus) :attack-speed-bonus as-bonus
                                        :crit-chance 0 :attack-range 200 :ability-haste 0} (get fields :stats {})))
  (def result (merge original {:health 500 :resource 500 :attack-range 200 :attack-missile-speed 0 :attack-speed-ratio 1 :attack-speed-cap 3
                               :ranks ranks :base (merge (original :base) {:ad 100})
                               :strategy {:abilities true :attacks false :priority [slot] :movement :hold}} (or fields {}) {:stats totals}))
  (put result :triggers (effects/ability-triggers (result :abilities) (result :ranks)))
  result)
(def target {:id "target" :kind :champion :position 0 :level 18 :stats {:hp 2000 :armor 0 :mr 0 :move-speed 100 :attack-speed 1} :strategy idle})
(defn run [id slot &opt fields other events duration]
  (engine/simulate {:duration (or duration 1) :initial-events (or events []) :actors [(actor id slot fields) (merge target (or other {}))]}))
(defn rows [result kind source] (filter |(and (= kind ($ :kind)) (= source ($ :source))) (result :trace)))
(defn damage [result source] (rows result :damage source))
(defn raw [result source] ((first (damage result source)) :raw))
(defn initial [at actor target source origin effect]
  {:at at :kind :effect :actor actor :target target :source source :origin origin :rank 1 :effect effect})
(defn incoming [at origin &opt effect]
  (initial at 1 0 "incoming" origin (or effect {:kind :damage :damage-type :magic :amount 100})))
(defn hit [at origin]
  (merge (initial at 0 1 "fixture" origin {:kind :damage :damage-type :physical :amount 10}) {:trigger :attack}))

# Warwick heals from damage after resistance, including damage into shields.
(def bite (run "Warwick" :q nil {:stats (merge (target :stats) {:mr 100})}))
(close 400 (raw bite "WarwickQ")) (close 200 ((first (damage bite "WarwickQ")) :damage))
(close 550 (get-in bite [:actors 0 :health]))
(def shield (initial 0 1 1 "fixture" "shield" {:kind :shield :amount 1000 :duration 5}))
(close 550 (get-in (run "Warwick" :q nil {:stats (merge (target :stats) {:mr 100})} [shield]) [:actors 0 :health]))
(close 680 (get-in (run "Warwick" :q {:ranks {:q 5}} {:stats (merge (target :stats) {:mr 100})}) [:actors 0 :health]))

(def glue (run "Singed" :w))
(close 0.625 ((first (rows glue :control "MegaAdhesive")) :at))
(close 50 (get-in glue [:actors 1 :stats :move-speed]))
(close 3.625 (get-in glue [:actors 1 :controls :grounded]))
(close 100 (get-in (run "Singed" :w nil nil nil 3.63) [:actors 1 :stats :move-speed]))
(def fling (run "Singed" :e nil {:position 100}))
(close 225 (raw fling "Fling"))
(close -420 (get-in fling [:actors 1 :position]))
(close 0.25 ((first (rows fling :displacement "Fling")) :at))
(def reverse-fling (run "Singed" :e {:position 100} {:position 0}))
(close 520 (get-in reverse-fling [:actors 1 :position]))

(def blink (run "Katarina" :e nil {:position 500}))
(close 105 (raw blink "KatarinaEWrapper"))
(close 500 (get-in blink [:actors 0 :position]))
(close 0.15 ((first (damage blink "KatarinaEWrapper")) :at))
(def missed-blink (run "Katarina" :e {:strategy {:abilities true :attacks false :priority [:e] :movement :hold :hit-chance 0}} {:position 500}))
(close 500 (get-in missed-blink [:actors 0 :position]))
(assert (empty? (damage missed-blink "KatarinaEWrapper")))

(def sweep (run "XinZhao" :r nil {:position 300}))
(close 535 (raw sweep "XinZhaoR"))
(def retreat (initial 0.4 0 1 "fixture" "retreat" {:kind :displace :distance 1000 :mode :over-caster}))
(def protected (run "XinZhao" :r nil {:position 300} [retreat (incoming 0.5 "a") (incoming 4.4 "b")] 4.5))
(assert (= 1 (length (rows protected :immune "incoming"))))
(close (- 500 (/ 100 1.5)) (get-in protected [:actors 0 :health]))
(def distant-guard (run "XinZhao" :r nil {:position 700} [(incoming 0.5 "far")]))
(assert (empty? (damage distant-guard "XinZhaoR")))
(close 500 (get-in distant-guard [:actors 0 :health]))

(def cleave (run "Yone" :w nil {:stats (merge (target :stats) {:armor 100 :mr 100})}))
(assert (= 2 (length (damage cleave "YoneW"))))
(each row (damage cleave "YoneW") (close 85 (row :raw)) (close 42.5 (row :damage)))
(close 245 ((first (rows cleave :shield "YoneW")) :amount))
(close 0.5 ((first (damage cleave "YoneW")) :at))
(def quick (run "Yone" :w {:stats {:attack-speed-bonus 0.5 :ability-haste 200}}))
(close (* 0.5 (- 1 (* 0.5 0.4166699945926666))) ((first (damage quick "YoneW")) :at))
(close 9.8 ((first (rows quick :cast "YoneW")) :cooldown))
(def capped (run "Yone" :w {:stats {:attack-speed-bonus 3}}))
(close 0.25 ((first (damage capped "YoneW")) :at))
(close (* 14 (- 1 0.5714200139045715)) ((first (rows capped :cast "YoneW")) :cooldown))
(assert (empty? (rows (run "Yone" :w {:strategy {:abilities true :attacks false :priority [:w] :movement :hold :hit-chance 0}}) :shield "YoneW")))

(close 110 (raw (run "Lulu" :q) "LuluQ"))
(close 60 (get-in (run "Lulu" :q nil nil nil 1.26) [:actors 1 :stats :move-speed]))
(close 100 (get-in (run "Lulu" :q nil nil nil 2.26) [:actors 1 :stats :move-speed]))
(def poly (run "Lulu" :w nil {:strategy {:abilities false :attacks true :movement :hold}} nil 1))
(close 40 (get-in poly [:actors 1 :stats :move-speed]))
(assert (empty? (damage poly "attack")))
(assert (= 1 (length (rows poly :interrupted "attack"))))
(close 100 (get-in (run "Lulu" :w nil nil nil 1.38) [:actors 1 :stats :move-speed]))
(def plasma (run "Velkoz" :q nil {:position 260}))
(close 170 (raw plasma "VelkozQ"))
(def plasma-at (+ 0.25099998712539673 (/ 260 1300)))
(close plasma-at ((first (damage plasma "VelkozQ")) :at))
(close 65 (get-in (run "Velkoz" :q nil {:position 260} nil (+ plasma-at 0.501)) [:actors 1 :stats :move-speed]))

(def domain (run "Trundle" :w))
(close 1.3 (get-in domain [:actors 0 :stats :attack-speed]))
(close 120 (get-in domain [:actors 0 :stats :move-speed]))
(def healing (initial 0.5 0 0 "fixture" "heal" {:kind :heal :amount 100}))
(close 625 (get-in (run "Trundle" :w nil nil [healing]) [:actors 0 :health]))
(close 575 (get-in (run "Trundle" :w {:stats {:healing-multiplier 0.6}} nil [healing]) [:actors 0 :health]))
(each [flat-name reduction-name] [["flat" "reduction"] ["a" "z"] ["z" "a"]]
  (def combined (run "Trundle" :w {:strategy idle} nil
                     [(initial 0 0 0 flat-name "flat" {:kind :stat-buff :stat :armor :amount 25 :duration 2})
                      (initial 0 0 0 reduction-name "reduction" {:kind :stat-buff :stat :armor :mode :multiply :amount 0.75 :duration 2})]))
  (close 93.75 (get-in combined [:actors 0 :stats :armor])))
(close 1 (get-in (run "Trundle" :w nil nil nil 8.26) [:actors 0 :stats :attack-speed]))
(def rush (run "Draven" :w nil nil nil 0.3))
(close 1.2 (get-in rush [:actors 0 :stats :attack-speed]))
(close 150 (get-in rush [:actors 0 :stats :move-speed]))
(close 125 (get-in (run "Draven" :w nil nil nil (+ 0.2418999969959259 0.751)) [:actors 0 :stats :move-speed]))
(close 100 (get-in (run "Draven" :w nil nil nil 1.75) [:actors 0 :stats :move-speed]))
(def spray (run "Twitch" :r {:strategy {:abilities true :attacks true :priority [:r] :movement :hold}} {:position 400}))
(close 180 (get-in spray [:actors 0 :stats :ad]))
(close 80 (get-in spray [:actors 0 :stats :bonus-ad]))
(close 500 (get-in spray [:actors 0 :attack-range]))
(close 180 (raw spray "attack"))
(def spray-ended (run "Twitch" :r nil nil nil 6.01))
(close 150 (get-in spray-ended [:actors 0 :stats :ad]))
(close 200 (get-in spray-ended [:actors 0 :attack-range]))

# Rewind changes actual E readiness; an isolated W has no cooldown to refund.
(def rewind (run "Zilean" :w {:ranks {:w 1 :e 1} :strategy {:abilities true :attacks false :priority [:e :w] :movement :hold}} nil nil 5.6))
(def warps (rows rewind :cast "TimeWarp"))
(assert (= 2 (length warps))) (close 0 ((warps 0) :at)) (close 5 ((warps 1) :at))
(close 10 ((first (rows rewind :cooldown-refund "ZileanW")) :amount))
(close 120 (get-in (run "Sivir" :r) [:actors 0 :stats :move-speed]))
(defn fake [id slot] {:id id :slot slot :cost 0 :cooldown 20 :range 0 :cast-time 0 :effects [{:kind :heal :target :self :amount 1 :status :estimated}]})
(def hunt (run "Sivir" :r {:abilities [(learned "Sivir" :r) (fake "fake-q" :q) (fake "fake-e" :e)] :ranks {:q 1 :e 1 :r 1}
                           :strategy {:abilities true :attacks true :priority [:q :e :r] :movement :hold}} nil nil 0.9))
(assert (= 2 (length (rows hunt :cooldown-refund "SivirR"))))
(close 19.5 (get-in hunt [:actors 0 :ready "fake-q"]))
(close 19.51 (get-in hunt [:actors 0 :ready "fake-e"]))

(def poison (run "Teemo" :e {:strategy idle} nil [(hit 0 "a")] 4.1))
(def poison-rows (damage poison "TeemoE"))
(assert (= 5 (length poison-rows))) (close 41.5 ((poison-rows 0) :raw))
(each row (array/slice poison-rows 1) (close 17.25 (row :raw)))
(def refreshed-poison (run "Teemo" :e {:strategy idle} nil [(hit 0 "a") (hit 0.5 "b") (hit 1 "c") (hit 1.5 "d") (hit 2 "e")] 6.1))
(assert (= 11 (length (damage refreshed-poison "TeemoE"))))
(assert (some |(and (= 1 ($ :at)) (< ($ :raw) 20)) (damage refreshed-poison "TeemoE")))
(def fractional-poison (run "Teemo" :e {:strategy idle} nil [(hit 0.3 "a") (hit 0.8 "b") (hit 1.3 "c") (hit 1.8 "d") (hit 2.3 "e")] 6.31))
(assert (= 11 (length (damage fractional-poison "TeemoE"))))
(def wall (run "Karthus" :w nil {:stats (merge (target :stats) {:mr 100})} nil 0.3))
(close 75 (get-in wall [:actors 1 :stats :mr]))
(close 60 (get-in wall [:actors 1 :stats :move-speed]))
(close 80 (get-in (run "Karthus" :w nil nil nil 2.751) [:actors 1 :stats :move-speed]))
(close 100 (get-in (run "Karthus" :w nil {:stats (merge (target :stats) {:mr 100})} nil 5.251) [:actors 1 :stats :mr]))

# One spell impact is blocked as a group, then another spell can land.
(def two-components [(incoming 0.25 "a") (incoming 0.25 "a" {:kind :control :control :stun :duration 2})
                     (incoming 0.5 "b" {:kind :damage :damage-type :true :amount 200})])
(def barrier (run "Sivir" :e nil nil two-components))
(assert (= 1 (length (rows barrier :spell-block "incoming"))))
(assert (empty? (rows barrier :control "incoming")))
(close 440 (get-in barrier [:actors 0 :health]))
(close 140 ((first (rows barrier :heal "SivirE")) :amount))
(def lethal-attack (merge (incoming 0.25 "lethal" {:kind :damage :damage-type :true :amount 1000}) {:trigger :attack}))
(def dying-barrier (run "Sivir" :e nil nil [lethal-attack (incoming 0.25 "late")]))
(close 0 (get-in dying-barrier [:actors 0 :health]))
(assert (empty? (rows dying-barrier :heal "SivirE")))
(def darkness (run "Nocturne" :w nil nil [(incoming 0.25 "a")]))
(close 1.6 (get-in darkness [:actors 0 :stats :attack-speed]))
(close 1.3 (get-in (run "Nocturne" :w nil nil [(incoming 0.25 "a")] 5.26) [:actors 0 :stats :attack-speed]))
(def boundary (run "Nocturne" :w nil nil [(incoming 1.5 "a")] 1.6))
(assert (empty? (rows boundary :spell-block "incoming")))
(close (- 500 (/ 100 1.5)) (get-in boundary [:actors 0 :health]))
(def old-poison (initial 0 1 0 "poison" "old" {:kind :periodic :damage-type :true :amount 40 :pulse-count 4 :pulse-interval 1 :first-delay 1 :duration 4 :buff "Old poison"}))
(def after-poison (run "Nocturne" :w {:strategy {:abilities true :attacks false :priority [:w] :movement :hold :activation {:w {:after 0.5}}}} nil [old-poison (incoming 1.2 "new")] 1.3))
(close 490 (get-in after-poison [:actors 0 :health]))
(assert (= 1 (length (rows after-poison :spell-block "incoming"))))
(def storm {:id "storm" :slot :q :cost 0 :cooldown 10 :range 1000 :cast-time 0
            :effects [{:kind :damage :damage-type :true :target :enemy :amount 100 :hits 3 :interval 0.25 :delay 0.25 :status :estimated}]})
(def pulses (run "Nocturne" :w nil {:abilities [storm] :ranks {:q 1} :strategy {:abilities true :attacks false :priority [:q] :movement :hold}}))
(assert (= 1 (length (rows pulses :spell-block "storm"))))
(assert (= 2 (length (damage pulses "storm"))))
(close 300 (get-in pulses [:actors 0 :health]))
(def returning (merge storm {:effects [{:kind :damage :damage-type :true :target :enemy :amount 100 :delay 0.25 :status :estimated}
                                       {:kind :damage :damage-type :true :target :enemy :amount 100 :delay 0.5 :status :estimated}]}))
(def returned (run "Nocturne" :w nil {:abilities [returning] :ranks {:q 1} :strategy {:abilities true :attacks false :priority [:q] :movement :hold}}))
(assert (= 1 (length (rows returned :spell-block "storm"))))
(assert (= 1 (length (damage returned "storm"))))
(close 400 (get-in returned [:actors 0 :health]))
(def out-of-range (run "Nocturne" :w nil {:position 500} [(incoming 0.25 "far" {:kind :damage :damage-type :true :amount 100 :range-at-impact 10}) (incoming 0.5 "in")] 1))
(assert (= 1 (length (rows out-of-range :spell-block "incoming"))))
(close 500 (get-in out-of-range [:actors 0 :health]))

(def blade (run "Kassadin" :w {:strategy {:abilities true :attacks true :priority [:w] :movement :hold}}))
(def blades (damage blade "NetherBlade"))
(assert (= 2 (length blades)))
(def blade-amounts (sort (map |($ :raw) blades)))
(close 35 (blade-amounts 0)) (close 130 (blade-amounts 1))
(close 599.2 (get-in blade [:actors 0 :resource]))
(def tough (run "Olaf" :w))
(close 97.5 ((first (rows tough :shield "OlafFrenziedStrikes")) :amount))
(close 1.4 (get-in tough [:actors 0 :stats :attack-speed]))
(close 132.5 ((first (rows (run "Olaf" :w {:health 100}) :shield "OlafFrenziedStrikes")) :amount))
(close 132.5 ((first (rows (run "Olaf" :w {:health 300}) :shield "OlafFrenziedStrikes")) :amount))
(def reset (run "Olaf" :w {:strategy {:abilities true :attacks true :priority [:w] :movement :hold :activation {:w {:after 0.5}}}}))
(close 0.5 (((rows reset :attack "attack") 1) :at))
(close (+ 0.5 (/ 0.3 1.4)) (((damage reset "attack") 1) :at))

# An auxiliary profile cannot be reused with a modified primary record.
(each [id slot handler] [["Velkoz" :q :velkoz-q] ["Katarina" :e :katarina-e]]
  (def ability (learned id slot))
  (def altered (merge (ability :record) {"__review_changed" true}))
  (def rejected (handlers/review (merge ability {:record altered}) handler))
  (assert (not (some |(= :estimated ($ :status)) (rejected :effects)))))

(def cases @[])
(each [id slot source kind count duration]
  [["Warwick" :q "WarwickQ" :damage 1 1] ["Singed" :w "MegaAdhesive" :control 2 1] ["Singed" :e "Fling" :damage 1 1]
   ["Katarina" :e "KatarinaEWrapper" :damage 1 1] ["XinZhao" :r "XinZhaoR" :damage 1 1] ["Yone" :w "YoneW" :damage 2 1]
   ["Lulu" :q "LuluQ" :damage 1 1] ["Lulu" :w "LuluW" :control 1 1] ["Velkoz" :q "VelkozQ" :damage 1 1]
   ["Trundle" :w "trundledesecrate" :buff 1 1] ["Draven" :w "DravenFury" :buff 1 1] ["Twitch" :r "TwitchFullAutomatic" :buff 1 1]
   ["Sivir" :r "SivirR" :buff 1 1] ["Zilean" :w "ZileanW" :cooldown-refund 1 5.6] ["Teemo" :e "TeemoE" :damage 1 1]
   ["Karthus" :w "KarthusWallOfPain" :control 1 1] ["Nocturne" :w "NocturneShroudofDarkness" :buff 1 1]
   ["Sivir" :e "SivirE" :buff 1 1] ["Kassadin" :w "NetherBlade" :damage 2 1] ["Olaf" :w "OlafFrenziedStrikes" :shield 1 1]]
  (each active [0 1]
    (def current (learned id slot))
    (def future (normalize/semantic-kit id "16.22.1"
                                        {:abilities [(normalize/ability slot "future" {"mSpell" (current :record)} {} {} "16.22.1")]}))
    (assert (empty? (get-in future [:abilities 0 :effects])))
    (def ranks {:q (if (= slot :q) 1 0) :w (if (= slot :w) 1 0) :e (if (or (= slot :e) (= id "Zilean")) 1 0) :r (if (= slot :r) 1 0)})
    (def selected {:champion id :level 18 :skill-order order :ranks ranks :health-fraction 0.5
                   :strategy {:abilities (not= id "Teemo") :attacks (some |(= id $) ["Teemo" "Kassadin"])
                              :priority (if (= id "Zilean") [:e :w] [slot]) :movement :hold}})
    (def other {:champion "Warwick" :level 18 :skill-order order :strategy idle})
    (def definition {:schema 1 :patch "16.21.1" :snapshot (refreshed :snapshot) :duration duration :distance 0 :seed 1 :samples 1
                     :player (if (= active 0) selected other) :target (merge (if (= active 1) selected other) {:kind :champion})})
    (def result (scenario/simulate definition))
    (assert (= (result :metrics) ((scenario/fitness definition) :metrics)))
    (assert (= count (length (rows result kind source))) (string id " " (util/encode-json (rows result kind source))))
    (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (result :metrics)
                       :passive-side (when (= id "Teemo") (if (= active 0) "player" "opponent")) :passive-slot "e" :passive-effect "Toxic Shot poison"
                       :sources (if (= kind :damage) [source] []) :trace-counts [{:kind kind :source source :count count}]})))
(each id ["Nocturne" "Sivir"]
  (each active [0 1]
    (def selected {:champion id :level 18 :skill-order order :health-fraction 0.5
                   :ranks {:q 0 :w (if (= id "Nocturne") 1 0) :e (if (= id "Sivir") 1 0) :r 0}
                   :strategy {:abilities true :attacks false :priority [(if (= id "Nocturne") :w :e)] :movement :hold}})
    (def other {:champion "Lulu" :level 18 :skill-order order :ranks {:q 1 :w 0 :e 0 :r 0}
                :strategy {:abilities true :attacks false :priority [:q] :movement :hold}})
    (def definition {:schema 1 :patch "16.21.1" :snapshot (refreshed :snapshot) :duration 1 :distance 0 :seed 1 :samples 1
                     :player (if (= active 0) selected other) :target (merge (if (= active 1) selected other) {:kind :champion})})
    (def result (scenario/simulate definition))
    (assert (= (result :metrics) ((scenario/fitness definition) :metrics)))
    (assert (= 1 (length (rows result :spell-block "LuluQ"))))
    (assert (empty? (damage result "LuluQ")))
    (array/push cases {:document (util/read-json (wire/encode definition)) :metrics (result :metrics) :sources [] :blocked-source "LuluQ"
                       :required-statuses ["Spell shield"]
                       :trace-counts [{:kind :spell-block :source "LuluQ" :count 1} {:kind :damage :source "LuluQ" :count 0} {:kind :control :source "LuluQ" :count 0}]})))
(when-let [export (os/getenv "PS_TWENTY_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string scratch "/patches") (string export "/seed"))
  (util/write (string export "/cases.json") (util/encode-json cases)))
(assert (= bytes (string (slurp (string (package :directory) "/package.jdn")))))
(util/remove-tree scratch)
(print "Twenty ability slots: sourced damage, health scaling/healing, controls/decay, attack stats/range, cooldown refunds, poison phase, single-impact spell shields, auxiliary guards, both roles and scoring parity passed.")
