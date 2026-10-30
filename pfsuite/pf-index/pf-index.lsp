;;; ==========================================================================
;;; pf-index.lsp  --  which lines a plan structure sits on.
;;; Load position 7: after pf-cfg, pf-lib, pf-carlson, pf-files, pf-record,
;;; pf-anchor.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; The membership record lives ON THE STRUCTURE, not on the line: MEMB is
;;; ((line station offset) ...), one entry per line it touches.  V5 learned
;;; that the hard way (pfanchor/INDEX-DESIGN.md: "index the structure, not
;;; the line") -- a structure with two entries IS a junction, no cross-line
;;; read needed.
;;;
;;; Two jobs, both run by PFASSIGN (Jake, 2026-10-27: no pick -- it goes by
;;; line membership, drawing-wide):
;;;   - V5's LINE TREE (ported 2026-10-22): every line (the grids plus V5's
;;;     grid-less stubs), every structure numbered along every line it is on
;;;     (lowest station = 1), and its name built from that -- "BA-5/BC-1",
;;;     written as a tool value; a name typed by hand is kept.
;;;   - assigning: every plan structure's lines, stations, face and rim into
;;;     MEMB and its attributes (SECTION 5).
;;;
;;; WHERE A POINT IS ON A LINE is measured against the .cl FILE, read here,
;;; not asked of Carlson.  Carlson's cl_location_at_pt answers nothing for a
;;; point just past a bend (no square-on foot), and V5 silently dropped those
;;; structures -- its one CRITICAL open bug.  It also prints an uncatchable
;;; error when it fails.  The nearest segment of the read .cl always answers.
;;; Carlson is still asked to CHECK each reading, and is walked instead for a
;;; .cl the reader refuses.
;;; ==========================================================================


;;; ==========================================================================
;;; SECTION 1  --  Reading a .cl file  (V5's pf:cl-parse)
;;; ==========================================================================
;;; A .cl is CSV, one row per alignment point, ending "0,0,L,0,0":
;;;   0, station, L,  northing, easting     tangent point
;;;   0, station, PC, northing, easting     start of an arc
;;;   0, delta,   R,  northing, easting     the arc's CENTRE; delta DD.MMSSsss
;;;   0, station, PT, northing, easting     end of the arc
;;; Northing first -- the drawing's X is the easting.  Arcs are filled in every
;;; *pf-cl-step* feet with exact stations (stations run ALONG the arc, so a
;;; curve's station difference is its length).  One row the reader does not
;;; know refuses the whole file: a guessed curve is silently wrong.

(defun pfm:pt2 (p) (list (car p) (cadr p)))

;; (pfm:dms->deg v) -> decimal degrees from Carlson's DD.MMSSsss
(defun pfm:dms->deg (v / sgn d r m s)
  (setq sgn (if (< v 0) -1.0 1.0)
        v   (abs v)
        d   (fix v)
        r   (* (- v d) 100.0)
        m   (fix r)
        s   (* (- r m) 100.0))
  (* sgn (+ d (/ m 60.0) (/ s 3600.0))))

;; (pfm:arc-points cx cy pc pt delta cl) -> the (x y sta) BETWEEN pc and pt.
;;   The sweep comes from the stationing (length / radius); the file's delta
;;   gives only the direction (negative = turns right) and is cross-checked.
(defun pfm:arc-points (cx cy pc pt delta cl / r rt arclen a0 sweep n i tt out)
  (setq r      (distance (list cx cy) (pfm:pt2 pc))
        rt     (distance (list cx cy) (pfm:pt2 pt))
        arclen (- (caddr pt) (caddr pc)))
  (cond
    ((or (<= r 1e-6) (<= arclen 1e-6)) nil)
    (T
     (if (> (abs (- r rt)) 0.01)
       (pfl:say (strcat "  Note: " (vl-filename-base cl) ".cl, arc at STA " (pfl:fmt-sta (caddr pc))
                        " -- its centre is " (rtos r 2 3) "' from the PC but " (rtos rt 2 3)
                        "' from the PT.")))
     (setq a0    (atan (- (cadr pc) cy) (- (car pc) cx))
           sweep (/ arclen r))
     (if (< delta 0) (setq sweep (- sweep)))
     (if (> (abs (- (abs (pfm:dms->deg delta)) (/ (* (abs sweep) 180.0) pi))) 0.05)
       (pfl:say (strcat "  Note: " (vl-filename-base cl) ".cl, arc at STA " (pfl:fmt-sta (caddr pc))
                        " -- its delta reads " (rtos (abs (pfm:dms->deg delta)) 2 4)
                        " deg, the stationing " (rtos (/ (* (abs sweep) 180.0) pi) 2 4)
                        " deg.  Stationing used.")))
     (setq n (fix (+ (/ arclen *pf-cl-step*) 0.9999)))
     (if (< n 1) (setq n 1))
     (setq i 1)
     (while (< i n)
       (setq tt  (/ (float i) (float n))
             out (cons (list (+ cx (* r (cos (+ a0 (* sweep tt)))))
                             (+ cy (* r (sin (+ a0 (* sweep tt)))))
                             (+ (caddr pc) (* arclen tt)))
                       out)
             i   (1+ i)))
     (reverse out))))

;; (pfm:parse-ok-p cl verts) -> T | nil   Two Carlson calls check a reading:
;;   its end stations against cl_sta_range, and its first point against where
;;   Carlson puts that station.  The swap check is named because a swapped
;;   reading otherwise just looks like "on no line" everywhere.
(defun pfm:parse-ok-p (cl verts / rng v0 vn p nm)
  (setq v0 (car verts) vn (last verts) nm (vl-filename-base cl))
  (cond
    ((null (setq rng (pfc:cl-range cl))) T)                ; cannot check
    ((or (> (abs (- (caddr v0) (car rng))) 0.01)
         (> (abs (- (caddr vn) (cadr rng))) 0.01))
     (pfl:say (strcat "  Note: " nm ".cl reads STA " (pfl:fmt-sta (caddr v0)) " to "
                      (pfl:fmt-sta (caddr vn)) ", Carlson says " (pfl:fmt-sta (car rng)) " to "
                      (pfl:fmt-sta (cadr rng)) " -- walked through Carlson instead."))
     nil)
    ((null (setq p (pfc:cl-point cl (caddr v0)))) T)        ; cannot check
    ((<= (distance p (pfm:pt2 v0)) *pf-cl-check-tol*) T)
    ((<= (distance p (list (cadr v0) (car v0))) *pf-cl-check-tol*)
     (pfl:say (strcat "  Note: " nm ".cl reads with its columns SWAPPED -- walked through Carlson instead."))
     nil)
    (T
     (pfl:say (strcat "  Note: " nm ".cl's first point is " (rtos (distance p (pfm:pt2 v0)) 2 2)
                      "' from where Carlson puts it -- walked through Carlson instead."))
     nil)))

;; (pfm:cl-parse cl) -> ((x y sta) ...) by climbing station | nil
(defun pfm:cl-parse (cl / f line parts v flag c4 c5 out pc cen delta done bad prev keep)
  (if (null (setq f (open cl "r")))
    (setq bad "could not be opened")
    (progn
      (while (and (not done) (not bad) (setq line (read-line f)))
        (setq parts (pfl:split line))
        (if (>= (length parts) 5)
          (progn
            (setq v    (atof (nth 1 parts))
                  flag (strcase (nth 2 parts))
                  c4   (atof (nth 3 parts))
                  c5   (atof (nth 4 parts)))
            (cond
              ;; "0,0,L,0,0" -- the end, not a point at the origin
              ((and (equal v 0.0 1e-9) (equal c4 0.0 1e-9) (equal c5 0.0 1e-9))
               (setq done T))
              ((= flag "L")
               (setq out (cons (list c5 c4 v) out) pc nil cen nil delta nil))
              ((= flag "PC")
               (setq pc (list c5 c4 v) out (cons pc out) cen nil delta nil))
              ((= flag "R")
               (if (null pc)
                 (setq bad "a radius-point row with no PC before it")
                 (setq cen (list c5 c4) delta v)))
              ((= flag "PT")
               (if (not (and pc cen delta))
                 (setq bad "a PT row without its PC and radius point")
                 (progn
                   (foreach p (pfm:arc-points (car cen) (cadr cen) pc (list c5 c4 v) delta cl)
                     (setq out (cons p out)))
                   (setq out (cons (list c5 c4 v) out) pc nil cen nil delta nil))))
              (T (setq bad (strcat "a row code it does not know ('" flag "')")))))))
      (close f)))
  (setq out (reverse out))
  ;; Stations must climb.  A repeat at the same point (a compound curve's PT
  ;; and next PC) is dropped; a repeat that moves, or a step back, refuses.
  (if (and (not bad) (cdr out))
    (progn
      (setq keep (list (car out)) prev (car out))
      (foreach p (cdr out)
        (cond
          (bad)
          ((> (caddr p) (caddr prev)) (setq keep (cons p keep) prev p))
          ((and (equal (caddr p) (caddr prev) 1e-6)
                (<= (distance (pfm:pt2 p) (pfm:pt2 prev)) 1e-4)))
          (T (setq bad (strcat "its stations step back or repeat at STA " (pfl:fmt-sta (caddr p)))))))
      (setq out (reverse keep))))
  (cond
    (bad
     (pfl:say (strcat "  Note: " (vl-filename-base cl) ".cl -- " bad "; walked through Carlson instead."))
     nil)
    ((< (length out) 2)
     (pfl:say (strcat "  Note: " (vl-filename-base cl) ".cl has fewer than 2 points; walked through Carlson instead."))
     nil)
    ((not (pfm:parse-ok-p cl out)) nil)
    (T out)))

;; (pfm:cl-walk cl) -> ((x y sta) ...) | nil   Carlson's own point every
;;   *pf-cl-step* feet.  One call a point -- only for a .cl the reader refused.
(defun pfm:cl-walk (cl / rng sta p out)
  (if (setq rng (pfc:cl-range cl))
    (progn
      (setq sta (car rng))
      (while (< sta (cadr rng))
        (if (setq p (pfc:cl-point cl sta)) (setq out (cons (list (car p) (cadr p) sta) out)))
        (setq sta (+ sta *pf-cl-step*)))
      (if (setq p (pfc:cl-point cl (cadr rng)))
        (setq out (cons (list (car p) (cadr p) (cadr rng)) out)))
      (if (cdr out) (reverse out)))))

;; (pfm:box verts) -> (xmin ymin xmax ymax)
(defun pfm:box (verts / x0 y0 x1 y1)
  (setq x0 1e30 y0 1e30 x1 -1e30 y1 -1e30)
  (foreach v verts
    (setq x0 (min x0 (car v)) y0 (min y0 (cadr v))
          x1 (max x1 (car v)) y1 (max y1 (cadr v))))
  (list x0 y0 x1 y1))

;; (pfm:in-box-p pt box tol) -> T when pt is within tol of the box.  The quick
;;   test before measuring: a point further than tol from the box is further
;;   than tol from the line (V5's proof), so most lines cost nothing.
(defun pfm:in-box-p (pt box tol)
  (and (>= (car pt)  (- (car box)    tol)) (<= (car pt)  (+ (caddr box)  tol))
       (>= (cadr pt) (- (cadr box)   tol)) (<= (cadr pt) (+ (cadddr box) tol))))

;; Kept for the session, keyed by the file's path, date and size -- an edited
;; .cl is read again.  Never written to the drawing.
(if (not (boundp '*pfm-geom*)) (setq *pfm-geom* nil))

;; (pfm:geom cl) -> (kind (s0 s1) verts box) | nil   kind 'read or 'walked
(defun pfm:geom (cl / key hit verts kind out)
  (setq key (list (strcase cl) (vl-file-systime cl) (vl-file-size cl))
        hit (assoc key *pfm-geom*))
  (cond
    (hit (cdr hit))
    (T
     (cond
       ((setq verts (pfm:cl-parse cl)) (setq kind 'read))
       ((setq verts (pfm:cl-walk cl))  (setq kind 'walked)))
     (if verts
       (setq out (list kind (list (caddr (car verts)) (caddr (last verts))) verts (pfm:box verts))
             *pfm-geom* (cons (cons key out)
                              (vl-remove-if '(lambda (c) (= (car (car c)) (strcase cl))) *pfm-geom*))))
     out)))


;;; ==========================================================================
;;; SECTION 2  --  Where a point is on a line
;;; ==========================================================================

;; (pfm:where verts pt) -> (station offset distance) off the NEAREST segment.
;;   Offset is signed like Carlson's: negative LEFT, looking up-station.  Past
;;   a bend the nearest point is the bend itself -- it always answers.
(defun pfm:where (verts pt / a dx dy l2 u fx fy d bd best)
  (setq a (car verts))
  (foreach b (cdr verts)
    (setq dx (- (car b) (car a))
          dy (- (cadr b) (cadr a))
          l2 (+ (* dx dx) (* dy dy))
          u  (if (> l2 1e-12)
               (max 0.0 (min 1.0 (/ (+ (* (- (car pt) (car a)) dx) (* (- (cadr pt) (cadr a)) dy)) l2)))
               0.0)
          fx (+ (car a) (* u dx))
          fy (+ (cadr a) (* u dy))
          d  (distance (pfm:pt2 pt) (list fx fy)))
    (if (or (null bd) (< d bd))
      (setq bd   d
            best (list (+ (caddr a) (* u (- (caddr b) (caddr a))))
                       (if (> (- (* dx (- (cadr pt) (cadr a))) (* dy (- (car pt) (car a)))) 0.0)
                         (- d) d)
                       d)))
    (setq a b))
  best)

;; (pfm:refine cl pt w) -> Carlson's exact (station offset distance) for a
;;   point near a WALKED line, whose chords cut corners | w when Carlson can't
(defun pfm:refine (cl pt w / loc)
  (if (setq loc (pfc:cl-locate cl pt))
    (list (car loc) (cadr loc) (abs (cadr loc)))
    w))

;; (pfm:where-on cl g pt) -> (station offset distance) on that line
(defun pfm:where-on (cl g pt / w)
  (setq w (pfm:where (nth 2 g) pt))
  (if (and (eq (car g) 'walked) (<= (caddr w) *pf-corridor-walk*))
    (pfm:refine cl pt w)
    w))

;; (pfm:face cl sta rng rot) -> (code margin) | string explaining why not
(defun pfm:face (cl sta rng rot / s-in s-out p-in p-0 p-out pair)
  (setq s-in  (max (car rng)  (- sta *pf-face-probe*))
        s-out (min (cadr rng) (+ sta *pf-face-probe*)))
  (cond
    ((or (>= s-in sta) (<= s-out sta))
     "at the very end of the line -- no line on one side to read a face from")
    ((not (and (setq p-in  (pfc:cl-point cl s-in))
               (setq p-0   (pfc:cl-point cl sta))
               (setq p-out (pfc:cl-point cl s-out))))
     "centerline would not return points near this station")
    (T
      (setq pair (pfl:face-pair (angle p-in p-0) (angle p-0 p-out) rot))
      (list (car pair) (cdr pair)))))

;; (pfm:plan-fp e) -> fingerprint of where an alpha block sits and what lines
;;   it is on.  PFASSIGN stamps it; a different answer later = moved or turned
;;   in plan since, and PFREFRESH says "run PFASSIGN first" (pfm:stale).
(defun pfm:plan-fp (e / ed)
  (setq ed (entget e))
  (pfl:fingerprint (list (cdr (assoc 10 ed)) (cond ((cdr (assoc 50 ed))) (0.0))
                         (pfr:memb-get e))))


;;; ==========================================================================
;;; SECTION 3  --  The line table  (V5's registry)
;;; ==========================================================================
;;; Every line: the grids (anchors) and V5's grid-less lines (stubs, in the
;;; drawing dictionary), ONE entry per .cl.  A stub counts as fully as a grid:
;;; membership is plan geometry, so a line with no profile drawn yet still
;;; numbers the structures on it.  Entry keys:
;;;   lname "STORM_BA"   short "BA"   util "STORM"   cl   rng (s0 s1)
;;;   kind read|walked   verts ((x y sta) ...)   box   from "grid"|"stub"
;;; READS ONLY.

;; (pfm:dict-keys dict) -> the entry names, in dictionary order
(defun pfm:dict-keys (dict / out pending)
  (foreach p (entget dict)
    (cond
      ((= (car p) 3) (setq pending (cdr p)))
      ((and pending (member (car p) '(350 360)))
       (setq out (cons pending out) pending nil))))
  (reverse out))

;; (pfm:stubs) -> ((util name cl) ...) V5's STUB_ records | nil
(defun pfm:stubs ( / d cur data out)
  (if (setq d (dictsearch (namedobjdict) *pf-nod-name*))
    (progn
      (setq d (cdr (assoc -1 d)))
      (foreach k (pfm:dict-keys d)
        (if (and (= (substr k 1 (strlen *pf-stub-prefix*)) *pf-stub-prefix*)
                 (setq cur (dictsearch d k)))
          (progn
            (setq data (cdr (member (assoc 100 cur) cur)))
            (setq out (cons (list (cdr (assoc 2 data)) (cdr (assoc 3 data)) (cdr (assoc 1 data)))
                            out)))))))
  (reverse out))

;; (pfm:find-cl p) -> the .cl path, checked to exist | nil.  The stored path,
;;   else the same name in the firm's Alignments folder.
(defun pfm:find-cl (p)
  (cond
    ((or (null p) (= p "")) nil)
    ((findfile p))
    ((pff:find-in-std p "cl"))))

;; (pfm:lines) -> (table . notes)
(defun pfm:lines ( / cands seen lname cl g parts out notes)
  (setq cands (append (mapcar '(lambda (g) (list (pfl:g 'cl g) "grid" (pfg:title g)))
                              (pfg:usable))
                      (mapcar '(lambda (s) (list (caddr s) "stub" (strcat (car s) " '" (cadr s) "'")))
                              (pfm:stubs))))
  (foreach c cands
    (cond
      ((or (null (car c)) (= (car c) ""))
       (setq notes (cons (strcat "  ** line " (caddr c) " has no .cl on record -- left out") notes)))
      ((member (setq lname (strcase (vl-filename-base (car c)))) seen))
      ((null (setq cl (pfm:find-cl (car c))))
       (setq seen  (cons lname seen)
             notes (cons (strcat "  ** line " (caddr c) ": " (car c) " not found -- left out") notes)))
      ((null (setq g (pfm:geom cl)))
       (setq seen  (cons lname seen)
             notes (cons (strcat "  ** line " (caddr c) ": " cl " could not be read -- left out") notes)))
      (T
       (setq seen  (cons lname seen)
             parts (pfl:line-parts lname)
             out   (cons (list (cons 'lname lname) (cons 'short (cdr parts)) (cons 'util (car parts))
                               (cons 'cl cl) (cons 'kind (car g)) (cons 'rng (cadr g))
                               (cons 'verts (caddr g)) (cons 'box (cadddr g)) (cons 'from (cadr c)))
                         out)))))
  (cons (reverse out) (reverse notes)))


;;; ==========================================================================
;;; SECTION 4  --  Numbers and names  (V5's id-for-hits)
;;; ==========================================================================
;;; Along each line, a structure's number is 1 + the structures at a lower
;;; station on that line.  Its name is its lines A-Z as LINE-number, joined
;;; by "/": BA-5/BC-1.  Only lines of its OWN utility -- the utility of the
;;; line it sits nearest -- a different utility meeting it is a crossing.

;; (pfm:hits pt lines) -> (hits . near)
;;   hits: ((lname station offset util short) ...) nearest first, every line
;;         the point is ON.
;;   near: ((lname distance) ...) lines within *pf-near-tol* it is NOT on.
(defun pfm:hits (pt lines / w rng hits near)
  (foreach l lines
    (if (pfm:in-box-p pt (pfl:g 'box l) (+ *pf-near-tol* *pf-corridor-walk*))
      (progn
        (setq w   (pfm:where-on (pfl:g 'cl l) (list (pfl:g 'kind l) nil (pfl:g 'verts l)) pt)
              rng (pfl:g 'rng l))
        (cond
          ((and (<= (abs (cadr w)) *pf-memb-tol*)
                (>= (car w) (- (car rng) *pf-range-eps*))
                (<= (car w) (+ (cadr rng) *pf-range-eps*)))
           (setq hits (cons (list (pfl:g 'lname l) (car w) (cadr w) (pfl:g 'util l) (pfl:g 'short l))
                            hits)))
          ((<= (caddr w) *pf-near-tol*)
           (setq near (cons (list (pfl:g 'lname l) (caddr w)) near)))))))
  (cons (vl-sort hits '(lambda (a b) (< (abs (caddr a)) (abs (caddr b))))) near))

;; (pfm:structures) -> every plan structure of ours: not a profile copy.  One
;;   never assigned (no PFVIEW yet) still counts -- it stands on the line.
(defun pfm:structures ()
  (vl-remove-if '(lambda (e) (= (strcase (cond ((pfr:view e)) (""))) (strcase *pf-view-pro*)))
                (pfr:all nil)))

;; (pfm:count-only-p e) -> T if e is a *pf-count-only* block: the root alone,
;;   or root + "_" + something starting with a digit (HDWL_24, HDWL_24x36)
(defun pfm:count-only-p (e / nm pre hit)
  (setq nm (strcase (pfl:effname e)))
  (foreach root *pf-count-only*
    (setq root (strcase root)
          pre  (strcat root *pf-size-sep*))
    (if (or (= nm root)
            (and (> (strlen nm) (strlen pre))
                 (= (substr nm 1 (strlen pre)) pre)
                 (pfr:digits-p (substr nm (1+ (strlen pre)) 1))))
      (setq hit T)))
  hit)

;; (pfm:others) -> every *pf-count-only* insert.  The DXF filter cuts the
;;   drawing down first; *U names stay in, since a dynamic block shows one.
(defun pfm:others (/ flt ss i e out)
  (if *pf-count-only*
    (progn
      (setq flt "`*U*")
      (foreach root *pf-count-only*
        (setq flt (strcat flt "," root "," root *pf-size-sep* "*")))
      (if (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 flt))))
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq e (ssname ss i))
            (if (pfm:count-only-p e) (setq out (cons e out)))
            (setq i (1+ i)))))))
  (reverse out))

;; (pfm:tree lines) -> (rows . index)
;;   rows:  ((ename hits near other) ...)  other = T for a *pf-count-only*
;;          block: it takes its number on the line but is never named
;;   index: ((lname station ...) ...) stations climbing.  vl-sort-i, not
;;          vl-sort: vl-sort may drop equal numbers, and two structures at
;;          one station must both count.
(defun pfm:tree (lines / others r u near rows idx c)
  (setq others (pfm:others))
  (foreach e (append (pfm:structures) others)
    (setq r    (pfm:hits (cdr (assoc 10 (entget e))) lines)
          ;; a near miss on ANOTHER utility's line is a crossing, not news
          u    (if (car r) (nth 3 (car (car r))))
          near (if u
                 (vl-remove-if-not '(lambda (n) (= (car (pfl:line-parts (car n))) u)) (cdr r))
                 (cdr r))
          rows (cons (list e (car r) near (if (member e others) T)) rows))
    (foreach h (car r)
      (setq idx (if (setq c (assoc (car h) idx))
                  (subst (cons (car h) (cons (cadr h) (cdr c))) c idx)
                  (cons (list (car h) (cadr h)) idx)))))
  (cons (reverse rows)
        (mapcar '(lambda (p / s) (setq s (cdr p))
                   (cons (car p) (mapcar '(lambda (i) (nth i s)) (vl-sort-i s '<))))
                idx)))

;; (pfm:rank sta stations) -> 1 + the stations below sta on that line
(defun pfm:rank (sta stations / n)
  (setq n 1)
  (foreach s stations (if (< s (- sta *pf-range-eps*)) (setq n (1+ n))))
  n)

;; (pfm:own-hits hits) -> the hits on lines of the structure's own utility,
;;   A-Z by line
(defun pfm:own-hits (hits / u keep)
  (if hits
    (progn
      (setq u    (nth 3 (car hits))
            keep (vl-remove-if-not '(lambda (h) (= (nth 3 h) u)) hits))
      (mapcar '(lambda (i) (nth i keep))
              (vl-sort-i (mapcar '(lambda (h) (nth 4 h)) keep) '<)))))

;; (pfm:name hits index) -> "BA-5/BC-1" | nil when on no line
(defun pfm:name (hits index)
  (if hits
    (pfl:join-with "/"
      (mapcar '(lambda (h) (strcat (nth 4 h) "-" (itoa (pfm:rank (cadr h) (cdr (assoc (car h) index))))))
              (pfm:own-hits hits)))))

;; (pfm:who e) -> "AA-2 (4BF799)", or "(4BF799)" with no name -- a structure
;;   named so it can be found.  Not ours: "HDWL_24 (4C80A1)".
(defun pfm:who (e / n)
  (setq n (if (pfr:ours-p e) (pfr:get e *pf-tag-name*) (pfl:effname e)))
  (strcat (if (and n (/= n "")) (strcat n " ") "") "(" (cdr (assoc 5 (entget e))) ")"))

;; (pfm:stacked rows) -> ((e1 e2 distance) ...) plan structures closer than
;;   *pf-stack-tol*: one drawn on top of another.  rows: pfm:tree's.
(defun pfm:stacked (rows / pts p out)
  (setq pts (mapcar '(lambda (r) (cons (car r) (pfm:pt2 (cdr (assoc 10 (entget (car r)))))))
                    rows))
  (while pts
    (setq p (car pts) pts (cdr pts))
    (foreach q pts
      (if (<= (distance (cdr p) (cdr q)) *pf-stack-tol*)
        (setq out (cons (list (car p) (car q) (distance (cdr p) (cdr q))) out)))))
  (reverse out))

;; (pfm:nearest pt lines) -> (lname distance) of the closest line | nil.
;;   Every line, no box test -- for reporting a structure on none.
(defun pfm:nearest (pt lines / w best)
  (foreach l lines
    (setq w (pfm:where (pfl:g 'verts l) pt))
    (if (or (null best) (< (caddr w) (cadr best)))
      (setq best (list (pfl:g 'lname l) (caddr w)))))
  best)

;; (pfm:names-put tree) -> lines to report.   WRITES PFNAME on every
;;   structure whose built name changed, as a tool value -- a name typed by
;;   hand is kept (pfr:refresh).  Reports what changed and what is near a
;;   line but not on it.  Says nothing about a structure that is already
;;   right.  A count-only block (not ours) is never named -- only its near
;;   misses are reported.
(defun pfm:names-put (tree / index e other nm cur src r out nkept)
  (setq index (cdr tree)
        nkept 0)
  (foreach row (car tree)
    (setq e     (car row)
          other (cadddr row)
          nm    (if (not other) (pfm:name (cadr row) index))
          cur   (if other "" (cond ((pfr:get e *pf-tag-name*)) ("")))
          src   (if (not other) (pfr:src-entry e *pf-tag-name*)))
    (cond
      ((null nm))
      ((and (= nm cur) src (= (cadr src) *pf-src-rule*) (= (caddr src) nm)))   ; already right
      (T
       (setq r (pfr:refresh e *pf-tag-name* nm *pf-src-rule*))
       (cond
         ((and (= r 'written) (/= nm cur))
          (setq out (cons (strcat "  " (if (= cur "") (strcat "named " nm) (strcat cur " -> " nm))) out)))
         ((= r 'adopted)
          (setq out (cons (strcat "  " cur "  typed by hand -- kept (the line tree says " nm ")") out)))
         ((and (= r 'kept) (/= (strcase nm) (strcase cur)))
          (setq nkept (1+ nkept))))))
    ;; nothing dropped without a reason: near a line but not on it
    (foreach n (caddr row)
      (setq out (cons (strcat "  ** " (cond (other (pfm:who e))
                                            ((/= cur "") cur)
                                            ((strcat "a structure (" (cdr (assoc 5 (entget e))) ")")))
                              " is " (pfl:fix (cadr n) 2) "' from line " (car n)
                              " -- not counted on it (limit " (pfl:fix *pf-memb-tol* 2) "')")
                      out))))
  (if (> nkept 0)
    (setq out (cons (strcat "  " (itoa nkept) " name(s) typed by hand differ from the line tree -- kept"
                            " (PFLINETEST lists them)")
                    out)))
  ;; one drawn on top of another -- they share a number
  (foreach s (pfm:stacked (car tree))
    (setq out (cons (strcat "  ** " (pfm:who (car s)) " and " (pfm:who (cadr s)) " are "
                            (pfl:fix (caddr s) 2) "' apart -- one on top of the other?  Erase one;"
                            " they get the same number")
                    out)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 5  --  Assigning  (PFASSIGN's: the plan side, drawing-wide)
;;; ==========================================================================
;;; No grid pick, no selection (Jake, 2026-10-27): every plan structure is put
;;; on every line of its own utility the tree finds it on.  Only what changed
;;; is written -- a structure not moved, turned or put on another line since
;;; PFASSIGN last stamped it is left alone.

;; (pfm:line-entry lname lines) -> that line's table entry | nil
(defun pfm:line-entry (lname lines)
  (vl-some '(lambda (l) (if (= (pfl:g 'lname l) lname) l)) lines))

;; (pfm:memb-same-p a b) -> T when two MEMB lists hold the same lines at the
;;   same stations and offsets, to the thousandth
(defun pfm:memb-same-p (a b)
  (and (= (length a) (length b))
       (vl-every '(lambda (m / o)
                    (and (setq o (assoc (car m) b))
                         (equal (cadr m) (cadr o) 0.001)
                         (equal (caddr m) (caddr o) 0.001)))
                 a)))

;; (pfm:face-of hits lines rot) -> (code margin) | string saying why not
;;   PFFACE is one value per structure, read off its THROUGH-line: the one
;;   that runs on both sides of it (pf-cfg).  Every other line starts or ends
;;   there.  None, or two, is said -- not guessed.
(defun pfm:face-of (hits lines rot / l f got why)
  (foreach h hits
    (setq l (pfm:line-entry (car h) lines)
          f (pfm:face (pfl:g 'cl l) (cadr h) (pfl:g 'rng l) rot))
    (if (= (type f) 'STR)
      (setq why f)
      (setq got (cons (cons (car h) f) got))))
  (cond
    ((null got) why)
    ((cdr got) (strcat "two lines run through it (" (car (cadr got)) ", " (car (car got))
                       ") -- set PFFACE by hand"))
    (T (cdr (car got)))))

;; (pfm:assign e hits lines) -> (status . lines-to-report)
;;   status 'new, 'updated, 'same, 'off (on no line) or 'skip.
;;   hits: its own-utility hits (pfm:own-hits).  Writes what it IS (PFVIEW,
;;   PFTYPE, PFSIZE off a sized name), MEMB -- every line it is on, lines it
;;   has left dropped -- and its face.  Anything a drafter typed is kept
;;   (pfr:refresh).  Rims are pfm:rim-put's.
(defun pfm:assign (e hits lines / nm row rot old memb status face r1 gone out)
  (setq nm  (pfl:effname e)
        row (pfr:row-for nm))
  (cond
    ((null row) (list 'skip))
    ((not (pfr:tags-ok-p e))
     (list 'skip (strcat "  ** " (pfm:who e) "  " nm " is missing attributes -- ATTSYNC it")))
    (T
     (setq rot  (cond ((cdr (assoc 50 (entget e)))) (0.0))
           old  (pfr:memb-get e)
           memb (mapcar '(lambda (h) (list (car h) (cadr h) (caddr h))) hits))
     (cond
       ;; not moved, turned or put on another line since the last stamp
       ((and (pfm:memb-same-p old memb) (= (pfr:stamp-get e) (pfm:plan-fp e)))
        (list 'same))
       ((null memb)
        (pfr:memb-put e nil)
        (pfr:stamp-put e (pfm:plan-fp e))
        (if old
          (list 'off (strcat "  " (pfm:who e) "  left " (pfl:join-with ", " (mapcar 'car old))
                             " -- on no line now; PFREFRESH erases its profile copies"))
          (list 'off)))
       (T
        (setq status (if old 'updated 'new)
              gone   (vl-remove-if '(lambda (m) (assoc (car m) memb)) old))
        ;; facts of the block the drafter placed.  PFSIZE only off a sized
        ;; name (PFSUITE_X_04): the one-block CBI's size is a field on
        ;; PFSIZE_LU, and writing the empty suffix over it blanked the size.
        (pfr:put e *pf-tag-view* *pf-view-plan*)
        (pfr:put e *pf-tag-type* (vl-symbol-name (car row)))
        (if (/= "" (pfr:size-of nm))
          (pfr:put e *pf-tag-size* (pfr:size-of nm)))
        (pfr:memb-put e memb)
        ;; face -- only blocks that carry the matrix
        (if (eq (caddr row) '*pf-states-face*)
          (progn
            (setq face (pfm:face-of hits lines rot))
            (if (= (type face) 'STR)
              (setq r1 face)
              (progn
                (setq r1 (pfr:refresh e *pf-tag-face* (car face) *pf-src-rule*))
                (if (and (= r1 'written) (< (cadr face) *pf-face-warn*))
                  (setq r1 (strcat "written, but only " (pfl:fix (cadr face) 1)
                                   " deg from a corner -- CHECK IT")))))))
        (pfr:schema-put e)
        (pfr:stamp-put e (pfm:plan-fp e))
        (setq out (list (strcat "  " (pfm:who e) "  "
                                (pfl:join-with "  " (mapcar '(lambda (m) (strcat (car m) " " (pfl:fmt-sta (cadr m))))
                                                            memb))
                                (if (/= "" (cond ((pfr:get e *pf-tag-face*)) ("")))
                                  (strcat "   face " (pfr:get e *pf-tag-face*))
                                  "")
                                (if (eq status 'new) "" "   (updated)"))))
        (if gone
          (setq out (append out (list (strcat "      left " (pfl:join-with ", " (mapcar 'car gone))
                                              " -- PFREFRESH erases its copies there")))))
        (if (= (type r1) 'STR) (setq out (append out (list (strcat "      face: " r1)))))
        (if (= r1 'kept)       (setq out (append out (list "      face: set by hand -- kept"))))
        (if (= r1 'adopted)    (setq out (append out (list "      face: changed by hand since last run -- now kept"))))
        (cons status out))))))

;; (pfm:rim-put e) -> 'written | 'kept | 'adopted | 'outside | nil
;;   The rim off the TIN loaded now.  A rim typed by hand is kept -- also one
;;   typed before the tool ever wrote a rim (no record yet: it is marked as
;;   typed rather than overwritten).  Outside the surface nothing is written.
(defun pfm:rim-put (e / z cur)
  (setq cur (pfr:get e *pf-tag-rim*))
  (cond
    ((null (setq z (pfc:tin-z (cdr (assoc 10 (entget e)))))) 'outside)
    ((and (null (pfr:src-entry e *pf-tag-rim*)) (pfl:number-p cur))
     (pfr:assert e *pf-tag-rim* cur)
     'kept)
    (T (pfr:refresh e *pf-tag-rim* (pfl:fix z 2) *pf-src-tin*))))

;; (pfm:stale plans) -> those of plans (plan structures; pfm:structures for
;;   all) moved, turned or new since PFASSIGN last stamped them.  PFREFRESH
;;   names them -- it does not assign.
(defun pfm:stale (plans)
  (vl-remove-if '(lambda (e) (= (pfr:stamp-get e) (pfm:plan-fp e))) plans))


(princ "\npf-index loaded.")
(princ)
