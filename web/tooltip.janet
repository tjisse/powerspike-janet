(import ../src/powerspike/expressions :as expr)
(import ../src/powerspike/tooltip :as parser)
(import ../src/powerspike/normalize :as normalize)

# Presentation uses the same expression evaluator as combat. Only text and
# structured segments cross into the browser; provider HTML is never rendered.
(defn number [value]
  (var text (string/format "%.4f" value))
  (while (string/has-suffix? "0" text) (set text (string/slice text 0 (dec (length text)))))
  (if (string/has-suffix? "." text) (string/slice text 0 (dec (length text))) text))
(def labels {:ap "ability power" :ad "attack damage" :hp "maximum health" :health "current health"
             :mp "maximum mana" :armor "armor" :mr "magic resist" :attack-speed "attack speed"
             :attack-speed-bonus "bonus attack speed" :move-speed "movement speed"
             :crit-chance "critical strike chance" :crit-damage "critical damage" :ability-haste "ability haste"
             :health-percent "health fraction" :missing-health "missing health" :missing-health-percent "missing health fraction"
             :armor-pen-flat "lethality" :attack-range "attack range"})
(defn formula [expression context &opt depth]
  (def nesting (or depth 0))
  (assert (< nesting 40) "Expression explanation limit")
  (defn child [node] (formula node context (inc nesting)))
  (def value (number (expr/evaluate expression context)))
  (case (expression :op)
    :constant value
    :rank (if (context :hide-rank) value (string value " (rank " (context :rank) ")"))
    :stat (string value " " (case (expression :formula) 1 "base " 2 "bonus " "")
                  (get labels (expression :stat) (string (expression :stat))))
    :target-stat (string value " target " (get labels (expression :stat) (string (expression :stat))))
    :sum (string "(" (string/join (map child (expression :children)) " + ") ")")
    :multiply (let [parts (filter |(not (and (= :constant ($ :op)) (= 1 ($ :value)))) (expression :children))]
                (case (length parts)
                  0 value
                  1 (child (parts 0))
                  (string "(" (string/join (map child parts) " × ") ")")))
    :with-rank (formula ((expression :children) 0) (merge context (if (number? (expression :rank)) {:rank (expression :rank)} {})) (inc nesting))
    :level-interpolation (string (number (expression :start)) " + (level " (context :level) " − 1) / 17 × ("
                                 (number (expression :end)) " − " (number (expression :start)) ")")
    :level-values (string value " (level " (context :level) ")")
    :buff-count (string value " stacks of " (expression :name))
    :conditional (do
                   (def active (> (get (context :buffs) (expression :buff) 0) 0))
                   (string (child ((expression :children) (if (not= active (expression :invert)) 0 1)))
                           " (" (expression :buff) (if active " active" " inactive") ")"))
    (error "Unsupported tooltip explanation")))
(defn lines [description]
  (var text (or description ""))
  (each tag ["<br>" "<br/>" "<br />" "</p>"] (set text (string/replace-all tag "\n" text)))
  (take 20 (filter |(not= "" $) (map string/trim (string/split "\n" (normalize/plain text))))))
(defn body [description variables context]
  (map (fn [line]
         (def segments @[])
         (var offset 0)
         (each token (parser/tokens line)
           (when (> (token :start) offset) (array/push segments {:text (string/slice line offset (token :start))}))
           (def variable (find |(= ($ :name) (token :name)) (or variables [])))
           (def result (when (and context variable)
                         (protect
                           (def expression (variable :expression))
                           (def value (expr/evaluate expression context))
                           (def shown (string (number value) (get variable :suffix "")))
                           {:text shown :calculation (string (formula expression context) " = " shown
                                                             (when (variable :note) (string "\n" (variable :note)))
                                                             "\nLevel " (context :level) (unless (context :hide-rank) (string " · rank " (context :rank)))
                                                             " · start of fight. Damage values are before mitigation.")})))
           (array/push segments (if (first result) (result 1) {:text (string/slice line (token :start) (token :end))}))
           (set offset (token :end)))
         (when (< offset (length line)) (array/push segments {:text (string/slice line offset)}))
         segments) (lines description)))
