(import ../src/powerspike/tooltip :as tooltip)
(import ../src/powerspike/normalize :as normalize)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/data-util :as util)
(import pshash :as hash)

(def path "data/combat-fixtures/16.19.1/empowered-attacks.json")
(def manifest (util/read-json (slurp "data/combat-fixtures/16.19.1/manifest.json")))
(assert (= (get-in manifest ["fixture_sha256" "empowered-attacks.json"]) (hash/sha256 (slurp path))))
(def fixtures (util/read-json (slurp path)))
(def expected {"Yorick" [:bonus 105] "Jax" [:bonus 110] "Draven" [:bonus 92.5]
               "Blitzcrank" [:replace 325] "Darius" [:replace 210] "Trundle" [:replace 182.5]
               "Leona" [:bonus 40] "XinZhao" [:bonus 43] "MasterYi" [:bonus 44.5]})
(defn close [expected actual]
  (assert (< (math/abs (- expected actual)) 0.0001) (string "Expected " expected ", got " actual)))
(each fixture (fixtures "cases")
  (def slot (keyword (fixture "slot")))
  (def parsed (tooltip/parse (fixture "tooltip") (fixture "spell")))
  # Simulate the old snapshot schema as well as newly parsed records. The
  # retained record must repair semantics without changing snapshot bytes.
  (def old-effects (map |(tabseq [[key value] :pairs $
                                  :when (not (some |(= $ key) (if (= :attack ($ :trigger))
                                                                [:attack-mode :attack-count :reset :duration]
                                                                [:attack-mode :attack-count :reset])))] key value)
                        (parsed :effects)))
  (def ability {:slot slot :id (fixture "id") :tooltip (fixture "tooltip") :record (fixture "spell")
                :effects old-effects :unresolved (parsed :unresolved) :available true
                :cost 0 :cooldown 99 :cast-time 0.1 :range 500})
  (def kit (normalize/semantic-kit (fixture "champion") "16.19.1" {:abilities [ability]}))
  (assert (= (util/canonical kit) (util/canonical (normalize/semantic-kit (fixture "champion") "16.19.1" kit))))
  (def fresh (first (filter |(and (= :damage ($ :kind)) (= :estimated ($ :status))) (parsed :effects))))
  (def repaired (first (filter |(and (= :damage ($ :kind)) (= :estimated ($ :status))) (get-in kit [:abilities 0 :effects]))))
  (assert (= (get-in expected [(fixture "champion") 0]) (repaired :attack-mode)))
  (assert (= (util/canonical fresh) (util/canonical repaired)))
  (def actor {:id "player" :kind :champion :level 1 :base {:ad 80 :hp 1000 :ap 0}
              :stats {:hp 1000 :mp 1000 :ad 150 :bonus-ad 70 :ap 100 :attack-speed 1 :armor 0 :mr 0}
              :ranks {slot 1} :position 0 :attack-range 200 :abilities (kit :abilities)
              :strategy {:abilities true :attacks true :priority [slot] :movement :hold}})
  (def target {:id "target" :kind :practice :stats {:hp 10000 :armor 0 :mr 0} :position 0
               :strategy {:abilities false :attacks false :movement :hold}})
  (def result (engine/simulate {:duration 3 :actors [actor target]}))
  (def hits (filter |(= (fixture "id") ($ :source)) (result :events)))
  (def count (if (some |(= $ (fixture "champion")) ["XinZhao" "MasterYi"]) 3 1))
  (assert (= count (length hits)) (string "Empowered hit count: " (fixture "champion")))
  (each hit hits (close (get-in expected [(fixture "champion") 1]) (hit :damage)))
  (def base-attacks (if (= :replace (repaired :attack-mode)) 2 3))
  (close (+ (* base-attacks 150) (* count (get-in expected [(fixture "champion") 1]))) (result :damage))
  (assert (not (some |(string/find "got nil" $) (result :unsupported)))))
(print "Retained empowered attacks: Yorick, Jax, Draven, Blitzcrank, Darius, Trundle, Leona, Xin Zhao and Master Yi; cached repair, damage types, counts and totals passed.")
