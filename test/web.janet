(import ../web/model :as model)
(import ../web/ui :as ui)
(import ../web/catalog :as catalog)

(catalog/initialize "build/runtime-data" "build/seed")

(var passed 0)
(defn test [description task]
  (task) (++ passed) (print "ok " description))
(defn rejects [task] (assert (not (first (protect (task)))) "Expected rejection"))

(test "legacy frontend wrapper preserves the curated rotation regression"
      (fn [] (def result (model/compare (model/parse-state {"mode" "legacy"})))
        (assert (< (math/abs (- (((result :selected) :combat) :damage) 1359.956399437412)) 0.000001))
        (assert (= 7600 ((result :selected) :cost)))
        (assert (= 4 (length (result :rows))))))
(test "changing target resistance and duration reruns the core instead of selecting cached sample numbers"
      (fn [] (def result (model/compare (model/parse-state {"mr" "97" "duration" "6.5" "level" "13"})))
        (assert (= 97 ((result :state) :mr)))
        (assert (= 6.5 ((result :state) :duration)))
        (each row (result :rows) (assert (> ((row :combat) :damage) 0)))))
(test "selected build remains selected when the ranking changes"
      (fn [] (def result (model/compare (model/parse-state {"duration" 8 "selected" "haste"})))
        (assert (= "haste" ((result :selected) :id)))
        (assert (= 7400 ((result :selected) :cost)))))
(test "untrusted scenario fields reject NaN, infinity, invalid levels and unsupported builds"
      (fn [] (each fields [{"level" 0} {"level" 19} {"level" 6.5} {"level" true}
                           {"mr" -1} {"mr" math/inf} {"mr" "NaN"} {"duration" 0}
                           {"duration" 31} {"selected" "<script>"} {"champion" "<script>"}
                           {"slot1" "../../secret"} {"slot6" 3089} {"armor" -1}]
               (rejects (fn [] (model/parse-state fields))))))
(test "all frontend levels produce legal ranks and builds"
      (fn [] (loop [level :range [1 19]]
               (def result (model/compare (model/parse-state {"level" level})))
               (assert (= 4 (length (result :rows)))))))
(test "evidence is computed from identity-free retained game captures"
      (fn [] (def records (model/evidence))
        (assert (= 5 (length records)))
        (each record records (assert (= :consistent (record :status))))
        (assert (= [10 11 12 12 12] (tuple ;(map |($ :checked) records))))))
(test "rendered errors escape markup rather than executing it"
      (fn [] (def text (ui/render (ui/error-result "<script>alert('bad')</script>")))
        (assert (string/find "&lt;script&gt;" text))
        (assert (not (string/find "<script>" text)))))
(test "page and stream fragments render local art, native form fallback, and scoped evidence"
      (fn [] (def result (model/compare model/default-state))
        (def text (ui/page result (model/evidence)))
        (each marker ["Annie.png" "name=\"level\"" "id=\"results\"" "<noscript>" "Combat damage unverified"]
          (assert (string/find marker text)))
        (assert (not (string/find "cdn.jsdelivr.net" text)))
        (assert (string/find "Q5" (ui/render (ui/ranks-fragment result))))))

(test "full catalog coverage remains unvalidated and every champion evaluates generic attacks"
      (fn []
        (assert (= 173 (length (catalog/champion-list))))
        (assert (= 870 (length (catalog/item-list))))
        (each champion (catalog/champion-list)
          (assert (= "unvalidated" (champion :status)))
          (def result (model/compare (model/parse-state {"champion" (champion :id) "selected" "custom"})))
          (assert (> (((result :selected) :combat) :damage) 0))
          (unless (= "Annie" (champion :id))
            (assert (= 0 (((result :selected) :combat) :ability-dps)))
            (assert (= 1 (length (result :rows))))))))
(test "every item can be selected as a sandbox entry without inventing passive damage"
      (fn [] (each item (catalog/item-list)
               (assert (= "unvalidated" (item :status)))
               (def result (model/compare (model/parse-state {"champion" "Garen" "slot1" (item :id)})))
               (assert (= (item :gold) ((result :selected) :cost)))
               (assert (= 0 (((result :selected) :combat) :ability-dps))))))
(test "custom inventory has six independent slots, holes survive, and arbitrary inputs rerun stats"
      (fn [] (def state (model/parse-state {"champion" "Aatrox" "level" 13 "armor" 97
                                            "selected" "custom" "slot2" "3031" "slot6" "3036"}))
        (def result (model/compare state))
        (assert (= "" (state :slot1))) (assert (= "3031" (state :slot2)))
        (assert (= 2 (length ((result :selected) :items))))
        (assert (< (math/abs (- .35 (((result :selected) :stats) :armor-pen-percent))) 1e-9))
        (assert (string/find "Edit slot 1: empty" (ui/render (ui/results result))))))
(test "excluded on-hit effects and other-mode inventory restrictions remain visible"
      (fn [] (def result (model/compare (model/parse-state {"champion" "Jhin" "slot1" "6672" "slot2" "222051"})))
        (def text (ui/render (ui/results result)))
        (each marker ["Basic" "Unvalidated estimate" "Kraken Slayer" "Passive and active effects excluded"
                      "not available on map"]
          (assert (string/find (if (= marker "Basic") "basic attacks" marker) text)))))

(test "graph distinguishes missing spell models from real zero spell damage"
      (fn []
        (def annie (model/compare (model/parse-state {"champion" "Annie"})))
        (def events (((annie :selected) :combat) :events))
        (assert (some |(= "AnnieQ" ($ :source)) events))
        (assert (some |(= "AnnieW" ($ :source)) events))
        (assert (string/find "Modeled abilities + attacks over time" (ui/render (ui/results annie))))
        (def ahri (ui/render (ui/results (model/compare (model/parse-state {"champion" "Ahri"})))))
        (each marker ["Basic attacks over time" "Spells: not modeled" "Spell damage unavailable for Ahri"]
          (assert (string/find marker ahri)))
        (assert (not (string/find "Abilities 0" ahri)))))

(test "frontend duels use two acting participants and report sampled health outcomes"
      (fn [] (def result (model/compare (model/parse-state {"mode" "duel" "champion" "Annie" "opponent" "Garen"
                                                            "level" 6 "opponentlevel" 6 "duration" 8 "samples" 3 "selected" "custom"})))
        (def combat (get-in result [:selected :combat]))
        (assert (= 3 (combat :samples)))
        (assert (> (get-in combat [:metrics :damage-taken]) 0))
        (assert (> (length (combat :trace)) 0))
        (assert (combat :scenario-id))
        (assert (not (empty? (combat :uncertainty))))))

(print passed " frontend tests passed")
