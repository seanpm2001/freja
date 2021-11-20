(import ./state)
(import freja/events :as e)
(import freja/new_gap_buffer :as gb)
(import freja/render_new_gap_buffer :as rgb)
(import freja/theme)
(import freja/checkpoint)
(import spork/path)

(def open-files
  @{})

(defn open-file*
  [compo-state]
  (state/push-buffer-stack compo-state))

(defn open-file
  [path &opt line column]

  (if-let [comp-state (open-files path)]
    (open-file* comp-state)
    (let [new-state (state/ext->editor (path/ext path) {:path path})]
      (put open-files path new-state)
      (open-file* (tracev new-state))))

  (let [gb (get-in open-files [path :editor :gb])]
    (when line
      (rgb/goto-line-number gb line))

    (when column
      (gb/move-n gb column))))

(comment
  (open-file "freja/main.janet")
  #
)
