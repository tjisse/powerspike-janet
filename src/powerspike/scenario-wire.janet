(import ./data-util :as util)
(import ./scenario :as scenario)
(import ./engine :as engine)
(def format-name "powerspike-scenario")
(def fields [:schema :patch :snapshot :model :duration :distance :seed :samples :player :target :champion :level :loadout
             :items :runes :summoners :health-fraction :resource-fraction :ranks :skill-order :strategy :priority :activation
             :movement :attacks :abilities :hit-chance :preferred-range :after :self-health-below :target-health-below
             :kind :hp :armor :mr :objective :game-time :minions-present :retaliation :q :w :e :r :d :f])
(defn normalize [value &opt depth parent]
  (def at (or depth 0))
  (assert (< at 12) "Scenario nesting is excessive.")
  (cond
    (dictionary? value)
    (do (assert (<= (length value) 48) "Too many scenario fields.")
      (tabseq [[name child] :pairs value]
        (let [key (find |(= (string $) (string name)) fields)]
          (assert key (string "Unknown scenario field: " name)) key)
        (normalize child (inc at) (string name))))
    (indexed? value)
    (do (assert (<= (length value) 24) "Scenario list is excessive.")
      (tuple ;(map |(normalize $ (inc at) parent) value)))
    (string? value)
    (do (assert (<= (length value) 128) "Scenario string is excessive.")
      (if (some |(= $ parent) ["kind" "movement" "objective" "priority" "skill-order"])
        (do (assert (some |(= value (string $)) [:champion :practice :objective :hold :approach :hold-range :q :w :e :r :d :f
                                                 :turret :baron :herald :dragon-fire :dragon-air :dragon-earth :dragon-water :dragon-hextech :dragon-chemtech :dragon-elder])
                    "Unsupported scenario choice.") (keyword value)) value))
    (or (number? value) (boolean? value) (nil? value)) value
    (error "Scenario values must be JSON data.")))
(defn encode [definition]
  (def compiled (scenario/compile definition))
  (util/encode-json {:format format-name :version 1 :scenario (compiled :definition)}))
(defn decode [data]
  (def bytes (if (buffer? data) (string data) data))
  (assert (and (string? bytes) (<= (length bytes) 65536)) "Scenario JSON must fit within 64 KB.")
  (def envelope (util/read-json bytes))
  (assert (and (dictionary? envelope) (= format-name (get envelope "format")) (= 1 (get envelope "version")))
          "Unsupported scenario document format or version.")
  (assert (dictionary? (get envelope "scenario")) "Scenario document is missing its scenario.")
  (def definition (util/canonical (normalize (envelope "scenario"))))
  (assert (and (util/version? (definition :patch)) (string? (definition :snapshot)) (= 64 (length (definition :snapshot)))
               (string? (definition :model)) (= 64 (length (definition :model)))) "Scenario requires exact patch, snapshot and model identities.")
  # Validation compiles against the exact retained revision. Missing data is an
  # error; never fall back to the current pointer or a different patch.
  (scenario/compile definition)
  definition)
