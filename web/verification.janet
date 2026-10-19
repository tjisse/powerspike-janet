(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/engine :as engine)

# Retain an offline snapshot in the executable. Development and installed users
# can atomically replace the report without shipping private replay cases.
(def bundled (util/read-json (slurp "observations/verification/progress.json")))
(defn read-report []
  (def configured (os/getenv "PS_VERIFICATION_REPORT"))
  (def path (or configured "observations/verification/progress.json"))
  (def report
    (if (or configured (os/stat path))
      (do (assert (<= (or (os/stat path :size) math/inf) 1048576) "Verification report unavailable.")
        (util/read-json (slurp path)))
      bundled))
  (assert (and (= "powerspike-verification-progress" (get report "format"))
               (= 1 (get report "version"))) "Verification report unavailable.")
  (each key ["games" "events" "ordinary-candidates" "numeric-ready" "admitted" "evaluated" "unknown-effects"]
    (def value (get-in report ["pipeline" key]))
    (assert (and (util/finite? value) (>= value 0) (= value (math/floor value))) "Verification report unavailable."))
  (assert (and (indexed? (report "families")) (= 8 (length (report "families")))
               (indexed? (report "obligations")) (indexed? (report "next-unlocks"))) "Verification report unavailable.")
  (each path [["coverage" "replay-reach"] ["coverage" "balanced-fraction"]
              ["coverage" "minimum-family-fraction"] ["agreement" "fraction"]]
    (def value (get-in report path))
    (assert (or (= :null value) (and (util/finite? value) (<= 0 value 1))) "Verification report unavailable."))
  report)

(defn percentage [value]
  (if (number? value) (string (string/format "%.1f" (* 100 value)) "%") "Not measured"))

(defn summary-tree [report]
  (def pipeline (report "pipeline"))
  (def coverage (report "coverage"))
  [:div {:class "verification-summary"}
   [:div [:span "Checked combat conditions"]
    [:strong (coverage "combat-checked") " / " (coverage "combat-total")]
    [:small "Of this verification plan; not all League behavior"]]
   [:div [:span "Replay situations admitted"] [:strong (percentage (coverage "replay-reach"))]
    [:small (pipeline "admitted") " of " (pipeline "events") " champion-to-champion hits"]]
   [:div [:span "Agreement on evaluated cases"] [:strong (percentage (get-in report ["agreement" "fraction"]))]
    [:small (get-in report ["agreement" "checked"]) " comparisons · "
     (get-in report ["agreement" "mismatches"]) " mismatches"]]])

(defn model-notice [report]
  (when (not= engine/identity (report "model"))
    [:p {:class "warning"} "Historical model snapshot. These counts have not been regenerated for the running model."]))

(def blocker-names
  {"buff-and-on-hit-context-unresolved" "Relevant buffs and on-hit effects"
   "inventory-and-rune-state-unresolved" "Items and rune effects at the time of the hit"
   "attack-classification-not-independently-verified" "Independent identification of the attack"
   "stat-sampling-window-unresolved" "When the game sampled the attack's stats"
   "shield-semantics-not-independently-verified" "Shield state and absorption"
   "damage-packet-amount-semantics-incomplete" "What the recorded damage amount measures"
   "other-effect" "Spell or effect identification"
   "outside-first-mechanic:nonphysical" "Admission rules for magic or true damage"
   "critical-outcome-unresolved" "The actual critical outcome"
   "observed-shield-candidate-nonzero" "A possible active shield"
   "nonzero-lethality-semantics-unverified" "Lethality interpretation"
   "bonus-armor-penetration-semantics-unverified" "Bonus armor penetration interpretation"
   "unknown-effect" "Unknown effect identity"
   "critical-attack-candidate" "Independent identification of a critical attack"})
(defn blocker-label [value] (get blocker-names value "An additional observation or effect needs review"))

(defn panel [result]
  (def loaded (protect (read-report)))
  [:details {:id "verification-progress" :class "scope-panel verification-panel" :data-preserve-attr "open"}
   [:summary "Replay verification progress"]
   (if (first loaded)
     (do (def report (loaded 1))
       [:div (model-notice report)
        [:p "Replay evidence for patch " (report "patch") " · build " (report "client-build")]
        (when (not= (get-in result [:package :patch]) (report "patch"))
          [:p {:class "muted"} "The selected patch differs. This evidence does not verify the selected scenario."])
        (summary-tree report)
        [:p "Provisional checks remain separate from verified comparisons."]
        [:a {:href "/verification"} "View coverage, blockers and next checks →"]])
     [:p "Verification report unavailable. Combat accuracy remains unverified."])])

(defn dashboard [report]
  (def pipeline (report "pipeline"))
  [:div {:class "verification-dashboard"}
   (model-notice report)
   [:p {:class "muted"} "Patch " (report "patch") " · build " (report "client-build")
    " · " (report "registry-revision") " · updated " (report "generated-at")]
   (summary-tree report)
   [:section [:h2 "Evidence moving through verification"]
    [:p "First milestone: " (get-in report ["bootstrap" "checked-attacks"]) " / "
     (get-in report ["bootstrap" "target" "admitted-ordinary-attacks"]) " reviewed attacks, across "
     (get-in report ["bootstrap" "games"]) " / " (get-in report ["bootstrap" "target" "games"]) " games and "
     (get-in report ["bootstrap" "source-champions"]) " / " (get-in report ["bootstrap" "target" "source-champions"]) " source champions."]
    [:ol {:class "verification-pipeline"}
     (map (fn [[key caption]] [:li [:strong (pipeline key)] [:span caption]])
          [["games" "Development and reserved games"] ["events" "Champion-to-champion hits"]
           ["ordinary-candidates" "Ordinary-attack candidates"] ["numeric-ready" "Candidates with numeric inputs"]
           ["admitted" "Admitted after review"] ["evaluated" "Compared with the model"]])]
    [:p {:class "muted"} "Candidate readiness is not verified damage. Missing context and unknown effects remain gaps."]]
   [:p (pipeline "unknown-effects") " of " (pipeline "events") " hits still have unidentified effects."]
   [:section [:h2 "Coverage by mechanic"]
    [:p "Each family gets equal weight. A mismatch adds checked evidence but remains a discrepancy."]
    [:div {:class "verification-table-scroll"}
     [:table {:class "verification-table"}
      [:thead [:tr [:th "Mechanic"] [:th "Checked conditions"] [:th "Varied"] [:th "Fresh-game checked"] [:th "Open mismatches"]]]
      [:tbody (map (fn [family]
                     [:tr [:th {:scope "row"} (family "label")]
                      [:td (family "checked") " / " (family "total")
                       [:progress {:max (family "total") :value (family "checked")
                                   :aria-label (string (family "label") " checked conditions")}]]
                      [:td (family "varied")] [:td (family "fresh")] [:td (family "open-mismatches")]]) (report "families"))]]]
    [:p {:class "muted"} "Balanced plan coverage: " (percentage (get-in report ["coverage" "balanced-fraction"]))
     " · least-covered family: " (percentage (get-in report ["coverage" "minimum-family-fraction"]))
     ". Overall League coverage is not measured."]
    [:details [:summary "Individual conditions and evidence gates"]
     [:ul {:class "verification-obligations"}
      (map (fn [row] [:li [:strong (row "label")] [:span (row "stage")]
                      [:small (row "candidates") " candidate " (row "candidate-unit") " · " (row "checked") " comparisons · "
                       (row "games") " / " (get-in row ["diversity" "games"]) " games · "
                       (row "actors") " / " (get-in row ["diversity" "actors"]) " source champions · "
                       (row "encounters") " / " (get-in row ["diversity" "encounters"]) " reviewed encounters"]])
           (report "obligations"))]]]
   [:section [:h2 "Interactions"]
    [:ul (map (fn [row] [:li (row "label") " · " (row "checked") " / " (row "total") " combinations checked"])
              (report "interactions"))]
    [:details [:summary "Where the evidence comes from"]
     [:div {:class "verification-table-scroll"}
      [:table {:class "verification-table"}
       [:thead [:tr [:th "Source champion"] [:th "Observed hits"] [:th "Games"] [:th "Checked"] [:th "Mismatches"]]]
       [:tbody (map (fn [row] [:tr [:th {:scope "row"} (row "champion")] [:td (row "observed-events")]
                               [:td (row "games")] [:td (row "checked")] [:td (row "mismatches")]])
                    (get-in report ["slices" "source-champions"]))]]]
     [:p {:class "muted"} "A champion appearing in a replay is not champion-wide verification. Item and rune coverage is not yet measured."]]]
   [:section [:h2 "Next useful unlocks"]
    (when (> (get report "pending-evaluations" 0) 0)
      [:p (report "pending-evaluations") " reviewed cases are ready for model execution."])
    [:p "These are review candidates. Every listed blocker must be resolved; the counts are not promised gains."]
    [:ol {:class "verification-unlocks"}
     (map (fn [row]
            [:li [:strong (row "candidates") " candidates across " (row "games") " games"]
             [:p "Potential checks: " (string/join (map (fn [id]
                                                          (get (find |(= id ($ "id")) (report "obligations")) "label" id)) (row "obligations")) ", ")]
             [:p {:class "muted"} "Review estimate: " (if (number? (row "estimated-review-hours"))
                                                        (string (row "estimated-review-hours") " hours") "not estimated")]
             (if (empty? (row "blockers"))
               [:p "Observation review complete; ready for comparison."]
               [:details [:summary (length (row "blockers")) " requirements still open"]
                [:ul (map |[:li (blocker-label $)] (row "blockers"))]])]) (take 5 (report "next-unlocks")))]]
   [:section [:h2 "Provisional checks and fresh games"]
    (when (> (get-in report ["diagnostics" "attack-context" "games"] 0) 0)
      [:div
       [:p (get-in report ["diagnostics" "attack-context" "decoded-actions"])
        " action announcements decoded across " (get-in report ["diagnostics" "attack-context" "games"])
        " games. " (get-in report ["diagnostics" "attack-context" "counts" "numeric-ready:unique-candidate"] 0)
        " numerically ready attacks have one announcement candidate; "
        (get-in report ["diagnostics" "attack-context" "counts" "numeric-ready:observed-stable"] 0)
        " also have unchanged relevant stat observations until the recorded damage."]
       [:p {:class "muted"} "Action associations and observed stat continuity are provisional. They do not establish attack completion, critical outcome, exact server sampling or absence of other effects."]])
    [:p (get-in report ["diagnostics" "stat-checks"]) " conditional stat checks; "
     (get-in report ["diagnostics" "damage-checks"]) " conditional damage diagnostic. These do not advance verified coverage."]
    (unless (true? (get-in report ["diagnostics" "components-current"]))
      [:p {:class "muted"} "The provisional study has not been refreshed for these component versions."])
    [:p (get-in report ["audit" "reserved-games"]) " games reserved for evaluation; "
     (get-in report ["audit" "fresh-evaluated-games"]) " fresh games evaluated. Population accuracy and statistical confidence are not yet measured."]
    [:p "Audit share of allocated review time: " (percentage (get-in report ["resources" "audit-review-fraction"]))
     " · planning target " (percentage (get-in report ["resources" "audit-review-target"]))
     ". Shared research time is excluded from this split."]]
   [:section [:h2 "Resources and history"]
    [:p "Measured review time: " (if (number? (get-in report ["resources" "recorded-seconds" "review"]))
                                   (string (string/format "%.1f" (/ (get-in report ["resources" "recorded-seconds" "review"]) 60)) " minutes") "not recorded")]
    [:p "Measured ledger processing: " (if (number? (get-in report ["resources" "recorded-seconds" "compute"]))
                                         (string (string/format "%.2f" (get-in report ["resources" "recorded-seconds" "compute"])) " seconds") "not recorded")
     ". Download, extraction and review costs are tracked separately."]
    [:p (get-in report ["history" "all-revision-mismatches"]) " mismatches retained across model revisions; "
     (get-in report ["history" "invalidated"]) " explicitly withdrawn records; "
     (get-in report ["history" "outside-current-view"]) " comparisons outside the current model or catalogue."]
    (when-let [previous (get report "previous-report")]
      [:div [:p "Previous report: " (get previous "generated-at" "unknown date")
             (cond (true? (get previous "scope-changed")) " · target catalogue changed; compare denominators before interpreting progress."
               (true? (get previous "model-changed")) " · model changed; previous agreement is historical."
               " · same target catalogue and model.")]
       (when-let [delta (get previous "delta")]
         [:p "Change since that report: " (delta "evaluated-cases") " evaluated cases and "
          (delta "checked-conditions") " checked conditions."])])]
   [:details [:summary "Scope and reproducibility"] [:p (report "scope")]
    [:dl [:dt "Catalogue identity"] [:dd [:code (report "registry")]]
     [:dt "Model identity"] [:dd [:code (report "model")]]
     [:dt "Ledger head"] [:dd [:code (get-in report ["ledger" "head"])]]]]
   [:a {:href "/verification"} "Refresh report"]])

(defn page []
  (def loaded (protect (read-report)))
  [:html {:lang "en"}
   [:head [:meta {:charset "utf-8"}] [:meta {:name "viewport" :content "width=device-width,initial-scale=1"}]
    [:title "PowerSpike · Verification progress"] [:link {:rel "stylesheet" :href "/assets/app.css"}]]
   [:body [:header {:class "top"} [:a {:class "brand" :href "/"} "POWER" [:span "SPIKE"]]
           [:a {:href "/" :class "verification-back"} "Back to comparisons"]]
    [:main {:class "content"} [:h1 "Verification progress"]
     (if (first loaded) (dashboard (loaded 1)) [:p "Verification report unavailable. Combat accuracy remains unverified."])]]])
