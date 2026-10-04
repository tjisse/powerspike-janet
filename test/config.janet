(import ../web/config :as config)

(defn rejects [args environment]
  (assert (not (first (protect (config/parse args environment)))) "Expected config rejection."))

(assert (= {:host "127.0.0.1" :port 8090 :mode :serve} (config/parse [] {})))
(assert (= 8765 ((config/parse [] {"PS_PORT" "8765"}) :port)))
(assert (= "0.0.0.0" ((config/parse [] {"PS_HOST" "0.0.0.0"}) :host)))
(assert (= 8766 ((config/parse ["--port" "8766"] {"PS_PORT" "8765"}) :port)))
(assert (= 8767 ((config/parse ["8767"] {}) :port)))
(assert (= "::1" ((config/parse ["--host" "::1"] {}) :host)))
(each value ["" "no-port" "8090.5" "1e4" "1023" "65536" "NaN" " 8090" "8090 "]
  (rejects [] {"PS_PORT" value}))
(each args [["--port"] ["--host"] ["--port" "8090" "8091"] ["--unknown"]]
  (rejects args {}))
(rejects [] {"PS_HOST" ""})
(assert (= :help ((config/parse ["--help"] {"PS_PORT" "invalid"}) :mode)))
(assert (= :version ((config/parse ["--version"] {}) :mode)))
(print "Configuration defaults, environment, precedence and rejection checks passed.")
