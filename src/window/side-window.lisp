(in-package :lem-core)

(defclass side-window (floating-window) ())

(defun side-window-p (window)
  (typep window 'side-window))

;; leftside
(defclass leftside-window (side-window) ())

(defun make-leftside-window (buffer &key (width 30))
  (cond ((frame-leftside-window (current-frame))
         (with-current-window (frame-leftside-window (current-frame))
           (switch-to-buffer buffer)))
        (t
         (setf (frame-leftside-window (current-frame))
               (make-instance 'leftside-window
                              :buffer buffer
                              :x 0
                              :y (topleft-window-y (current-frame))
                              :width width
                              :height (max-window-height (current-frame))
                              :use-modeline-p nil
                              :background-color nil
                              :border 0))
         (balance-windows))))

(defun delete-leftside-window ()
  (delete-window (frame-leftside-window (current-frame)))
  (setf (frame-leftside-window (current-frame)) nil)
  (balance-windows))

(defun resize-leftside-window (width)
  (let ((window (frame-leftside-window (current-frame))))
    (window-set-size window width (window-height window))
    (balance-windows)))

(defun resize-leftside-window-relative (offset)
  (let* ((window (frame-leftside-window (current-frame)))
         (new-width (+ (window-width window) offset)))
    (when (< 2 new-width)
      (window-set-size window
                       new-width
                       (window-height window))
      (balance-windows)
      t)))

;; rightside
(defclass rightside-window (side-window) ())

(defun make-rightside-window (buffer &key (width 30))
  (cond ((frame-rightside-window (current-frame))
         (with-current-window (frame-rightside-window (current-frame))
           (switch-to-buffer buffer)))
        (t
         (setf (frame-rightside-window (current-frame))
               (make-instance 'rightside-window
                              :buffer buffer
                              :x (1+ (- (display-width) width))
                              :y (topleft-window-y (current-frame))
                              :width width
                              :height (max-window-height (current-frame))
                              :use-modeline-p nil
                              :background-color nil
                              :border 1
                              :border-shape :left-border))
         (balance-windows))))

(defun delete-rightside-window ()
  (delete-window (frame-rightside-window (current-frame)))
  (setf (frame-rightside-window (current-frame)) nil)
  (balance-windows))

;; TODO: resize rightside window
