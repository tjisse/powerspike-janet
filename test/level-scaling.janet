(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/tooltip :as parser)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/scenario :as scenario)
(import ../src/powerspike/data-util :as util)
(import ../web/tooltip :as tooltip)
(import pshash :as hash)

(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.000001) (string "Expected " expected ", got " actual)))
(defn rejects [f] (assert (not (first (protect (f))))))
(defn context [level] {:level level :rank 1 :stats {} :base {} :buffs {}})
# Independent sum of each level-up increment, rather than the implementation's
# closed-form growth factor. Endpoints are retained game data, not fitted values.
(defn reference [start end level]
  (+ start (* (/ (- end start) 17) (sum (seq [n :range [2 (inc level)]] (+ 0.65 (* 0.035 n)))))))
(def root "data/form-fixtures/16.19.1/")
(def manifest (util/read-json (slurp (string root "gnar-manifest.json"))))
(def bytes (slurp (string root "Gnar-characters.json")))
(assert (= (get-in manifest ["fixture_sha256" "Gnar-characters.json"]) (hash/sha256 bytes)))
(def source (get-in (util/read-json bytes) ["Characters/Gnar/Spells/GnarPassiveAbility/GnarPassive" "mSpell"]))
(assert (= "{7fe8e3b3}" (expr/fnv "mScaleByStatProgressionMultiplier")))
(def names ["TotalAS" "TotalMegaGnarArmor" "TotalMegaGnarMR" "TotalMegaGnarAD"])
(each name names
  (def calculation (get-in source ["mSpellCalculations" name]))
  (def part (get-in calculation ["mFormulaParts" 0]))
  (assert (= true (get part "mScaleByStatProgressionMultiplier")))
  (def start (part "mStartValue"))
  (def end (part "mEndValue"))
  (def hashed (merge (tabseq [[key value] :pairs part :when (not= key "mScaleByStatProgressionMultiplier")] key value)
                     {"{7fe8e3b3}" true}))
  (loop [level :range [1 19]]
    (def expected (reference start end level))
    (close expected (expr/evaluate (expr/variable name source) (context level)))
    (close expected (expr/evaluate (expr/compile-part hashed source) (context level)))
    (close expected (expr/evaluate (expr/compile-part (merge hashed {"mScaleByStatProgressionMultiplier" true}) source) (context level)))))

# The real passive's localized tooltip uses these expressions too. Resolving
# numbers supplies no activation handler and must not enable passive casts.
(def actual-kit (normalize/kit "Gnar" (util/read-json bytes) {}
                               ((util/read-json (slurp (string root "Gnar-strings.json"))) "entries") "16.19.1"))
(def passive (find |(= :p ($ :slot)) (actual-kit :abilities)))
(each effect (passive :effects)
  (assert (= :unresolved (effect :trigger)))
  (assert (= :unresolved (effect :status))))
(each name names
  (def variable (find |(= name ($ :name)) (passive :variables)))
  (assert variable)
  (loop [level :range [1 19]]
    (def value (expr/evaluate (expr/variable name source) (context level)))
    (close value (expr/evaluate (variable :expression) (context level)))
    (assert (some |(= (tooltip/number value) ($ :text))
                  (mapcat identity (tooltip/body (passive :tooltip) (passive :variables) (context level)))))))

(def part {"__type" "ByCharLevelInterpolationCalculationPart" "mStartValue" 6 "mEndValue" 48.5})
(each flags [{} {"mScaleByStatProgressionMultiplier" false} {"{7fe8e3b3}" false}
             {"mScaleByStatProgressionMultiplier" false "{7fe8e3b3}" false}]
  (loop [level :range [1 19]]
    (close (+ 6 (* 2.5 (dec level))) (expr/evaluate (expr/compile-part (merge part flags) {}) (context level)))))
(each flags [{"mScaleByStatProgressionMultiplier" "false"} {"{7fe8e3b3}" 0}
             {"{7fe8e3b3}" []}
             {"mScaleByStatProgressionMultiplier" true "{7fe8e3b3}" false}
             {"mScaleByStatProgressionMultiplier" false "{7fe8e3b3}" true}
             {"mStartValue" math/inf} {"mEndValue" "48.5"}]
  (def expression (expr/compile-part (merge part flags) {}))
  (assert (not (empty? (expr/problems expression))))
  (rejects (fn [] (expr/evaluate expression (context 9)))))
(each flag [false true]
  (def expression (expr/compile-part (merge part {"mScaleByStatProgressionMultiplier" flag}) {}))
  (each level [nil 0 19 -1 1.5 "9" math/inf]
    (rejects (fn [] (expr/evaluate expression (context level))))))
(close 6 (expr/evaluate (expr/compile-part {"__type" "ByCharLevelInterpolationCalculationPart" "mEndValue" 6} {}) (context 18)))

# A synthetic carrier checks the actual display, damage and optimizer paths.
# It does not turn Gnar's stat bonus into a cast or claim new champion coverage.
(def spell {"mSpellCalculations" {"Amount" (get-in source ["mSpellCalculations" "TotalMegaGnarAD"])}
            "__powerspike_patch" "16.19.1"})
(def text "Deals <trueDamage>@Amount@ true damage</trueDamage>.")
(def parsed (parser/parse text spell))
(def legacy-expression (expr/variable "Amount" spell nil true))
(defn old-parsed [record]
  (merge (tabseq [[key value] :pairs record :when (not= key :expression-parser)] key value)
         {:variables [{:name "Amount" :expression legacy-expression}]
          :effects (map |(merge $ {:amount legacy-expression}) (record :effects))}))
(def old (old-parsed parsed))
(def repaired (expr/refresh old spell))
(assert (= (util/canonical repaired) (util/canonical (expr/refresh repaired spell))))
(assert (= legacy-expression (get-in old [:variables 0 :expression])))
(loop [level :range [1 19]]
  (def expected (reference 6 48.5 level))
  (close expected (expr/evaluate (get-in repaired [:effects 0 :amount]) (context level)))
  (def segments (mapcat identity (tooltip/body text (repaired :variables) (context level))))
  (assert (some |(= (tooltip/number expected) ($ :text)) segments))
  (assert (some |(string/find "scales with level like champion stats" (get $ :calculation "")) segments)))
(close 25.35 (expr/evaluate (expr/variable "Amount" spell) (context 10)))
(close 28.5 (expr/evaluate legacy-expression (context 10)))
# Variables inside products, durations, costs, recasts and charge counts all
# receive the same repair. Existing unresolved triggers remain unresolved.
(def nested (expr/refresh (merge old {:cost {:op :multiply :children [legacy-expression {:op :constant :value 0.5}]}
                                      :recast {:window legacy-expression} :cast-lock legacy-expression}) spell))
(close 12.675 (expr/evaluate (nested :cost) (context 10)))
(close 25.35 (expr/evaluate (get-in nested [:recast :window]) (context 10)))
(def unresolved (expr/refresh (merge old {:effects [{:amount legacy-expression :status :unresolved :trigger :unresolved}]}) spell))
(assert (= :unresolved (get-in unresolved [:effects 0 :status])))
(assert (= :unresolved (get-in unresolved [:effects 0 :trigger])))
# The old compiler rejected hashed flags. The whole calculation must be
# recompiled; treating every unknown node as the same formula is unsafe.
(def hashed-spell {"mSpellCalculations" {"Amount" {"__type" "GameCalculation"
                                                   "mFormulaParts" [(merge part {"{7fe8e3b3}" true})]}}})
(def hashed-old {:variables [{:name "Amount" :expression (expr/variable "Amount" hashed-spell nil true)}]})
(close 25.35 (expr/evaluate (get-in (expr/refresh hashed-old hashed-spell) [:variables 0 :expression]) (context 10)))
# Two legacy ASTs can be identical even though their source curves differ.
# Their missing provenance cannot be guessed; a fresh fetch resolves it.
(def ambiguous-spell {"mSpellCalculations" {"Amount" (merge part {"mScaleByStatProgressionMultiplier" true}) "Linear" part}})
(def ambiguous {:variables [{:name "Amount" :expression (expr/variable "Amount" ambiguous-spell nil true)}]})
(rejects (fn [] (expr/evaluate (get-in (expr/refresh ambiguous ambiguous-spell) [:variables 0 :expression]) (context 10))))
# Parser 6 already preserved interpolation flags. A later parser version must
# not rerun the lossy parser-5 repair against its correctly compiled linear AST.
(def current-linear {:expression-parser "6" :variables [{:name "Linear" :expression (expr/variable "Linear" ambiguous-spell)}]})
(close 28.5 (expr/evaluate (get-in (expr/refresh current-linear ambiguous-spell) [:variables 0 :expression]) (context 10)))

# Exercise each cached record adapter and preserve the snapshot's actual bytes.
(def catalog (util/read-data "data/16.19.1/catalog/catalog.jdn"))
(def annie (find |(= "Annie" ($ :id)) (catalog :champions)))
(def ability (merge old {:slot :q :id "ScalingFixture" :record spell :available true :max-rank 5
                         :cooldown {:op :constant :value 99} :cost {:op :constant :value 0}
                         :range {:op :constant :value 600} :cast-time 0 :missile-speed 0}))
(def item {:id "fixture" :patch "16.19.1" :record {"mItemCalculations" (spell "mSpellCalculations")}
           :effect-variables (old :variables) :effects (old :effects)})
(def rune {"id" 999 :record {"mScript" {"mSpellScriptData" {"mCalculations" (spell "mSpellCalculations")}}} :parsed old})
(def summoner {:record spell :parsed old})
(def package-bytes (util/encode-data {:schema 1 :parser "5" :patch "16.19.1"
                                      :champions [(merge annie {:abilities [ability]})] :items [item]
                                      :runes [{"slots" [{"runes" [rune]}]}] :summoners [summoner]}))
(def snapshot (hash/sha256 package-bytes))
(def scratch (string "build/level-scaling-tests/" (hash/sha256 (os/cryptorand 8))))
(def directory (string scratch "/patches/16.19.1/" snapshot))
(util/write (string directory "/package.jdn") package-bytes)
(util/write (string directory "/manifest.json") (util/encode-json {"initial" false "package_sha256" snapshot}))
(util/write (string scratch "/patches/16.19.1/current") snapshot)
(def package (packages/initialize scratch nil))
(each path [[:champions 0 :abilities 0 :variables 0 :expression]
            [:items 0 :effect-variables 0 :expression] [:item-map "fixture" :effect-variables 0 :expression]
            [:runes 0 "slots" 0 "runes" 0 :parsed :variables 0 :expression]
            [:summoners 0 :parsed :variables 0 :expression]]
  (close 25.35 (expr/evaluate (get-in package path) (context 10))))
(def order [:q :w :e :q :q :r :q :w :q :w :r :w :w :e :e :r :e :e])
(loop [level :range [1 19]]
  (def definition {:schema 1 :patch "16.19.1" :snapshot snapshot :duration 0.5 :distance 0 :seed 1
                   :player {:champion "Annie" :level level :skill-order order :loadout {:items []}
                            :strategy {:attacks false :abilities true :movement :hold}}
                   :target {:kind :practice :hp 1000 :armor 0 :mr 0}})
  (def outcome (scenario/simulate definition))
  (close (reference 6 48.5 level) (outcome :damage))
  (assert (= (outcome :metrics) ((scenario/fitness definition) :metrics)))
  (def reversed (merge definition {:player (merge (definition :player) {:strategy {:attacks false :abilities false :movement :hold}})
                                   :target (merge (definition :player) {:kind :champion})}))
  (def incoming (scenario/simulate reversed))
  (close (reference 6 48.5 level) (get-in incoming [:actors 1 :damage-dealt]))
  (assert (= (incoming :metrics) ((scenario/fitness reversed) :metrics))))
(when-let [export (os/getenv "PS_LEVEL_SCALING_FIXTURE")]
  (when (os/stat export) (util/remove-tree export))
  (util/copy-tree (string scratch "/patches") (string export "/seed"))
  (def definition {:schema 1 :patch "16.19.1" :snapshot snapshot :duration 0.5 :distance 0 :seed 1
                   :player {:champion "Annie" :level 10 :skill-order order :loadout {:items []}
                            :strategy {:attacks false :abilities true :movement :hold}}
                   :target {:kind :practice :hp 1000 :armor 0 :mr 0}})
  (util/write (string export "/scenario.json")
              (util/encode-json {:format "powerspike-scenario" :version 1 :scenario ((scenario/compile definition) :definition)})))
(assert (= snapshot (hash/sha256 (slurp (string directory "/package.jdn")))))
(util/remove-tree scratch)
(print "Source-backed nonlinear interpolation, aliases, all 18 levels, invalid inputs, tooltips, immutable cached adapters, combat and optimizer parity passed.")
