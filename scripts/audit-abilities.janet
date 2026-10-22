# Read an existing developer cache; do not download, refresh or reparse it.
(import ./lib/ability-audit :as audit)
(import ../src/powerspike/packages :as packages)
(import ../src/powerspike/data-util :as util)

(def args (dyn :args))
(assert (<= 3 (length args) 5)
        "Usage: janet scripts/audit-abilities.janet DATA_DIRECTORY PATCH [SNAPSHOT] [REPORT.json]")
(packages/initialize (args 1) nil)
(def snapshot (unless (= "-" (get args 3)) (get args 3)))
(def report (audit/run (packages/load (args 2) snapshot)))
(if (get args 4) (util/write (args 4) (util/encode-json report))
  (print (util/encode-json report)))
