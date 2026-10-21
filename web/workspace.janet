(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/calibration :as calibration)
(import ./saves :as saves)
(import ./config :as config)
(def model-identity engine/identity)
(defn report-context [result]
  (defn observed [row]
    (when row
      {:scenario-id (get-in row [:combat :scenario-id])
       :samples (get-in row [:combat :samples]) :metrics (get-in row [:combat :metrics])
       :damage-breakdown (get-in row [:combat :damage-breakdown])}))
  {:release config/version
   :observed {:selected (observed (result :selected)) :reference (observed (result :reference))}})

(defn report-dialog []
  [:dialog {:id "problem-report" :class "problem-report" :aria-labelledby "problem-report-title"}
   [:header [:h2 {:id "problem-report-title"} "Report a problem"]
    [:button {:type "button" :class "catalog-close" :data-report-action "close" :aria-label "Close problem report"} "×"]]
   [:p {:id "problem-report-context" :class "muted"}]
   [:p "Describe a result or interaction that seems wrong. The download includes this simulation and any pinned items for the developer to reproduce."]
   [:form {:id "problem-report-form"}
    [:label "What happened?" [:textarea {:name "actual" :rows 3 :maxlength 2000 :required true}]]
    [:label "What did you expect?" [:textarea {:name "expected" :rows 3 :maxlength 2000 :required true}]]
    [:label "Steps to reproduce (optional)" [:textarea {:name "steps" :rows 3 :maxlength 2000}]]
    [:p {:class "muted"} "Download the file, review it, then send it to the developer. Nothing is sent automatically. Include only information you want to share."]
    [:button {:type "submit" :class "apply"} "Download report"]]
   [:p {:id "problem-report-status" :role "status"}]])

(defn tools [result]
  (def definition (get-in result [:selected :combat :scenario]))
  [:details {:id "scenario-tools" :class "control-group scenario-tools" :data-preserve-attr "open"}
   [:summary [:span "Saved scenarios"] [:span {:class "muted"} "Save · share · import"]]
   (if definition
     [:div
      [:span {:id "scenario-data" :hidden true :data-json (util/encode-json {:format "powerspike-scenario" :version 1 :scenario definition})}]
      [:span {:id "workspace-data" :hidden true :data-json (when (not (result :reference-error)) (saves/encode result))}]
      [:span {:id "problem-report-data" :hidden true :data-json (when (not (result :reference-error)) (util/encode-json (report-context result)))}]
      (when (result :reference-error)
        [:p {:class "warning"} "Clear or replace the invalid pinned items before saving or sharing."])
      (when (and (get-in result [:state :savedmodel]) (not= engine/identity (get-in result [:state :savedmodel])))
        [:p {:class "warning"} "The saved model differs from this release. Its exact patch snapshot is retained, and this result uses the current model. Use the original release to reproduce the original calculation."])
      [:div {:class "scenario-actions"}
       [:input {:id "scenario-name" :type "text" :maxlength 80 :aria-label "Scenario name" :placeholder "Scenario name"}]
       (map (fn [[action caption]]
              [:button {:type "button" :data-scenario-action action
                        :data-attr:disabled (if (result :reference-error) "true" "$busy || $evaluationerror")} caption])
            [["save" "Save locally"] ["export" "Export JSON"] ["share" "Create share link"]])]
      [:label "Share link" [:input {:id "scenario-link" :type "text" :readonly true}]]
      [:div {:class "scenario-actions"}
       [:select {:id "saved-scenarios" :aria-label "Locally saved scenarios"} [:option {:value ""} "Choose a local save"]]
       [:button {:type "button" :data-scenario-action "load"} "Load saved"]
       [:button {:type "button" :data-scenario-action "remove"} "Remove saved"]]
      [:p {:class "muted"} "Saves stay in this browser. Links and exports include pinned items when comparing builds, along with the exact patch, snapshot, model, trial seed and fight settings. Keep the retained snapshot for offline reproduction."]]
     [:p "Choose a combat scenario to save its result."])
   [:details [:summary "Import a scenario"]
    [:label "JSON file" [:input {:id "scenario-file" :type "file" :accept ".json,application/json"}]]
    [:label "Scenario JSON" [:textarea {:id "scenario-json" :rows 5 :maxlength 65536 :data-bind:scenariojson true}]]
    [:button {:id "import-scenario" :type "button" :class "apply" :data-on:click "@post('/scenario/import')"} "Load scenario"]]
   [:p {:id "scenario-storage-status" :role "status"}]])
(defn evidence [result]
  (def package (result :package))
  (def manifest (package :manifest))
  (def sources [;(get manifest "sources" []) ;(get package :rune-sources [])])
  [:details {:id "source-evidence" :class "scope-panel source-evidence"}
   [:summary "Source records & model identity"]
   [:dl
    [:dt "Data Dragon"] [:dd (package :patch)]
    [:dt "CommunityDragon"] [:dd (get package :communitydragon "Unavailable")]
    [:dt "Snapshot SHA-256"] [:dd [:code (package :snapshot)]]
    [:dt "Parser"] [:dd (get manifest "parser" (get package :parser "Unavailable"))]
    [:dt "Combat model"] [:dd [:code engine/identity]]
    [:dt "Providers retained"] [:dd (length sources)]]
   [:p "Available source records and interpreted mechanics are separate from in-game checks. Unsupported effects remain in each result's coverage notes."]
   [:div {:class "source-records"}
    [:table [:thead [:tr [:th "Source"] [:th "SHA-256"]]]
     [:tbody (map (fn [record]
                    [:tr [:td [:a {:href (record "url") :target "_blank" :rel "noopener noreferrer"} (record "url")]]
                     [:td [:code (record "sha256")]]]) sources)]]]
   (when (get manifest "initial") [:p "This is the bundled catalog excerpt. Refresh this patch to retain complete spell and effect records with their source hashes."])
   [:h3 "Calibration by mechanic family"]
   [:p "The five retained Annie captures check their original stat conditions on 26.19. Other families await reviewed measurements; missing measurements are not measured zero."]
   [:ul (map |[:li (string $) " · awaiting reviewed measurements"] calibration/families)]])
