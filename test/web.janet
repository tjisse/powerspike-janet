(import ../web/model :as model)
(import ../web/ui :as ui)
(import ../web/catalog :as catalog)
(import ../web/details :as details)
(import ../web/optimizer :as optimizer)
(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/skills :as skills)
(import ../src/powerspike/scenario :as scenarios)
(import ../src/powerspike/normalize :as normalize)
(import ../web/tooltip :as tooltip)
(import ../web/server :as server)
(import ../src/powerspike/scenario-wire :as wire)
(import pshash :as hash)

# Frontend regressions start from the seed, independently of patches refreshed
# in a running development app.
(catalog/initialize (string "build/web-tests/" (hash/sha256 (os/cryptorand 8))) "build/seed")

(var passed 0)
(defn test [description task]
  (task) (++ passed) (print "ok " description))
(defn rejects [task] (assert (not (first (protect (task)))) "Expected rejection"))

(test "retained tooltip formulas resolve ranks and scaling without replacing unknown values"
      (fn []
        (def root "data/parser-fixtures/16.18.1/")
        (def kit (normalize/kit "Annie" (util/read-json (slurp (string root "Annie-characters.json")))
                                (util/read-json (slurp (string root "Annie-abilities.json")))
                                (util/read-json (slurp (string root "strings.json"))) "16.18.1"))
        (def q (first (kit :abilities)))
        (def context {:rank 5 :level 18 :stats {:ap 100 :ad 150} :base {:ap 0 :ad 80} :buffs {}})
        (def segments (mapcat identity (tooltip/body (q :tooltip) (q :variables) context)))
        (def damage (find |(= "340" ($ :text)) segments))
        (assert damage)
        (assert (string/find "260 (rank 5)" (damage :calculation)))
        (assert (string/find "100 ability power" (damage :calculation)))
        (assert (string/find "0.8" (damage :calculation)))
        (def rendered (first (model/ability-settings {:abilities [q]} (context :stats) 18 {:q 5} context)))
        (assert (find |(= "340" ($ :text)) (mapcat identity ((details/ability rendered) :body-rich))))
        (assert (not (some |(get $ :calculation) (mapcat identity (tooltip/body "@TotalDamage@" (q :variables) (merge context {:rank 0}))))))
        (assert (= "@Unknown@" (get-in (tooltip/body "@Unknown@" (q :variables) context) [0 0 :text])))
        (def item (normalize/item-effects {:id "3089" :patch "16.18.1" :stats {} :limitations []}
                                          (util/read-json (slurp (string root "items.json")))
                                          (util/read-json (slurp (string root "strings.json")))))
        (assert (find |(and (= "30" ($ :text)) ($ :calculation))
                      (mapcat identity (tooltip/body (item :tooltip) (item :effect-variables) (merge context {:rank 1})))))))

(test "tooltip values use the selected build and rank at the start of combat"
      (fn []
        (defn value [input]
          (def result (model/compare (model/parse-state (merge {"champion" "Annie" "selected" "custom"} input))))
          (def ability (find |(= :q ($ :slot)) (get-in result [:selected :ability-settings])))
          ((find |($ :calculation) (mapcat identity ((details/ability ability) :body-rich))) :text))
        (assert (= "260" (value {})))
        (assert (= "276" (value {"slot1" "1052"})))
        (assert (= "80" (value {"level" "1"})))))

(test "item-picker tooltip requests preserve exact scenario identities and reject invalid inputs"
      (fn []
        (def result (model/compare (model/parse-state {"champion" "Annie" "selected" "custom"})))
        (def document (wire/encode (get-in result [:selected :combat :scenario])))
        (def request {:method "POST" :route "/details/item" :query {"id" "3089"}
                      :headers {"content-length" (string (length document))} :body document})
        (def response (server/app request))
        (assert (= 200 (response :status)))
        (assert (= "Rabadon's Deathcap" (get (util/read-json (response :body)) "name")))
        (assert (= 400 ((server/app (merge request {:query {"id" "missing"}})) :status)))
        (assert (= 400 ((server/app (merge request {:body "{}"})) :status)))
        (assert (= 400 ((server/app (merge request {:headers {"content-length" "65537"}})) :status)))
        (def envelope (util/read-json document))
        (put (envelope "scenario") "snapshot" (string/repeat "0" 64))
        (assert (= 400 ((server/app (merge request {:body (util/encode-json envelope)})) :status)))))

(test "optimization renders ten ranked rows with shared item details and no graphs"
      (fn []
        (def package (catalog/current))
        (def item (first (package :items)))
        (def rows (seq [index :range [0 10]]
                    {:key (string index) :ids [(item :id)] :cost (item :gold) :metrics {:damage (- 1000 index)}
                     :definition {:patch (package :patch) :snapshot (package :snapshot)} :samples 16 :uncertainty {} :coverage []}))
        (def text (ui/render (optimizer/panel {:package package} {:id "fixture" :status :done :result {:rows rows :preset :burst :notes []}})))
        (assert (= 10 (dec (length (string/split "role=\"listitem\"" text)))))
        (assert (string/find ">Build 10<" text))
        (assert (string/find "data-details=" text))
        (assert (string/find "data-detail-pin=\"true\"" text))
        (assert (not (string/find "<svg" text)))
        (assert (< (string/find ">Build 1<" text) (string/find ">Build 10<" text)))))

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
                           {"duration" 121} {"selected" "<script>"} {"champion" "<script>"}
                           {"slot1" "../../secret"} {"slot6" 3089} {"armor" -1}]
               (rejects (fn [] (model/parse-state fields))))))
(test "all frontend levels produce legal ranks and builds"
      (fn [] (loop [level :range [1 19]]
               (def result (model/compare (model/parse-state {"level" level})))
               (assert (= 4 (length (result :rows)))))))
(def w-order [:w :q :w :e :w :r :w :q :w :q :r :q :q :e :e :r :e :e])
(test "skill order determines unlocks and ranks at every selected level"
      (fn []
        (for level 1 19
          (def result (model/compare (model/parse-state {"level" level "skillorder" (map string w-order)})))
          (assert (= (table/to-struct (skills/ranks-from-order w-order level))
                     (table/to-struct (get-in result [:selected :ranks])))))
        (def result (model/compare (model/parse-state {"level" 1 "skillorder" (map string w-order) "priority" "q,w,e,r,d,f"})))
        (def text (ui/render (ui/ranks-fragment result)))
        (assert (string/find "data-ability-slot=\"w\"" text))
        (assert (string/find "data-unlocked=\"true\"" text))
        (assert (string/find "spell spell-locked" text))
        (assert (string/find "AnnieQ locked details" text))
        (assert (string/find "class=\"spell-key\"" text))
        (assert (string/find "class=\"spell-rank spell-rank-learned\"" text))
        (def locked (find |(= :q ($ :slot)) (get-in result [:selected :ability-settings])))
        (assert (nil? (locked :effective-cooldown)))
        (assert (= "Q · Locked (not learned)" ((details/ability locked) :subtitle)))
        (def events (get-in result [:selected :combat :events]))
        (assert (some |(= "AnnieW" ($ :source)) events))
        (assert (not (some |(= "AnnieQ" ($ :source)) events)))
        (def lowered (model/compare (model/parse-state {"level" 3 "skillorder" (map string w-order)})))
        (assert (= {:q 1 :w 2 :e 0 :r 0} (table/to-struct (get-in lowered [:selected :ranks]))))))
(test "both champions require skill orders independent of cast priority and retain manual ranks"
      (fn []
        (def state (model/parse-state {"mode" "duel" "level" 1 "priority" "q,w,e,r,d,f" "skillorder" (map string w-order)
                                       "opponentlevel" 1 "opponentpriority" "w,q,e,r,d,f" "opponentskillorder" "e"}))
        (def definition (model/definition state []))
        (def actors ((scenarios/compile definition) :actors))
        (assert (= 1 (get-in actors [0 :ranks :w])))
        (assert (= 1 (get-in actors [1 :ranks :e])))
        (def locked (merge state {:wrank 0}))
        (assert (= 0 (get-in (scenarios/compile (model/definition locked [])) [:actors 0 :ranks :w])))
        (def missing-player (merge (definition :player)))
        (put missing-player :skill-order nil)
        (def missing (merge definition {:player missing-player}))
        (rejects (fn [] (scenarios/compile missing)))
        (each fields [{"skillorder" ""} {"opponentskillorder" ""} {"skillorder" "q,q"}
                      {"skillorder" "d"} {"skillorder" "r"}]
          (rejects (fn [] (model/parse-state fields))))
        (rejects (fn [] (model/compare (model/parse-state {"level" 2 "skillorder" "q"}))))
        (def restored (model/state-from-definition definition))
        (def signaled (model/parse-state (util/read-json (util/encode-json (ui/signals restored)))))
        (assert (= w-order (tuple ;(signaled :skillorder))))
        (assert (= [:e] (tuple ;(signaled :opponentskillorder))))
        (assert (= -1 (signaled :wrank)))
        (def raised (merge signaled {:level 3}))
        (assert (= 2 (get-in (scenarios/compile (model/definition raised [])) [:actors 0 :ranks :w])))
        (def text (ui/render (ui/tactics (model/compare state))))
        (assert (string/find "name=\"skillorder\"" text))
        (assert (string/find "name=\"opponentskillorder\"" text))
        (assert (string/find "Annie skill order" text))))
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
        (assert (string/find "class=\"spell-ranks\"" (ui/render (ui/ranks-fragment result))))))

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
        (assert (string/find "Edit slot 1: empty" (ui/render (ui/loadout result))))))
(test "excluded on-hit effects and other-mode inventory restrictions remain visible"
      (fn [] (def result (model/compare (model/parse-state {"champion" "Jhin" "slot1" "6672" "slot2" "222051"})))
        (def text (ui/render (ui/results result) (ui/coverage result)))
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

(test "downloaded ability descriptions do not count as supported spell damage"
      (fn []
        (def result (model/compare (model/parse-state {"champion" "Ahri" "selected" "custom"})))
        (def row (merge (result :selected)
                        {:ability-settings [{:slot :q :name "Orb" :effects [{:kind :damage :status :unresolved}]}]}))
        (def text (ui/render (ui/results (merge result {:selected row}))))
        (assert (string/find "No supported spell damage for Ahri" text))
        (assert (not (string/find "Modeled abilities + attacks" text)))))

(test "recommendations display the gold limit captured when the search started"
      (fn []
        (def result (model/context (model/parse-state {})))
        (def job {:id "fixture" :status :done :gold-budget 2000 :next-purchase false
                  :result {:rows [] :notes []}})
        (assert (string/find "Gold limit: 2000" (ui/render (optimizer/panel result job))))
        (assert (string/find "Available gold: 2000" (ui/render (optimizer/panel result (merge job {:next-purchase true})))))))

(test "initial champion spell download explains the temporary estimate and preserves settings on upgrade"
      (fn []
        (def result (model/compare (model/parse-state {"champion" "Ahri" "selected" "custom"})))
        (def pending {:id "fixture" :key "16.19.1" :status :running
                      :progress {:message "Downloading Ahri" :completed 1 :total 173}})
        (def text (ui/render (ui/results (merge result {:spell-data-job pending}))))
        (assert (string/find "Downloading ability data for Ahri" text))
        (assert (not (string/find "Spells: not modeled" text)))
        (def failed (ui/render (ui/results (merge result {:spell-data-job (merge pending {:status :failed})}))))
        (assert (string/find "Ability data download failed for Ahri" failed))
        (def cancelled (ui/render (ui/results (merge result {:spell-data-job (merge pending {:status :cancelled})}))))
        (assert (string/find "Ability data download cancelled for Ahri" cancelled))
        (def done (merge pending {:status :done :result {:patch "16.19.1" :snapshot (string/repeat "a" 64)}}))
        (def panel (ui/render (ui/patch-panel result done)))
        (assert (string/find "new FormData(form)" panel))
        (assert (string/find "field.type === &#x27;checkbox&#x27;" panel))
        (assert (string/find "slot.dataset.itemId" panel))
        (assert (string/find "selected&#x27;, $selected" panel))
        (assert (string/find "data-item-id=\"3089\"" (ui/render (ui/loadout (model/compare model/default-state)))))
        (assert (string/find (string/repeat "a" 64) panel))))

(test "frontend duels use two acting participants and report sampled health outcomes"
      (fn [] (def result (model/compare (model/parse-state {"mode" "duel" "champion" "Annie" "opponent" "Garen"
                                                            "level" 6 "opponentlevel" 6 "duration" 8 "samples" 3 "selected" "custom"})))
        (def combat (get-in result [:selected :combat]))
        (assert (= 3 (combat :samples)))
        (assert (> (get-in combat [:metrics :damage-taken]) 0))
        (assert (> (length (combat :trace)) 0))
        (assert (combat :scenario-id))
        (assert (not (empty? (combat :uncertainty))))))

(test "rank locks, activation thresholds and opponent inventories affect one shared simulation"
      (fn []
        (def disabled (model/compare (model/parse-state {"selected" "custom" "qrank" 0 "wrank" 0 "erank" 0 "rrank" 0})))
        (assert (= 0 (get-in disabled [:selected :combat :ability-dps])))
        (def delayed (model/compare (model/parse-state {"selected" "custom" "qafter" 2})))
        (assert (not (some |(and (= "AnnieQ" ($ :source)) (< ($ :at) 2)) (get-in delayed [:selected :combat :trace]))))
        (def state (model/parse-state {"mode" "duel" "enemyslot2" "3089" "qrank" 0 "hitchance" 0.5 "healthfraction" 0.7}))
        (def roundtrip (model/parse-state (util/read-json (util/encode-json (ui/signals state)))))
        (assert (= 0.5 (roundtrip :hit-chance)))
        (assert (= 0.7 (roundtrip :health-fraction)))
        (assert (= ["3089"] (tuple ;(roundtrip :opponentitems))))
        (rejects (fn [] (model/compare (model/parse-state {"level" 1 "qrank" 5}))))))

(test "loadout tray promotes core inputs and keeps the full scenario form associated"
      (fn [] (def result (model/compare model/default-state))
        (def primary (ui/render (ui/loadout result)))
        (each marker ["id=\"loadout-tray\"" "Optimize build" "Ability power" "Six editable inventory slots"]
          (assert (string/find marker primary)))
        (assert (not (string/find "Combat window" primary)))
        (assert (not (string/find "searchbudget" primary)))
        (assert (not (string/find "Remaining" primary)))
        (assert (string/find "Search gold budget" (ui/render (optimizer/controls result))))
        (def secondary (ui/render (ui/fight-controls result)))
        (each marker ["Opponent &amp; fight" "form=\"scenario\"" "name=\"duration\"" "data-preserve-attr=\"open\""]
          (assert (string/find marker secondary)))))
(test "game-style details retain safe text and explicit unresolved coverage"
      (fn [] (def result (model/compare model/default-state))
        (def payload (details/item (catalog/items "3089")))
        (assert (= "Rabadon's Deathcap" (payload :name)))
        (assert (string/find "handler" (payload :coverage)))
        (def text (ui/render [:button (details/attrs (merge payload {:body ["<script>alert(1)</script>"]}) true) "Details"]))
        (assert (string/find "data-details=" text))
        (assert (not (string/find "<script>" text)))
        (assert (string/find "data-trace=" (ui/render (ui/results result))))))
(test "rune art uses only the selected package's supported image reference"
      (fn [] (defn package [path] {:runes [{"slots" [{"runes" [{"id" 8112 "icon" path}]}]}]})
        (assert (= "https://ddragon.leagueoflegends.com/cdn/img/perk-images/Styles/Domination/Electrocute/Electrocute.png"
                   (details/rune-source (package "perk-images/Styles/Domination/Electrocute/Electrocute.png") "8112.png")))
        (each path ["https://example.com/x.png" "perk-images/../secret.png" "perk-images/%2e%2e/secret.png" "perk-images/x.svg"]
          (rejects (fn [] (details/rune-source (package path) "8112.png"))))
        (rejects (fn [] (details/rune-source (package "perk-images/x.png") "9999.png")))))

(print passed " frontend tests passed")
