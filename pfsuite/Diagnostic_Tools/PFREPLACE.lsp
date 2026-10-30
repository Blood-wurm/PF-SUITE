;;; ==========================================================================
;;; PFREPLACE.lsp  --  test-drawing setup.  STANDALONE: not part of the suite,
;;; not loaded by pf-load.  APPLOAD it on its own.
;;;
;;; PFREPLACE   select block inserts (model space).  Each becomes
;;;             PFSUITE_CBI at the same insertion point, rotation and layer,
;;;             scale 1, in the PLAN state.  The originals are erased.
;;;             One U puts everything back.
;;;
;;; Size:  if the old block's name ends in a size PFSIZE_LU offers
;;;        ("..._04" -> 4), it is set.  Otherwise the block's default stays,
;;;        and the run lists it.
;;; Name:  an old attribute tagged PFNAME, NAME or ID is copied to PFNAME.
;;; Faces: the face codes assume a CBI's front faces +X at zero rotation.  If
;;;        the old blocks were drawn facing another way, set
;;;        *pfrep-rot-offset* (degrees, added to every rotation) and rerun.
;;; ==========================================================================

(vl-load-com)

(setq *pfrep-block*      "PFSUITE_CBI")
(setq *pfrep-vis*        "PFVIS")
(setq *pfrep-plan*       "PLAN")
(setq *pfrep-size*       "PFSIZE_LU")
(setq *pfrep-name-tag*   "PFNAME")
(setq *pfrep-name-from*  '("PFNAME" "NAME" "ID"))
(setq *pfrep-rot-offset* 0.0)


;; (pfrep:effname obj) -> the real block name, never *U47
(defun pfrep:effname (obj / r)
  (setq r (vl-catch-all-apply 'vla-get-effectivename (list obj)))
  (if (vl-catch-all-error-p r) (vla-get-name obj) r))

;; (pfrep:props obj) -> the dynamic properties | nil
(defun pfrep:props (obj / r)
  (setq r (vl-catch-all-apply
            '(lambda () (vlax-safearray->list
                          (vlax-variant-value (vla-getdynamicblockproperties obj))))))
  (if (not (vl-catch-all-error-p r)) r))

;; (pfrep:prop obj name) -> that property, case ignored | nil
(defun pfrep:prop (obj name / hit nm)
  (foreach p (pfrep:props obj)
    (setq nm (vl-catch-all-apply 'vla-get-propertyname (list p)))
    (if (and (null hit) (not (vl-catch-all-error-p nm)) (= (strcase nm) (strcase name)))
      (setq hit p)))
  hit)

;; (pfrep:allowed p) -> the allowed values as strings | nil
(defun pfrep:allowed (p / r)
  (setq r (vl-catch-all-apply
            '(lambda () (vlax-safearray->list (vlax-variant-value (vla-get-allowedvalues p))))))
  (if (not (vl-catch-all-error-p r))
    (mapcar '(lambda (v) (vl-princ-to-string (if (= (type v) 'VARIANT) (vlax-variant-value v) v))) r)))

;; (pfrep:put p v) -> T | nil   written in the property's own variant type
(defun pfrep:put (p v / cur)
  (setq cur (vl-catch-all-apply 'vla-get-value (list p)))
  (and p
       (not (vl-catch-all-error-p cur))
       (not (vl-catch-all-error-p
              (vl-catch-all-apply 'vla-put-value
                                  (list p (vlax-make-variant v (vlax-variant-type cur))))))))

;; (pfrep:atts obj) -> (("TAG" . attrib-object) ...)
(defun pfrep:atts (obj / r)
  (if (= :vlax-true (vla-get-hasattributes obj))
    (progn
      (setq r (vl-catch-all-apply
                '(lambda () (vlax-safearray->list (vlax-variant-value (vla-getattributes obj))))))
      (if (not (vl-catch-all-error-p r))
        (mapcar '(lambda (a) (cons (strcase (vla-get-tagstring a)) a)) r)))))

;; (pfrep:old-name obj) -> the first non-blank PFNAME / NAME / ID value | nil
(defun pfrep:old-name (obj / at hit v)
  (setq at (pfrep:atts obj))
  (foreach tg *pfrep-name-from*
    (if (and (null hit) (assoc tg at)
             (/= "" (setq v (vl-string-trim " " (vla-get-textstring (cdr (assoc tg at)))))))
      (setq hit v)))
  hit)

;; (pfrep:size-match nm allowed) -> the PFSIZE_LU value the name's suffix
;;   gives | nil.  The suffix is the text after the LAST underscore, compared
;;   as a number: "_04" matches "4".
(defun pfrep:size-match (nm allowed / i s n hit)
  (if (and (setq i (vl-string-position (ascii "_") nm 0 T))
           (setq s (substr nm (+ i 2)))
           (setq n (distof s 2)))
    (foreach a allowed
      (if (and (null hit) (distof a 2) (equal (distof a 2) n 1e-6)) (setq hit a))))
  hit)

;; (pfrep:tally key lst) -> lst with key's count raised by one
(defun pfrep:tally (key lst / c)
  (if (setq c (assoc key lst))
    (subst (cons key (1+ (cdr c))) c lst)
    (cons (cons key 1) lst)))


(defun c:PFREPLACE ( / doc ms ss i e ed obj nm new p nmv size n skips nosize mirr)
  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        ms  (vla-get-modelspace doc))
  (cond
    ((= 1 (getvar "BLOCKEDITOR"))
     (princ "\nPFREPLACE: close the Block Editor first."))
    ((null (tblsearch "BLOCK" *pfrep-block*))
     (princ (strcat "\nPFREPLACE: no " *pfrep-block* " in this drawing.  Insert one once, erase it, then rerun.")))
    ((null (progn (princ "\nSelect the blocks to replace: ")
                  (setq ss (ssget '((0 . "INSERT") (410 . "Model"))))))
     (princ "\nPFREPLACE: nothing selected."))
    (T
     (vla-startundomark doc)
     (setq n 0 i 0)
     (repeat (sslength ss)
       (setq e   (ssname ss i)
             i   (1+ i)
             ed  (entget e)
             obj (vlax-ename->vla-object e)
             nm  (pfrep:effname obj))
       (cond
         ((= (strcase nm) (strcase *pfrep-block*))
          (setq skips (pfrep:tally (strcat nm " -- already one") skips)))
         (T
          (setq new (vl-catch-all-apply 'vla-insertblock
                      (list ms (vla-get-insertionpoint obj) *pfrep-block* 1.0 1.0 1.0
                            (+ (vla-get-rotation obj) (* pi (/ *pfrep-rot-offset* 180.0))))))
          (cond
            ((vl-catch-all-error-p new)
             (setq skips (pfrep:tally (strcat nm " -- AutoCAD would not insert " *pfrep-block*) skips)))
            (T
             (vl-catch-all-apply 'vla-put-layer (list new (vla-get-layer obj)))
             ;; state first, then size -- a state change can reset nothing we set
             (pfrep:put (pfrep:prop new *pfrep-vis*) *pfrep-plan*)
             (if (and (setq p (pfrep:prop new *pfrep-size*))
                      (setq size (pfrep:size-match nm (pfrep:allowed p))))
               (pfrep:put p size)
               (setq nosize (pfrep:tally nm nosize)))
             (if (and (setq nmv (pfrep:old-name obj))
                      (assoc *pfrep-name-tag* (pfrep:atts new)))
               (vla-put-textstring (cdr (assoc *pfrep-name-tag* (pfrep:atts new))) nmv))
             (if (or (minusp (cond ((cdr (assoc 41 ed))) (1.0)))
                     (minusp (cond ((cdr (assoc 42 ed))) (1.0))))
               (setq mirr (pfrep:tally nm mirr)))
             ;; erase the old one; if it won't go (locked layer), take the new
             ;; one back out so nothing is doubled
             (if (vl-catch-all-error-p (vl-catch-all-apply 'vla-delete (list obj)))
               (progn
                 (vl-catch-all-apply 'vla-delete (list new))
                 (setq skips (pfrep:tally (strcat nm " -- could not erase the old block (locked layer?)") skips)))
               (setq n (1+ n))))))))
     (vla-endundomark doc)
     (princ (strcat "\nPFREPLACE: " (itoa n) " replaced with " *pfrep-block* ".  One U puts them back."))
     (if nosize
       (progn
         (princ (strcat "\n  Size left at the block's default -- the name gives none " *pfrep-size* " offers:"))
         (foreach c (reverse nosize) (princ (strcat "\n    " (car c) "  x" (itoa (cdr c)))))))
     (if mirr
       (progn
         (princ "\n  Were MIRRORED (negative scale) -- check their facing:")
         (foreach c (reverse mirr) (princ (strcat "\n    " (car c) "  x" (itoa (cdr c)))))))
     (if skips
       (progn
         (princ "\n  Skipped:")
         (foreach c (reverse skips) (princ (strcat "\n    " (car c) "  x" (itoa (cdr c)))))))))
  (princ))


(princ "\nPFREPLACE loaded (standalone setup tool).  Command: PFREPLACE")
(princ)
