(defpackage :lem/peek-source
  (:use :cl :lem)
  (:export :with-collecting-sources
           :with-appending-source))
(in-package :lem/peek-source)

(defvar *collector*)

(defclass collector ()
  ((buffer :initarg :buffer
           :reader collector-buffer)
   (count :initform 0
          :accessor collector-count)))

(defvar *peek-window*)
(defvar *source-window*)
(defvar *parent-window*)

(define-minor-mode peek-source-mode
    (:name "Peek"
     :keymap *peek-source-keymap*))

(define-key *peek-source-keymap* "Return" 'peek-source-select)

(defclass peek-window (floating-window) ())

(defmethod lem::%delete-window :before ((peek-window peek-window))
  (finalize-peek-source))

(defun finalize-peek-source ()
  (finalize-highlight-overlays)
  (setf (current-window) *parent-window*)
  (delete-window *source-window*))

(defun set-move-function (start end move-function)
  (put-text-property start end 'move-function move-function))

(defun get-move-function (point)
  (with-point ((point point))
    (line-start point)
    (text-property-at point 'move-function)))

(defun make-two-side-by-side-windows (buffer)
  (let* ((x-margin 4)
         (y-margin 2)
         (width (- (floor (display-width) 2) 2 x-margin))
         (height (- (display-height) 2 (* 2 y-margin))))
    (let* ((peek-window (make-instance 'peek-window
                                       :buffer buffer
                                       :x (+ 1 x-margin)
                                       :y (+ 1 y-margin)
                                       :width width
                                       :height height
                                       :use-border t))
           (source-window (make-floating-window :buffer (make-buffer "*source*" :temporary t :enable-undo-p nil)
                                                :x (+ (window-x peek-window) (window-width peek-window) 2)
                                                :y (+ 1 y-margin)
                                                :width width
                                                :height height
                                                :use-border t)))
      (list peek-window source-window))))

(defun display (collector)
  (destructuring-bind (peek-window source-window)
      (make-two-side-by-side-windows (collector-buffer collector))

    (setf *parent-window* (current-window))
    (setf *peek-window* peek-window)
    (setf *source-window* source-window)

    (setf (current-window) peek-window)
    (peek-source-mode t)

    (add-hook (window-leave-hook *peek-window*) 'peek-source-quit)

    (show-matched-line)))

(defun make-peek-source-buffer ()
  (let ((buffer (make-buffer "*peek-source*" :temporary t :enable-undo-p t)))
    (setf (variable-value 'line-wrap :buffer buffer) nil)
    buffer))

(defun call-with-collecting-sources (function)
  (let ((*collector* (make-instance 'collector :buffer (make-peek-source-buffer))))
    (funcall function *collector*)
    (unless (zerop (collector-count *collector*))
      (display *collector*))))

(defmacro with-collecting-sources ((collector) &body body)
  `(call-with-collecting-sources (lambda (,collector) ,@body)))

(defun call-with-appending-source (insert-function move-function)
  (let ((point (buffer-point (collector-buffer *collector*))))
    (with-point ((start point))
      (funcall insert-function point)
      (unless (start-line-p point)
        (insert-string point (string #\newline) :read-only t))
      (set-move-function start point move-function))
    (incf (collector-count *collector*))))

(defmacro with-appending-source ((point &key move-function) &body body)
  `(call-with-appending-source (lambda (,point) ,@body)
                               ,move-function))

;;;
(define-attribute match-line-attribute
  (t :background "#444444"))

(defun get-matched-point (&key temporary)
  (alexandria:when-let* ((move (get-move-function (buffer-point (window-buffer *peek-window*))))
                         (point (funcall move :temporary temporary)))
    point))

(defun show-matched-line ()
  (alexandria:when-let* ((point (get-matched-point :temporary t))
                         (buffer (point-buffer point)))
    (with-current-window *source-window*
      (switch-to-buffer buffer nil nil)
      (update-highlight-overlay point)
      (move-point (buffer-point buffer) point)
      (window-see (current-window)))))

(defmethod execute :after ((mode peek-source-mode) command argument)
  (when (eq (current-window) *peek-window*)
    (show-matched-line)))

(define-command peek-source-select () ()
  (alexandria:when-let ((point (get-matched-point :temporary nil)))
    (let ((line (line-number-at-point point)))
      (peek-source-quit)
      (switch-to-buffer (point-buffer point))
      (move-to-line (current-point) line))))

(define-command peek-source-quit () ()
  (setf (current-window) *parent-window*)
  (start-timer
   (make-idle-timer (lambda ()
                      (delete-window *peek-window*)
                      (delete-window *source-window*)))
   0))

;;;
(defvar *highlight-overlays* '())

(defun set-highlight-overlay (point)
  (let ((overlay (make-overlay point point (ensure-attribute 'match-line-attribute))))
    (push overlay *highlight-overlays*)
    (overlay-put overlay :display-line t)
    (setf (buffer-value (point-buffer point) 'highlight-overlay) overlay)))

(defun get-highlight-overlay (point)
  (buffer-value (point-buffer point) 'highlight-overlay))

(defun update-highlight-overlay (point)
  (let ((overlay (get-highlight-overlay point)))
    (cond (overlay
           (move-point (overlay-start overlay) point)
           (move-point (overlay-end overlay) point))
          (t
           (set-highlight-overlay point)))))

(defun finalize-highlight-overlays ()
  (dolist (overlay *highlight-overlays*)
    (buffer-unbound (overlay-buffer overlay) 'highlight-overlay)
    (delete-overlay overlay))
  (setf *highlight-overlays* '()))

;;;
(defun run-grep (string directory)
  (with-output-to-string (output)
    (uiop:run-program string
                      :directory directory
                      :output output
                      :error-output output)))

(defun parse-grep-result (text)
  (let* ((text (string-right-trim '(#\newline) text))
         (lines (uiop:split-string text :separator '(#\newline)))
         (file-line-content-tuples
           (mapcar (lambda (line)
                     (destructuring-bind (file line-number content)
                         (ppcre:split ":" line :limit 3)
                       (list file
                             (parse-integer line-number)
                             content)))
                   lines)))
    file-line-content-tuples))

(defun move (directory file line-number temporary)
  (setf temporary nil) ;TODO
  (let ((buffer (find-file-buffer (merge-pathnames file directory) :temporary temporary)))
    (with-point ((point (copy-point (buffer-point buffer) :temporary)))
      (move-to-line point line-number)
      point)))

(defun make-move-function (directory file line-number)
  (lambda (&key temporary)
    (move directory file line-number temporary)))

(defun get-content-string (start)
  (with-point ((start start)
               (end start))
    (line-start start)
    (next-single-property-change start :content-start)
    (character-offset start 1)
    (line-end end)
    (points-to-string start end)))

(defun change-grep-buffer (start end old-len)
  (declare (ignore end old-len))
  (let ((string (get-content-string start))
        (move (get-move-function start)))
    (with-point ((point (funcall move :temporary nil)))
      (with-point ((start point)
                   (end point))
        (line-start start)
        (line-end end)
        (buffer-undo-boundary (point-buffer start))
        (delete-between-points start end)
        (insert-string start string)
        (buffer-undo-boundary (point-buffer start)))))
  (show-matched-line))

(define-command grep (string &optional (directory (buffer-directory)))
    ((prompt-for-string ": " :initial-value "grep -nH "))
  (let ((result (parse-grep-result (run-grep string directory))))
    (if (null result)
        (editor-error "No match")
        (with-collecting-sources (collector)
          (loop :for (file line-number content) :in result
                :do (with-appending-source (point :move-function (make-move-function directory file line-number))
                      (insert-string point file :attribute 'lem/sourcelist:title-attribute :read-only t)
                      (insert-string point ":" :read-only t)
                      (insert-string point (princ-to-string line-number)
                                     :attribute 'lem/sourcelist:position-attribute
                                     :read-only t)
                      (insert-string point ":" :read-only t :content-start t)
                      (insert-string point content)))
          (add-hook (variable-value 'after-change-functions :buffer (collector-buffer collector))
                    'change-grep-buffer)))))
