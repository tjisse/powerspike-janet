# Developer-only audit of retained normalized range expressions. No provider
# calls or simulation rules are added by this report.
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(defn health-dependent? [expression]
  (and (dictionary? expression)
       (or (and (some |(= $ (expression :op)) [:stat :target-stat])
                (some |(= $ (expression :stat)) [:health :health-percent :missing-health :missing-health-percent]))
           (some health-dependent? (get expression :children [])))))
(def groups @[])
(def nonfixed @[])
(def totals @{:kits 0 :abilities 0 :fixed 0 :event 0 :health 0 :other 0})
(each [patch root ids strings] [["16.18.1" "data/parser-fixtures/16.18.1/" ["Annie" "Ahri" "Garen" "Aatrox" "DrMundo" "Zac" "Khazix"] "strings.json"]
                                ["16.19.1" "data/combat-fixtures/16.19.1/" ["Annie" "Ahri" "Viktor"] "champion-strings.json"]
                                ["16.19.1" "data/parry-fixtures/16.19.1/" ["Fiora"] "strings.json"]]
  (def manifest (util/read-json (slurp (string root "manifest.json"))))
  (defn verified [file]
    (def bytes (slurp (string root file)))
    (assert (= (get-in manifest ["fixture_sha256" file]) (hash/sha256 bytes)) (string "Range audit source integrity failure: " root file))
    (util/read-json bytes))
  (def fonts (verified strings))
  (def counts @{:kits (length ids) :abilities 0 :fixed 0 :event 0 :health 0 :other 0})
  (each id ids
    (def kit (normalize/kit id (verified (string id "-characters.json")) (verified (string id "-abilities.json")) fonts patch))
    (each ability (kit :abilities)
      (unless (= :p (ability :slot))
        (def expression (ability :range))
        (def kind (cond (engine/fixed-value? expression) :fixed
                    (health-dependent? expression) :health
                    (engine/event-value? expression) :event :other))
        (put counts :abilities (inc (counts :abilities)))
        (put counts kind (inc (counts kind)))
        (unless (= kind :fixed)
          (array/push nonfixed {:patch patch :champion id :slot (ability :slot) :range expression :kind kind})))))
  (eachp [key count] counts (put totals key (+ (totals key) count)))
  (array/push groups (merge counts {:patch patch :source root :champions ids})))
(print (util/encode-json {:groups groups :totals totals :nonfixed nonfixed}))
