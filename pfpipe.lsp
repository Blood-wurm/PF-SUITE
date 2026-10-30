;;; pfpipe.lsp -- standalone.  Places the PFPIPE profile pipe block.
;;;
;;; PFPIPE  pick upstream invert, pick downstream invert.  That's it.
;;;         Before the first pick, type S for Size or M for Material.
;;;         Uses the last size / material.  Walls are left OFF.
;;;
;;; Needs: a PFPIPE block already in the drawing (insert one once, erase it).
;;; Reads Carlson's own libraries at run time (nothing is stored here):
;;;   USER\pipesize.dta   size in inches = 3rd field, wall thickness = LAST field
;;;   USER\pipen.dta      n, Material, typecode
;;; To add a size or material, use Carlson's dialogs.  No restart needed.
;;;
;;; Drawn at vertical exaggeration *pfp-ve* (10).  Block goes in at scale 1.

(vl-load-com)

(if (not *pfp-ve*)   (setq *pfp-ve* 10.0))
(if (not *pfp-size*) (setq *pfp-size* nil))   ; inches
(if (not *pfp-mat*)  (setq *pfp-mat* nil))    ; material name

;;; ---- Carlson library ------------------------------------------------------

;; folder that holds pipesize.dta, or nil
(defun pfp:userdir ( / hit root dirs d)
  (cond
    ((and (boundp 'usrdir$) usrdir$ (findfile (strcat usrdir$ "\\pipesize.dta")))
     usrdir$)
    (T
     (setq root (strcat (getenv "AppData") "\\Carlson Software"))
     ;; newest-looking folder first
     (foreach y (reverse (vl-sort (or (vl-directory-files root "Carlson*" -1) '()) '<))
       (foreach r (reverse (vl-sort (or (vl-directory-files (strcat root "\\" y) "R*" -1) '()) '<))
         (setq d (strcat root "\\" y "\\" r "\\USER"))
         (if (and (null hit) (findfile (strcat d "\\pipesize.dta"))) (setq hit d))))
     hit)))

;; split "a, b, c" -> ("a" "b" "c"), trimmed
(defun pfp:split (s / out i cur)
  (setq cur "")
  (foreach c (vl-string->list s)
    (if (= c 44)
      (setq out (cons (vl-string-trim " \t\"" cur) out) cur "")
      (setq cur (strcat cur (chr c)))))
  (reverse (cons (vl-string-trim " \t\"" cur) out)))

;; (pfp:readlines path) -> list of non-blank lines
(defun pfp:readlines (path / f l out)
  (if (and path (setq f (open path "r")))
    (progn
      (while (setq l (read-line f))
        (if (/= "" (vl-string-trim " \t" l)) (setq out (cons l out))))
      (close f)))
  (reverse out))

;; -> ((size-inches . wall-inches) ...) sorted.  Skips headers / short rows.
(defun pfp:sizes ( / d out f)
  (if (setq d (pfp:userdir))
    (foreach l (pfp:readlines (strcat d "\\pipesize.dta"))
      (setq f (pfp:split l))
      (if (and (>= (length f) 4)
               (numberp (distof (nth 2 f)))
               (numberp (distof (last f)))
               (> (distof (nth 2 f)) 0.0))
        (setq out (cons (cons (distof (nth 2 f)) (distof (last f))) out)))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

;; -> ("Concrete" "RCP III" ...)
(defun pfp:mats ( / d out f)
  (if (setq d (pfp:userdir))
    (foreach l (pfp:readlines (strcat d "\\pipen.dta"))
      (setq f (pfp:split l))
      (if (and (>= (length f) 2) (numberp (distof (car f))))
        (setq out (cons (cadr f) out)))))
  (reverse out))

;;; ---- dynamic block helpers ------------------------------------------------

(defun pfp:nospace (s) (vl-list->string (vl-remove 32 (vl-string->list s))))

(defun pfp:dynprop (obj name / hit nm)
  (foreach p (vlax-safearray->list (vlax-variant-value (vla-getdynamicblockproperties obj)))
    (setq nm (vl-catch-all-apply 'vla-get-propertyname (list p)))
    (if (and (null hit) (not (vl-catch-all-error-p nm))
             (= (strcase (pfp:nospace nm)) (strcase (pfp:nospace name))))
      (setq hit p)))
  hit)

(defun pfp:dynset (obj name val / p r)
  (if (setq p (pfp:dynprop obj name))
    (progn
      (setq r (vl-catch-all-apply 'vla-put-value
                (list p (if (= (type val) 'STR)
                          (vlax-make-variant val vlax-vbString)
                          (vlax-make-variant (float val) vlax-vbDouble)))))
      (if (vl-catch-all-error-p r)
        (progn (prompt (strcat "\n  " name " refused " (vl-princ-to-string val))) nil)
        T))
    (progn (prompt (strcat "\n  no dynamic property " name " on PFPIPE")) nil)))

(defun pfp:attref (obj tag / hit)
  (foreach a (vlax-invoke obj 'GetAttributes)
    (if (and (null hit) (= (strcase (vla-get-tagstring a)) (strcase tag)))
      (setq hit a)))
  hit)

(defun pfp:attset (obj tag txt / a)
  (if (setq a (pfp:attref obj tag)) (vla-put-textstring a txt)))

;; angle a, flipped if it would read upside down
(defun pfp:readable (a)
  (setq a (rem a (* 2.0 pi)))
  (if (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (if (and (> a (/ pi 2.0)) (<= a (* 1.5 pi))) (- a pi) a))

;;; ---- size / material choice -----------------------------------------------

(defun pfp:pick-size ( / sizes s)
  (setq sizes (pfp:sizes))
  (cond
    ((null sizes) (prompt "\nNo sizes found in Carlson's pipesize.dta."))
    (T
     (prompt (strcat "\nSizes (in): "
                     (apply 'strcat
                            (mapcar '(lambda (x) (strcat (rtos (car x) 2 0) "  ")) sizes))))
     (setq s (getreal (strcat "\nInside diameter, inches <" (if *pfp-size* (rtos *pfp-size* 2 0) "none") ">: ")))
     (cond
       ((null s))
       ((assoc s sizes) (setq *pfp-size* s))
       (T (prompt "\nThat size is not in the library.  Add it in Carlson first."))))))

(defun pfp:pick-mat ( / mats i n)
  (setq mats (pfp:mats))
  (cond
    ((null mats) (prompt "\nNo materials found in Carlson's pipen.dta."))
    (T
     (setq i 0)
     (foreach m mats (setq i (1+ i)) (prompt (strcat "\n  " (itoa i) "  " m)))
     (setq n (getint (strcat "\nMaterial number <" (or *pfp-mat* "none") ">: ")))
     (if (and n (<= 1 n (length mats))) (setq *pfp-mat* (nth (1- n) mats))))))

;;; ---- the command ----------------------------------------------------------

(defun c:PFPIPE ( / doc spc p1u p2u p1 p2 dx dy sz wall dia obj run txt ang mid att k go)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (cond
    ((= 1 (getvar "BLOCKEDITOR")) (prompt "\nPFPIPE: close the Block Editor first."))
    ((null (tblsearch "BLOCK" "PFPIPE"))
     (prompt "\nPFPIPE: no PFPIPE block in this drawing.  Insert one once, then erase it."))
    ((null (pfp:sizes)) (prompt "\nPFPIPE: can't read Carlson's pipesize.dta."))
    (T
     ;; first-time defaults
     (if (null *pfp-size*) (pfp:pick-size))
     (if (null *pfp-mat*)  (setq *pfp-mat* (car (pfp:mats))))
     (if *pfp-size*
       (progn
         (setq go T)
         ;; options loop, then the picks
         (while go
           (initget "Size Material")
           (setq p1u (getpoint (strcat "\nUpstream invert (" (rtos *pfp-size* 2 0) "\" " (or *pfp-mat* "?")
                                       ")  [Size/Material]: ")))
           (cond
             ((= p1u "Size")     (pfp:pick-size))
             ((= p1u "Material") (pfp:pick-mat))
             (T (setq go nil))))
         (cond
           ((null p1u))
           ((null (setq p2u (getpoint p1u "\nDownstream invert: "))))
           (T
            (setq p1 (trans p1u 1 0)
                  p2 (trans p2u 1 0)
                  dx (- (car p2) (car p1))
                  dy (- (cadr p2) (cadr p1)))
            (if (< (abs dx) 1e-6)
              (prompt "\nPFPIPE: both inverts are at the same station.")
              (progn
                (setq sz   *pfp-size*
                      wall (cdr (assoc sz (pfp:sizes)))
                      dia  (* (/ sz 12.0) *pfp-ve*)
                      spc  (if (or (= 1 (getvar "TILEMODE")) (> (getvar "CVPORT") 1))
                             (vla-get-modelspace doc)
                             (vla-get-paperspace doc))
                      obj  (vla-insertblock spc (vlax-3d-point p1) "PFPIPE" 1.0 1.0 1.0 0.0))
                ;; sizes first, then the run, then visibility
                (pfp:dynset obj "PFDIA" dia)
                (pfp:dynset obj "PFWT"  (* (/ wall 12.0) *pfp-ve*))
                (pfp:dynset obj "PFWB"  (* (/ wall 12.0) *pfp-ve*))
                (pfp:dynset obj "PFRUNX" dx)
                (pfp:dynset obj "PFRUNY" dy)
                (pfp:dynset obj "PFVIS" "PIPE")
                (vla-regen doc 1)
                ;; attributes + label LAST (a property change can reset the label)
                (setq run (abs dx)
                      txt (strcat (rtos sz 2 0) "\" " (or *pfp-mat* "")
                                  "  L=" (rtos run 2 2) "'  S="
                                  (rtos (* 100.0 (/ (/ dy *pfp-ve*) run)) 2 2) "%")
                      ang (pfp:readable (angle p1 p2))
                      mid (list (/ (+ (car p1) (car p2)) 2.0)
                                (+ (/ (+ (cadr p1) (cadr p2)) 2.0) (/ dia 2.0)) 0.0))
                (pfp:attset obj "PFSIZE" (strcat (rtos sz 2 0) "\""))
                (pfp:attset obj "PFMAT" (or *pfp-mat* ""))
                (if (setq att (pfp:attref obj "PFLABEL"))
                  (progn
                    (vla-put-textstring att txt)
                    (vla-put-textalignmentpoint att (vlax-3d-point mid))
                    (vla-put-rotation att ang)
                    (setq k (textbox (list (cons 1 txt) (cons 40 (vla-get-height att))
                                           (cons 7 (vla-get-stylename att)))))
                    (if (or (> (- (caadr k) (caar k)) (distance p1 p2))
                            (> (vla-get-height att) dia))
                      (prompt "\nLabel is bigger than the pipe -- move it out by hand."))))
                (prompt (strcat "\nPlaced " txt))))))))))
  (princ))

(prompt "\npfpipe loaded.  Command: PFPIPE")
(princ)
