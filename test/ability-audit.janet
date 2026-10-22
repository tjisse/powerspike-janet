(import ../scripts/lib/ability-audit :as audit)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn read [path] (util/read-json (slurp path)))
(defn verified [root]
  (def manifest (read (string root "manifest.json")))
  (eachp [file expected] (manifest "fixture_sha256")
    (assert (= expected (hash/sha256 (slurp (string root file)))) "Ability audit source corruption.")))
(verified "data/ability-fixtures/16.21.1/")
(verified "data/parser-fixtures/16.21.1/")
(def champions
  (map (fn [[id root]]
         (def kit (normalize/kit id (read (string root id "-characters.json"))
                                 (read (string root id "-abilities.json"))
                                 ((read (string root "strings.json")) "entries") "16.21.1"))
         (merge kit {:id id}))
       [["Seraphine" "data/ability-fixtures/16.21.1/"] ["Garen" "data/parser-fixtures/16.21.1/"]
        ["Fiddlesticks" "data/ability-fixtures/16.21.1/"]]))
(def package {:patch "16.21.1" :parser "7" :snapshot "retained-ability-audit" :champions champions :manifest {"initial" false}})
(def before (util/encode-data package))
(def report (audit/run package))
(assert (= 3 (report :champions)))
(assert (= 12 (length (report :abilities))))
(assert (= 12 (sum (values (report :summary)))))
(defn row [id slot]
  (find |(and (= id ($ :champion)) (= slot ($ :slot))) (report :abilities)))
(each slot [:w :e]
  (assert (= :executes ((row "Seraphine" slot) :status)))
  (assert (> ((row "Seraphine" slot) :effect-count) 0)))
(each slot [:e :r] (assert (= :executes ((row "Garen" slot) :status))))
(assert (= :executes ((row "Fiddlesticks" :e) :status)))
(each slot [:q :w :r]
  (assert (= :no-executable-effect ((row "Fiddlesticks" slot) :status))))
(def objects (read "data/ability-fixtures/16.21.1/Fiddlesticks-characters.json"))
(def detail (read "data/ability-fixtures/16.21.1/Fiddlesticks-abilities.json"))
(def expected "Characters/FiddleSticks/CharacterRecords/Root")
(assert (= expected (normalize/character-root-path "Fiddlesticks" objects)))
(def normalized (normalize/champion "16.21.1" (get-in detail ["data" "Fiddlesticks"]) objects))
(assert (= expected (normalized :root)))
(assert (some |(= "FiddleSticksE" ($ :id)) (get-in (find |(= "Fiddlesticks" ($ :id)) champions) [:abilities])))
(assert (all |(not (empty? ($ :record))) ((find |(= "Fiddlesticks" ($ :id)) champions) :abilities)))
(def reap (find |(= :e ($ :slot)) ((find |(= "Fiddlesticks" ($ :id)) champions) :abilities)))
(def damage (find |(and (= :damage ($ :kind)) (= :estimated ($ :status))) (reap :effects)))
(each [rank expected] [[1 120] [5 260]]
  (assert (< (math/abs (- expected (expr/evaluate (damage :amount) {:rank rank :stats {:ap 100}}))) 0.0001)))
(assert (not (first (protect (normalize/character-root-path "Fiddlesticks"
                                                            {"Characters/fiddlesticks/CharacterRecords/Root" {} "Characters/FIDDLESTICKS/CharacterRecords/Root" {}})))))
(assert (= before (util/encode-data package)) "A developer audit must not mutate the input snapshot.")

# Distinguish compilation omissions, activation guards, runtime exclusions and
# actual applied effects; the presence of a cast alone is insufficient.
(def base {:id "synthetic" :name "Synthetic" :slot :q :max-rank 1 :cast-time 0 :cost 0 :range 200 :cooldown 99
           :effects [{:kind :damage :status :estimated :target :enemy :amount 10 :damage-type :magic}] :unresolved []})
(assert (= :executes ((audit/inspect "Synthetic" base) :status)))
(assert (= :no-executable-effect ((audit/inspect "Synthetic" (merge base {:effects []})) :status)))
(def blocked (audit/inspect "Synthetic" (merge base {:cooldown 0})))
(assert (= :not-cast (blocked :status)))
(assert (some |(string/find "Zero-cooldown activation" $) (blocked :runtime)))
(def no-effect (audit/inspect "Synthetic" (merge base {:effects [{:kind :shield :status :estimated :target :self :amount 10}]})))
(assert (= :cast-without-effect (no-effect :status)))
(assert (> (no-effect :cast-count) 0))
(assert (= 0 (no-effect :effect-count)))
(def parry (audit/inspect "Synthetic" (merge base {:effects [{:kind :parry :status :estimated :target :self :duration 0.75 :source-kinds [:champion]}]})))
(assert (= :executes (parry :status)))
(def missing (audit/run (merge package {:champions [{:id "Empty" :abilities []}]})))
(assert (= 4 (get-in missing [:summary :missing-definition])))
(def baseline (read "docs/audits/ability-coverage-16.21.1.json"))
(assert (= 173 (baseline "champions")))
(assert (= (* 4 (baseline "champions")) (length (baseline "abilities"))))
(assert (= (length (baseline "abilities")) (sum (values (baseline "summary")))))
(print "Ability audit: reported Seraphine W/E and reviewed Garen E/R execution, applied-effect checks, activation/runtime omissions, parry, missing definitions, complete inventory and immutable inputs passed.")
