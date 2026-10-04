(import ./server :as server)
(import ./config :as config)

(defn main [& args]
  # JPM passes argv[0] just like Janet's :args dynamic.
  (def settings (config/from-environment (drop 1 args)))
  (case (settings :mode)
    :help (print config/usage)
    :version (print "PowerSpike " config/version)
    (do
      # Disconnected SSE clients must not terminate the process via SIGPIPE.
      (os/sigaction :pipe (fn [&] nil))
      (server/start (settings :port) (settings :host))
      (ev/sleep math/inf))))
