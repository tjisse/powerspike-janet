(import ../src/powerspike/data-util :as util)

# Exact retained responses for a small champion subset; no network requests.
(defn provider [patch]
  (def root (string "data/parser-fixtures/" patch "/"))
  (def fonts (util/read-json (slurp (string root "strings.json"))))
  (def details (tabseq [id :in ["Annie" "Garen"]] id
                 (util/read-json (slurp (string root id "-abilities.json")))))
  (fn [url cancelled]
    (assert (not (cancelled)))
    (util/encode-json
      (cond
        (string/has-suffix? "/champion.json" url)
        {"version" patch "data" (tabseq [[id detail] :pairs details] id (get-in detail ["data" id]))}
        (or (string/has-suffix? "/item.json" url) (string/has-suffix? "/summoner.json" url))
        {"version" patch "data" {}}
        (string/find "/lol.stringtable.json" url) fonts
        (string/find "/champion/Annie.json" url) (details "Annie")
        (string/find "/champion/Garen.json" url) (details "Garen")
        (string/find "/annie/annie.bin.json" url) (util/read-json (slurp (string root "Annie-characters.json")))
        (string/find "/garen/garen.bin.json" url) (util/read-json (slurp (string root "Garen-characters.json")))
        {}))))
