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

(defn visible-text [text]
  (def out @"")
  (var tag false)
  (each byte (string/bytes text)
    (cond (= byte 60) (set tag true)
      (= byte 62) (set tag false)
      (not tag) (buffer/push-byte out byte)))
  (string/ascii-lower (string out)))

(defn attack-semantics [text spell effect]
  # Use the effect's own paragraph, rather than a nearby slow, heal or recast,
  # to identify the attack and whether its number includes ordinary AD.
  (def tag (case (effect :damage-type) :physical "physicalDamage" :magic "magicDamage" :true "trueDamage" nil))
  (def block (when tag (find |(= ($ :text) (get-in effect [:evidence :tooltip])) (blocks text tag))))
  (if (not block) effect
    (do
      (def prefix (visible-text (last (string/split "<br" (string/slice text 0 (block :start))))))
      (def suffix (visible-text (first (string/split ". " (first (string/split "<br" (string/slice text (block :end))))))))
      (def next-at (last (string/find-all "next " prefix)))
      (def next-text (when next-at (string/slice prefix next-at)))
      (def counted (when next-text
                     (peg/match ~(* "next " '(+ (some (range "09")) "two" "three" (* "@" (some (if-not "@" 1)) "@"))
                                    " " (? "basic ") "attacks") next-text)))
      (def single (and next-text (or (string/has-prefix? "next attack" next-text)
                                     (string/has-prefix? "next basic attack" next-text))))
      (def repeated (and (not single) (not counted) (string/find "attacks deal" prefix)))
      (if (not (or single counted repeated (= :attack (effect :trigger)))) effect
        (do
          (def phrase (if next-text next-text (last (string/split "." prefix))))
          (def bonus (or (string/find "additional" phrase) (string/find "bonus" (visible-text (block :text)))
                         (string/find "on-hit" phrase)))
          (def override (get-in effect [:evidence :override]))
          (def count (cond repeated :all counted
                       (let [raw (first counted)]
                         (cond (= raw "two") 2 (= raw "three") 3 (scan-number raw) (scan-number raw)
                           (expr/variable (string/slice raw 1 (dec (length raw))) spell)))
                       1))
          (def duration-text (string phrase " " suffix))
          (def explicit-time (or (peg/match ~(* (any (if-not "within " 1)) "within "
                                                '(* (some (range "09")) (? (* "." (some (range "09"))))) " second") phrase)
                                 (when repeated
                                   (peg/match ~(* (any (if-not "for " 1)) "for "
                                                  '(* (some (range "09")) (? (* "." (some (range "09"))))) " second") duration-text))))
          (def duration-token (find (fn [token]
                                      (or (string/find (string "within @" (token :name) "@ second") phrase)
                                          (and repeated
                                               (not (some |(string/find $ (token :name)) ["slow" "stun" "knock" "shred" "heal" "mark" "shield"]))
                                               (string/find (string "for @" (token :name) "@ second") duration-text))))
                                    (tokens duration-text)))
          (def values (expr/named-values spell))
          (def source-window (find |(expr/lookup values $) ["AttackWindow" "AttackBuffDuration" "EmpowerDuration" "BuffDuration" "PrepDuration"]))
          (def duration (cond override (effect :duration)
                          explicit-time (scan-number (first explicit-time))
                          duration-token (expr/variable (duration-token :name) spell)
                          source-window (expr/variable source-window spell)))
          (def errors (mapcat |(if (dictionary? $) (expr/problems $) []) [duration count]))
          (def passive-at (last (string/find-all "passive:" prefix)))
          (def active-at (last (string/find-all "active:" prefix)))
          (def passive (and repeated passive-at (or (not active-at) (> passive-at active-at))))
          (def enriched (merge @{} effect {:trigger :attack :attack-mode (get effect :attack-mode (if bonus :bonus :replace))
                                           :attack-count (if (has-key? effect :attack-count) (effect :attack-count) count)
                                           :reset (or (effect :reset) (some |(= $ "Trait_AttackReset") (get spell "mSpellTags" [])))
                                           :status (if (or passive (not (empty? errors)) (and repeated (not duration))) :unresolved (effect :status))}))
          # Explicitly remove the old parser's duration when it described CC.
          (put enriched :duration duration)
          (table/to-struct enriched))))))

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
          (def attack (or (string/find "next attack" preceding) (string/find "next basic attack" preceding)
                          (string/find "attacks deal" preceding)))
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
          (array/push effects (attack-semantics text spell effect))
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
