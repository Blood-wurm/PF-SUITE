;;; ==========================================================================
;;; pfpipe.lsp  --  PIPEPRO: places the PFSUITE_PIPE profile pipe block
;;;                 WITHOUT the rest of pfsuite.  Standalone.  Prefix ppr:.
;;;
;;; PIPEPRO  click the upstream invert, then the downstream invert.  Done.
;;;          Before the first click:  S = size,  M = material,
;;;          V = vertical exaggeration (default 10, i.e. 1"=20' / 1"=2').
;;;          L = Label: drag a label's PFLEAD grip, then L and click the pipe.
;;;              Outside the pipe the rows turn level and justify away from
;;;              it; dragged back inside they centre along the pipe again.
;;;          Size, material and exaggeration are remembered for the session.
;;;
;;; Needs:
;;;   - the PFSUITE_PIPE block.  If the drawing hasn't got it, PIPEPRO loads
;;;     the definition from the block drawing named by *ppr-block-file* (SETUP,
;;;     below) -- nothing is placed.  A block already in the drawing is never
;;;     redefined; to pick up a changed server copy, redefine it by hand.
;;;   - its sidecar, pfpipe.csv, the pipe table -- KEEP IT BESIDE THIS FILE.
;;;     Found in *ppr-dir* (below), else anywhere on the support path.  Moving
;;;     the pair?  Change *ppr-dir*, or put the folder on the support path.
;;;     Edit the CSV, not this file, to add a size or material.  Read fresh
;;;     every run.  Uses nothing of pfsuite's.
;;;
;;; What it does to the block -- the same as the suite's PFPIPE, minus the grid:
;;;   PFSIZE / PFMAT / PFID / PFOD attributes, PFRUN to the downstream invert,
;;;   state WALL OFF, PFDIA = inside diameter x exaggeration, PFWT / PFWB from
;;;   the OD when the table has one, and the two-row label along the pipe:
;;;       CONST. 45 L.F. ~ 15"
;;;       RCP III @ 0.5%
;;;   The four label words (PFLENPRE, PFLENSUF, PFSLOPEPRE, PFSLOPESUF) are
;;;   taken from the block's own attribute presets; blank -> the suite default.
;;;   Text height = the height PFLABEL already has in the block.
;;;
;;; What it does NOT do (that is the suite's job): read grid anchors, draw
;;; leaders, write XDATA, or refresh labels later.  If the suite is loaded
;;; later, PFREFRESH sees these pipes as new and rebuilds them -- harmless.
;;;
;;; Replaces the old standalone PFPIPE (block PFPIPE, Carlson .dta files),
;;; 2026-11-20.  Safe to load alongside the suite: no shared names.
;;; ==========================================================================

(vl-load-com)

;;; ---- SETUP: the only lines to edit when PipePro moves --------------------
;;; AutoLISP can't see where a file was loaded from, so the paths are written
;;; here.  Use double backslashes.  A server share works:  "\\\\server\\share\\..."

;; The folder holding pfpipe.lsp and pfpipe.csv.
(setq *ppr-dir* "C:\\Users\\Guest01\\Data\\LIBRARY\\LISP\\PFSUITE\\V6")

;; Full path to the pipe block drawing -- any folder, any file name; it comes
;; in as PFSUITE_PIPE whatever the file is called.  Leave "" to look for
;; PFSUITE_PIPE.dwg in *ppr-dir*, then on the support path.
(setq *ppr-block-file* "")
;;; ---- end of SETUP ---------------------------------------------------------

(if (not (boundp '*ppr-ve*))   (setq *ppr-ve*   10.0))   ; vertical exaggeration
(if (not (boundp '*ppr-size*)) (setq *ppr-size* nil))    ; nominal, inches
(if (not (boundp '*ppr-mat*))  (setq *ppr-mat*  nil))    ; material name

;; Names typed in the block -- must match the Block Editor exactly.
(setq *ppr-block* "PFSUITE_PIPE")
(setq *ppr-label-defaults*
  '(("PFLENPRE" . "CONST.") ("PFLENSUF" . "L.F. ~") ("PFSLOPEPRE" . "@") ("PFSLOPESUF" . "%")))


;;; ==========================================================================
;;; Small helpers
;;; ==========================================================================

;; n with exactly dec decimals, whatever DIMZIN says
(defun ppr:fix (n dec / s p)
  (setq s (rtos n 2 dec))
  (if (and (> dec 0) (not (vl-string-search "." s))) (setq s (strcat s ".")))
  (if (> dec 0)
    (progn
      (setq p (vl-string-search "." s))
      (while (< (- (strlen s) p 1) dec) (setq s (strcat s "0")))))
  s)

;; the non-empty parts joined with single spaces
(defun ppr:join (parts / out)
  (setq out "")
  (foreach p parts
    (if (and p (/= p "")) (setq out (if (= out "") p (strcat out " " p)))))
  out)

(defun ppr:num (s)
  (if (and s (/= (vl-string-trim " " s) "")) (distof s 2)))

;; angle a, flipped if text at that angle would read upside down
(defun ppr:readable (a)
  (setq a (rem a (* 2.0 pi)))
  (if (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (if (and (> a (/ pi 2.0)) (<= a (* 1.5 pi))) (- a pi) a))

;; one CSV line's fields as Excel writes them (quotes, "" inside quotes,
;; a UTF-8 byte-order mark at the start), each trimmed
(defun ppr:csv-split (s / cs out cur inq c nx)
  (setq cs (vl-string->list s))
  (cond
    ((and (>= (length cs) 3) (= (car cs) 239) (= (cadr cs) 187) (= (caddr cs) 191))
     (setq cs (cdddr cs)))
    ((and cs (= (car cs) 65279)) (setq cs (cdr cs))))
  (while cs
    (setq c (car cs) cs (cdr cs) nx (car cs))
    (cond
      ((and inq (= c 34) (= nx 34)) (setq cur (cons 34 cur) cs (cdr cs)))
      ((= c 34) (setq inq (not inq)))
      ((and (not inq) (= c 44))
       (setq out (cons (vl-string-trim " \t" (vl-list->string (reverse cur))) out) cur nil))
      (T (setq cur (cons c cur)))))
  (reverse (cons (vl-string-trim " \t" (vl-list->string (reverse cur))) out)))


;;; ==========================================================================
;;; The pipe table (the sidecar, pfpipe.csv)
;;; ==========================================================================

;; -> the sidecar's full path | nil.  Each clause RETURNS the path -- a bare
;;    (and ...) test would return T.
(defun ppr:table-path ( / p)
  (cond
    ((and (= (type *ppr-dir*) 'STR) (setq p (findfile (strcat *ppr-dir* "\\pfpipe.csv")))) p)
    ((findfile "pfpipe.csv"))))

;; -> ((name default-p ((nominal id od) ...)) ...) in file order | nil
;;    id blank = the nominal; od nil = wall unknown
(defun ppr:table ( / path f l ln hdr cm cn ci co cd fl nm nom id od m out)
  (if (and (setq path (ppr:table-path)) (setq f (open path "r")))
    (progn
      (while (setq l (read-line f))
        (setq ln (vl-string-trim " \t" l))
        (cond
          ((or (= ln "") (= (substr ln 1 1) "#")))
          ((null hdr)
           (setq hdr (mapcar 'strcase (ppr:csv-split ln))
                 cm  (vl-position "MATERIAL" hdr)
                 cd  (vl-position "DEFAULT" hdr)
                 cn  (vl-position "NOMINAL" hdr)
                 ci  (vl-position "ID" hdr)
                 co  (vl-position "OD" hdr)))
          ((and cm cn)
           (setq fl  (ppr:csv-split ln)
                 nm  (cond ((nth cm fl)) (""))
                 nom (ppr:num (nth cn fl))
                 id  (if ci (ppr:num (nth ci fl)))
                 od  (if co (ppr:num (nth co fl))))
           (if (and (/= nm "") nom (> nom 0.0))
             (progn
               (if (null id) (setq id nom))
               (if (and od (<= od id)) (setq od nil))
               (if (setq m (assoc nm out))
                 (if (not (assoc nom (caddr m)))
                   (setq out (subst (list nm (cadr m) (cons (list nom id od) (caddr m))) m out)))
                 (setq out (cons (list nm
                                       (and cd (wcmatch (strcase (cond ((nth cd fl)) (""))) "Y*") T)
                                       (list (list nom id od)))
                                 out))))))))
      (close f)
      (mapcar '(lambda (m)
                 (list (car m) (cadr m)
                       (vl-sort (caddr m) '(lambda (a b) (< (car a) (car b))))))
              (reverse out)))))

;; that material's row, any case | nil
(defun ppr:mat (tbl name)
  (if name
    (vl-some '(lambda (m) (if (= (strcase (car m)) (strcase name)) m)) tbl)))

(defun ppr:sizes (tbl name / m)
  (if (setq m (ppr:mat tbl name)) (mapcar 'car (caddr m))))

;; (id od) for a material and size | nil
(defun ppr:dims (tbl name nom / m s)
  (if (and (setq m (ppr:mat tbl name)) (setq s (assoc nom (caddr m))))
    (cdr s)))


;;; ==========================================================================
;;; The block
;;; ==========================================================================

;; -> the block drawing's full path | nil.  Order: *ppr-block-file*, then
;;    PFSUITE_PIPE.dwg in *ppr-dir*, then PFSUITE_PIPE.dwg on the support path.
;;    A set path that isn't found is reported, so a stale copy found further
;;    down the list is never used silently.
(defun ppr:block-file-path ( / wanted p)
  (setq wanted (and (= (type *ppr-block-file*) 'STR)
                    (/= "" (vl-string-trim " \t" *ppr-block-file*))))
  (cond
    ((and wanted (setq p (findfile *ppr-block-file*))) p)
    ((or (and (= (type *ppr-dir*) 'STR)
              (setq p (findfile (strcat *ppr-dir* "\\" *ppr-block* ".dwg"))))
         (setq p (findfile (strcat *ppr-block* ".dwg"))))
     (if wanted
       (prompt (strcat "\nPIPEPRO: block drawing not found at " *ppr-block-file*
                       "\n  using " p " instead.")))
     p)))

;; T when the drawing has the block -- loading its definition from the block
;; drawing first if it hasn't.  Nothing is placed: -INSERT "NAME=file" defines
;; the block under NAME, then the insertion-point prompt is cancelled.  Only
;; runs when the block is missing, so AutoCAD never asks "Redefine it?".
(defun ppr:ensure-block ( / path echo)
  (cond
    ((tblsearch "BLOCK" *ppr-block*) T)
    ((null (setq path (ppr:block-file-path)))
     (prompt (strcat "\nPIPEPRO: no " *ppr-block* " block in this drawing, and no block drawing found."
                     "\n  Set *ppr-block-file* at the top of pfpipe.lsp (now: \""
                     (vl-princ-to-string *ppr-block-file*) "\")."))
     nil)
    (T
     (setq echo (getvar "CMDECHO"))
     (setvar "CMDECHO" 0)
     (command "_.-INSERT" (strcat *ppr-block* "=" path))
     (command)                                ; cancel at the insertion point
     (setvar "CMDECHO" echo)
     (if (tblsearch "BLOCK" *ppr-block*)
       (progn (prompt (strcat "\nPIPEPRO: loaded " *ppr-block* " from " path)) T)
       (progn (prompt (strcat "\nPIPEPRO: AutoCAD would not load " *ppr-block* " from " path)) nil)))))

(defun ppr:nospace (s) (vl-list->string (vl-remove 32 (vl-string->list s))))

;; the dynamic property of that name (spaces ignored: "PFRUN X" = "PFRUNX") | nil
(defun ppr:prop (obj name / all want hit nm)
  (setq want (strcase (ppr:nospace name))
        all  (vl-catch-all-apply
               '(lambda () (vlax-safearray->list
                             (vlax-variant-value (vla-getdynamicblockproperties obj))))))
  (if (not (vl-catch-all-error-p all))
    (foreach p all
      (setq nm (vl-catch-all-apply 'vla-get-propertyname (list p)))
      (if (and (null hit) (not (vl-catch-all-error-p nm))
               (= (strcase (ppr:nospace nm)) want))
        (setq hit p))))
  hit)

;; write a dynamic property; the variant type is taken from what it holds now.
;; -> T, or prints why not and returns nil
(defun ppr:set (obj name val / p cur r)
  (cond
    ((null (setq p (ppr:prop obj name)))
     (prompt (strcat "\n  ** " *ppr-block* " has no \"" name "\" parameter")) nil)
    ((vl-catch-all-error-p (setq cur (vl-catch-all-apply 'vla-get-value (list p))))
     (prompt (strcat "\n  ** can't read " name)) nil)
    (T
     (if (and (numberp val) (/= (type val) 'REAL)) (setq val (float val)))
     (setq r (vl-catch-all-apply
               '(lambda () (vla-put-value p (vlax-make-variant val (vlax-variant-type cur))))))
     (if (vl-catch-all-error-p r)
       (progn (prompt (strcat "\n  ** " name " refused " (vl-princ-to-string val)
                              ": " (vl-catch-all-error-message r)))
              nil)
       T))))

;; the ATTRIB carrying tag | nil
(defun ppr:att (e tag / sub sd out)
  (if (= 1 (cdr (assoc 66 (entget e))))
    (progn
      (setq sub (entnext e))
      (while (and sub (null out) (setq sd (entget sub)) (/= "SEQEND" (cdr (assoc 0 sd))))
        (if (and (= "ATTRIB" (cdr (assoc 0 sd))) (= (strcase (cdr (assoc 2 sd))) (strcase tag)))
          (setq out sub))
        (setq sub (entnext sub)))))
  out)

(defun ppr:get (e tag / a) (if (setq a (ppr:att e tag)) (cdr (assoc 1 (entget a)))))

(defun ppr:put (e tag val / a ed)
  (if (setq a (ppr:att e tag))
    (progn
      (setq ed (entget a))
      (entmod (subst (cons 1 val) (assoc 1 ed) ed))
      (entupd e))))

;; a dynamic property's value | nil
(defun ppr:val (obj name / p r)
  (if (setq p (ppr:prop obj name))
    (progn
      (setq r (vl-catch-all-apply 'vla-get-value (list p)))
      (if (not (vl-catch-all-error-p r))
        (if (= (type r) 'VARIANT) (vlax-variant-value r) r)))))

;; an attribute to pt at rotation rot.  jc: 0 middle-left, 1 middle-centre,
;; 2 middle-right.  (ATTRIB keeps vertical justification in 74, not 73 as
;; TEXT does.)
(defun ppr:place (e tag pt rot jc / a ed p3)
  (if (setq a (ppr:att e tag))
    (progn
      (setq ed (entget a)
            p3 (list (car pt) (cadr pt) 0.0))
      (foreach g (list (cons 10 p3) (cons 11 p3) (cons 50 rot) (cons 72 jc) (cons 74 2))
        (setq ed (if (assoc (car g) ed) (subst g (assoc (car g) ed) ed) (append ed (list g)))))
      (entmod ed)
      (entupd e))))

;; a label word: the block's preset, else the suite default
(defun ppr:word (e tag / v)
  (if (and (setq v (ppr:get e tag)) (/= (vl-string-trim " " v) ""))
    v
    (cdr (assoc tag *ppr-label-defaults*))))

(defun ppr:text-len (s ht style / b)
  (setq b (textbox (list (cons 1 s) (cons 40 ht) (cons 7 (cond (style) ("Standard"))))))
  (if b (- (caadr b) (caar b)) (* (strlen s) ht)))


;;; ==========================================================================
;;; The label
;;; ==========================================================================

(defun ppr:mid (p1 p2)
  (list (/ (+ (car p1) (car p2)) 2.0) (/ (+ (cadr p1) (cadr p2)) 2.0)))

;; T when pt is within the drawn pipe: between its ends, and between its
;; invert and its top at that station
(defun ppr:inside-p (pt p1 p2 dia / lo hi yi)
  (setq lo (min (car p1) (car p2))
        hi (max (car p1) (car p2)))
  (if (and (> (- hi lo) 1e-6) (<= lo (car pt) hi))
    (progn
      (setq yi (+ (cadr p1) (* (- (car pt) (car p1))
                               (/ (- (cadr p2) (cadr p1)) (- (car p2) (car p1))))))
      (<= yi (cadr pt) (+ yi dia)))))

;; T when e is a PFSUITE_PIPE insert (a dynamic one reads *U.. in its name)
(defun ppr:pipe-p (e / r)
  (and e
       (= "INSERT" (cdr (assoc 0 (entget e))))
       (not (vl-catch-all-error-p
              (setq r (vl-catch-all-apply 'vla-get-effectivename
                        (list (vlax-ename->vla-object e))))))
       (= (strcase r) *ppr-block*)))

;; (ppr:label e) -> notes, in print order.  Places the two label rows from
;; where the PFLEAD grip is now -- the suite's rule, without the leader:
;;   grip OUTSIDE the pipe -> rows level at the grip, justified away from the
;;                            pipe's middle (left-justified when the label is
;;                            right of it, right-justified when left)
;;   grip INSIDE the pipe  -> grip back to the centre, rows along the pipe,
;;                            centred on it
;; The block is read as PIPEPRO inserts it: scale 1, no rotation.
(defun ppr:label (e / obj ins rx ry lx ly dia p1 p2 lab ht sty half cen lead
                    jc ang nrm w notes)
  (setq obj (vlax-ename->vla-object e)
        ins (cdr (assoc 10 (entget e)))
        rx  (ppr:val obj "PFRUN X")
        ry  (ppr:val obj "PFRUN Y")
        lx  (ppr:val obj "PFLEAD X")
        ly  (ppr:val obj "PFLEAD Y")
        dia (cond ((ppr:val obj "PFDIA")) (0.0)))
  (if (not (and (numberp rx) (numberp ry)))
    (list "  ** can't read this pipe's PFRUN")
    (progn
      (setq p1   (list (car ins) (cadr ins))
            p2   (list (+ (car p1) rx) (+ (cadr p1) ry))
            lab  (ppr:att e "PFLABEL")
            ht   (if lab (cdr (assoc 40 (entget lab))) 1.6)
            sty  (if lab (cdr (assoc 7 (entget lab))))
            half ht                                   ; rows 2 text heights apart
            cen  (list (car (ppr:mid p1 p2)) (+ (cadr (ppr:mid p1 p2)) (/ dia 2.0)))
            lead (if (and (numberp lx) (numberp ly)) (list (+ (car p1) lx) (+ (cadr p1) ly))))
      (cond
        ((and lead (not (ppr:inside-p lead p1 p2 dia)))
         (setq jc (if (>= (car lead) (car cen)) 0 2))
         (ppr:place e "PFLABEL"  (list (car lead) (+ (cadr lead) half)) 0.0 jc)
         (ppr:place e "PFLABEL2" (list (car lead) (- (cadr lead) half)) 0.0 jc))
        (T
         ;; the grip first (a property write moves the rows), rows last
         (if lead
           (progn
             (ppr:set obj "PFLEAD X" (- (car cen) (car p1)))
             (ppr:set obj "PFLEAD Y" (- (cadr cen) (cadr p1))))
           (setq notes (list "  ** no PFLEAD grip on this block -- label kept on the pipe")))
         (setq ang (ppr:readable (angle p1 p2))
               nrm (+ ang (/ pi 2.0)))
         (ppr:place e "PFLABEL"  (polar cen nrm half) ang 1)
         (ppr:place e "PFLABEL2" (polar cen nrm (- half)) ang 1)
         (setq w (max (ppr:text-len (cond ((ppr:get e "PFLABEL")) ("")) ht sty)
                      (ppr:text-len (cond ((ppr:get e "PFLABEL2")) ("")) ht sty)))
         (if (or (> w (distance p1 p2)) (> (* 3.0 ht) dia))
           (setq notes (append notes
                               (list "  ** label is bigger than the pipe -- drag its PFLEAD grip clear, then PIPEPRO > Label"))))))
      notes)))


;;; ==========================================================================
;;; Placing one pipe
;;; ==========================================================================

;; p1 p2: WORLD upstream / downstream inverts.  -> nil (prints what it did)
(defun ppr:place-pipe (p1 p2 tbl / doc ms obj e dims id od dia wall run slope
                         row1 row2 notes)
  (setq doc  (vla-get-activedocument (vlax-get-acad-object))
        ms   (vla-get-modelspace doc)
        dims (ppr:dims tbl *ppr-mat* *ppr-size*)
        id   (cond ((car dims)) (*ppr-size*))
        od   (cadr dims)
        obj  (vl-catch-all-apply 'vla-insertblock
               (list ms (vlax-3d-point (list (car p1) (cadr p1) 0.0)) *ppr-block* 1.0 1.0 1.0 0.0)))
  (if (vl-catch-all-error-p obj)
    (prompt (strcat "\nPIPEPRO: AutoCAD would not insert " *ppr-block* "."))
    (progn
      (setq e (vlax-vla-object->ename obj))
      ;; record attributes
      (ppr:put e "PFSIZE" (strcat (rtos *ppr-size* 2 0) "\""))
      (ppr:put e "PFMAT"  *ppr-mat*)
      (ppr:put e "PFID"   (ppr:fix id 3))
      (ppr:put e "PFOD"   (if od (ppr:fix od 3) ""))
      ;; geometry: the run, the state, then the sizes
      (ppr:set obj "PFRUN X" (- (car p2) (car p1)))
      (ppr:set obj "PFRUN Y" (- (cadr p2) (cadr p1)))
      (ppr:set obj "PFVIS" "WALL OFF")
      (setq dia (* (/ id 12.0) *ppr-ve*))
      (ppr:set obj "PFDIA" dia)
      (if od
        (progn
          (setq wall (* (/ (/ (- od id) 2.0) 12.0) *ppr-ve*))
          (ppr:set obj "PFWT" wall)
          (ppr:set obj "PFWB" wall)))
      ;; the label text
      (setq run   (abs (- (car p2) (car p1)))
            slope (* 100.0 (/ (/ (- (cadr p1) (cadr p2)) *ppr-ve*) run))
            row1  (ppr:join (list (ppr:word e "PFLENPRE") (ppr:fix run 0)
                                  (ppr:word e "PFLENSUF") (strcat (rtos *ppr-size* 2 0) "\"")))
            row2  (ppr:join (list *ppr-mat* (ppr:word e "PFSLOPEPRE")
                                  (strcat (ppr:fix slope 1) (ppr:word e "PFSLOPESUF")))))
      (ppr:put e "PFLABEL"  row1)
      (ppr:put e "PFLABEL2" row2)
      (if (null (ppr:att e "PFLABEL2"))
        (setq notes (cons "  ** this block has no PFLABEL2 -- ATTSYNC PFSUITE_PIPE for the second row" notes)))
      ;; the label: a new pipe's grip sits in the pipe (it starts where the
      ;; block definition put it), so ppr:label centres the rows along it
      (if (ppr:prop obj "PFLEAD X")
        (progn
          (ppr:set obj "PFLEAD X" (- (car (ppr:mid p1 p2)) (car p1)))
          (ppr:set obj "PFLEAD Y" (+ (- (cadr (ppr:mid p1 p2)) (cadr p1)) (/ dia 2.0)))))
      (setq notes (reverse (ppr:label e)))
      (if (< slope 0.0)
        (setq notes (cons "  ** runs UPHILL from the first click -- adverse slope, or drawn backwards" notes)))
      (if (null od)
        (setq notes (cons (strcat "  " *ppr-mat* " " (rtos *ppr-size* 2 0)
                                  "\" has no OD in the table -- wall unknown, walls not sized")
                          notes)))
      (prompt (strcat "\nPlaced  " row1 "  /  " row2))
      (foreach n (reverse notes) (prompt (strcat "\n" n))))))


;;; ==========================================================================
;;; Choices
;;; ==========================================================================

(defun ppr:pick-size (tbl / sizes s)
  (setq sizes (ppr:sizes tbl *ppr-mat*))
  (prompt (strcat "\nSizes for " *ppr-mat* " (in): "
                  (ppr:join (mapcar '(lambda (x) (rtos x 2 0)) sizes))))
  (setq s (getreal (strcat "\nNominal size, inches <"
                           (if *ppr-size* (rtos *ppr-size* 2 0) "none") ">: ")))
  (cond
    ((null s))
    ((member s sizes) (setq *ppr-size* s))
    (T (prompt "\nThat size isn't in pfpipe.csv for this material."))))

(defun ppr:pick-mat (tbl / i n)
  (setq i 0)
  (foreach m tbl (setq i (1+ i)) (prompt (strcat "\n  " (itoa i) "  " (car m))))
  (setq n (getint (strcat "\nMaterial number <" *ppr-mat* ">: ")))
  (if (and n (<= 1 n (length tbl)))
    (progn
      (setq *ppr-mat* (car (nth (1- n) tbl)))
      (if (and *ppr-size* (not (member *ppr-size* (ppr:sizes tbl *ppr-mat*))))
        (progn
          (prompt (strcat "\n  " (rtos *ppr-size* 2 0) "\" isn't listed for " *ppr-mat* "."))
          (setq *ppr-size* nil)
          (ppr:pick-size tbl))))))

;; Label: click pipes one at a time; each label is redone from where its
;; grip is.  Enter (or a click on nothing) goes back to placing pipes.
(defun ppr:pick-label (doc / sel e)
  (while (setq sel (entsel "\nClick a pipe to fix its label <back>: "))
    (setq e (car sel))
    (if (ppr:pipe-p e)
      (progn
        (vla-startundomark doc)
        (foreach n (ppr:label e) (prompt (strcat "\n" n)))
        (vla-endundomark doc)
        (prompt "\n  label fixed."))
      (prompt (strcat "\n  that isn't a " *ppr-block* ".")))))

(defun ppr:pick-ve ( / v)
  (initget 6)   ; no zero, no negative
  (if (setq v (getreal (strcat "\nVertical exaggeration <" (rtos *ppr-ve* 2 2) ">: ")))
    (setq *ppr-ve* v)))


;;; ==========================================================================
;;; PIPEPRO
;;; ==========================================================================

(defun c:PIPEPRO ( / *error* doc tbl go p1u p2u p1 p2)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vl-catch-all-apply 'vla-endundomark (list doc))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nPIPEPRO stopped: " msg)))
    (princ))
  (setq tbl (ppr:table))
  (cond
    ((= 1 (getvar "BLOCKEDITOR")) (prompt "\nPIPEPRO: close the Block Editor first."))
    ((and (= 0 (getvar "TILEMODE")) (= 1 (getvar "CVPORT")))
     (prompt "\nPIPEPRO: work in model space (double-click into the viewport)."))
    ((not (ppr:ensure-block)))   ; it says what went wrong
    ((null tbl)
     (prompt (strcat "\nPIPEPRO: can't find pfpipe.csv.  Keep it beside pfpipe.lsp and set *ppr-dir*"
                     " at the top of pfpipe.lsp (now: " (vl-princ-to-string *ppr-dir*) ").")))
    (T
     ;; first-time / stale choices: the table's Default material, else its first
     (if (null (ppr:mat tbl *ppr-mat*))
       (setq *ppr-mat* (car (cond ((vl-some '(lambda (m) (if (cadr m) m)) tbl)) ((car tbl))))))
     (if (not (member *ppr-size* (ppr:sizes tbl *ppr-mat*))) (setq *ppr-size* nil))
     (if (null *ppr-size*) (ppr:pick-size tbl))
     (if *ppr-size*
       (progn
         (setq go T)
         (while go
           (initget "Size Material Vexag Label")
           (setq p1u (getpoint (strcat "\nUpstream invert (" (rtos *ppr-size* 2 0) "\" " *ppr-mat*
                                       ", VE " (rtos *ppr-ve* 2 2) ")  [Size/Material/Vexag/Label]: ")))
           (cond
             ((= p1u "Size")     (ppr:pick-size tbl))
             ((= p1u "Material") (ppr:pick-mat tbl))
             ((= p1u "Vexag")    (ppr:pick-ve))
             ((= p1u "Label")    (ppr:pick-label doc))
             (T (setq go nil))))
         (cond
           ((or (null p1u) (null *ppr-size*)))
           ((null (setq p2u (getpoint p1u "\nDownstream invert: "))))
           ((< (abs (- (car (setq p2 (trans p2u 1 0))) (car (setq p1 (trans p1u 1 0))))) 1e-6)
            (prompt "\nPIPEPRO: both inverts are at the same station."))
           (T
            (vla-startundomark doc)
            (ppr:place-pipe p1 p2 tbl)
            (vla-endundomark doc)))))))
  (princ))


(prompt "\npfpipe loaded.  Command: PIPEPRO")
(princ)
