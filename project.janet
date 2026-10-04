(declare-project
  :name "powerspike"
  :version (string/trim (slurp "VERSION"))
  :description "League of Legends build comparisons in Janet.")

(def deps (string (os/cwd) "/build/web-deps"))
(def native
  [(declare-native
     :name "spork/json"
     :source [(string deps "/spork/src/json.c")]
     :headers ["web/deps.lock" "project.janet"])
   (declare-native :name "pshash" :source ["native/hash.c"] :lflags ["-lcrypto"])
   (declare-native :name "jurl/native"
                   :source (map |(string deps "/jurl/src/" $ ".c")
                                ["main" "jurl" "callbacks" "cleanup" "enums" "errors" "getinfo" "mime" "polyfill" "setopt" "util"])
                   :headers [(string deps "/jurl/src/jurl.h") "web/deps.lock"]
                   :cflags (if-let [flags (os/getenv "CURL_CFLAGS")] (string/split " " flags) [])
                   :lflags ["-l:libcurl.so.4"])])

# Prepared locally by build.sh. No network dependency resolution inside JPM.
(def records (parse-all (slurp "build/executable-inputs.jdn")))
(assert (= 1 (length records)) "Expected one executable input manifest.")
(declare-executable :name "powerspike" :entry "web/release.janet"
                    :deps [;(first records) ;(mapcat values native)])
