(import ./server :as server)
(import ./config :as config)
(import ./cli :as cli)

(defn main [& args]
  # JPM passes argv[0] just like Janet's :args dynamic.
  (def settings (config/from-environment (drop 1 args)))
  (case (settings :mode)
    :help (print config/usage)
    :version (print "PowerSpike " config/version)
    :simulate (cli/run settings)
    :optimize (cli/run settings)
    :calibrate (cli/run settings)
    (do
      # Disconnected SSE clients must not terminate the process via SIGPIPE.
      (os/sigaction :pipe (fn [&] nil))
      (server/start (settings :port) (settings :host) (settings :data-dir) (settings :seed-dir))
      (ev/sleep math/inf))))
