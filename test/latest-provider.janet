(import ../src/powerspike/data-util :as util)

# Exact retained responses for a small champion subset; no network requests.
(defn provider [patch &opt fixture-root champions]
  (def root (or fixture-root (string "data/parser-fixtures/" patch "/")))
  (def ids (or champions ["Annie" "Garen"]))
  (def fonts (util/read-json (slurp (string root "strings.json"))))
  (def details (tabseq [id :in ids] id
                 (util/read-json (slurp (string root id "-abilities.json")))))
  (fn [url cancelled]
    (assert (not (cancelled)))
    (def detail-id (find |(string/find (string "/champion/" $ ".json") url) ids))
    (def character-id (find |(string/find (string "/" (string/ascii-lower $) "/" (string/ascii-lower $) ".bin.json") url) ids))
    (util/encode-json
      (cond
        (string/has-suffix? "/champion.json" url)
        {"version" patch "data" (tabseq [[id detail] :pairs details] id (get-in detail ["data" id]))}
        (or (string/has-suffix? "/item.json" url) (string/has-suffix? "/summoner.json" url))
        {"version" patch "data" {}}
        (string/find "/lol.stringtable.json" url) fonts
        detail-id (details detail-id)
        character-id (util/read-json (slurp (string root character-id "-characters.json")))
        {}))))
