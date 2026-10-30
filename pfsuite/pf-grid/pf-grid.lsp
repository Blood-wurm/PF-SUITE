;;; ==========================================================================
;;; pf-grid.lsp  --  PFSETUP and PFREMOVE: the profile grid anchors.
;;; Load position 13: after pf-refresh (it uses pf-pipe's materials and pipes,
;;; and pf-struct's copies).  Prefix pfn:.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; Ported from V5's pfsetup.lsp + pfanchor.lsp (Jake, 2026-10-30: "port mostly
;;; as-is").  What changed for V6:
;;;   - the anchor is YOUR PFSUITE_ANCHOR block, inserted and filled -- every
;;;     V5 attribute plus CL.  Its definition is checked for all nine tags
;;;     first; nothing is written to a block that lacks one.
;;;   - its records are pf-record XDATA (CL, PRO-INV, PRO-TOP, TIN-EXIST,
;;;     TIN-DESIGN, MATERIAL, SUMS, STAMP), not V5's ledger.  V5's anchors are
;;;     still read (pfg:grid falls back to their ledger).
;;;   - dropped: the GEOM / twin caches, pass and status records, the index
;;;     repair, the XFORM stamp -- the line tree, PFASSIGN and the
;;;     fingerprints do those jobs now.
;;;   - PFREMOVE erases the anchor ONLY by default; what sat on the grid is
;;;     RELEASED (the suite leaves it alone from then on).  "Everything"
;;;     erases that too.
;;;
;;; PFSETUP [Scan/Anchor/Edit] <Scan> until the palette exists:
;;;   Scan    V5's AUTO: grid-name text -> TYPE_NAME.cl -> a STUB per line
;;;           (a line known before its grid), .pro pairs filled in later,
;;;           never guessed.  Then every anchor is checked.
;;;   Anchor  a stub (or a blank form) -> the dialog -> two corner picks
;;;   Edit    click a grid -> the dialog -> written in place
;;; ==========================================================================

(vl-load-com)

;; Session memory (V5's pfs:remember): the scales, the datum and the material
;; per utility type last confirmed.  Dies with the drawing session.
(if (not (boundp '*pfn-last*)) (setq *pfn-last* nil))


;;; ==========================================================================
;;; SECTION 1  --  The anchor's record
;;; ==========================================================================
;;; A record (rec) is an alist, the one thing every writer here consumes:
;;;   type name material hs vs datum cl inv top tine tind  (+ ll tr when placed)
;;; The dialog is only ONE way to build one -- PFSELFTEST builds them by code.

(defun pfn:g (k rec) (cdr (assoc k rec)))

;; (pfn:missing-tags) -> the tags *pf-anc-tags* names that the anchor block's
;;   DEFINITION lacks | nil when it has them all (or isn't in the drawing)
(defun pfn:missing-tags ( / e ed have)
  (if (setq e (tblobjname "BLOCK" *pf-anc-block*))
    (progn
      (while (and (setq e (entnext e)) (setq ed (entget e)) (/= (cdr (assoc 0 ed)) "ENDBLK"))
        (if (= (cdr (assoc 0 ed)) "ATTDEF") (setq have (cons (strcase (cdr (assoc 2 ed))) have))))
      (vl-remove-if '(lambda (tg) (member (strcase tg) have)) *pf-anc-tags*))))

;; (pfn:sums rec) -> ((role . checksum) ...) of the .cl and the .pro pair
(defun pfn:sums (rec / out s)
  (foreach r '(("CL" . cl) ("INV" . inv) ("TOP" . top))
    (if (setq s (pfl:file-sum (pfn:g (cdr r) rec)))
      (setq out (cons (cons (car r) s) out))))
  (reverse out))

;; (pfn:write a rec sta0) -> T   the attributes and the V6 records.  ll / tr
;;   in rec give WIDTH and HEIGHT (relative to the corner, V5's rule).
(defun pfn:write (a rec sta0 / ll tr)
  (setq ll (pfn:g 'll rec) tr (pfn:g 'tr rec))
  (pfr:put a *pf-anc-line*   (strcase (pfn:g 'name rec)))
  (pfr:put a *pf-anc-util*   (strcase (pfn:g 'type rec)))
  (pfr:put a *pf-anc-sta0*   (rtos sta0 2 6))
  (pfr:put a *pf-anc-datum*  (rtos (pfn:g 'datum rec) 2 6))
  (pfr:put a *pf-anc-hplot*  (rtos (pfn:g 'hs rec) 2 6))
  (pfr:put a *pf-anc-vplot*  (rtos (pfn:g 'vs rec) 2 6))
  (pfr:put a *pf-anc-width*  (rtos (- (car tr) (car ll)) 2 6))
  (pfr:put a *pf-anc-height* (rtos (- (cadr tr) (cadr ll)) 2 6))
  (pfr:put a *pf-anc-cl*     (pfn:g 'cl rec))
  (pfr:val-put a *pf-xd-cl*      (pfn:g 'cl rec))
  (pfr:val-put a *pf-xd-pro-inv* (cond ((pfn:g 'inv rec)) ("")))
  (pfr:val-put a *pf-xd-pro-top* (cond ((pfn:g 'top rec)) ("")))
  (pfr:val-put a *pf-xd-tin-ex*  (cond ((pfn:g 'tine rec)) ("")))
  (pfr:val-put a *pf-xd-tin-des* (cond ((pfn:g 'tind rec)) ("")))
  (pfr:val-put a *pf-xd-mat*     (cond ((pfn:g 'material rec)) ("")))
  (pfr:val-put a *pf-xd-sums*    (pfn:sums rec))
  (pfr:schema-put a)
  T)

;; (pfn:make rec) -> anchor | explanation string
;;   A new PFSUITE_ANCHOR at the lower-left corner, on the no-plot anchor
;;   layer, icon scaled to the sheet, records written, its own handle stamped
;;   (a copy keeps this one's -- that is how it is caught), sent behind.
(defun pfn:make (rec / rng a miss)
  (cond
    ((not (tblsearch "BLOCK" *pf-anc-block*))
     (strcat "no " *pf-anc-block* " block in this drawing -- insert one once, then erase it"))
    ((setq miss (pfn:missing-tags))
     (strcat *pf-anc-block* " is missing " (pfl:join-with ", " miss)
             " -- BEDIT it and run PFMKANCATT, then ATTSYNC"))
    ((null (setq rng (pfc:cl-range (pfn:g 'cl rec))))
     (strcat "Carlson could not read a station range from " (vl-filename-base (pfn:g 'cl rec)) ".cl"))
    ((null (setq a (pfd:insert-on *pf-anc-block* (pfn:g 'll rec)
                                  (/ (pfn:g 'hs rec) *pf-anc-icon-hplot*)
                                  (pfd:layer *pf-anc-layer* *pf-anc-layer-color* T))))
     "AutoCAD would not insert the anchor")
    (T
     (pfn:write a rec (car rng))
     (pfr:val-put a *pf-xd-stamp* (pfl:handle a))
     (pfd:to-back a)
     a)))

;; (pfn:rec-of anchor) -> the record an anchor holds now -- the dialog's
;;   starting point on Edit
(defun pfn:rec-of (anchor / g at out)
  (setq at  (pfg:atts anchor)
        g   (pfg:grid anchor)
        out (list (cons 'edit T)
                  (cons 'type (strcase (pfg:att *pf-anc-util* at)))
                  (cons 'name (strcase (pfg:att *pf-anc-line* at)))))
  (if g
    (foreach k '((cl . cl) (inv . pro-inv) (top . pro-top) (tine . tin-exist)
                 (tind . tin-design) (material . material) (hs . hplot) (vs . vplot))
      (if (pfl:g (cdr k) g) (setq out (cons (cons (car k) (pfl:g (cdr k) g)) out)))))
  (if (pfg:num (pfg:att *pf-anc-datum* at))
    (setq out (cons (cons 'datum (pfg:num (pfg:att *pf-anc-datum* at))) out)))
  out)


;;; ==========================================================================
;;; SECTION 2  --  Validation  (V5's pfs:validate -- THE refusal cascade)
;;; ==========================================================================
;;; Name is the identity key: picked files VALIDATE against it, they never
;;; set it.  Pairs bind both-or-neither.  The numeric checks apply only when
;;; their key is present -- a record without them will be prompted, where
;;; initget enforces the same rule.

;; (pfn:validate rec) -> refusal message | nil
(defun pfn:validate (rec / nm inv top tine tind)
  (setq nm (strcase (cond ((pfn:g 'name rec)) ("")))
        inv (pfn:g 'inv rec) top (pfn:g 'top rec) tine (pfn:g 'tine rec) tind (pfn:g 'tind rec))
  (cond
    ((or (null (pfn:g 'cl rec)) (= (pfn:g 'cl rec) "")) "Select the .cl file -- the stations come from it.")
    ((= nm "") "Line name is empty.")
    ((and (assoc 'hs rec)
          (not (and (numberp (pfn:g 'hs rec)) (numberp (pfn:g 'vs rec))
                    (> (pfn:g 'hs rec) 0.0) (> (pfn:g 'vs rec) 0.0))))
     "Plot scales must be positive numbers (e.g. 20 and 2).")
    ((and (assoc 'datum rec) (not (numberp (pfn:g 'datum rec))))
     "Type the datum elevation (the lower-left grid corner).")
    ((and inv (null top)) "Crown _TOP .pro missing -- bind both .pro files or neither.")
    ((and top (null inv)) "Invert _INV .pro missing -- bind both .pro files or neither.")
    ((and inv (/= (car (pfl:pro-parts inv)) nm))
     (strcat "INV .pro is for '" (car (pfl:pro-parts inv)) "' but Name says '" nm "'."))
    ((and top (/= (car (pfl:pro-parts top)) nm))
     (strcat "TOP .pro is for '" (car (pfl:pro-parts top)) "' but Name says '" nm "'."))
    ((and tine (null tind)) "DESIGN_* surface missing -- bind both surfaces or neither.")
    ((and tind (null tine)) "Existing surface missing -- bind both surfaces or neither.")))

;; (pfn:range-same cl-old cl-new) -> T | nil | 'UNKNOWN  (V5's pfs:range-match)
;;   Edit may swap a .cl for one with the same station range; a different
;;   range is a rebuild -- PFREMOVE, then set it up fresh.
(defun pfn:range-same (cl-old cl-new / r1 r2)
  (cond
    ((or (null cl-old) (= cl-old "")) 'UNKNOWN)
    ((= (strcase cl-old) (strcase cl-new)) T)
    ((or (null (setq r1 (pfc:cl-range cl-old))) (null (setq r2 (pfc:cl-range cl-new)))) 'UNKNOWN)
    ((and (<= (abs (- (car r1) (car r2))) 0.01) (<= (abs (- (cadr r1) (cadr r2))) 0.01)) T)))


;;; ==========================================================================
;;; SECTION 3  --  The anchor checks
;;; ==========================================================================
;;; Run by PFSETUP Scan over every anchor, and by PFLINETEST.  Each finding is
;;; a sentence; none = the anchor is fine.

;; (pfn:seg-dist p a b) -> distance from point p to segment a-b (2D)
(defun pfn:seg-dist (p a b / dx dy l2 u)
  (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)) l2 (+ (* dx dx) (* dy dy))
        u  (if (> l2 1e-12)
             (max 0.0 (min 1.0 (/ (+ (* (- (car p) (car a)) dx) (* (- (cadr p) (cadr a)) dy)) l2)))
             0.0))
  (distance (list (car p) (cadr p)) (list (+ (car a) (* u dx)) (+ (cadr a) (* u dy)))))

;; (pfn:grid-lines) -> ((p1 p2) ...) every LINE on Carlson's grid layers.
;;   Read once per run and handed to the checks.
(defun pfn:grid-lines ( / ss i ed out)
  (if (setq ss (ssget "_X" (list '(0 . "LINE") (cons 8 *pf-anc-grid-layers*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed  (entget (ssname ss (setq i (1- i))))
            out (cons (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))) out))))
  out)

;; (pfn:corner-ok-p pt glines) -> T when a grid LINE passes the anchor's
;;   corner, or there are no grid lines to check against (V5's probe)
(defun pfn:corner-ok-p (pt glines)
  (or (null glines)
      (and (vl-some '(lambda (l) (<= (pfn:seg-dist pt (car l) (cadr l)) *pf-anc-probe-tol*)) glines) T)))

;; (pfn:checks anchor top glines) -> ("finding" ...) | nil
;;   top: pfg:top-lines.  glines: pfn:grid-lines.
(defun pfn:checks (anchor top glines / g out sums now cl att x y)
  (setq g (pfg:grid anchor))
  (cond
    ((pfg:copy-p anchor)
     (list "a COPY of another anchor (same stamp) -- erase it, or PFREMOVE it"))
    ((null g) (list "its station, datum, scales or height can't be read -- check it in Properties"))
    (T
     (cond
       ((null (pfl:g 'cl g)) (setq out (cons "no .cl on record -- PFSETUP Edit it" out)))
       ((null (setq cl (pfg:cl g)))
        (setq out (cons (strcat (vl-filename-base (pfl:g 'cl g)) ".cl not found") out)))
       ((and (pfc:ready-p) (null (pfc:cl-range cl)))
        (setq out (cons (strcat "Carlson can't read " (vl-filename-base cl) ".cl") out))))
     ;; a bound file changed since setup (V6 anchors only -- V5 kept no sums
     ;; this way)
     (setq sums (pfr:val-get anchor *pf-xd-sums*))
     (foreach s sums
       (setq now (pfl:file-sum (cond ((= (car s) "CL") (pfl:g 'cl g))
                                     ((= (car s) "INV") (pfl:g 'pro-inv g))
                                     (T (pfl:g 'pro-top g)))))
       (cond
         ((null now) (setq out (cons (strcat "its " (car s) " file can't be read") out)))
         ((/= now (cdr s))
          (setq out (cons (strcat "its " (car s) " file changed since setup -- PFSETUP Edit to accept it")
                          out)))))
     ;; the CL attribute and the stored .cl must name the same file
     (setq att (pfg:cl-att (pfg:atts anchor)))
     (if (and att (pfr:val-get anchor *pf-xd-cl*)
              (/= (strcase (vl-filename-base att))
                  (strcase (vl-filename-base (pfr:val-get anchor *pf-xd-cl*)))))
       (setq out (cons (strcat "its CL attribute says " (vl-filename-base att)
                               " but its record says " (vl-filename-base (pfr:val-get anchor *pf-xd-cl*))
                               " -- typed over?  PFSETUP Edit it")
                       out)))
     ;; the grid moved without its anchor, or was stretched
     (if (not (pfn:corner-ok-p (pfl:ins anchor) glines))
       (setq out (cons "no grid line at the anchor's corner -- grid moved without its anchor?" out)))
     (if (pfl:g 'rightx g)
       (progn
         (setq x (- (pfl:g 'rightx g) 0.1)
               y (pfg:top-at x g top))
         (cond
           ((null y) (setq out (cons (strcat "no " *pf-top-layer* " top found at its right edge") out)))
           ((> (abs (- y (pfl:g 'topy g))) *pf-anc-top-tol*)
            (setq out (cons "its top at the right edge differs from setup -- grid stretched or redrawn?" out))))))
     (reverse out))))


;;; ==========================================================================
;;; SECTION 4  --  Scan  (V5's AUTO: names every line the sheet declares)
;;; ==========================================================================
;;; Never guesses: no .cl, or two .cl matching, is reported and skipped.
;;; Idempotent: a line already anchored or stubbed is never renamed, only
;;; re-checked for a .pro pair that appeared since -- FILL-EMPTY ONLY, so a
;;; scan can't undo a deliberate binding (that stays Edit's job).

;; (pfn:sheet-names) -> ((type . name) ...) from the grid-name text, deduped.
;;   A text naming a utility whose name can't be read is REPORTED.
(defun pfn:sheet-names ( / ss i s ty nm out notes)
  (if (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 8 *pf-name-layer*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq s  (cdr (assoc 1 (entget (ssname ss (setq i (1- i))))))
            ty (if s (pfl:sheet-type s))
            nm (if ty (pfl:sheet-name s ty)))
      (cond
        ((and ty nm) (if (not (member (cons ty nm) out)) (setq out (cons (cons ty nm) out))))
        (ty (setq notes (cons (strcat "  SKIPPED \"" s "\" -- the line name must be in straight quotes, 'NAME'")
                              notes))))))
  (cons (reverse out) notes))

;; (pfn:cl-lookup dir ty nm) -> path | 'AMBIG | nil   TYPE_NAME.cl, exactly
(defun pfn:cl-lookup (dir ty nm / hits p)
  (foreach f (vl-directory-files dir "*.cl" 1)
    (setq p (pfl:line-parts (strcase (vl-filename-base f))))
    (if (and (= (car p) (strcase ty)) (= (cdr p) (strcase nm)))
      (setq hits (cons (strcat dir f) hits))))
  (cond ((null hits) nil) ((cdr hits) 'AMBIG) (T (car hits))))

;; (pfn:pro-lookup dir ty nm role) -> TYPE_NAME_ROLE.pro | nil
(defun pfn:pro-lookup (dir ty nm role / want hit)
  (setq want (strcase (strcat ty "_" nm "_" role ".PRO")))
  (if dir
    (foreach f (vl-directory-files dir "*.pro" 1)
      (if (and (null hit) (= (strcase f) want)) (setq hit (strcat dir f)))))
  hit)

;; (pfn:anchor-index) -> (("STORM" "CA" anchor) ...) every non-copy anchor.
;;   Built once per run: telling a copy apart reads every anchor, so asking
;;   "is this line anchored?" anchor by anchor, name by name, would not scale.
(defun pfn:anchor-index ( / at out)
  (foreach a (pfg:all)
    (if (not (pfg:copy-p a))
      (setq at  (pfg:atts a)
            out (cons (list (strcase (pfg:att *pf-anc-util* at)) (strcase (pfg:att *pf-anc-line* at)) a)
                      out))))
  out)

;; (pfn:find-in ty nm idx) -> that line's anchor | nil   idx: pfn:anchor-index
(defun pfn:find-in (ty nm idx / hit)
  (foreach r idx
    (if (and (null hit) (= (car r) (strcase ty)) (= (cadr r) (strcase nm))) (setq hit (caddr r))))
  hit)

;; (pfn:find-anchor ty nm) -> the (non-copy) anchor of that line | nil
(defun pfn:find-anchor (ty nm) (pfn:find-in ty nm (pfn:anchor-index)))

(defun pfn:nz (s) (if (and s (/= s "")) s))

;; (pfn:fill-anchor a ty nm pdir) -> a line to report | nil   late .pro pair
;;   into an anchor whose slots are EMPTY (V5's or V6's records)
(defun pfn:fill-anchor (a ty nm pdir / g inv top ninv ntop rec)
  (setq g   (pfg:grid a)
        inv (pfn:nz (pfl:g 'pro-inv g)) top (pfn:nz (pfl:g 'pro-top g)))
  (if (null inv) (setq ninv (pfn:pro-lookup pdir ty nm "INV")))
  (if (null top) (setq ntop (pfn:pro-lookup pdir ty nm "TOP")))
  (if (or ninv ntop)
    (progn
      (if ninv (pfr:val-put a *pf-xd-pro-inv* ninv))
      (if ntop (pfr:val-put a *pf-xd-pro-top* ntop))
      (setq rec (list (cons 'cl (pfl:g 'cl g)) (cons 'inv (cond (inv) (ninv))) (cons 'top (cond (top) (ntop)))))
      (pfr:val-put a *pf-xd-sums* (pfn:sums rec))
      (strcat "  Bound " ty " '" nm "' (anchored)"
              (if ninv (strcat " + INV " (vl-filename-base ninv)) "")
              (if ntop (strcat " + TOP " (vl-filename-base ntop)) "")))))

;; (pfn:fill-stub st ty nm pdir) -> a line to report | nil   same, for a stub
(defun pfn:fill-stub (st ty nm pdir / inv top ninv ntop)
  (setq inv (pfn:nz (cdr (assoc 4 st))) top (pfn:nz (cdr (assoc 5 st))))
  (if (null inv) (setq ninv (pfn:pro-lookup pdir ty nm "INV")))
  (if (null top) (setq ntop (pfn:pro-lookup pdir ty nm "TOP")))
  (if (or ninv ntop)
    (progn
      (pfr:stub-put ty nm (cdr (assoc 1 st)) (cond (inv) (ninv)) (cond (top) (ntop)))
      (strcat "  Bound " ty " '" nm "' (named)"
              (if ninv (strcat " + INV " (vl-filename-base ninv)) "")
              (if ntop (strcat " + TOP " (vl-filename-base ntop)) "")))))

;; (pfn:scan) -> lines to report.   WRITES stubs.  The project's folders and
;;   the sheet's grid names.
(defun pfn:scan ( / cdir)
  (if (setq cdir (pff:std-dir "cl"))
    (pfn:scan-in cdir (pff:std-dir "pro") (pfn:sheet-names))
    (list "  Can't scan: the project's Alignments folder wasn't found (no Carlson project open?).")))

;; (pfn:scan-in cdir pdir sn) -> lines to report.   WRITES stubs.  The work,
;;   handed its folders and names (pfn:sheet-names' shape) -- PFSELFTEST hands
;;   a scratch folder and its own names (2026-10-30).
(defun pfn:scan-in (cdir pdir sn / new fill a st m inv top out r idx)
  (setq new 0 fill 0 idx (pfn:anchor-index)
        out (cdr sn))
  (if (null (car sn))
    (setq out (cons (strcat "  No grid names found on layer " *pf-name-layer* ".") out)))
  (foreach p (car sn)
    (cond
      ((setq a (pfn:find-in (car p) (cdr p) idx))
       (if (setq r (pfn:fill-anchor a (car p) (cdr p) pdir)) (setq out (cons r out) fill (1+ fill))))
      ((setq st (pfr:stub-get (car p) (cdr p)))
       (if (setq r (pfn:fill-stub st (car p) (cdr p) pdir)) (setq out (cons r out) fill (1+ fill))))
      ((null (setq m (pfn:cl-lookup cdir (car p) (cdr p))))
       (setq out (cons (strcat "  SKIPPED " (car p) " '" (cdr p) "' -- no " (car p) "_" (cdr p)
                               ".cl in the Alignments folder")
                       out)))
      ((eq m 'AMBIG)
       (setq out (cons (strcat "  SKIPPED " (car p) " '" (cdr p) "' -- more than one .cl matches; never guessed")
                       out)))
      (T
       (setq inv (pfn:pro-lookup pdir (car p) (cdr p) "INV")
             top (pfn:pro-lookup pdir (car p) (cdr p) "TOP")
             new (1+ new))
       (pfr:stub-put (car p) (cdr p) m inv top)
       (setq out (cons (strcat "  Named " (car p) " '" (cdr p) "'  (" (vl-filename-base m) ".cl"
                               (cond ((and inv top) " + INV/TOP .pro") ((or inv top) " + ONE .pro only")
                                     (" -- no .pro pair yet"))
                               ")")
                       out)))))
  ;; the other direction: a .cl with no grid name on the sheet (read only)
  (foreach f (vl-directory-files cdir "*.cl" 1)
    (setq r (pfl:line-parts (strcase (vl-filename-base f))))
    (if (and (member (car r) *pf-types*)
             (null (pfn:find-in (car r) (cdr r) idx))
             (null (pfr:stub-get (car r) (cdr r))))
      (setq out (cons (strcat "  NOTE: " f " has no grid name on the sheet") out))))
  (setq out (cons (strcat "  " (itoa new) " line(s) named, " (itoa fill) " late .pro binding(s).") out))
  (if (null pdir) (setq out (cons "  NOTE: no Profiles folder found -- .pro files not looked for." out)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 5  --  The record dialog  (V5's pfsetup_main, pf-grid.dcl)
;;; ==========================================================================
;;; d-cl d-inv d-top d-tine d-tind d-res live in pfn:dialog and are reached by
;;; the callbacks through dynamic scope while start_dialog runs.

;; (pfn:seed k rec) -> the starting value for the scales / datum: the record
;;   (Edit), then Carlson's own setting (scales), then this session's last
(defun pfn:seed (k rec / v)
  (cond
    ((numberp (setq v (pfn:g k rec))) v)
    ((and (= k 'hs) (boundp 'sv:sm) (numberp (eval 'sv:sm)) (> (eval 'sv:sm) 0)) (float (eval 'sv:sm)))
    ((and (= k 'vs) (boundp 'sv:vs) (numberp (eval 'sv:vs)) (> (eval 'sv:vs) 0)) (float (eval 'sv:vs)))
    ((cdr (assoc k *pfn-last*)))))

;; (pfn:remember rec) -> nil   what the next record starts from
(defun pfn:remember (rec / ty)
  (setq ty (strcase (pfn:g 'type rec)))
  (foreach k '(hs vs datum)
    (setq *pfn-last* (cons (cons k (pfn:g k rec)) (vl-remove-if '(lambda (c) (eq (car c) k)) *pfn-last*))))
  (if (pfn:nz (pfn:g 'material rec))
    (setq *pfn-last* (cons (cons ty (pfn:g 'material rec)) (vl-remove-if '(lambda (c) (equal (car c) ty)) *pfn-last*))))
  (princ))

(defun pfn:show (key f) (set_tile key (if f (strcat (vl-filename-base f) (vl-filename-extension f)) "")))

(defun pfn:fill-mats (sel / mats i)
  (setq mats (pfp:mats))
  (start_list "s_mat") (foreach m mats (add_list m)) (end_list)
  (if mats (set_tile "s_mat" (itoa (cond ((and sel (setq i (vl-position sel mats))) i) (0))))))

(defun pfn:on-type ( / ty)
  (setq ty (nth (atoi (get_tile "s_type")) *pf-types*))
  (pfn:fill-mats (cdr (assoc ty *pfn-last*))))

(defun pfn:on-cl ( / f i p)
  (if (setq f (pff:browse "Select Centerline (.CL) File" "cl"))
    (progn
      (setq d-cl f p (pfl:line-parts (strcase (vl-filename-base f))))
      (pfn:show "s_cl" f)
      (if (= (vl-string-trim " " (get_tile "s_name")) "") (set_tile "s_name" (cdr p)))
      (if (setq i (vl-position (car p) *pf-types*))
        (progn (set_tile "s_type" (itoa i)) (pfn:on-type)))
      (set_tile "error" ""))))

(defun pfn:on-pro (role / f)
  (if (setq f (pff:browse (strcat "Select the _" role " Profile (.PRO) File") "pro"))
    (if (/= (cdr (pfl:pro-parts f)) role)
      (set_tile "error" (strcat "'" (vl-filename-base f) "' is not a _" role " .pro."))
      (progn
        (if (= role "INV") (setq d-inv f) (setq d-top f))
        (pfn:show (if (= role "INV") "s_inv" "s_top") f)
        (set_tile "error" "")))))

(defun pfn:on-tin (design / f)
  (if (setq f (pff:browse (if design "Select the DESIGN_* (proposed) Surface (.TIN) File"
                                     "Select the EXISTING Ground Surface (.TIN) File")
                          "tin"))
    (cond
      ((and design (not (pfl:tin-design-p f)))
       (set_tile "error" (strcat "'" (vl-filename-base f) "' is not a DESIGN_* surface.")))
      ((and (not design) (pfl:tin-design-p f))
       (set_tile "error" (strcat "'" (vl-filename-base f) "' is DESIGN_* -- pick the existing ground.")))
      (design (setq d-tind f) (pfn:show "s_tind" f) (set_tile "error" ""))
      (T (setq d-tine f) (pfn:show "s_tine" f) (set_tile "error" "")))))

(defun pfn:on-ok ( / ty mats rec msg)
  (setq ty   (nth (atoi (get_tile "s_type")) *pf-types*)
        mats (pfp:mats)
        rec  (list (cons 'type ty)
                   (cons 'name (strcase (vl-string-trim " " (get_tile "s_name"))))
                   (cons 'material (if mats (nth (atoi (get_tile "s_mat")) mats) ""))
                   (cons 'hs (distof (get_tile "s_hs") 2))
                   (cons 'vs (distof (get_tile "s_vs") 2))
                   (cons 'datum (distof (get_tile "s_datum") 2))
                   (cons 'cl d-cl) (cons 'inv d-inv) (cons 'top d-top)
                   (cons 'tine d-tine) (cons 'tind d-tind)
                   (cons 'repick (= (get_tile "s_repick") "1"))))
  (if (setq msg (pfn:validate rec))
    (set_tile "error" msg)
    (progn (setq d-res rec) (done_dialog 1))))

;; (pfn:dialog init) -> rec | nil (cancelled)
(defun pfn:dialog (init / id d-cl d-inv d-top d-tine d-tind d-res i r v)
  (setq id (load_dialog (strcat *pf-root* "\\pf-grid\\pf-grid.dcl")))
  (cond
    ((< id 0) (pfl:say "PFSETUP: can't load pf-grid.dcl.") nil)
    ((not (new_dialog "pfsetup_main" id)) (unload_dialog id) (pfl:say "PFSETUP: can't open its dialog.") nil)
    (T
     (setq d-cl (pfn:g 'cl init) d-inv (pfn:g 'inv init) d-top (pfn:g 'top init)
           d-tine (pfn:g 'tine init) d-tind (pfn:g 'tind init))
     (start_list "s_type") (foreach ty *pf-types* (add_list ty)) (end_list)
     (set_tile "s_type" (itoa (cond ((setq i (vl-position (pfn:g 'type init) *pf-types*))) (0))))
     (pfn:fill-mats (cond ((pfn:g 'material init))
                          ((cdr (assoc (nth (atoi (get_tile "s_type")) *pf-types*) *pfn-last*)))))
     (set_tile "s_name" (cond ((pfn:g 'name init)) ("")))
     (if (setq v (pfn:seed 'hs init)) (set_tile "s_hs" (rtos v 2 2)))
     (if (setq v (pfn:seed 'vs init)) (set_tile "s_vs" (rtos v 2 2)))
     (if (setq v (pfn:seed 'datum init)) (set_tile "s_datum" (rtos v 2 2)))
     (pfn:show "s_cl" d-cl) (pfn:show "s_inv" d-inv) (pfn:show "s_top" d-top)
     (pfn:show "s_tine" d-tine) (pfn:show "s_tind" d-tind)
     (set_tile "s_repick" "0")
     (if (not (pfn:g 'edit init)) (mode_tile "s_repick" 1))
     (action_tile "s_type"      "(pfn:on-type)")
     (action_tile "s_cl_pick"   "(pfn:on-cl)")
     (action_tile "s_inv_pick"  "(pfn:on-pro \"INV\")")
     (action_tile "s_top_pick"  "(pfn:on-pro \"TOP\")")
     (action_tile "s_tine_pick" "(pfn:on-tin nil)")
     (action_tile "s_tind_pick" "(pfn:on-tin T)")
     (action_tile "s_pro_clr"   "(progn (setq d-inv nil d-top nil) (pfn:show \"s_inv\" nil) (pfn:show \"s_top\" nil))")
     (action_tile "s_tin_clr"   "(progn (setq d-tine nil d-tind nil) (pfn:show \"s_tine\" nil) (pfn:show \"s_tind\" nil))")
     (action_tile "accept"      "(pfn:on-ok)")
     (action_tile "cancel"      "(done_dialog 0)")
     (action_tile "help"
       "(alert \"PFSETUP records a profile grid.\\n\\nName is the identity key -- picked files validate against it.\\nBind the .cl (station source), the _INV/_TOP .pro pair and the existing + DESIGN_* surfaces (each pair both-or-neither).\\n\\nType the datum elevation (lower-left grid corner), then OK: pick LOWER-LEFT, then TOP-RIGHT.\")")
     (setq r (vl-catch-all-apply 'start_dialog nil))
     (unload_dialog id)
     (cond
       ((vl-catch-all-error-p r) (pfl:say (strcat "Dialog error: " (vl-catch-all-error-message r))) nil)
       ((= r 1) d-res)))))


;;; ==========================================================================
;;; SECTION 6  --  Anchor and Edit
;;; ==========================================================================

;; (pfn:pick-corners) -> (ll tr) WORLD | nil
(defun pfn:pick-corners ( / ll tr)
  (cond
    ((null (setq ll (getpoint "\nPick the grid's LOWER-LEFT corner (on the datum line): "))) nil)
    ((null (setq tr (getcorner ll "\nPick the grid's TOP-RIGHT corner: "))) nil)
    ((or (<= (car tr) (car ll)) (<= (cadr tr) (cadr ll)))
     (pfl:say "Top-right must be above and right of lower-left -- cancelled.") nil)
    (T (list (trans ll 1 0) (trans tr 1 0)))))

;; (pfn:anchored-msg rec) -> the refusal when rec's line has an anchor | nil
(defun pfn:anchored-msg (rec)
  (if (pfn:find-anchor (pfn:g 'type rec) (pfn:g 'name rec))
    (strcat (pfn:g 'type rec) " '" (pfn:g 'name rec) "' is already anchored -- use Edit.")))

;; (pfn:place-rec rec stub) -> anchor | refusal string.  The work of Anchor,
;;   no questions -- what PFSELFTEST drives (2026-10-30).  rec: complete, ll
;;   and tr included.  stub: the stub it came from (deleted once anchored) |
;;   nil.
(defun pfn:place-rec (rec stub / r)
  (cond
    ((setq r (pfn:anchored-msg rec)) r)
    ((= (type (setq r (pfn:make rec))) 'STR) (strcat "REFUSED -- " r))
    (T (if stub (pfr:stub-del (car stub) (cadr stub))) r)))

;; (pfn:place stub) -> nil   stub: (type name cl inv top) | nil (blank form)
(defun pfn:place (stub / init rec pts r)
  (if stub
    (setq init (list (cons 'type (car stub)) (cons 'name (cadr stub)) (cons 'cl (caddr stub))
                     (cons 'inv (pfn:nz (nth 3 stub))) (cons 'top (pfn:nz (nth 4 stub))))))
  (cond
    ((null (setq rec (pfn:dialog init))) (pfl:say "Cancelled -- nothing written."))
    ;; asked before the picks, so nobody picks two corners to be refused
    ((setq r (pfn:anchored-msg rec)) (pfl:say r))
    ((null (setq pts (pfn:pick-corners))) (pfl:say "Cancelled -- nothing written."))
    (T
     (pfn:remember rec)
     (setq rec (append (list (cons 'll (car pts)) (cons 'tr (cadr pts))) rec)
           r   (pfn:place-rec rec stub))
     (if (= (type r) 'STR)
       (pfl:say r)
       (progn
         (pfl:say (strcat "Anchored " (pfn:g 'type rec) " '" (pfn:g 'name rec) "'.  Run PFASSIGN to put"
                          " structures on it."))
         (foreach s (pfn:checks r (pfg:top-lines) (pfn:grid-lines)) (pfl:say (strcat "  ** " s)))))))
  (princ))

;; (pfn:edit-check anchor rec) -> refusal string | 'UNKNOWN (go ahead -- the
;;   old .cl can't be read, so the station ranges weren't compared) | nil (go)
(defun pfn:edit-check (anchor rec / at rm)
  (setq at (pfg:atts anchor))
  (cond
    ((or (/= (strcase (pfg:att *pf-anc-line* at)) (strcase (pfn:g 'name rec)))
         (/= (strcase (pfg:att *pf-anc-util* at)) (strcase (pfn:g 'type rec))))
     (strcat "REFUSED -- a new name or utility is a NEW grid.  PFREMOVE this one, then"
             " PFSETUP Anchor it fresh."))
    ((null (setq rm (pfn:range-same (pfn:g 'cl (pfn:rec-of anchor)) (pfn:g 'cl rec))))
     "REFUSED -- the new .cl has a DIFFERENT station range: a rebuild, not a swap.  PFREMOVE, then anchor it fresh.")
    ((null (pfc:cl-range (pfn:g 'cl rec)))
     (strcat "REFUSED -- Carlson can't read a station range from " (vl-filename-base (pfn:g 'cl rec)) ".cl"))
    ((eq rm 'UNKNOWN) 'UNKNOWN)))

;; (pfn:corners anchor) -> (ll tr) the grid's corners on record | nil (an old
;;   anchor that never kept its width)
(defun pfn:corners (anchor / g)
  (if (and (setq g (pfg:grid anchor)) (pfl:g 'rightx g))
    (list (pfl:ins anchor) (list (pfl:g 'rightx g) (pfl:g 'topy g)))))

;; (pfn:edit-write anchor rec pts) -> T   The work of Edit, no questions --
;;   rec past pfn:edit-check, pts the corners (ll tr).
(defun pfn:edit-write (anchor rec pts)
  (setq rec (append (list (cons 'll (car pts)) (cons 'tr (cadr pts))) rec))
  (pfd:move anchor (car pts))
  (pfd:rescale anchor (/ (pfn:g 'hs rec) *pf-anc-icon-hplot*))
  (pfn:write anchor rec (car (pfc:cl-range (pfn:g 'cl rec))))
  ;; a V5 anchor gets V6 records now, stamped with its own handle
  (if (null (pfr:val-get anchor *pf-xd-stamp*)) (pfr:val-put anchor *pf-xd-stamp* (pfl:handle anchor)))
  T)

;; (pfn:edit anchor) -> nil
(defun pfn:edit (anchor / rec r pts)
  (foreach s (pfn:checks anchor (pfg:top-lines) (pfn:grid-lines)) (pfl:say (strcat "  ** " s)))
  (cond
    ((null (setq rec (pfn:dialog (pfn:rec-of anchor)))) (pfl:say "Cancelled -- nothing written."))
    ((= (type (setq r (pfn:edit-check anchor rec))) 'STR) (pfl:say r))
    (T
     (if (eq r 'UNKNOWN) (pfl:say "  NOTE: the old .cl can't be read -- the station range wasn't compared."))
     (setq pts (cond
                 ((pfn:g 'repick rec) (pfn:pick-corners))
                 ((pfn:corners anchor))
                 (T (pfl:say "  No width on record (an old anchor) -- pick the corners.") (pfn:pick-corners))))
     (cond
       ((null pts) (pfl:say "Cancelled -- nothing written."))
       (T
        (pfn:remember rec)
        (pfn:edit-write anchor rec pts)
        (pfl:say (strcat "Updated " (pfn:g 'type rec) " '" (pfn:g 'name rec) "' in place.  PFASSIGN, then"
                         " PFREFRESH, to bring the profile along."))))))
  (princ))


;;; ==========================================================================
;;; SECTION 7  --  PFREMOVE
;;; ==========================================================================
;;; Jake, 2026-10-30: nothing is deleted but the anchor, unless asked -- the
;;; line just leaves the line table.  "Anchor": what sat on the grid stays, but
;;; RELEASED, so the suite never touches it again (a refresh would otherwise
;;; erase the copies as orphans and re-label the pipes against the nearest
;;; OTHER grid).  "Everything": those are erased too.

;; (pfn:on-grid anchor) -> (copies pipes leaders) whose grid is this anchor's
(defun pfn:on-grid (anchor / cs ps ls ends)
  (foreach c (pfs:copies) (if (eq (nth 3 c) anchor) (setq cs (cons (car c) cs))))
  (foreach p (pfp:all)
    (if (and (setq ends (pfp:ends p)) (eq (pfg:anchor-of (car ends)) anchor))
      (setq ps (cons p ps) ls (append (pfp:leaders p) ls))))
  (list cs ps ls))

;; (pfn:remove anchor mode objs) -> count of objects erased or released
;;   mode "Anchor" | "Everything".  objs from pfn:on-grid.
(defun pfn:remove (anchor mode objs / title n)
  (setq title (if (pfg:grid anchor) (pfg:title (pfg:grid anchor)) "a removed grid") n 0)
  (foreach e (apply 'append objs)
    (if (and e (entget e))
      (progn
        (if (= mode "Everything") (pfd:erase e) (pfr:release e title))
        (setq n (1+ n)))))
  (pfd:erase anchor)
  n)

;; (pfn:remove-main) -> nil   the command body
(defun pfn:remove-main ( / pt hit a g objs mode ans n)
  (cond
    ((null (setq pt (getpoint "\nClick the grid to remove (anywhere inside it): "))))
    ((null (setq hit (pfg:nearest (trans pt 1 0)))) (pfl:say "PFREMOVE: no grids in this drawing."))
    ((pfg:copy-p (setq a (car hit)))
     (initget "Yes No")
     (if (= "Yes" (getkword "\nThat anchor is a COPY of another one.  Erase just the copy?  [Yes/No] <No>: "))
       (progn (pfd:erase a) (pfl:say "Copied anchor erased."))
       (pfl:say "Nothing removed.")))
    (T
     (setq g    (pfg:grid a)
           objs (pfn:on-grid a))
     (pfl:say (strcat "Grid " (if g (pfg:title g) "(unreadable)") ":  "
                      (itoa (length (car objs))) " profile structure(s), "
                      (itoa (length (cadr objs))) " pipe(s), "
                      (itoa (length (caddr objs))) " pipe-label leader(s) on it."))
     (initget "Anchor Everything")
     (setq mode (cond ((getkword "\nRemove [Anchor/Everything] <Anchor>: ")) ("Anchor")))
     (initget "Yes No")
     (setq ans (getkword (strcat "\n" (if (= mode "Anchor")
                                         "Erase the anchor; leave what's on the grid, released.  Sure?"
                                         "Erase the anchor AND everything listed.  Sure?")
                                 "  [Yes/No] <No>: ")))
     (if (/= ans "Yes")
       (pfl:say "Nothing removed.")
       (progn
         (setq n (pfn:remove a mode objs))
         (pfl:say (strcat "Removed the anchor"
                          (if (= mode "Anchor")
                            (strcat "; " (itoa n) " object(s) left in place, released -- the suite leaves them alone.")
                            (strcat " and " (itoa n) " object(s)."))))
         (pfl:say "  The line has left the line table: PFASSIGN takes it off its structures (a junction's name drops it).")
         (pfl:say "  One UNDO takes this back.")))))
  (princ))

(defun c:PFREMOVE ()
  (if (null pfd:run)
    (pfl:say "PFREMOVE: load pf-load.lsp first.")
    (pfd:run "PFREMOVE" 'pfn:remove-main))
  (princ))


;;; ==========================================================================
;;; SECTION 8  --  PFSETUP
;;; ==========================================================================

;; (pfn:pick-stub) -> a stub | 'NEW (blank form) | nil
(defun pfn:pick-stub ( / stubs i n idx)
  (setq idx (pfn:anchor-index))
  (foreach s (pfm:stubs)
    (if (not (pfn:find-in (car s) (cadr s) idx))
      (setq stubs (cons (append s (list (cdr (assoc 4 (pfr:stub-get (car s) (cadr s))))
                                        (cdr (assoc 5 (pfr:stub-get (car s) (cadr s))))))
                        stubs))))
  (setq stubs (reverse stubs) i 0)
  (pfl:say "  Lines named but not anchored yet:")
  (if (null stubs) (pfl:say "    (none -- run PFSETUP Scan, or use 0 for a blank form)"))
  (foreach s stubs (pfl:say (strcat "    " (itoa (setq i (1+ i))) "  " (car s) " '" (cadr s) "'")))
  (pfl:say "    0  a new grid, blank form")
  (initget 4)
  (setq n (getint "\nNumber <Enter = cancel>: "))
  (cond ((null n) nil) ((= n 0) 'NEW) ((<= n (length stubs)) (nth (1- n) stubs))))

;; (pfn:main) -> nil   the command body
(defun pfn:main ( / k s top gl pt hit)
  (pfc:load)
  (cond
    ((pfc:metric-p) (pfl:say "PFSETUP: this is a METRIC drawing.  V6 is english-only and refuses."))
    ((not (pfc:ready-p)) (pfl:say "PFSETUP: Carlson isn't loaded."))
    (T
     (initget "Scan Anchor Edit")
     (setq k (cond ((getkword "\nPFSETUP [Scan/Anchor/Edit] <Scan>: ")) ("Scan")))
     (cond
       ((= k "Anchor")
        (setq *pfd-stage* "anchoring a grid")
        (cond ((null (setq s (pfn:pick-stub))) (pfl:say "Cancelled."))
              ((eq s 'NEW) (pfn:place nil))
              (T (pfn:place s))))
       ((= k "Edit")
        (setq *pfd-stage* "editing a grid")
        (cond
          ((null (setq pt (getpoint "\nClick the grid to edit (anywhere inside it): "))))
          ((null (setq hit (pfg:nearest (trans pt 1 0)))) (pfl:say "PFSETUP: no grids in this drawing."))
          ((pfg:copy-p (car hit)) (pfl:say "That anchor is a COPY of another one -- PFREMOVE it."))
          (T (pfn:edit (car hit)))))
       (T
        (pfl:say "")
        (pfl:say "=== PFSETUP  scan ===")
        (setq *pfd-stage* "scanning the grid names")
        (foreach s (pfn:scan) (pfl:say s))
        (setq *pfd-stage* "checking the anchors" top (pfg:top-lines) gl (pfn:grid-lines))
        (pfl:say "")
        (pfl:say "  Anchor checks:")
        (setq k nil)
        (foreach a (pfg:all)
          (if (setq s (pfn:checks a top gl))
            (progn
              (setq k T)
              (pfl:say (strcat "    " (if (pfg:grid a) (pfg:title (pfg:grid a)) (pfl:handle a))))
              (foreach f s (pfl:say (strcat "      ** " f))))))
        (if (not k) (pfl:say "    all fine"))
        (pfl:say "  One UNDO takes this whole run back.")))))
  (princ))

(defun c:PFSETUP ()
  (if (null pfd:run)
    (pfl:say "PFSETUP: load pf-load.lsp first.")
    (pfd:run "PFSETUP" 'pfn:main))
  (princ))


(princ "\npf-grid loaded.  PFSETUP, PFREMOVE.")
(princ)
