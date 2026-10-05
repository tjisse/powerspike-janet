; Run with the pinned reference source and its dependencies on the classpath.
; Requires the retained 16.18.1 champion/item/bin records in PS_BENCH_CLOJURE_CACHE.
(require '[powerspike.optimization :as opt]
         '[powerspike.mechanics :as mech]
         '[powerspike.mechanics.parsing :as parsing]
         '[powerspike.data :as data]
         '[cheshire.core :as json]
         '[clojure.java.io :as io])
(def benchmark-cache (or (System/getenv "PS_BENCH_CLOJURE_CACHE") "build/reference-clojure/cache"))
(doseq [filename ["16.18.1-champion.json" "16.18.1-item.json" "bin-Annie.json" "bin-Ahri.json" "bin-Ashe.json" "bin-Garen.json"]]
  (assert (.isFile (io/file benchmark-cache filename)) (str "Missing retained benchmark record: " filename)))
(alter-var-root #'data/cache-dir (constantly benchmark-cache))
(def champions (:data (data/get-champions "16.18.1")))
(def items (:data (data/get-items "16.18.1")))
(defn item-build [ids] (mapv #(get items (keyword %)) ids))
(defn seconds [started] (/ (- (System/nanoTime) started) 1e9))
(defn output [x] (println (json/generate-string x)) (flush))
(doseq [name ["Annie" "Ahri" "Ashe" "Garen"]]
  (let [champion (get champions (keyword name))
        bin (parsing/get-champion-bin name)
        spells (parsing/extract-calculations bin name)]
    (output {:measurement "spell-selection" :champion name
             :spells (mapv (fn [[id s]] {:id (str id) :slot (:slot s) :calculations (count (:calculations s))}) spells)})
    (doseq [ids [[] ["3089" "3135" "6655"] ["1086" "2031" "3046" "3145" "3153" "6695"]]]
      (try (output {:measurement "fixed-build" :champion name :ids ids
                    :cost (reduce + (map #(get-in % [:gold :total]) (item-build ids)))
                    :result (dissoc (opt/calculate-effective-dps champion 18 (item-build ids) 80 80 5) :rotation :stats)})
           (catch Throwable e (output {:measurement "error" :champion name :ids ids :message (.getMessage e)}))))))
(let [champion (:Annie champions) build (item-build ["3089" "3135" "6655"])]
  (dotimes [_ 100] (opt/evaluate-fitness champion 18 build :total 5))
  (let [started (System/nanoTime)]
    (dotimes [_ 100] (opt/evaluate-fitness champion 18 build :total 5))
    (output {:measurement "evaluation" :iterations 100 :seconds (seconds started) :source "original-local-file-loader"}))
  (let [bin (parsing/get-champion-bin "Annie")]
    (with-redefs [parsing/get-champion-bin (constantly bin)]
      (let [started (System/nanoTime)]
        (dotimes [_ 100] (opt/evaluate-fitness champion 18 build :total 5))
        (output {:measurement "evaluation" :iterations 100 :seconds (seconds started) :source "in-memory-pinned-record"})))))
;; Retain the original GA, but stop at the first generation boundary after five
;; seconds. This is a throughput probe, not an equivalent legal-build contest.
(doseq [mode [:ability :ad :total]]
  (reset! opt/fitness-cache {})
  (let [started (System/nanoTime) calls (atom 0) misses (atom 0) progress (atom nil)
        cached opt/evaluate-fitness-cached fitness opt/evaluate-fitness
        champion (:Annie champions)
        rng (java.util.Random. 1)]
    (with-redefs [opt/evaluate-fitness-cached (fn [& args] (swap! calls inc) (apply cached args))
                  opt/evaluate-fitness (fn [& args] (swap! misses inc) (apply fitness args))
                  clojure.core/rand (fn ([] (.nextDouble rng)) ([n] (* n (.nextDouble rng))))
                  clojure.core/rand-int (fn [n] (.nextInt rng n))
                  clojure.core/shuffle (fn [coll] (let [a (java.util.ArrayList. ^java.util.Collection (vec coll))] (java.util.Collections/shuffle a rng) (vec a)))]
      (let [result (try (opt/optimize-build champion 18 "16.18.1" :build-type mode :generations 200 :pop-size 100 :runs 5 :window 5
                                           :progress-fn (fn [p] (reset! progress p) (when (> (seconds started) 5) (throw (ex-info "Time probe complete" {})))))
                        (catch clojure.lang.ExceptionInfo e {:interrupted true}))
            best-key (first (sort-by #(get @opt/fitness-cache %) > (keys @opt/fitness-cache)))]
        (output {:measurement "search-probe" :mode mode :seconds (seconds started) :fitness-calls @calls :uncached-evaluations @misses
                 :cache-size (count @opt/fitness-cache) :progress @progress :result result
                 :highest-cached-score (get @opt/fitness-cache best-key) :highest-cached-items (nth best-key 2 nil)})))))
