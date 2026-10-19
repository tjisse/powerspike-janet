# The production damage functions used by the engine, with reviewed scalar
# inputs only. No patch build, champion fixture, observation or tolerance enters.
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/damage :as damage)
(def records (parse-all (slurp ((dyn :args) 1))))
(assert (= 1 (length records)) "one conditional input record required")
(def input (records 0))
(assert (= (input :model) engine/identity) "conditional model identity changed")
(def source (input :source))
(def target (input :target))
(assert (= 0 (source :crit-chance)) "individual critical outcome unsupported")
(assert (and (= 0 (source :armor-pen-flat)) (= 0 (source :armor-pen-percent))
             (= 0 (target :armor-reduction-flat)) (= 0 (target :armor-reduction-percent))
             (> (target :armor) 0)) "outside reviewed conditional domain")
(def raw (damage/expected-attack-damage source))
(def result (damage/resolve-hit raw :physical source target))
(print engine/identity "\t" (string/format "%.17g" raw) "\t"
       (string/format "%.17g" (result :effective-resistance)) "\t"
       (string/format "%.17g" (result :damage)))
