(import ./expressions :as expr)

(defn tokens [text]
  (def found @[])
  (var offset 0)
  (while (< offset (length text))
    (def at (string/find "@" text offset))
    (def curly (string/find "{{" text offset))
    (def start (cond (and at curly) (min at curly) at at curly curly))
    (unless start (break))
    (def delimiter (if (= start at) "@" "}}"))
    (def width (if (= start at) 1 2))
    (def end (string/find delimiter text (+ start width)))
    (unless end (break))
    (array/push found {:name (string/trim (string/slice text (+ start width) end)) :start start :end (+ end width)})
    (set offset (+ end width)))
  found)

(defn blocks [text tag]
  (def result @[])
  (var offset 0)
  (def lower (string/ascii-lower text))
  (def opening (string "<" (string/ascii-lower tag) ">"))
  (def closing (string "</" (string/ascii-lower tag) ">"))
  (forever
    (def start (string/find opening lower offset))
    (unless start (break))
    (def end (string/find closing lower (+ start (length opening))))
    (unless end (break))
    (array/push result {:start start :end (+ end (length closing))
                        :text (string/slice text (+ start (length opening)) end)})
    (set offset (+ end (length closing))))
  result)

(defn parse [text spell &opt dd]
  (def variables (map (fn [token] (merge token {:expression (expr/variable (token :name) spell dd)})) (tokens text)))
  (def effects @[])
  (def unresolved @[])
  (def seen @{})
  (def seen-kind @{})
  (each [tag kind damage-type] [["magicDamage" :damage :magic] ["physicalDamage" :damage :physical]
                                ["trueDamage" :damage :true] ["healing" :heal nil] ["shield" :shield nil]]
    (each block (blocks text tag)
      (def available (filter |(and (<= (block :start) ($ :start)) (< ($ :end) (block :end))) variables))
      (def token (first available))
      (def lower (string/ascii-lower (block :text)))
      (when (and token (or (not= kind :damage) (string/find "damage" lower)))
        (def key (string kind "/" damage-type "/" (token :name)))
        # Repeated displays of the same number are not separate damage hits.
        (unless (seen key)
          (put seen key true)
          (def errors (expr/problems (token :expression)))
          (def preceding (string/ascii-lower (string/slice text (max 0 (- (block :start) 120)) (block :start))))
          (def conditional (or (string/find "if " preceding) (string/find "against minions" preceding)
                               (string/find "while " preceding) (string/find "who " preceding)
                               (string/find "reduced to" preceding) (string/find "instead" lower)
                               (string/find "maximum" lower) (string/find "up to" lower)
                               (> (length available) 1)
                               (and (not= kind :damage) (string/find "%" lower))
                               (get seen-kind (tuple kind damage-type))))
          (put seen-kind (tuple kind damage-type) true)
          (def following (string/ascii-lower (string/slice text (block :end) (min (length text) (+ (block :end) 80)))))
          (def periodic (or (string/find "per second" lower) (string/find "over " lower) (string/find "over " following)))
          (def attack (or (string/find "next attack" preceding) (string/find "attacks deal" preceding)))
          (def duration-token (find (fn [candidate]
                                      (and (>= (candidate :start) (block :end))
                                           (< (candidate :start) (+ (block :end) 60))
                                           (string/has-prefix? " second" (string/slice text (candidate :end))))) variables))
          (def effect {:id key :kind kind :damage-type damage-type :amount (token :expression)
                       :trigger (if attack :attack :cast) :target (if (= kind :damage) :enemy :self)
                       :condition (if conditional :unresolved :always)
                       :timing (if periodic :unresolved :impact) :hits 1
                       :duration (when duration-token (duration-token :expression))
                       :status (if (or conditional periodic (not (empty? errors))) :unresolved :estimated)
                       :evidence {:tooltip (block :text) :variable (token :name)}})
          (array/push effects effect)
          (each error errors (array/push unresolved error))
          (when conditional (array/push unresolved (string "Conditional/maximum effect needs semantics: " key)))
          (when periodic (array/push unresolved (string "Periodic damage needs tick/duration semantics: " key)))))))
  (each block (blocks text "status")
    (def lower (string/ascii-lower (block :text)))
    (def control (cond (string/find "stun" lower) :stun (string/find "root" lower) :root
                   (string/find "charm" lower) :charm (string/find "fear" lower) :fear
                   (string/find "silenc" lower) :silence (string/find "slow" lower) :slow
                   (string/find "knock" lower) :airborne))
    (def duration-token (find (fn [candidate]
                                (and (>= (candidate :start) (block :end))
                                     (< (candidate :start) (+ (block :end) 100))
                                     (string/has-prefix? " second" (string/slice text (candidate :end))))) variables))
    (when control
      (def prefix (string/ascii-lower (string/slice text (max 0 (- (block :start) 150)) (block :start))))
      (def uncertain (or (not duration-token) (some |(string/find $ prefix) ["if " "remove" "minion" "next attack"])))
      (array/push effects {:id (string "control/" control "/" (block :start)) :kind :control :control control
                           :duration (when duration-token (duration-token :expression)) :target :enemy :trigger :cast
                           :status (if uncertain :unresolved :estimated) :condition (if uncertain :unresolved :always)
                           :evidence {:tooltip (block :text)}})
      (when uncertain (array/push unresolved (string "Control trigger/duration unresolved: " control)))))
  (each variable variables
    (each problem (expr/problems (variable :expression))
      (unless (some |(= problem $) unresolved) (array/push unresolved problem))))
  {:tooltip text :variables variables :effects effects :unresolved unresolved})
