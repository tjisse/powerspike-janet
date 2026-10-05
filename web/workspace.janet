(import ../src/powerspike/data-util :as util)
(import ../src/powerspike/engine :as engine)
(import ../src/powerspike/calibration :as calibration)
(def model-identity engine/identity)
(defn tools [result]
  (def definition (get-in result [:selected :combat :scenario]))
  [:details {:id "scenario-tools" :class "control-group scenario-tools" :data-preserve-attr "open"}
   [:summary [:span "Saved scenarios"] [:span {:class "muted"} "Save · share · import"]]
   (if definition
     [:div
      [:span {:id "scenario-data" :hidden true :data-json (util/encode-json {:format "powerspike-scenario" :version 1 :scenario definition})}]
      (when (and (get-in result [:state :savedmodel]) (not= engine/identity (get-in result [:state :savedmodel])))
        [:p {:class "warning"} "The saved model differs from this release. Its exact patch snapshot is retained, and this result uses the current model. Use the original release to reproduce the original calculation."])
      [:div {:class "scenario-actions"}
       [:input {:id "scenario-name" :type "text" :maxlength 80 :aria-label "Scenario name" :placeholder "Scenario name"}]
       [:button {:type "button" :data-scenario-action "save" :data-attr:disabled "$busy"} "Save locally"]
       [:button {:type "button" :data-scenario-action "export" :data-attr:disabled "$busy"} "Export JSON"]
       [:button {:type "button" :data-scenario-action "share" :data-attr:disabled "$busy"} "Create share link"]]
      [:label "Share link" [:input {:id "scenario-link" :type "text" :readonly true}]]
      [:div {:class "scenario-actions"}
       [:select {:id "saved-scenarios" :aria-label "Locally saved scenarios"} [:option {:value ""} "Choose a local save"]]
       [:button {:type "button" :data-scenario-action "load"} "Load saved"]
       [:button {:type "button" :data-scenario-action "remove"} "Remove saved"]]
      [:p {:class "muted"} "Saves stay in this browser. Links and exports contain the exact patch, snapshot, model, trial seed and fight settings. Keep the retained snapshot for offline reproduction."]]
     [:p "Choose a combat scenario to save its result."])
   [:details [:summary "Import a scenario"]
    [:label "JSON file" [:input {:id "scenario-file" :type "file" :accept ".json,application/json"}]]
    [:label "Scenario JSON" [:textarea {:id "scenario-json" :rows 5 :maxlength 65536 :data-bind:scenariojson true}]]
    [:button {:id "import-scenario" :type "button" :class "apply" :data-on:click "@post('/scenario/import')"} "Load scenario"]]
   [:p {:id "scenario-storage-status" :role "status"}]])
(defn evidence [result]
  (def package (result :package))
  (def manifest (package :manifest))
  [:details {:id "source-evidence" :class "scope-panel source-evidence"}
   [:summary "Source records & model identity"]
   [:dl
    [:dt "Data Dragon"] [:dd (package :patch)]
    [:dt "CommunityDragon"] [:dd (get package :communitydragon "Unavailable")]
    [:dt "Snapshot SHA-256"] [:dd [:code (package :snapshot)]]
    [:dt "Parser"] [:dd (get manifest "parser" (get package :parser "Unavailable"))]
    [:dt "Combat model"] [:dd [:code engine/identity]]
    [:dt "Providers retained"] [:dd (length (get manifest "sources" []))]]
   [:p "Available source records and interpreted mechanics are separate from in-game checks. Unsupported effects remain in each result's coverage notes."]
   [:div {:class "source-records"}
    [:table [:thead [:tr [:th "Source"] [:th "SHA-256"]]]
     [:tbody (map (fn [record]
                    [:tr [:td [:a {:href (record "url") :target "_blank" :rel "noopener noreferrer"} (record "url")]]
                     [:td [:code (record "sha256")]]]) (get manifest "sources" []))]]]
   (when (get manifest "initial") [:p "This is the bundled catalog excerpt. Refresh this patch to retain complete spell and effect records with their source hashes."])
   [:h3 "Calibration by mechanic family"]
   [:p "The five retained Annie captures check their original stat conditions on 26.19. Other families await reviewed measurements; missing measurements are not measured zero."]
   [:ul (map |[:li (string $) " · awaiting reviewed measurements"] calibration/families)]])
