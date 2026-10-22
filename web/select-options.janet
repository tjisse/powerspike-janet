(import janet-html :as html)

# Build escaped, unselected options once for a render, then insert each slot's
# selected marker at its recorded byte offset. No HTML parsing or shared cache.
(defn prepare [choices]
  (def body @"")
  (def offsets @{})
  (each [id caption] choices
    (def value (string id))
    (assert (not (has-key? offsets value)) "Select option values must be unique.")
    (buffer/push-string body "<option value=\"" (html/escape value) "\"")
    (put offsets value (length body))
    (buffer/push-string body ">" (html/escape caption) "</option>"))
  {:body (string body) :offsets (table/to-struct offsets)})

(defn selected [options id]
  (def body (options :body))
  (def offset (get (options :offsets) (string id)))
  (html/raw (if offset (string (string/slice body 0 offset) " selected=\"\"" (string/slice body offset)) body)))
