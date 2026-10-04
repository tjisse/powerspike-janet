# Read environment settings inside main, after an embedded executable starts.
# Command-line settings override the service environment; a positional port
# remains compatible with the development entry point.
(def version (string/trim (slurp "VERSION")))

(def usage "Usage: powerspike [--host ADDRESS] [--port PORT]\n\nEnvironment: PS_HOST (default 127.0.0.1), PS_PORT (default 8090).\nPorts must be 1024–65535. A positional port is also accepted.\n")

(defn parse [args environment]
  (var host (get environment "PS_HOST" "127.0.0.1"))
  (var port-text (get environment "PS_PORT" "8090"))
  (var port-set false)
  (var host-set false)
  (var mode :serve)
  (var index 0)
  (while (< index (length args))
    (def arg (args index))
    (cond
      (= arg "--help") (set mode :help)
      (= arg "--version") (set mode :version)
      (= arg "--port")
      (do (assert (not port-set) "Specify the port only once.")
        (++ index) (assert (< index (length args)) "--port requires a value.")
        (set port-text (args index)) (set port-set true))
      (= arg "--host")
      (do (assert (not host-set) "Specify the host only once.")
        (++ index) (assert (< index (length args)) "--host requires a value.")
        (set host (args index)) (set host-set true))
      (do (assert (not (string/has-prefix? "-" arg)) (string "Unknown option: " arg))
        (assert (not port-set) "Specify the port only once.")
        (set port-text arg) (set port-set true)))
    (++ index))
  (when (= mode :serve)
    (assert (and (string? host) (not (empty? host)) (= host (string/trim host)))
            "PS_HOST / --host must be a nonempty listen address.")
    (assert (and (string? port-text) (not (empty? port-text))
                 (not (some |(not (<= 48 $ 57)) (string/bytes port-text))))
            "PS_PORT / --port must be an integer from 1024 to 65535.")
    (def port (scan-number port-text))
    (assert (and (number? port) (<= 1024 port 65535))
            "PS_PORT / --port must be an integer from 1024 to 65535."))
  {:host host :port (if (= mode :serve) (scan-number port-text) nil) :mode mode})

(defn from-environment [args]
  (parse args (tabseq [name :in ["PS_HOST" "PS_PORT"]
                       :let [value (os/getenv name)] :when value] name value)))
