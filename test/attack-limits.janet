(import ../src/powerspike/attack-limits :as limits)
(import ../src/powerspike/attacks :as attacks)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/stats :as stats)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn close [expected actual] (assert (< (math/abs (- expected actual)) 0.000001)))
(each patch ["16.19.1" "16.20.1" "16.21.1"]
  (close 3 (limits/baseline patch))
  (close 3 (limits/cap {:patch patch :attack-speed-cap 2.5}))
  (close 3 (limits/cap {:patch patch}))
  (each configured [1.5 3 90]
    (close configured (limits/cap {:patch patch :attack-speed-cap configured}))))
(each patch ["16.18.1" "16.22.1" "99.1.1"]
  (assert (nil? (limits/baseline patch)))
  (close 2.5 (limits/cap {:patch patch :attack-speed-cap 2.5})))
(def old {:patch "16.19.1" :abilities [] :attack-speed-cap 2.5
          :limitations ["Attack-speed cap 2.5, windup 30% and projectile travel zero are assumptions."]})
(each id ["Ahri" "Annie" "Garen"]
  (def repaired (normalize/semantic-kit id "16.19.1" old))
  (close 3 (repaired :attack-speed-cap))
  (assert (not (some |(string/find "cap 2.5" $) (repaired :limitations))))
  (assert (= (util/canonical repaired) (util/canonical (normalize/semantic-kit id "16.19.1" repaired))))
  (if (= id "Ahri") (assert (not (some |(string/find "windup 30%" (string/ascii-lower $)) (repaired :limitations))))
    (assert (some |(string/find "windup 30%" (string/ascii-lower $)) (repaired :limitations)))))
(close 2.5 ((normalize/semantic-kit "Garen" "16.18.1" (merge old {:patch "16.18.1"})) :attack-speed-cap))

(def directory (string "build/attack-limits-tests/" (hash/sha256 (os/cryptorand 8))))
(def package (packages/initialize directory "build/seed"))
(def snapshot-file (string (package :directory) "/package.jdn"))
(def before (hash/sha256 (slurp snapshot-file)))
(each champion (package :champions)
  (close 3 (champion :attack-speed-cap))
  (assert (not (some |(string/find "cap 2.5" $) (champion :limitations)))))
(def annie ((package :champion-map) "Annie"))
(each raw [2.4 2.7 3 3.4]
  (def total (stats/total-stats annie 1 [] [{:attack-speed-bonus (/ (- raw (annie :attack-speed-base)) (annie :attack-speed-ratio))}]))
  (close raw (total :attack-speed-uncapped))
  (close (min raw 3) (total :attack-speed)))

# A legal six-item inventory reaches the new baseline through shared form stats.
(def ids ["3046" "3115" "3091" "3032" "2512" "6675"])
(def participant {:champion "Gnar" :form "mini" :level 18 :skill-order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e]
                  :loadout {:items ids} :strategy {:attacks true :abilities false :movement :hold}})
(def definition {:schema 1 :patch "16.19.1" :snapshot (package :snapshot) :duration 1.2 :distance 0 :seed 7 :samples 1
                 :player participant :target {:kind :practice :hp 1000000 :armor 0 :mr 0}})
(def compiled (scenario/compile definition))
(def actor (get-in compiled [:actors 0]))
(assert (> (get-in actor [:stats :attack-speed-uncapped]) 3))
(close 3 (get-in actor [:stats :attack-speed]))
(close 3 (actor :attack-speed-cap))
(def outcome (scenario/simulate definition))
(def hits (filter |(= "attack" ($ :source)) (outcome :events)))
(assert (= 4 (length hits)))
(for index 0 4 (close (+ (/ 0.3 3) (/ index 3)) ((hits index) :at)))
(assert (= (outcome :metrics) ((scenario/fitness definition) :metrics)))
(def first-impact (/ 0.3 3))
(each critical [0 1]
  (def unit (merge actor {:stats (merge (actor :stats) {:crit-chance critical}) :triggers []}))
  (def target (get-in compiled [:actors 1]))
  (defn run [duration] (engine/simulate {:duration duration :actors [unit target]}))
  (assert (empty? ((run first-impact) :events)))
  (def landed (first ((run (+ first-impact 0.000001)) :events)))
  (close first-impact (landed :at))
  (assert (= (= critical 1) (landed :critical))))
(def duel (scenario/simulate (merge definition {:duration 0.8 :target (merge participant {:kind :champion})})))
(each owner ["player" "opponent"]
  (def hits (filter |(and (= :damage ($ :kind)) (= "attack" ($ :source)) (= owner ($ :actor))) (duel :trace)))
  (assert (= 3 (length hits)))
  (close first-impact ((first hits) :at)))

# The bundled seed intentionally searches curated purchases. Keep the existing
# five items locked and compare its supported Dagger/Greaves choices.
(def optimized (search/run package definition {:pool ["1042" "3006"] :locked (take 5 ids) :slots 6 :budget 100000 :seconds 10 :final-samples 1}
                           (fn [progress] nil) (fn [] false)))
(assert (optimized :complete))
(assert (some |(> (get-in (scenario/compile ($ :definition)) [:actors 0 :stats :attack-speed-uncapped]) 3) (optimized :rows)))
(each row (optimized :rows)
  (assert (= (row :metrics) ((scenario/fitness (row :definition)) :metrics))))
(assert (= before (hash/sha256 (slurp snapshot-file))))
(util/remove-tree directory)
(print "Reviewed baseline attack-speed limit: patch bounds, preserved overrides, cached repair, capped cadence, critical endpoints, both participants and optimizer parity passed.")
