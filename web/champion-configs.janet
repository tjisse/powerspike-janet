(import ./model :as model)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/engine :as engine)

(def format-name "powerspike-champion")
(defn slots [state opponent]
  (map |(get state $ "") (if opponent model/enemy-slot-keys model/slot-keys)))
(defn documents [definition player-items opponent-items]
  (defn document [spec items]
    {:format format-name :version 1 :patch (definition :patch) :snapshot (definition :snapshot)
     :model (definition :model) :champion (merge spec {:kind :champion}) :slots items})
  {:player (document (definition :player) player-items)
   :opponent (document (definition :target) opponent-items)})

(defn decode [payload state]
  (def bytes (if (buffer? payload) (string payload) payload))
  (assert (and (string? bytes) (<= (length bytes) 16384)) "Champion save must fit within 16 KB.")
  (def data (util/read-json bytes))
  (assert (and (dictionary? data) (= format-name (get data "format")) (= 1 (get data "version")))
          "Unsupported champion save format or version.")
  (each key (keys data)
    (assert (some |(= key $) ["format" "version" "patch" "snapshot" "model" "champion" "slots"]) "Unknown champion save field."))
  (assert (and (= (state :patch) (get data "patch")) (= (state :snapshot) (get data "snapshot")))
          "This champion was saved on another patch snapshot. Switch to that snapshot before loading it.")
  (assert (and (string? (get data "model")) (= 64 (length (data "model")))) "Champion save is missing its model identity.")
  (def spec (wire/normalize (get data "champion")))
  (assert (and (dictionary? spec) (= :champion (get spec :kind))) "Champion save is missing its champion configuration.")
  (def items (get data "slots"))
  (assert (and (indexed? items) (= 6 (length items)) (all string? items)) "Champion save requires six inventory slots.")
  (assert (= (tuple ;(filter |(not= "" $) items)) (tuple ;(get-in spec [:loadout :items] [])))
          "Champion save inventory does not match its slots.")
  {:champion spec :slots items :model (data "model")})

(defn apply-action [state action who &opt bytes]
  (assert (= "duel" (state :mode)) "Champion slots require a champion matchup.")
  (assert (some |(= who $) ["player" "opponent"]) "Choose a champion side.")
  (def preview (model/preview state))
  (def original (preview :definition))
  (var player (original :player))
  (var opponent (original :target))
  (var player-items (if (= "custom" (state :selected)) (slots state false)
                      (map |(get-in preview [:selected :ids $] "") (range 0 6))))
  (var opponent-items (slots state true))
  (var old-model false)
  (case action
    "swap" (do
             (def previous player) (set player opponent) (set opponent previous)
             (def previous-items player-items) (set player-items opponent-items) (set opponent-items previous-items))
    "load" (do
             (def saved (decode bytes state))
             (set old-model (not= engine/identity (saved :model)))
             (if (= who "player")
               (do (set player (saved :champion)) (set player-items (saved :slots)))
               (do (set opponent (saved :champion)) (set opponent-items (saved :slots)))))
    (error "Choose load or swap."))
  # Compilation validates the saved participant against the exact retained data.
  # Restoration preserves automatic ranks; physical inventory holes are separate.
  (def restored (model/state-from-definition (merge original {:player player :target (merge opponent {:kind :champion})})))
  (def updated (merge restored
                      (tabseq [[index id] :pairs player-items] (model/slot-keys index) id)
                      (tabseq [[index id] :pairs opponent-items] (model/enemy-slot-keys index) id)
                      {:snapshotlocked (state :snapshotlocked)
                       :referencejson (if (not= (get-in original [:player :champion]) (player :champion)) "" (get state :referencejson ""))}))
  (put updated :savedmodel (state :savedmodel))
  {:state updated :message (string (if (= action "swap") "Champions swapped. " "Champion loaded. ")
                                   (if old-model "Saved with an earlier model. " "") "Run matchup to update the result.")})
