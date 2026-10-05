(import ./data-util :as util)
(import ./scenario-wire :as wire)
(import ./scenario :as scenario)
(def families [:isolated-damage :mitigation :timing :on-hit :healing-shields :control :objectives :combinations])
(def metrics [:damage :attack-damage :health :resource :damage-taken :healing :absorbed :control :mean-kill-time :mean-death-time])
(defn check [record]
  (assert (and (= "powerspike-calibration" (get record "format")) (= 1 (get record "version"))) "Unsupported calibration document.")
  (def family (find |(= (string $) (get record "family")) families))
  (assert family "Unknown calibration family.")
  (def observation (get record "observation" {}))
  (if (or (not (= true (get observation "reviewed"))) (not (util/finite? (get observation "value"))))
    {:family family :status :unmeasured :checked false :reason "No reviewed numerical observation. Missing measurements are not zero."}
    (do
      (assert (and (string? (get observation "game-version")) (string? (get observation "source"))
                   (not (empty? (get observation "source"))) (string? (get observation "captured-at"))) "Reviewed measurements require game version, source and capture time.")
      (def metric (find |(= (string $) (get observation "metric")) metrics))
      (assert metric "Unknown calibration metric.")
      (def tolerance (get observation "tolerance" 0.01))
      (assert (and (util/finite? tolerance) (>= tolerance 0)) "Calibration tolerance must be nonnegative.")
      (def definition (wire/decode (util/encode-json (get record "scenario-document"))))
      (def outcome (scenario/simulate definition))
      (def required (get observation "required-source"))
      (def actual (get-in outcome [:metrics metric]))
      (if (or (not (util/finite? actual)) (not (string? required))
              (not (some |(and (= required (string (get $ :source)))
                               (some (fn [kind] (= kind ($ :kind))) [:damage :heal :shield :control])) (outcome :trace))))
        {:family family :status :unresolved :checked false :reason "Required effect or metric is unavailable in the simulation trace."}
        {:family family :status (if (<= (math/abs (- actual (observation "value"))) tolerance) :consistent :mismatch)
         :checked true :metric metric :observed (observation "value") :predicted actual :tolerance tolerance
         :patch (definition :patch) :snapshot (definition :snapshot) :model (get-in outcome [:scenario :model])
         :source (observation "source") :unsupported (outcome :unsupported)}))))
(defn read [path]
  (assert (<= (or (os/stat path :size) math/inf) 65536) "Calibration document must fit within 64 KB.")
  (check (util/read-json (slurp path))))
