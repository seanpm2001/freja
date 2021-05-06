(use jaylib)

(import spork/test)
(import ./code_api :prefix "")
(import ./textfield :as t)
#(import ./../misc/frp3 :prefix "")
(import ./../misc/frp4 :prefix "")
(import ./../backwards2 :prefix "")
(use ./highlighting)
(import ./text_rendering :prefix "")
(import ./text_rendering_ints :prefix "" :fresh true)
(import ../build/text-rendering :prefix "")
(import ./input :prefix "")
(import ./file_handling :prefix "")
(import ./dumb :prefix "")
(import ./find_row_etc :prefix "")
(import ./new_gap_buffer :prefix "")
(import ./new_gap_buffer_util :prefix "")
(import ./render_new_gap_buffer :prefix "")
(import ./theme :prefix "")
(import spork/netrepl)
(import ./font :prefix "")
(import ./state :prefix "")
(setdyn :pretty-format "%.40M")

(defmacro defonce
  "Define a value once."
  [name & more]
  (when (nil? (dyn name))
    ~(def ,name ,;more)))

(defmacro varonce
  "Var a value once."
  [name & more]
  (when (nil? (dyn name))
    ~(var ,name ,;more)))

(comment
  (top-env 'ta/split-words))

(var top-env (fiber/getenv (fiber/current)))
(var font nil)
(var loop-fiber nil)

(var conf nil)
(var conf2 nil)
(var conf3 nil)

(var data @{:latest-res @""
            :focus gb-data
            :quit false
            :top-env top-env})

(defn select-keys
  [t ks]
  (def nt (table/new (length ks)))
  (loop [k :in ks
         :let [v (t k)]]
    (put nt k v))
  nt)

(defn dumb-set
  "Creates a table that acts like a set, where the value is equal to the key."
  [& ks]
  (table ;(flatten (map (fn [k] [k k]) ks))))

(defn remove-keys
  [t ks]
  (def nt @{})
  (loop [[k v] :pairs t
         :when (not (ks k))]
    (put nt k v))
  nt)

(varfn frame
  [dt]
  (clear-background :blank)
  #  (draw-text* (conf :text) (string (data :latest-res)) [605 660] :blue)
  )

(var texture nil)

(varfn draw-frame
  [dt]
  (begin-texture-mode texture)
  (rl-push-matrix)

  (try (frame dt)
    ([err fib]
      (print "hmm")
      (put data :latest-res (string "Error: " err))
      (print (debug/stacktrace fib err))))

  (rl-pop-matrix)
  (end-texture-mode)

  (rl-push-matrix)

  (draw-texture-pro
    (get-render-texture texture)
    [0
     0
     (* 1 500)
     (* 1 (- 500))]
    [(+ (get-in gb-data [:position 0])
        (get-in gb-data [:size 0]))
     10
     500 500]
    [0 0]
    0
    :white)
  
  (rl-pop-matrix))


(defn styling-worker
  [parent]
  (def content (thread/receive))
  (def res (peg/match styling-grammar content))
  (:send parent [:hl res]))

(array/push draws {:draw (fn [_ data] (draw-frame (data :dt)))})

#_(array/concat fs [gb-data])

(varfn internal-frame
  []
  (def dt (get-frame-time))

  (put data :dt dt)
  
  (put data :changed-focus false)
  (try
    (loop [o :in focus-checks]
      (when (and (o :focus?)
                 (:focus? o data))
        (put data :focus o)
        (put data :changed-focus true)))
    ([err fib]
      (print "draws")
      (put data :latest-res (string "Error: " err))
      (print (debug/stacktrace fib err))))
  (comment
    (unless (data :changed-focus)
      (put data :focus gb-data)))
  
  (comment
    (when-let [active-data (data :focus)]
      (handle-mouse mouse-data active-data)
      (handle-scroll active-data))
    )
  
  (when (window-resized?)
    (put gb-data :resized true))
  
  (def [x-scale y-scale] screen-scale)
  
  (def w (* x-scale (get-screen-width)))
  (def h (* y-scale (get-screen-height)))
  
  (comment (loop [f :in updates]
             (:update f data)))
  
  (def changed (or (gb-data :changed)
                   (gb-data :changed-nav)
                   (gb-data :changed-scroll)))
  
  (if (gb-data :changed)
    (-> gb-data
        (put :not-changed-timer 0)
        (put :styled false))
    (update gb-data :not-changed-timer + dt))
  
  (when (and (not (gb-data :styled))
             (>= (gb-data :not-changed-timer) 0.3)) ## delay before re-styling
    (def thread (thread/new styling-worker 32))
    (:send thread (content gb-data))
    
    (put gb-data :styled true))
  
  # (gb-pre-render debug-data)
  (comment
    (cond
      
      (= (data :focus) file-open-data)
      (gb-pre-render file-open-data)
      
      (= (data :focus) search-data)
      (gb-pre-render search-data)
      
      nil))
  
  (begin-drawing)
  
  (clear-background (colors :background))  
  
  (render-all fs)
  
  
  
  (comment (rl-viewport 0 0 w h)
    (rl-matrix-mode :rl-projection)
    (rl-load-identity)
    (rl-ortho 0 w h 0 0 1) # Recalculate internal projection matrix      
    (rl-matrix-mode :rl-modelview) # Enable internal modelview matrix        
    (rl-load-identity)) # Reset internal modelview matrix
  
  
  #(when changed (print "render"))
  #(gb-render-text debug-data)
  
  #(print)
  
  #(print)
  
  (cond (= (data :focus) file-open-data)
    (gb-render-text file-open-data)
    
    (= (data :focus) search-data)
    (gb-render-text search-data)
    
    nil)
  
  (when-let [focus (cond
                     (= (data :focus) gb-data) gb-data
                     (= (data :focus) file-open-data) file-open-data
                     (= (data :focus) search-data) search-data)]
    #    (render-cursor focus)
    )

  (trigger dt)
  
  (try
    (loop [f :in draws]
      (:draw f data)
      )
    ([err fib]
      (print "draws")
      (put data :latest-res (string "Error: " err))
      (print (debug/stacktrace fib err))))

  (end-drawing)

  (try
    (let [[kind res] (thread/receive 0)]
      (case kind
        :hl
        (do
          (-> gb-data
              (put :highlighting res)
              (put :changed-styling true)))

        # else
        (print "unmatched message"))
      :ok)
    ([err fib])))

(comment
  (ez-gb file-open-data)
  (ez-gb gb-data)

  (focus {:context data :id :main}))

(defn loop-it
  []

  (set loop-fiber
       (ev/call (fn [] (while true
                         (when (data :quit)
                           (close-window)
                           (os/exit)
                           (error "QUIT!"))

                         (try
                           (do (internal-frame)
                             (ev/sleep 0.01))
                           ([err fib]
                             (let [path "text_experiment_dump"]
                               (debug/stacktrace fib err)
                               ## TODO:  Dump-state
                               #(dump-state path gb-data)
                               (print "Dumped state to " path))
                             (print (debug/stacktrace fib err))
                             (ev/sleep 1))))))))

(defn load-font
  [text-data opts]
  (let [font (load-font-ex (opts :font-path) (opts :size) (opts :glyphs))]

    (put opts :font font)

    (def t (freeze opts))

    (put text-data :conf t)
    (put text-data :sizes (glyphs->size-struct t (t :glyphs)))

    {:text t
     :colors colors}))

(defn run-init-file
  []
  (def env (data :top-env))
  (try
    (do
      (dofile "./init.janet"
              #             :env (fiber/getenv (fiber/current))
              :env env)
      (merge-into env env))
    ([err fib]
      (print "nope")
      (print (debug/stacktrace fib err)))))

(defn start
  []
  (try
    (do 
      (set-config-flags :vsync-hint)
      (set-config-flags :window-highdpi)
      (set-config-flags :window-resizable)
      
      (init-window 1310 700
                   "Textfield")
      
      (set-exit-key :f12) ### doing this because I don't have KEY_NULL

      (let [[xs ys] (get-window-scale-dpi)]
        (put screen-scale 0 xs)
        (put screen-scale 1 ys))

      (let [[x-scale y-scale] screen-scale
            tc @{:font-path "./assets/fonts/Monaco.ttf"
                 :size (* 14 x-scale)
                 :line-height 1.2
                 :mult (/ 1 x-scale)
                 :glyphs default-glyphs
                 :spacing 0.5}

            tc2 @{:font-path "./assets/fonts/Texturina-VariableFont_opsz,wght.ttf"
                  :line-height 1.1
                  :size (* 20 x-scale)
                  :mult (/ 1 x-scale)
                  :glyphs (string/bytes " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHI\nJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmn\nopqrstuvwxyz{|}~\\")
                  :spacing 2}]

        (set conf (load-font gb-data tc))
        (put gb-data :context data)
        (put gb-data :screen-scale [x-scale y-scale])
        (put gb-data :colors colors)
        
        (set conf (load-font search-data tc))
        (put search-data :context data)
        (put search-data :screen-scale [x-scale y-scale])
        (put search-data :colors colors)
        
        (set conf2 (load-font file-open-data tc))
        (put file-open-data :context data)
        (put file-open-data :screen-scale [x-scale y-scale])
        (put file-open-data :colors colors)
        
        (array/push updates file-open-data)
        
        (array/push updates search-data)


        (put data :mouse (new-mouse-data))

        (set-target-fps 60)

        (run-init-file)

        (set texture (load-render-texture 500 500))

        (loop-it)))
    ([err fib]
      (print "error! " err)
      (debug/stacktrace fib err)

      (let [path "text_experiment_dump"]
        ## TODO:  Dump-state
        #(dump-state path gb-data)
        (print "Dumped state to " path))

      (close-window))))

(def env (fiber/getenv (fiber/current)))

(var server nil)

(defn main [& args]
  (set server (netrepl/server "127.0.0.1" "9365" env))
  (pp args)
  (when-let [file (get args 1)]
    (load-file gb-data file))
  (start))
