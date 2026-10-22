# Run sequentially from the repository root, using the retained seed/cache.
(import ../../web/catalog :as catalog)
(import ../../web/model :as model)
(import ../../web/ui :as ui)
(import ../../src/powerspike/packages :as packages)
(import ../../src/powerspike/data-util :as util)
(import ../../src/powerspike/engine :as engine)

(catalog/initialize (os/getenv "PS_DATA_DIR" "build/page-benchmark") (os/getenv "PS_SEED_DIR" "build/seed"))
(set catalog/versions-ready true)
(def evidence (model/evidence))
(defn measure [task]
  (task)
  (def times @[])
  (var bytes 0)
  (repeat 3
    (def started (os/clock :monotonic))
    (def text (task))
    (array/push times (- (os/clock :monotonic) started))
    (set bytes (length text)))
  {:bytes bytes :seconds times :median-seconds ((sorted times) 1)})

(each mode ["practice" "duel"]
  (def state (model/parse-state (merge {"mode" mode "champion" "Annie" "opponent" "Garen"
                                        "level" 6 "opponentlevel" 6 "duration" (if (= mode "practice") 3 5)
                                        "samples" 1 "seed" 1 "snapshotlocked" true
                                        "patch" (os/getenv "PS_BENCH_PATCH" packages/default-version)}
                                       (if-let [snapshot (os/getenv "PS_BENCH_SNAPSHOT")] {"snapshot" snapshot} {}))))
  (def result (model/compare state))
  (with-dyns [:patch-package (result :package)]
    (print (util/encode-json {:mode mode :patch (get-in result [:package :patch]) :snapshot (get-in result [:package :snapshot])
                              :model engine/identity :metrics (get-in result [:selected :combat :metrics])
                              :loadout (measure (fn [] (ui/render (ui/loadout result))))
                              :native-inventory (when (= mode "practice") (measure (fn [] (ui/render (ui/native-inventory result)))))
                              :page (measure (fn [] (ui/page result evidence)))}))))
