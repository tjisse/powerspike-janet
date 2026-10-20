(import ./model :as model)
(import ../src/powerspike/scenario-wire :as wire)
(import ../src/powerspike/search :as search)
(import ../src/powerspike/data-util :as util)

# Comparison documents belong to the workspace, outside combat scenario identity.
# Both builds always use one shared scenario; only the pinned inventory differs.
(def format-name "powerspike-comparison")
(defn- restore [definition]
  (assert (<= (get definition :samples 1) 64) "Saved scenario exceeds the workspace limit of 64 trials.")
  (model/state-from-definition definition))
(defn encode [result]
  (assert (not (result :reference-error)) "Clear or replace the invalid pinned items before saving or sharing.")
  (def definition (get-in result [:selected :combat :scenario]))
  (assert definition "No completed scenario is available to save.")
  (util/encode-json
    (if (result :reference)
      {:format format-name :version 1 :scenario definition :pinned-items (get-in result [:reference :ids])}
      {:format wire/format-name :version 1 :scenario definition})))

(defn decode [data]
  (def bytes (if (buffer? data) (string data) data))
  (assert (and (string? bytes) (<= (length bytes) 65536)) "Scenario JSON must fit within 64 KB.")
  (def envelope (util/read-json bytes))
  (if (= wire/format-name (get envelope "format"))
    (restore (wire/decode bytes))
    (do
      (assert (and (dictionary? envelope) (= format-name (get envelope "format")) (= 1 (get envelope "version")))
              "Unsupported saved document format or version.")
      (each name (keys envelope)
        (assert (some |(= name $) ["format" "version" "scenario" "pinned-items"]) "Unknown comparison document field."))
      (def ids (get envelope "pinned-items"))
      (assert (and (indexed? ids) (<= (length ids) 6) (not (some |(not (string? $)) ids))) "Pinned inventory must contain up to six item IDs.")
      (def definition (wire/decode (util/encode-json {:format wire/format-name :version 1 :scenario (get envelope "scenario")})))
      # Compile the pinned inventory against the same exact snapshot too.
      (def pinned (wire/encode (search/replace-items definition ids)))
      (merge (restore definition) {:referencejson (string pinned)}))))
