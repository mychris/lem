(defsystem "lem-vi-mode"
  :depends-on ("esrap"
               "closer-mop"
               "lem"
               "cl-ppcre"
               "parse-number"
               "cl-package-locks"
               "alexandria")
  :serial t
  :components ((:file "core")
               (:file "word")
               (:file "visual")
               (:file "jump-motions")
               (:module "commands-dir"
                :pathname "commands"
                :components
                ((:file "utils")))
               (:file "commands")
               (:file "options")
               (:file "ex-core")
               (:file "ex-parser")
               (:file "ex-command")
               (:file "ex")
               (:file "binds")
               (:file "vi-mode"))
  :in-order-to ((test-op (test-op "lem-vi-mode/tests"))))

(defsystem "lem-vi-mode/tests"
  :depends-on ("lem"
               "lem-vi-mode"
               "lem-fake-interface"
               "rove"
               "cl-ppcre"
               "cl-interpol"
               "named-readtables"
               "alexandria")
  :components
  ((:module "tests"
    :components
    ((:file "motion" :depends-on ("utils"))
     (:file "utils"))))
  :perform (test-op (op c) (symbol-call :rove '#:run c)))
