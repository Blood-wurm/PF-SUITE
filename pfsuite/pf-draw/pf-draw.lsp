;;; ==========================================================================
;;; pf-draw.lsp  --  the drawing boundary.  NO COMMANDS.
;;; Load position 8: after pf-cfg, pf-lib, pf-record.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; THE ONLY FILE THAT CREATES, MOVES OR ERASES ENTITIES, OR SETS A DYNAMIC
;;; PROPERTY.  (Attribute values and stored data are pf-record's.)  The same
;;; job V5's pfdraw did, plus V5's pf:run-command: the ONE wrapper every
;;; command runs inside -- one UNDO group, always closed, and an error that
;;; says which stage it was in.
;;;
;;; Commands live in their own modules and call down into this one.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  The command wrapper
;;; ==========================================================================

;; What the command is doing right now, so a failure can say WHERE.  Each
;; step sets it as it starts.
(setq *pfd-stage* nil)

;; (pfd:run name fn) -> fn's result.   THE command wrapper.
;;   One UNDO group around the whole command, so one UNDO takes it back.  An
;;   error or Esc still closes the group, and an error names the stage.
(defun pfd:run (name fn / *error* doc r before)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vl-catch-all-apply 'vla-endundomark (list doc))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (pfl:say (strcat name " stopped"
                       (if *pfd-stage* (strcat " while " *pfd-stage*) "")
                       ": " msg)))
    (princ))
  (setq *pfd-stage* nil)
  ;; block names learned before this command may be out of date (a RENAME)
  (pfl:effname-forget)
  (setq before (if (boundp '*pfr-write-failures*) *pfr-write-failures* 0))
  (vla-startundomark doc)
  (setq r (apply fn nil))
  (vla-endundomark doc)
  (if (and (boundp '*pfr-write-failures*) (> *pfr-write-failures* before))
    (pfl:say (strcat "  ** " (itoa (- *pfr-write-failures* before))
                     " write(s) FAILED; review the messages above.")))
  r)

;; (pfd:try label fn args) -> fn's result, or nil after saying what failed.
;;   One structure or pipe that trips an error is reported and skipped, and
;;   the run goes on.  First CAD run died on "bad argument type: consp nil"
;;   with nothing to say where (2026-10-15).
(defun pfd:try (label fn args / r)
  (setq *pfd-stage* nil
        *pfd-try-failed* nil
        r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r)
    (progn
      (setq *pfd-try-failed* T)
      (pfl:say (strcat "  ** " label " FAILED"
                       (if *pfd-stage* (strcat " while " *pfd-stage*) "")
                       ": " (vl-catch-all-error-message r)))
      nil)
    r))


;;; ==========================================================================
;;; SECTION 2  --  Setting dynamic properties
;;; ==========================================================================
;;; Reading them is pf-lib's (pfl:dynprop / pfl:prop-get / pfl:allowed ...).

;; (pfd:prop-put p value) -> T | explanation string     THE one write.
;;   Variant type is taken from what the property ALREADY holds.  Every COM
;;   call is caught, including the type probe.
(defun pfd:prop-put (p value / cur r)
  (setq cur (vl-catch-all-apply 'vla-get-value (list p)))
  (if (vl-catch-all-error-p cur)
    (strcat "could not read the property's current value: "
            (vl-catch-all-error-message cur))
    (progn
      (if (and (numberp value) (/= (type value) 'REAL)) (setq value (float value)))
      (setq r (vl-catch-all-apply
                '(lambda ()
                   (vla-put-value p (vlax-make-variant value (vlax-variant-type cur))))))
      (if (vl-catch-all-error-p r)
        (strcat "AutoCAD refused it: " (vl-catch-all-error-message r))
        T))))

(defun pfd:dynprop-put (obj propname value / p)
  (if (setq p (pfl:dynprop obj propname))
    (pfd:prop-put p value)
    (strcat "block has no \"" propname "\" parameter")))

;; (pfd:set-state obj state) -> T | explanation string
(defun pfd:set-state (obj state / p)
  (cond
    ((or (null state) (= state "")) "no state to set")
    ((null (setq p (pfl:visprop obj))) "block has no visibility parameter")
    ((not (member (strcase state) (mapcar 'strcase (pfl:allowed p))))
     (strcat "state \"" state "\" is not one of this block's states"))
    ((= (strcase (vl-princ-to-string (pfl:prop-get p))) (strcase state)) T)
    (T (pfd:prop-put p state))))


;;; ==========================================================================
;;; SECTION 3  --  Entities
;;; ==========================================================================

;; (pfd:insert name pt) -> ename | nil    model space, scale 1, no rotation
(defun pfd:insert (name pt / ms obj)
  (setq ms  (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object)))
        obj (vl-catch-all-apply 'vla-insertblock
              (list ms (vlax-3d-point (list (car pt) (cadr pt) 0.0)) name 1.0 1.0 1.0 0.0)))
  (if (not (vl-catch-all-error-p obj)) (vlax-vla-object->ename obj)))

;; (pfd:move e pt) -> T | nil    insertion point to pt
(defun pfd:move (e pt / r)
  (setq r (vl-catch-all-apply 'vla-put-insertionpoint
            (list (vlax-ename->vla-object e) (vlax-3d-point (list (car pt) (cadr pt) 0.0)))))
  (not (vl-catch-all-error-p r)))

(defun pfd:erase (e) (if (and e (entget e)) (entdel e)))

;; (pfd:layer name color noplot) -> name   CREATE-ONLY: an existing layer keeps
;;   its colour and plot flag (V5's pfd:ensure-layer-c rule -- never repaint).
(defun pfd:layer (name color noplot)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 name) '(70 . 0) (cons 62 color) (cons 290 (if noplot 0 1)))))
  name)

;; (pfd:rescale e sc) -> nil   the insert scaled sc, the same in X, Y and Z
(defun pfd:rescale (e sc / obj)
  (setq obj (vlax-ename->vla-object e))
  (foreach f '(vla-put-xscalefactor vla-put-yscalefactor vla-put-zscalefactor)
    (vl-catch-all-apply f (list obj sc)))
  (princ))

;; (pfd:insert-on name pt sc layer) -> ename | nil   pfd:insert, scaled sc in
;;   X, Y and Z and put on layer
(defun pfd:insert-on (name pt sc layer / e)
  (if (setq e (pfd:insert name pt))
    (progn
      (pfd:rescale e sc)
      (vl-catch-all-apply 'vla-put-layer (list (vlax-ename->vla-object e) layer))
      e)))

;; (pfd:to-back e) -> nil   draw order: behind everything (the anchor icon must
;;   not cover the grid it marks -- V5's pfa:send-to-back)
(defun pfd:to-back (e / echo)
  (if (and e (entget e))
    (progn
      (setq echo (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (vl-catch-all-apply 'command-s (list "_.DRAWORDER" (ssadd e) "" "_Back"))
      (setvar "CMDECHO" echo)))
  (princ))

;; (pfd:pline verts layer) -> ename | nil    an open polyline in model space.
;;   verts: ((pt start-width end-width) ...) -- a segment's widths are on the
;;   vertex it starts from.
(defun pfd:pline (verts layer)
  (entmakex
    (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(410 . "Model")
                  (cons 8 layer) '(100 . "AcDbPolyline")
                  (cons 90 (length verts)) '(70 . 0))
            (apply 'append
                   (mapcar '(lambda (v)
                              (list (list 10 (car (car v)) (cadr (car v)))
                                    (cons 40 (cadr v)) (cons 41 (caddr v))))
                           verts)))))


;; (pfd:line p1 p2 layer) -> ename | nil    a LINE in model space
(defun pfd:line (p1 p2 layer)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") '(410 . "Model") (cons 8 layer)
                  '(100 . "AcDbLine")
                  (list 10 (car p1) (cadr p1) 0.0) (list 11 (car p2) (cadr p2) 0.0))))

;; (pfd:text pt s layer ht rot just style) -> ename | nil   a TEXT in model
;;   space.  just: 'ML 'MR 'MC (middle row, like the attributes).  style nil
;;   = the current one.
(defun pfd:text (pt s layer ht rot just style / h p3)
  (setq h  (cond ((eq just 'MR) 2) ((eq just 'MC) 1) (T 0))
        p3 (list (car pt) (cadr pt) 0.0))
  (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity") '(410 . "Model") (cons 8 layer)
                  '(100 . "AcDbText") (cons 10 p3) (cons 40 ht) (cons 1 s) (cons 50 rot)
                  (cons 7 (cond (style) ((getvar "TEXTSTYLE"))))
                  (cons 72 h) (cons 11 p3) '(100 . "AcDbText") '(73 . 2))))

;; (pfd:dim-vert p1 p2 x layer txt) -> ename | nil   a vertical rotated
;;   dimension from p1 to p2, its dimension line at X x, text replaced by txt.
;;   The current dimension style and DIMSCALE size it, like a drafter's.
(defun pfd:dim-vert (p1 p2 x layer txt / ms d)
  (setq ms (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object)))
        d  (vl-catch-all-apply 'vla-adddimrotated
             (list ms (vlax-3d-point (list (car p1) (cadr p1) 0.0))
                   (vlax-3d-point (list (car p2) (cadr p2) 0.0))
                   (vlax-3d-point (list x (/ (+ (cadr p1) (cadr p2)) 2.0) 0.0))
                   (/ pi 2.0))))
  (if (not (vl-catch-all-error-p d))
    (progn
      (vl-catch-all-apply 'vla-put-layer (list d layer))
      (if txt (vl-catch-all-apply 'vla-put-textoverride (list d txt)))
      (vlax-vla-object->ename d))))

;; (pfd:color e color) -> T | nil   an entity's colour: 1 red, 256 ByLayer
(defun pfd:color (e color / r)
  (setq r (vl-catch-all-apply 'vla-put-color (list (vlax-ename->vla-object e) color)))
  (not (vl-catch-all-error-p r)))


;;; ==========================================================================
;;; SECTION 4  --  Fitting the station line
;;; ==========================================================================
;;; One end gets fitted: PFTOP stretches the station line's TOP up to the
;;; label rows.  The barrel depth (PFDEPTH) is the drafter's, set with its
;;; grip -- the tool never touches it (Jake, 2026-10-15).  Rather than trust
;;; which way PFTOP runs or where its base point sits, the end is MEASURED in
;;; the insert's own geometry (pfl:end-y), the parameter is set, and the end
;;; is measured again.  Moved the wrong way: set the other way.  Not moved:
;;; reported.

;; (pfd:fit-end e param which target) -> T | explanation string
;;   which: 'top or 'bot.  target: the world Y that end should sit at.
(defun pfd:fit-end (e param which target / obj p v0 cur d r y)
  (setq obj (vlax-ename->vla-object e))
  (cond
    ((null (setq cur (pfl:end-y e which)))
     (if (eq which 'top) "no station line found in the block" "no barrel found in the block"))
    ((< (abs (- target cur)) 0.005) T)
    ((null (setq p (pfl:dynprop obj param))) (strcat "block has no " param " parameter"))
    ((not (numberp (setq v0 (pfl:prop-get p)))) (strcat param " has no readable value"))
    (T
     (setq d (- target cur) r nil)
     (foreach try (list (+ v0 d) (- v0 d))
       (if (null r)
         (progn
           (pfd:prop-put p try)
           (if (and (setq y (pfl:end-y e which)) (< (abs (- target y)) 0.01))
             (setq r T)))))
     (if r r
       (progn
         (pfd:prop-put p v0)
         (strcat param " did not move the "
                 (if (eq which 'top) "station line's top" "barrel bottom")
                 " -- check its stretch action"))))))

;; (pfd:depth-probe e param) -> (bottom rate index) | explanation string
;;   The tool never SETS PFDEPTH -- the drafter does, with its grip.  This is
;;   only PFGATE's check that the grip really moves the barrel.  It nudges the
;;   parameter by 1 and puts it back.
;;   PFDEPTH is judged by what it MOVES, not by the lowest line: on a big CBI
;;   the riser reaches below a short barrel, and the lowest line is then the
;;   riser (CAD, 2026-10-15).
;;     bottom -- world Y of the lowest vertex the nudge moved: the barrel bottom
;;     rate   -- how far that vertex moves per unit of param, sign included
;;     index  -- its place in pfl:geom-ys, to read it again after a change
(defun pfd:depth-probe (e param / obj p v0 a b dv i bot k idx)
  (setq obj (vlax-ename->vla-object e))
  (cond
    ((null (setq p (pfl:dynprop obj param))) (strcat "block has no " param " parameter"))
    ((not (numberp (setq v0 (pfl:prop-get p)))) (strcat param " has no readable value"))
    ((null (setq a (pfl:geom-ys e))) "no barrel found in the block")
    (T
     (setq dv 1.0)
     (if (/= T (pfd:prop-put p (+ v0 dv)))
       (progn (setq dv -1.0) (pfd:prop-put p (+ v0 dv))))
     (setq b (pfl:geom-ys e))
     (pfd:prop-put p v0)
     (if (= (length a) (length b))
       (progn
         (setq i 0)
         (foreach y a
           (if (and (> (abs (- (nth i b) y)) 1e-6) (or (null bot) (< y bot)))
             (setq bot y k (/ (- (nth i b) y) dv) idx i))
           (setq i (1+ i)))))
     (cond
       ((/= (length a) (length b))
        (strcat "the block changed shape when " param " moved -- can't measure it"))
       ((null bot) (strcat param " did not move the barrel -- check its stretch action"))
       (T (list bot k idx))))))


(princ "\npf-draw loaded (drawing boundary).")
(princ)
