;;; ==========================================================================
;;; pf-anchor.lsp  --  read the profile grid anchors.  READ ONLY.
;;; Load position 6: after pf-cfg, pf-lib, pf-files.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; Reads PFSUITE_ANCHOR and V5's PF-ANCHOR / PF-GRIDANCHOR the same way.
;;; Making an anchor is pf-grid's job (not written yet).
;;;
;;; Every profile grid in our drawings already has a V5 PF-ANCHOR block at its
;;; lower-left corner.  It carries the grid (starting station, datum, plot
;;; scales, size) and, in its records, which .cl the profile was cut along.
;;; So a V6 command never asks for a centerline or grid numbers -- you click
;;; inside the grid and everything comes from its anchor.
;;;
;;; NOTHING HERE WRITES.  Not to the anchor, not to its records, not to the
;;; drawing.  That keeps the same drawing working in V5, and it is the one
;;; exception to "only pf-record touches entity data": these are V5's
;;; entities, and we only look at them.
;;;
;;; Ported from V5 pfanchor.lsp (find / read / extents / ledger read / copy
;;; check), pftools-lib.lsp (the transform) and pfpro.lsp (which grid a point
;;; belongs to).
;;;
;;; A grid here is pf-lib's grid alist -- so pfl:sta->x and friends work on it
;;; unchanged -- with these extra keys:
;;;   topy rightx hplot vplot line util cl pro-inv pro-top tin-exist
;;;   tin-design material anchor
;;; rightx is nil on an old anchor that never recorded its width.
;;; ==========================================================================

(vl-load-com)

;;; ---- reading the anchor ---------------------------------------------------

;; (pfg:all) -> every anchor insert in model space, copies included.
;;   Anonymous *U names are fetched too and kept only when their real name
;;   is an anchor's: a DYNAMIC anchor is filed under *U123 once placed, and a
;;   search by name alone would miss it.
(defun pfg:all ( / ss i e out)
  (if (setq ss (ssget "_X" (list '(0 . "INSERT")
                                 (cons 2 (strcat *pf-anchor-blocks* ",`*U*"))
                                 '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))))
      (if (wcmatch (strcase (pfl:effname e)) (strcase *pf-anchor-blocks*))
        (setq out (cons e out)))))
  out)

;; (pfg:atts anchor) -> (("TAG" . "value") ...)
(defun pfg:atts (anchor / e ed out)
  (setq e (entnext anchor))
  (while (and e (setq ed (entget e)) (= (cdr (assoc 0 ed)) "ATTRIB"))
    (setq out (cons (cons (strcase (cdr (assoc 2 ed))) (cdr (assoc 1 ed))) out)
          e   (entnext e)))
  (reverse out))

;; (pfg:att tag atts) -> value, "" when absent (never nil)
(defun pfg:att (tag at / v)
  (if (setq v (cdr (assoc (strcase tag) at))) v ""))

;; (pfg:num s) -> number | nil   also reads "1+00" in case someone typed one
(defun pfg:num (s)
  (cond ((or (null s) (= s "")) nil)
        ((distof s 2))
        ((and (vl-string-search "+" s) (pfl:number-p (vl-string-subst "" "+" s)))
         (pfl:parse-sta s))))

;; (pfg:extents anchor) -> (width height), either may be nil
;;   Current anchors store them in WIDTH/HEIGHT.  An anchor with no HEIGHT is
;;   the old kind, whose insert scales were the grid size -- V5's rule,
;;   including its guard that no real grid is 2 ft wide.
(defun pfg:extents (anchor / at w h ed xs ys)
  (setq at (pfg:atts anchor)
        w  (pfg:num (pfg:att *pf-anc-width*  at))
        h  (pfg:num (pfg:att *pf-anc-height* at)))
  (if (and h (> h 0.0))
    (list (if (and w (> w 0.0)) w) h)
    (progn
      (setq ed (entget anchor)
            xs (cdr (assoc 41 ed))
            ys (cdr (assoc 42 ed)))
      (list (if (and xs (> xs 2.0)) xs)
            (if (and ys (> ys 0.0)) ys)))))


;;; ---- the anchor's records -------------------------------------------------

(defun pfg:extdict (ent / in out)
  (foreach p (entget ent)
    (cond
      ((and (= (car p) 102) (= (cdr p) "{ACAD_XDICTIONARY")) (setq in T))
      ((and in (= (car p) 360) (null out)) (setq out (cdr p)))
      ((and (= (car p) 102) (= (cdr p) "}")) (setq in nil))))
  out)

;; (pfg:ledger anchor) -> the anchor's record dictionary | nil
;;   V5 renames the old dictionary on its first WRITE.  We never write, so we
;;   just read whichever is there.
(defun pfg:ledger (anchor / xd sub)
  (if (setq xd (pfg:extdict anchor))
    (cond
      ((setq sub (dictsearch xd *pf-anc-dict*))        (cdr (assoc -1 sub)))
      ((setq sub (dictsearch xd *pf-anc-dict-legacy*)) (cdr (assoc -1 sub))))))

;; (pfg:rec anchor key) -> the record's data groups | nil
(defun pfg:rec (anchor key / d cur tail)
  (if (and (setq d (pfg:ledger anchor))
           (setq cur (dictsearch d key)))
    (progn
      (setq tail (cdr (member (assoc 100 cur) cur)))
      (if (and tail (= (caar tail) 280)) (setq tail (cdr tail)))
      tail)))

;; (pfg:code k data) -> that group's value, nil when missing or blank
(defun pfg:code (k data / v)
  (setq v (cdr (assoc k data)))
  (if (and v (/= v "")) v))

;; (pfg:stamp anchor) -> the handle stamped on the anchor when it was made | nil
(defun pfg:stamp (anchor)
  (pfg:code 302 (pfg:rec anchor *pf-anc-meta*)))

;; (pfg:copy-p anchor) -> T when this anchor is a COPY of another one.
;;   A copy keeps the original's stamp, so a copy shows up as TWO anchors
;;   sharing one stamp -- the one whose own handle matches it is the
;;   original.  An anchor whose stamp NO other anchor shares is never a copy,
;;   even when its handle no longer matches: that is a drawing whose handles
;;   were all renumbered (contents copied into a new drawing).  V5's plain
;;   "stamp /= handle" rule flagged all 67 anchors in V6_Test (2026-10-15).
;;   An anchor with no stamp is never called a copy.
(defun pfg:copy-p (anchor / self mine twin)
  (setq self (cdr (assoc 5 (entget anchor)))
        mine (pfg:stamp anchor))
  (cond
    ((null mine) nil)
    ((= mine self) nil)
    (T
     (foreach a (pfg:all)
       (if (and (null twin) (not (eq a anchor)) (= (pfg:stamp a) mine))
         (setq twin a)))
     (and twin T))))


;;; ---- the grid -------------------------------------------------------------

;; (pfg:cl-att at) -> the CL attribute as a .cl file name | nil when blank.
;;   A name typed without its extension gets ".cl".
(defun pfg:cl-att (at / v)
  (setq v (vl-string-trim " \t\"" (pfg:att *pf-anc-cl* at)))
  (cond
    ((= v "") nil)
    ((vl-filename-extension v) v)
    (T (strcat v ".cl"))))

;; (pfg:grid anchor) -> grid alist | nil when its numbers cannot be read
;;   The .cl: the anchor's CL attribute first (PFSUITE_ANCHOR), then the
;;   ledger's META record (V5's anchors).
(defun pfg:grid (anchor / ins ext at sta0 datum hp vp meta files)
  (setq ins   (cdr (assoc 10 (entget anchor)))
        ext   (pfg:extents anchor)
        at    (pfg:atts anchor)
        sta0  (pfg:num (pfg:att *pf-anc-sta0*  at))
        datum (pfg:num (pfg:att *pf-anc-datum* at))
        hp    (pfg:num (pfg:att *pf-anc-hplot* at))
        vp    (pfg:num (pfg:att *pf-anc-vplot* at)))
  (if (and ins (cadr ext) sta0 datum hp vp (> hp 0.0) (> vp 0.0))
    (progn
      (setq meta  (pfg:rec anchor *pf-anc-meta*)
            files (pfg:rec anchor *pf-anc-files*))
      (append
        (pfl:grid (car ins) (cadr ins) sta0 datum (/ hp vp))
        (list (cons 'topy       (+ (cadr ins) (cadr ext)))
              (cons 'rightx     (if (car ext) (+ (car ins) (car ext))))
              (cons 'hplot      hp)
              (cons 'vplot      vp)
              (cons 'line       (strcase (pfg:att *pf-anc-line* at)))
              (cons 'util       (strcase (pfg:att *pf-anc-util* at)))
              (cons 'cl         (cond ((pfg:cl-att at)) ((pfg:code 1 meta))))
              (cons 'pro-inv    (pfg:code 1 files))
              (cons 'pro-top    (pfg:code 2 files))
              (cons 'tin-exist  (pfg:code 3 files))
              (cons 'tin-design (pfg:code 4 files))
              (cons 'material   (pfg:code 5 files))
              (cons 'anchor     anchor))))))

;; (pfg:title g) -> "STORM 'CA'"
(defun pfg:title (g)
  (strcat (pfl:g 'util g) " '" (pfl:g 'line g) "'"))

;; (pfg:text-ht g) -> text height for this grid's plot scale
(defun pfg:text-ht (g)
  (* *pf-text-base* (/ (pfl:g 'hplot g) *pf-ref-hplot*)))

;; (pfg:sta-range g) -> (first last) station shown on the grid | nil if the
;;   anchor never recorded its width
(defun pfg:sta-range (g)
  (if (pfl:g 'rightx g)
    (list (pfl:g 'sta0 g) (pfl:x->sta (pfl:g 'rightx g) g))))

;; (pfg:on-grid-p sta g) -> T when that station falls on the grid (or the
;;   width is unknown, in which case we cannot say it does not)
(defun pfg:on-grid-p (sta g / r)
  (or (null (setq r (pfg:sta-range g)))
      (and (>= sta (- (car r) 0.01)) (<= sta (+ (cadr r) 0.01)))))

;; (pfg:cl g) -> the profile's .cl path, checked to exist | nil
;;   The stored path first.  If that file is gone -- project copied or moved --
;;   the same file name in the firm's Alignments folder.
(defun pfg:cl (g / p)
  (setq p (pfl:g 'cl g))
  (cond
    ((null p) nil)
    ((findfile p))
    ((pff:find-in-std p "cl"))))

;; (pfg:line-name g) -> "STORM_CA"   the name MEMB files this line under:
;;   the .cl file's name, same as PFASSIGN has always used.
(defun pfg:line-name (g / p)
  (if (setq p (pfl:g 'cl g)) (strcase (vl-filename-base p))))


;;; ---- which grid is this point in? ------------------------------------------
;;; V5 pfpro's rule: the grid whose BOX is nearest the point -- zero when the
;;; point is inside.  Distance to the box, not to the anchor: the anchor is a
;;; corner, so on stacked sheets a point high in the lower grid is nearer the
;;; upper grid's anchor than its own.

;; (pfg:box-dist p ins ext) -> 0 inside the box, else the distance to it.
;;   A missing width or height leaves that side open.
(defun pfg:box-dist (p ins ext / x0 y0 x1 y1 dx dy)
  (setq x0 (car ins) y0 (cadr ins)
        x1 (if (car ext)  (+ x0 (car ext)))
        y1 (if (cadr ext) (+ y0 (cadr ext)))
        dx (cond ((< (car p) x0) (- x0 (car p)))
                 ((and x1 (> (car p) x1)) (- (car p) x1))
                 (T 0.0))
        dy (cond ((< (cadr p) y0) (- y0 (cadr p)))
                 ((and y1 (> (cadr p) y1)) (- (cadr p) y1))
                 (T 0.0)))
  (sqrt (+ (* dx dx) (* dy dy))))

;; (pfg:nearest pt) -> (anchor . distance) | nil   pt in WORLD coordinates.
;;   Copies are candidates here and refused by the caller if one wins --
;;   skipping them would hand a point inside a copy to the wrong real grid.
(defun pfg:nearest (pt / best bestd ins d)
  (foreach a (pfg:all)
    (if (setq ins (cdr (assoc 10 (entget a))))
      (progn
        (setq d (pfg:box-dist pt ins (pfg:extents a)))
        (if (or (null bestd) (< d bestd)) (setq best a bestd d)))))
  (if best (cons best bestd)))

;; (pfg:at pt) -> grid | nil, saying why when nil.   pt in WORLD coordinates.
(defun pfg:at (pt / hit g)
  (cond
    ((null (setq hit (pfg:nearest pt)))
     (pfl:say (strcat "No profile grids in this drawing -- no " *pf-anchor-blocks* " blocks found."))
     nil)
    ((pfg:copy-p (car hit))
     (pfl:say "The nearest grid's anchor is a COPY of another anchor (they carry the same stamp), so it is not used.  Erase the copy.")
     nil)
    ((null (setq g (pfg:grid (car hit))))
     (pfl:say "The nearest grid's anchor is missing its station, datum, scales or height -- check it in Properties.")
     nil)
    (T
     (if (> (cdr hit) 0.0)
       (pfl:say (strcat "Note: that point is " (rtos (cdr hit) 2 2)
                        "' outside grid " (pfg:title g) " -- using it anyway.")))
     g)))

;; (pfg:pick msg) -> grid | nil   asks for a point, returns its grid
(defun pfg:pick (msg / pt)
  (if (setq pt (getpoint msg)) (pfg:at (trans pt 1 0))))

;; (pfg:anchor-of pt) -> the non-copy anchor whose grid this point is in | nil
;;   Quiet version of pfg:at, for sorting existing objects onto grids.
(defun pfg:anchor-of (pt / hit)
  (if (and (setq hit (pfg:nearest pt)) (not (pfg:copy-p (car hit))))
    (car hit)))

;; (pfg:usable) -> every usable grid in the drawing, sorted by title: not a
;;   copied anchor, its numbers readable, a .cl on record.  What PFSTRUCT and
;;   PFREFRESH work over -- neither asks for a grid pick (Jake, 2026-10-16).
(defun pfg:usable ( / out g)
  (foreach a (pfg:all)
    (if (and (not (pfg:copy-p a)) (setq g (pfg:grid a)) (pfg:line-name g))
      (setq out (cons g out))))
  (vl-sort out '(lambda (a b) (< (pfg:title a) (pfg:title b)))))

;; (pfg:grid-for lname sta prefer grids) -> the grid of line lname that shows
;;   station sta | nil.  prefer (an anchor, or nil) wins when it qualifies --
;;   a copy stays on its own grid when the station still fits there.
(defun pfg:grid-for (lname sta prefer grids / pg hit)
  (if (and prefer (setq pg (pfg:grid prefer))
           (= (pfg:line-name pg) lname) (pfg:on-grid-p sta pg))
    pg
    (progn
      (foreach g grids
        (if (and (null hit) (= (pfg:line-name g) lname) (pfg:on-grid-p sta g))
          (setq hit g)))
      hit)))


;;; ---- top of grid ------------------------------------------------------------
;;; V5's probe, unchanged: straight up from the structure, the HIGHEST line on
;;; the grid's top layer.  Grids have stepped tops, so it is per station.  The
;;; ray stops a margin above the anchor's top so it never reads the next grid.

;; (pfg:top-lines) -> ((p1 p2) ...) every LINE on the top layer.  Read once
;;   per run and handed to pfg:top-at.
(defun pfg:top-lines ( / ss i ed out)
  (if (setq ss (ssget "_X" (list '(0 . "LINE") (cons 8 *pf-top-layer*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq ed  (entget (ssname ss (setq i (1- i))))
            out (cons (list (list (car (cdr (assoc 10 ed))) (cadr (cdr (assoc 10 ed))))
                            (list (car (cdr (assoc 11 ed))) (cadr (cdr (assoc 11 ed)))))
                      out))))
  out)

;; (pfg:top-at x g lines) -> Y of the grid top above x | nil when no line is
;;   found there.  The caller decides what nil means -- no silent fallback to
;;   the anchor's recorded top (Jake, 2026-10-16).
(defun pfg:top-at (x g lines / pa pb best hit)
  (setq pa (list x (pfl:g 'basey g))
        pb (list x (+ (pfl:g 'topy g)
                      (* *pf-top-margin* (/ (pfl:g 'hplot g) *pf-ref-hplot*)))))
  (foreach l lines
    (if (setq hit (inters pa pb (car l) (cadr l)))
      (if (or (null best) (> (cadr hit) best)) (setq best (cadr hit)))))
  best)


(princ "\npf-anchor loaded.")
(princ)
