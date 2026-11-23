;;; ==========================================================================
;;; PFLOCKATT.lsp  --  lock or unlock every attribute in the blocks you pick.
;;; STANDALONE: not part of the suite, not loaded by pf-load.  APPLOAD it on
;;; its own.
;;;
;;; PFLOCKATT   pick blocks, answer Lock or Unlock.  For each block NAME
;;;             picked (not just each insert), every attribute gets that
;;;             Lock position:
;;;               1. the block definition (what BEDIT shows)
;;;               2. the hidden copies a dynamic block makes (*U..), so the
;;;                  placed inserts match without a BSAVE
;;;               3. every insert of that block in the drawing, through
;;;                  ATTSYNC -- a placed attribute keeps its own copy of the
;;;                  lock, and ActiveX can't change it there.
;;;
;;; Lock position = Yes  -> no grip on the attribute; code (entmod) and
;;;                         dynamic actions still move it.
;;; ATTSYNC sends every label back to where the definition puts it.  The
;;; suite puts dragged structure rows and plan labels back on its next run.
;;;
;;; Locking skips the tags in *pflock-keep-draggable* -- labels meant to be
;;; dragged by hand.  Unlocking does them all.
;;; ==========================================================================

(vl-load-com)

(setq *pflock-keep-draggable* '("PFPLABEL"))


;; (pflock:effective-name obj) -> the real block name, never *U47
(defun pflock:effective-name (obj / r)
  (setq r (vl-catch-all-apply 'vla-get-effectivename (list obj)))
  (if (vl-catch-all-error-p r) (vla-get-name obj) r))

;; (pflock:picked-block-names ss) -> unique effective names in the selection
(defun pflock:picked-block-names (ss / i name names)
  (setq i 0)
  (repeat (sslength ss)
    (setq name (pflock:effective-name (vlax-ename->vla-object (ssname ss i))))
    (if (not (member (strcase name) (mapcar 'strcase names)))
      (setq names (cons name names)))
    (setq i (1+ i)))
  (reverse names))

;; (pflock:definitions-for name) -> the definition NAME plus every hidden
;;   *U copy that an insert of NAME is using
(defun pflock:definitions-for (name / ss i obj real defs)
  (setq defs (list name))
  (if (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 (strcat name ",`*U*")))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq obj  (vlax-ename->vla-object (ssname ss i))
              real (vla-get-name obj))
        (if (and (= (strcase (pflock:effective-name obj)) (strcase name))
                 (not (member (strcase real) (mapcar 'strcase defs))))
          (setq defs (cons real defs)))
        (setq i (1+ i)))))
  defs)

;; (pflock:set-definition-locks def-name lock?) -> (changed . kept-draggable)
(defun pflock:set-definition-locks (def-name lock? / blocks def changed kept tag)
  (setq blocks  (vla-get-blocks (vla-get-activedocument (vlax-get-acad-object)))
        def     (vla-item blocks def-name)
        changed 0
        kept    0)
  (vlax-for item def
    (if (= (vla-get-objectname item) "AcDbAttributeDefinition")
      (progn
        (setq tag (strcase (vla-get-tagstring item)))
        (cond
          ((and lock? (member tag (mapcar 'strcase *pflock-keep-draggable*)))
           (setq kept (1+ kept)))
          ((/= (= (vla-get-lockposition item) :vlax-true) lock?)
           (vla-put-lockposition item (if lock? :vlax-true :vlax-false))
           (setq changed (1+ changed)))))))
  (cons changed kept))

;; (pflock:count-placed name) -> (attributes . locked) over every insert of NAME
(defun pflock:count-placed (name / ss i obj total locked)
  (setq total 0 locked 0)
  (if (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 (strcat name ",`*U*")))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq obj (vlax-ename->vla-object (ssname ss i)))
        (if (and (= (strcase (pflock:effective-name obj)) (strcase name))
                 (= (vla-get-hasattributes obj) :vlax-true))
          (foreach att (vlax-safearray->list (vlax-variant-value (vla-getattributes obj)))
            (setq total (1+ total))
            (if (= (vla-get-lockposition att) :vlax-true) (setq locked (1+ locked)))))
        (setq i (1+ i)))))
  (cons total locked))

;; (pflock:run ss lock?) -> list of (name changed kept locked-placed placed)
;;   the work, no prompts -- c:PFLOCKATT asks, this does
(defun pflock:run (ss lock? / names result changed kept placed echo report)
  (setq names (pflock:picked-block-names ss)
        echo  (getvar "CMDECHO"))
  (vla-startundomark (vla-get-activedocument (vlax-get-acad-object)))
  (setvar "CMDECHO" 0)
  (foreach name names
    (setq changed 0 kept 0)
    (foreach def-name (pflock:definitions-for name)
      (setq result  (pflock:set-definition-locks def-name lock?)
            changed (+ changed (car result))
            kept    (max kept (cdr result))))
    (command "_.ATTSYNC" "_Name" name)
    (while (> (getvar "CMDACTIVE") 0) (command "_Yes"))
    (setq placed (pflock:count-placed name)
          report (cons (list name changed kept (cdr placed) (car placed)) report)))
  (setvar "CMDECHO" echo)
  (vla-endundomark (vla-get-activedocument (vlax-get-acad-object)))
  (reverse report))

(defun c:PFLOCKATT ( / ss answer report)
  (prompt "\nPick the blocks (one of each kind is enough): ")
  (if (setq ss (ssget '((0 . "INSERT"))))
    (progn
      (initget "Lock Unlock")
      (setq answer (getkword "\nAttributes: [Lock/Unlock] <Lock>: ")
            report (pflock:run ss (/= answer "Unlock")))
      (foreach row report
        (princ (strcat "\n  " (nth 0 row) ":  " (itoa (nth 1 row))
                       " attribute(s) changed in the definitions"
                       (if (> (nth 2 row) 0) (strcat ", " (itoa (nth 2 row)) " left draggable") "")
                       ".  Placed: " (itoa (nth 3 row)) " of " (itoa (nth 4 row)) " locked.")))
      (princ (strcat "\n" (itoa (length report)) " block name(s) done.  One U puts it all back."))))
  (princ))

(princ "\nPFLOCKATT loaded.  Type PFLOCKATT.")
(princ)
