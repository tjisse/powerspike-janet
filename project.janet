(declare-project
  :name "powerspike"
  :version (string/trim (slurp "VERSION"))
  :description "League of Legends build comparisons in Janet.")

(def deps (string (os/cwd) "/build/web-deps"))
(def native
  (declare-native
    :name "spork/json"
    :source [(string deps "/spork/src/json.c")]
    :headers ["web/deps.lock" "project.janet"]))

# Prepared locally by build.sh. No network dependency resolution inside JPM.
(def records (parse-all (slurp "build/executable-inputs.jdn")))
(assert (= 1 (length records)) "Expected one executable input manifest.")
(declare-executable :name "powerspike" :entry "web/release.janet"
                    :deps [;(first records) ;(values native)])
