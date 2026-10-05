(import ./data-util :as util)

# ASTs contain numbers and data references only; no Janet source is evaluated.
(def stat-ids {0 :ap 1 :armor 2 :ad 4 :attack-speed 6 :mr 7 :move-speed 8 :crit-chance
               9 :crit-damage 11 :ability-haste 12 :hp 13 :health 14 :health-percent
               15 :missing-health 16 :missing-health-percent 29 :armor-pen-flat 31 :attack-range})
(defn unresolved [reason] {:op :unresolved :reason reason})
(defn fnv [text]
  (var value 2166136261)
  (each byte (string/bytes (string/ascii-lower text))
    (def signed (bxor (if (>= value 2147483648) (- value 4294967296) value) byte))
    (def unsigned (if (< signed 0) (+ signed 4294967296) signed))
    # Split multiplication keeps all intermediate integers exact in doubles.
    (set value (% (+ (* unsigned 403) (* (% unsigned 256) 16777216)) 4294967296)))
  (string/format "{%08x}" value))
(defn lookup [dictionary name]
  (when (and (dictionary? dictionary) (string? name))
    (or (get dictionary name)
        (get dictionary (fnv name))
        (let [key (find |(= (string/ascii-lower $) (string/ascii-lower name)) (keys dictionary))]
          (when key (get dictionary key))))))
(defn ranked [values offset source]
  (if (and (indexed? values) (not (empty? values)) (not (some |(not (util/finite? $)) values)))
    {:op :rank :values values :offset offset :source source}
    (unresolved (string "Missing numeric rank values: " source))))
(defn named-values [spell]
  (tabseq [row :in (or (get spell "DataValues") (get spell "mDataValues") [])]
    (or (get row "name") (get row "mName") "")
    (or (get row "values") (get row "mValues")
        (when (number? (get row "mValue")) [(get row "mValue") (get row "mValue")]))))
(defn stat-node [part spell]
  (def id (get part "mStat" 0))
  (def formula (get part "mStatFormula" 0))
  (def patch (get spell "__powerspike_patch" "16.19.1"))
  (def family (some |(= $ (util/cdragon-version patch)) ["16.17" "16.18" "16.19"]))
  (if (and family (stat-ids id) (some |(= $ formula) [0 1 2]))
    {:op :stat :stat (stat-ids id) :formula formula}
    (unresolved (string "Unknown stat/formula mapping " id "/" formula " on " patch))))

(defn compile-part [part spell &opt depth trail]
  (def level (or depth 0))
  (def visited (or trail []))
  (cond
    (> level 32) (unresolved "Calculation nesting limit")
    (number? part) {:op :constant :value part}
    (not (dictionary? part)) (unresolved "Missing calculation part")
    (do
      (def type (get part "__type" ""))
      (defn child [node] (compile-part node spell (inc level) visited))
      (defn named [name] (ranked (lookup (named-values spell) name) 0 name))
      (case type
        "NumberCalculationPart" (child (get part "mNumber" 0))
        "NamedDataValueCalculationPart" (named (get part "mDataValue"))
        "EffectValueCalculationPart"
        (ranked (get-in spell ["mEffectAmount" (dec (get part "mEffectIndex" 0)) "value"]) 0 "effect array")
        "StatByCoefficientCalculationPart" {:op :multiply :children [(stat-node part spell) (child (get part "mCoefficient" 0))]}
        "StatByNamedDataValueCalculationPart" {:op :multiply :children [(stat-node part spell) (named (get part "mDataValue"))]}
        "StatBySubPartCalculationPart" {:op :multiply :children [(stat-node part spell) (child (get part "mSubpart"))]}
        "SumOfSubPartsCalculationPart"
        (if (and (indexed? (get part "mSubparts")) (<= 1 (length (part "mSubparts")) 128))
          {:op :sum :children (map child (part "mSubparts"))}
          (unresolved "Missing or excessive sum parts"))
        "ProductOfSubPartsCalculationPart" {:op :multiply :children [(child (get part "mPart1")) (child (get part "mPart2"))]}
        "GameCalculation"
        (if (and (indexed? (get part "mFormulaParts")) (<= 1 (length (part "mFormulaParts")) 128))
          {:op :multiply :children [{:op :sum :children (map child (part "mFormulaParts"))}
                                    (child (get part "mMultiplier" 1))]}
          (unresolved "Missing or excessive formula parts"))
        "GameCalculationModified"
        (let [name (get part "mModifiedGameCalculation")]
          (if (some |(= $ name) visited) (unresolved "Recursive calculation reference")
            {:op :with-rank :rank (get part "mOverrideSpellLevel")
             :children [{:op :multiply :children [(compile-part (lookup (get spell "mSpellCalculations" {}) name)
                                                                spell (inc level) [;visited name])
                                                  (child (get part "mMultiplier" 1))]}]}))
        "GameCalculationConditional"
        (let [requirement (get part "mConditionalCalculationRequirements")
              yes (get part "mConditionalGameCalculation") no (get part "mDefaultGameCalculation")]
          (if (and (= "HasBuffCastRequirement" (get requirement "__type"))
                   (not (some |(some (fn [name] (= $ name)) visited) [yes no])))
            {:op :conditional :buff (get requirement "mBuffName") :invert (get requirement "mInvertResult" false)
             :children [(compile-part (lookup (get spell "mSpellCalculations" {}) yes) spell (inc level) [;visited yes])
                        (compile-part (lookup (get spell "mSpellCalculations" {}) no) spell (inc level) [;visited no])]}
            (unresolved "Conditional calculation requires an explicit supported branch predicate")))
        "ByCharLevelBreakpointsCalculationPart"
        (let [points (get part "mBreakpoints" [])]
          {:op :level-values :values
           (seq [level :range [0 19]]
             (var result (get part "mLevel1Value" 0))
             (var scale (get part "mInitialBonusPerLevel" (get part "{02deb550}" 0)))
             (var previous 1)
             (each point points
               (when (<= (get point "mLevel" 100) level)
                 (+= result (* (- (dec (point "mLevel")) previous) scale))
                 (+= result (get point "mAdditionalBonusAtThisLevel" (get point "{d5fd07ed}" 0)))
                 (set previous (dec (point "mLevel")))
                 (set scale (get point "mBonusPerLevelAtAndAfter" (get point "{57fdc438}" 0)))))
             (+ result (* (max 0 (- level previous)) scale)))})
        "ByCharLevelInterpolationCalculationPart"
        (if (get part "{7fe8e3b3}") (unresolved "Nonlinear character-level interpolation")
          {:op :level-interpolation :start (get part "mStartValue" 0) :end (get part "mEndValue" 0)})
        "ByCharLevelFormulaCalculationPart" {:op :level-values :values (get part "mValues" [])}
        "BuffCounterByCoefficientCalculationPart"
        {:op :multiply :children [{:op :buff-count :name (get part "mBuffName")} (child (get part "mCoefficient" 0))]}
        "BuffCounterByNamedDataValueCalculationPart"
        {:op :multiply :children [{:op :buff-count :name (get part "mBuffName")} (named (get part "mDataValue"))]}
        "AbilityResourceByCoefficientCalculationPart"
        (if (= 0 (get part "mAbilityResource" 0))
          {:op :multiply :children [{:op :stat :stat :mp :formula (get part "mStatFormula" 0)} (child (get part "mCoefficient" 0))]}
          (unresolved "Unmodeled ability-resource kind"))
        (unresolved (string "Unsupported calculation: " type))))))

(defn variable [name spell &opt dd]
  (def parts (string/split "*" (string/trim name)))
  (def key (string/trim (parts 0)))
  (def calculations (get spell "mSpellCalculations" {}))
  (def calculation (lookup calculations key))
  (def values (lookup (named-values spell) key))
  (def legacy (peg/match ~(* (+ "e" "Effect") '(some (range "09")) (? "Amount") -1) key))
  (def expression
    (cond calculation (compile-part calculation spell 0 [key])
      values (ranked values 0 key)
      legacy (let [index (scan-number (legacy 0))]
               (if (string/has-prefix? "e" key)
                 (let [values (get-in dd ["effect" index])]
                   (if (and (indexed? values) (not (empty? values)) (not (some |(not= $ 0) values)))
                     (unresolved (string "Unresolved placeholder effect array: " key))
                     (ranked values -1 key)))
                 (ranked (get-in spell ["mEffectAmount" (dec index) "value"]) 0 key)))
      (unresolved (string "Unresolved tooltip variable: " key))))
  (if (= 1 (length parts)) expression
    (let [scale (and (= 2 (length parts)) (scan-number (parts 1)))]
      (if (util/finite? scale) {:op :multiply :children [expression {:op :constant :value scale}]}
        (unresolved (string "Unsupported tooltip expression: " name))))))

(defn evaluate [expression context &opt depth]
  (def nesting (or depth 0))
  (assert (< nesting 40) "Expression recursion limit")
  (defn next [node] (evaluate node context (inc nesting)))
  (def value
    (case (expression :op)
      :constant (expression :value)
      :rank (let [rank (get context :rank 0) index (+ rank (expression :offset))]
              (assert (> rank 0) "Unlearned ability")
              (assert (<= 0 index (dec (length (expression :values)))) "Rank data unavailable")
              ((expression :values) index))
      :stat (let [stat (expression :stat) formula (expression :formula)
                  total (get (context :stats) stat) base (get (context :base) stat)]
              (case formula 0 (do (assert (number? total) (string "Missing stat " stat)) total)
                1 (do (assert (number? base) (string "Missing base stat " stat)) base)
                2 (if (and (= stat :attack-speed) (has-key? (context :stats) :attack-speed-bonus))
                    ((context :stats) :attack-speed-bonus)
                    (do (assert (and (number? total) (number? base)) (string "Missing bonus stat " stat)) (- total base)))
                (error "Unsupported stat formula")))
      :sum (sum (map next (expression :children)))
      :multiply (product (map next (expression :children)))
      :with-rank (evaluate ((expression :children) 0) (merge context (if (number? (expression :rank)) {:rank (expression :rank)} {})) (inc nesting))
      :conditional (do (assert (dictionary? (context :buffs)) "Conditional buff state unavailable")
                     (def active (> (get (context :buffs) (expression :buff) 0) 0))
                     (next ((expression :children) (if (not= active (expression :invert)) 0 1))))
      :level-interpolation (+ (expression :start) (* (/ (dec (context :level)) 17) (- (expression :end) (expression :start))))
      :level-values (do (assert (< (context :level) (length (expression :values))) "Missing level value")
                      ((expression :values) (context :level)))
      :buff-count (do (assert (dictionary? (context :buffs)) "Buff state unavailable") (get (context :buffs) (expression :name) 0))
      :target-stat (do (assert (number? (get (context :target) (expression :stat))) "Target stat unavailable")
                     ((context :target) (expression :stat)))
      :unresolved (error (expression :reason))
      (error "Unknown expression operation")))
  (assert (util/finite? value) "Non-finite expression result")
  value)
(defn problems [expression]
  (if (= :unresolved (expression :op)) [(expression :reason)]
    (mapcat problems (get expression :children []))))
