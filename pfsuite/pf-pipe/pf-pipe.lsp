;;; ==========================================================================
;;; pf-pipe.lsp  --  PFPIPE: the profile pipe block.
;;; Load position 11: after pf-anchor, pf-record, pf-draw, pf-struct.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; PFPIPE  click the upstream invert, then the downstream invert, inside a
;;;         profile grid.  Before the first click, S = size, M = material.
;;;         Uses the last size / material.  Walls are left off.
;;;
;;; The standalone pfpipe.lsp in the V6 folder is now PIPEPRO (ppr:, 2026-11-20),
;;; the same block without the suite -- no shared names, safe to load both.
;;;   - the grid comes from the anchor you click in: its exaggeration, its
;;;     text height, and its pipe material as the first default.  No fixed x10.
;;;   - the label is written by pfp:update, which the pipe-label step will
;;;     rerun, so placing a pipe and refreshing one cannot disagree.
;;;
;;; THE PIPE'S ENDS ARE THE TRUTH (first version, 2026-10-13).  Nothing about
;;; which structures it connects is stored: it is worked out from where the
;;; ends are, so a grip-stretched pipe is simply re-read.
;;;
;;; Size and material are attributes on the pipe (PFSIZE, PFMAT), and so are
;;; its inside and outside diameters (PFID, PFOD -- hidden, 2026-11-20).
;;;
;;; THE LABEL'S GRIP IS PFLEAD (2026-10-22).  Drag it out of the pipe and the
;;; next PFREFRESH turns the label level and draws a leader to it -- a
;;; polyline of the tool's, tagged with the pipe's handle.  Drag it back in
;;; and the label lies along the pipe again, the leader erased.
;;;
;;; SIZES AND MATERIALS come from the pipe table kept with the lisp,
;;; pf-cfg\pf-pipes.csv (pf-mats; Jake, 2026-11-20).  Carlson's pipesize.dta
;;; and pipen.dta are no longer read.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfp-size*)) (setq *pfp-size* nil))   ; inches
(if (not (boundp '*pfp-mat*))  (setq *pfp-mat*  nil))   ; material name


;;; ==========================================================================
;;; SECTION 1  --  The pipe table (pf-mats)
;;; ==========================================================================
;;; Kept under their old names: PFSETUP's material list, PFCONVERT and the
;;; bench call them.

;; (pfp:sizes) -> ((nominal . wall) ...) every size any material has; wall
;;   from the first material with an OD for it, else 0.0
(defun pfp:sizes ( / out w)
  (foreach s (pft:sizes nil)
    (setq w (vl-some '(lambda (m) (pft:wall m s)) (pft:materials nil))
          out (cons (cons s (cond (w) (0.0))) out)))
  (reverse out))

;; (pfp:mats) -> every material name in the table
(defun pfp:mats () (pft:materials nil))

;; (pfp:wall size) -> a wall thickness for that size, inches | nil.  Size
;;   only -- use (pfp:dims e) for a placed pipe, which knows its material.
(defun pfp:wall (size / w) (if (> (setq w (cond ((cdr (assoc size (pfp:sizes)))) (0.0))) 0.0) w))


;;; ==========================================================================
;;; SECTION 2  --  Reading a placed pipe
;;; ==========================================================================

;; (pfp:pipe-p e) -> T if e is a pipe insert
(defun pfp:pipe-p (e)
  (and (= "INSERT" (cdr (assoc 0 (entget e))))
       (= (strcase (pfl:effname e)) (strcase *pf-pipe-block*))))

;; (pfp:all) -> every pipe in model space.  Anonymous *U names included,
;;   since a dynamic block takes one as soon as a property changes.  A pipe
;;   RELEASED by PFREMOVE (its grid gone) is not ours any more -- skipped, or
;;   it would be re-labelled against the nearest OTHER grid.
(defun pfp:all ( / ss i e out)
  (if (setq ss (ssget "_X" (list '(0 . "INSERT")
                                 (cons 2 (strcat *pf-pipe-block* ",`*U*"))
                                 '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))))
      (if (and (pfp:pipe-p e) (not (pfr:released-p e))) (setq out (cons e out)))))
  out)

;; (pfp:xform e) -> (ins-x ins-y sx sy rot)   the insert's own placement
(defun pfp:xform (e / ed ins)
  (setq ed  (entget e)
        ins (cdr (assoc 10 ed)))
  (list (car ins) (cadr ins)
        (cond ((cdr (assoc 41 ed))) (1.0))
        (cond ((cdr (assoc 42 ed))) (1.0))
        (cond ((cdr (assoc 50 ed))) (0.0))))

;; (pfp:to-world e lp) -> WORLD (x y) of a point in the block's own
;;   coordinates (a point parameter's X / Y), turned and scaled with the
;;   insert in case someone rotated or scaled it
(defun pfp:to-world (e lp / xf a x y)
  (setq xf (pfp:xform e)
        a  (nth 4 xf)
        x  (* (nth 2 xf) (car lp))
        y  (* (nth 3 xf) (cadr lp)))
  (list (+ (car xf)  (- (* x (cos a)) (* y (sin a))))
        (+ (cadr xf) (+ (* x (sin a)) (* y (cos a))))))

;; (pfp:to-local e wp) -> the reverse: a WORLD point in the block's coordinates
(defun pfp:to-local (e wp / xf a dx dy)
  (setq xf (pfp:xform e)
        a  (nth 4 xf)
        dx (- (car wp)  (car xf))
        dy (- (cadr wp) (cadr xf)))
  (list (/ (+ (* dx (cos a)) (* dy (sin a))) (nth 2 xf))
        (/ (- (* dy (cos a)) (* dx (sin a))) (nth 3 xf))))

;; (pfp:ends e) -> ((x1 y1) (x2 y2)) upstream end, downstream end | nil
;;   Upstream = the base point.  Downstream = base + the PFRUN grip.
(defun pfp:ends (e / obj rx ry)
  (setq obj (vlax-ename->vla-object e)
        rx  (pfl:dynprop-get obj *pf-pipe-run-x*)
        ry  (pfl:dynprop-get obj *pf-pipe-run-y*))
  (if (and (numberp rx) (numberp ry))
    (list (pfp:to-world e '(0.0 0.0)) (pfp:to-world e (list rx ry)))))

;; (pfp:pt-get e name) -> WORLD (x y) of point parameter NAME | nil
(defun pfp:pt-get (e name / obj x y)
  (setq obj (vlax-ename->vla-object e)
        x   (pfl:dynprop-get obj (strcat name " X"))
        y   (pfl:dynprop-get obj (strcat name " Y")))
  (if (and (numberp x) (numberp y)) (pfp:to-world e (list x y))))

;; (pfp:state-now obj) -> the visibility state's name, upper case | nil
(defun pfp:state-now (obj / p)
  (if (setq p (pfl:visprop obj)) (strcase (vl-princ-to-string (pfl:prop-get p)))))

;; (pfp:walls-p obj) -> T when the pipe shows its walls.  "WALL ON..." also
;;   counts: the in-block leader's states (WALL ON LEADER, tried and dropped
;;   2026-10-22) may linger on pipes until the block is redefined.
(defun pfp:walls-p (obj / s)
  (and (setq s (pfp:state-now obj))
       (wcmatch s (strcat (strcase *pf-pipe-state-walls*) "*"))))

;; (pfp:leaders e) -> the leader polylines drawn for this pipe (normally one;
;;   more after a COPY took a leader along without its pipe)
(defun pfp:leaders (e / h)
  (setq h (cdr (assoc 5 (entget e))))
  (vl-remove-if-not '(lambda (l) (= h (pfp:leader-pipe l))) (pfp:all-leaders)))

;; (pfp:all-leaders) -> every pipe-label leader in model space, released ones
;;   (PFREMOVE) left out
(defun pfp:all-leaders ( / ss i e out)
  (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") '(410 . "Model") (list -3 (list *pf-app*)))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))))
      (if (and (pfp:leader-pipe e) (not (pfr:released-p e))) (setq out (cons e out)))))
  out)

;; (pfp:leader-pipe l) -> the handle of the pipe a leader belongs to | nil
(defun pfp:leader-pipe (l / h)
  (if (= (type (setq h (pfr:deser (pfr:xd-get l *pf-xd-pipe*)))) 'STR) h))

;; (pfp:leader-owner l) -> the pipe's ename if it is still a pipe | nil
(defun pfp:leader-owner (l / h p)
  (if (and (setq h (pfp:leader-pipe l))
           (setq p (handent h))
           (entget p)
           (pfp:pipe-p p))
    p))

;; (pfp:leader-fp e) -> each of this pipe's leaders as its points | nil
(defun pfp:leader-fp (e)
  (mapcar '(lambda (l)
             (mapcar 'cdr (vl-remove-if-not '(lambda (g) (= 10 (car g))) (entget l))))
          (pfp:leaders e)))

;; (pfp:inside-p pt ends dia) -> T when pt is within the drawn pipe: between
;;   its ends, and between its invert and its top at that station
(defun pfp:inside-p (pt ends dia / p1 p2 lo hi yi)
  (setq p1 (car ends) p2 (cadr ends)
        lo (min (car p1) (car p2))
        hi (max (car p1) (car p2)))
  (if (and (> (- hi lo) 1e-6) (<= lo (car pt) hi))
    (progn
      (setq yi (+ (cadr p1) (* (- (car pt) (car p1))
                               (/ (- (cadr p2) (cadr p1)) (- (car p2) (car p1))))))
      (<= yi (cadr pt) (+ yi dia)))))

;; (pfp:mid ends) -> the midpoint between a pipe's two ends
(defun pfp:mid (ends)
  (list (/ (+ (car (car ends)) (car (cadr ends))) 2.0)
        (/ (+ (cadr (car ends)) (cadr (cadr ends))) 2.0)))

;; A pipe is owned by one profile grid only when BOTH inverts are inside its
;; anchor's box.  The nearest-grid rule is intentionally looser for mouse picks.
;;   A loop over pipes builds one anchor index (pfg:index) and calls the -in
;;   forms; one call builds its own (2026-11-20).
(defun pfp:grid-of-ends (ends) (if ends (pfp:grid-of-ends-in ends (pfg:index))))

(defun pfp:grid-of-ends-in (ends idx / a b)
  (if (and ends
           (setq a (pfg:anchor-containing-in (car ends) idx))
           (setq b (pfg:anchor-containing-in (cadr ends) idx))
           (eq a b))
    (pfg:grid a)))

(defun pfp:grid-issue (ends expected)
  (pfp:grid-issue-in ends expected (if ends (pfg:index))))

(defun pfp:grid-issue-in (ends expected idx / a b g)
  (cond
    ((null ends) "the pipe's ends cannot be read")
    ((null (setq a (pfg:anchor-containing-in (car ends) idx)))
     "upstream end is outside a usable profile grid")
    ((null (setq b (pfg:anchor-containing-in (cadr ends) idx)))
     "downstream end is outside a usable profile grid")
    ((not (eq a b)) "the two ends are on different profile grids")
    ((and expected (not (eq a (pfl:g 'anchor expected))))
     "the ends do not belong to the selected profile grid")
    ((null (setq g (pfg:grid a))) "the profile grid cannot be read")))

;; (pfp:size e) -> inches as a number | nil    PFSIZE reads like 15"
(defun pfp:size (e / s n)
  (setq s (pfr:get e *pf-pipe-size*))
  (if (and s (> (setq n (atof s)) 0.0)) n))

;; (pfp:mat e) -> material text, "" when blank
(defun pfp:mat (e / s)
  (if (setq s (pfr:get e *pf-pipe-mat*)) s ""))

(defun pfp:size-text (n) (strcat (rtos n 2 0) "\""))

;; (pfp:dims-table e) -> (id od) inches from the pipe table for this pipe's
;;   material and size | nil when the table has no such row
(defun pfp:dims-table (e / size)
  (if (setq size (pfp:size e)) (pft:dims (pfp:mat e) size)))

;; (pfp:dims e) -> (id od) inches as THE BLOCK says them -- PFID / PFOD, which
;;   the tool fills from the table and a drafter may type over.  id falls back
;;   to the table, then the nominal size; od nil = wall unknown.  What inverts
;;   and crossings read: the block is the source of truth.
(defun pfp:dims (e / id od tb)
  (setq id (pft:num (pfr:get e *pf-pipe-id*))
        od (pft:num (pfr:get e *pf-pipe-od*))
        tb (pfp:dims-table e))
  (if (null id) (setq id (cond ((car tb)) ((pfp:size e)))))
  (if (and (null od) (null (pfr:attr-ent e *pf-pipe-od*))) (setq od (cadr tb)))
  (if (and od id (<= od id)) (setq od nil))
  (if id (list id od)))

;; (pfp:dims-put e) -> notes   PFID / PFOD from the table, as tool values: a
;;   value typed over is kept (pfr:refresh).  A blank OD in the table writes
;;   a blank PFOD -- wall unknown.
(defun pfp:dims-put (e / tb r notes)
  (setq tb (pfp:dims-table e))
  (cond
    ((null (pfr:attr-ent e *pf-pipe-id*))
     (setq notes (list (strcat "      ** no " *pf-pipe-id* " / " *pf-pipe-od* " on this pipe -- BEDIT "
                               *pf-pipe-block* ", add them (hidden), then ATTSYNC"))))
    (T
     ;; not in the table: the tool's values go blank (inside = the nominal,
     ;; wall unknown) -- an old size's numbers must not stay behind
     (if (null tb)
       (setq notes (list (strcat "      ** " (pfp:mat e) " " (cond ((pfr:get e *pf-pipe-size*)) ("?"))
                                 " is not in the pipe table -- inside diameter = the nominal size,"
                                 " wall unknown"))))
     (foreach p (list (cons *pf-pipe-id* (if tb (pfl:fix (car tb) 3) ""))
                      (cons *pf-pipe-od* (if (cadr tb) (pfl:fix (cadr tb) 3) "")))
       (setq r (pfr:refresh e (car p) (cdr p) *pf-src-rule*))
       (if (eq r 'adopted)
         (setq notes (cons (strcat "      " (car p) " typed over by hand -- kept") notes))))))
  (reverse notes))


;;; ==========================================================================
;;; SECTION 3  --  One pipe's diameter and label
;;; ==========================================================================

;; (pfp:sync) -> (inputs . notes)   the four label inputs made the same on
;;   every pipe (Jake, 2026-10-16: shared) -- pf-record's shared logic
(defun pfp:sync () (pfp:sync-in (pfp:all)))

;; (pfp:sync-in pipes) -> (inputs . notes)   the same, over these pipes only
;;   (PFSELFTEST hands its own)
(defun pfp:sync-in (pipes)
  (pfr:sync-inputs pipes *pf-pipe-tags-fmt* *pf-pipe-fmt-defaults* nil))

;; (pfp:rows run slope size mat inputs) -> (row1 . row2)
;;   CONST. 45 L.F. ~ 15"   /   ADS N-12 HDPE @ 5.5%
;;   Rounded per Jake's sample: whole feet, slope to 0.1%.
(defun pfp:rows (run slope size mat inputs)
  (cons (pfl:join (list (pfr:input *pf-pipe-len-pre* inputs)
                        (pfl:fix run *pf-pipe-len-dec*)
                        (pfr:input *pf-pipe-len-suf* inputs)
                        (pfp:size-text size)))
        (pfl:join (list mat
                        (pfr:input *pf-pipe-slope-pre* inputs)
                        (strcat (pfl:fix slope *pf-pipe-slope-dec*)
                                (pfr:input *pf-pipe-slope-suf* inputs))))))

;; (pfp:fp e g inputs) -> fingerprint of everything this pipe's label and
;;   diameter are built from, and of what the tool left on it: its ends,
;;   size, material, the shared inputs, the grid's numbers, the drawn
;;   diameter, each label row's text and position, the state, the label
;;   grip, and the leader drawn for it.  The same answer next time = nothing
;;   changed = PFREFRESH leaves the pipe alone.
(defun pfp:fp (e g inputs)
  (pfl:fingerprint
    (list *pf-fp-ver*
          (pfp:ends e)
          (pfr:get e *pf-pipe-size*)
          (pfr:get e *pf-pipe-mat*)
          (pfr:get e *pf-pipe-id*)
          (pfr:get e *pf-pipe-od*)
          (pfp:dims-table e)                ; an edit to the table is a change
          (if inputs inputs
            (pfv:fp-inputs e (pfg:line-name g) "PIPE" ""
                           *pf-pipe-tags-fmt* *pf-pipe-fmt-defaults*))
          (mapcar '(lambda (k) (pfl:g k g)) '(leftx basey sta0 datum vscale hplot))
          (pfl:dynprop-get (vlax-ename->vla-object e) *pf-pipe-dia*)
          (mapcar '(lambda (tg) (list (pfr:get e tg) (pfr:att-pt e tg)))
                  (list *pf-pipe-label* *pf-pipe-label2*))
          (pfp:state-now (vlax-ename->vla-object e))
          (pfp:pt-get e *pf-pipe-lead*)
          (pfp:leader-fp e))))

;; (pfp:put obj name v) -> T | explanation   a dynamic property, written only
;;   when it differs -- every write rebuilds the insert
(defun pfp:put (obj name v / cur)
  (setq cur (pfl:dynprop-get obj name))
  (if (and (numberp cur) (equal cur v 1e-6))
    T
    (pfd:dynprop-put obj name v)))

;; (pfp:pt-put e name wp) -> T | explanation   point parameter NAME to the
;;   WORLD point wp
(defun pfp:pt-put (e name wp / obj lp r)
  (setq obj (vlax-ename->vla-object e)
        lp  (pfp:to-local e wp)
        r   (pfp:put obj (strcat name " X") (car lp)))
  (if (= r T) (pfp:put obj (strcat name " Y") (cadr lp)) r))

;; (pfp:leader-verts e top right mid up dia walls sf) -> ((pt sw ew) ...)
;;   The leader for a label outside the pipe whose top row's insertion point
;;   is top.  right = the label is right of the arrow.  up = above the pipe.
;;   The arrow touches the pipe at its midpoint: its top when the label is
;;   above, its bottom when below -- the outside of the wall when the walls
;;   show (Jake, 2026-10-22).  The landing is level, ending a gap short of
;;   the top row; the bend is a landing's length further from the text.  The
;;   first segment tapers from nothing at the tip to the arrow's width: that
;;   is the arrowhead, pointing along the leg.
(defun pfp:leader-verts (e top right mid up dia walls sf / obj tip)
  (setq obj  (vlax-ename->vla-object e)
        tip  (if up
               (list (car mid) (+ (cadr mid) dia
                                  (if walls (cond ((pfl:dynprop-get obj *pf-pipe-wt*)) (0.0)) 0.0)))
               (list (car mid) (- (cadr mid)
                                  (if walls (cond ((pfl:dynprop-get obj *pf-pipe-wb*)) (0.0)) 0.0)))))
  ;; the shape is shared with the crossing label (pf-lib)
  (pfl:leader-path tip top right sf))

;; (pfp:leader-put e verts) -> (note ...)   this pipe's leaders erased, and a
;;   new one drawn when verts is given
(defun pfp:leader-put (e verts / l notes)
  (foreach old (pfp:leaders e) (pfd:erase old))
  (cond
    ((null verts))
    ((null (setq l (pfd:pline verts (cdr (assoc 8 (entget e))))))
     (setq notes (list "      ** AutoCAD would not draw the leader")))
    (T
     (pfr:xd-put l *pf-xd-pipe* (pfr:ser (cdr (assoc 5 (entget e)))))
     (if (< (distance (car (car verts)) (car (caddr verts)))
            (distance (car (car verts)) (car (cadr verts))))
       (setq notes (list "      leader's leg is shorter than its arrow -- drag the label further out")))))
  notes)

;; (pfp:update e g inputs) -> (label-text note ...)
;;   Used by PFPIPE when placing; the pipe-label step will rerun it.
;;   inputs: from pfp:sync.
(defun pfp:update (e g inputs / obj lead moved ends ref p1 p2 e1 e2 run size mat vs dia
                     wall rows r slope ht sf ang cen nrm half lab out right walls
                     rot just top bot notes w default-run dims)
  (setq *pfd-stage* "reading the pipe")
  (setq default-run (null inputs))
  (if (null inputs)
    (setq inputs (pfv:inputs e (pfg:line-name g) "PIPE" ""
                             *pf-pipe-tags-fmt* *pf-pipe-fmt-defaults*)))
  (setq obj    (vlax-ename->vla-object e)
        ends   (pfp:ends e)
        ;; the reference the label grip is measured against: the midpoint of
        ;; the pipe's two ends.  PFLEAD rides PFRUN with it, so a stretched
        ;; pipe does NOT make the label look moved by hand (CAD, 2026-10-16)
        ref    (if ends (pfp:mid ends))
        ;; BEFORE any property change.  The label grip, not the rows: ATTSYNC
        ;; resets the rows but leaves the grip where the drafter dragged it.
        lead   (pfp:pt-get e *pf-pipe-lead*)
        moved  (pfr:moved-from-p e *pf-pipe-lead* lead ref)
        size   (pfp:size e)
        mat    (pfp:mat e)
        vs     (pfl:g 'vscale g))
  (cond
    ((null ends) (list "?" "      ** can't read this pipe's ends (PFRUN missing?)"))
    ((null size) (list "?" "      ** PFSIZE is blank or not a number -- type one in Properties"))
    (T
     ;; PFID / PFOD from the table first (a typed value is kept), then the
     ;; drawing follows the block's own numbers
     (setq *pfd-stage* "inside and outside diameter")
     (setq notes (append (reverse (pfp:dims-put e)) notes))
     (setq dims (pfp:dims e)
           p1  (car ends) p2 (cadr ends)
           e1  (pfl:y->elev (cadr p1) g)
           e2  (pfl:y->elev (cadr p2) g)
           run (abs (- (car p2) (car p1)))
           dia (* (/ (car dims) 12.0) vs))

     ;; the drawn diameter is the INSIDE diameter; the walls, when the OD is known
     (setq *pfd-stage* "setting the diameter and walls")
     (if (> (abs (- dia (cond ((pfl:dynprop-get obj *pf-pipe-dia*)) (0.0)))) 1e-4)
       (if (/= T (setq r (pfd:dynprop-put obj *pf-pipe-dia* dia)))
         (setq notes (cons (strcat "      diameter: " r) notes))))
     (if (cadr dims)
       (progn
         (setq wall (/ (- (cadr dims) (car dims)) 2.0))
         (foreach prm (list *pf-pipe-wt* *pf-pipe-wb*)
           (if (> (abs (- (* (/ wall 12.0) vs) (cond ((pfl:dynprop-get obj prm)) (0.0)))) 1e-4)
             (pfd:dynprop-put obj prm (* (/ wall 12.0) vs))))))

     (if (< run 1e-6)
       (setq rows (cons "" "") notes (cons "      ** both ends at the same station" notes))
       (setq slope (* 100.0 (/ (- e1 e2) run))
             rows  (pfp:rows run slope size mat inputs)))
     (if (and slope (< slope 0.0))
       (setq notes (cons "      ** runs UPHILL from the first end you clicked -- adverse slope, or drawn backwards" notes)))
     (if (null (pfr:attr-ent e *pf-pipe-label2*))
       (setq notes (cons (strcat "      ** this pipe has no " *pf-pipe-label2*
                                 " -- ATTSYNC " *pf-pipe-block* " to give it the second row")
                         notes)))

     ;; label text -- a row typed over by hand is kept
     (setq *pfd-stage* "writing the pipe label")
     (foreach rt (list (cons *pf-pipe-label* (car rows)) (cons *pf-pipe-label2* (cdr rows)))
       (setq r (pfr:refresh e (car rt) (cdr rt) *pf-src-rule*))
       (if (member r '(kept adopted))
         (setq notes (cons (strcat "      " (car rt) " typed over by hand -- kept") notes))))

     ;; label position.  PFLEAD is the label's grip; it carries both rows.
     ;;   Inside the pipe -> centred on it (V5's pipe label: the rows straddle
     ;;                      its centre), rotated to it, no leader -- dragged
     ;;                      there or not (Jake, 2026-10-27).
     ;;   Dragged outside -> stays exactly where the drafter put it, level, on
     ;;                      a leader (Jake, 2026-10-22).
     ;; Rotation, justification and leader are redone every time; a spot
     ;; outside the pipe a drafter chose never is.  The leader is a polyline
     ;; the tool draws.
     (setq *pfd-stage* "placing the pipe label")
     (setq ht    (pfg:text-ht g)
           sf    (/ (pfl:g 'hplot g) *pf-ref-hplot*)
           ang   (pfl:readable (angle p1 p2))
           nrm   (+ ang (/ pi 2.0))                 ; "up" for upright text
           half  (* 0.5 ht *pf-pipe-row-gap*)
           cen   (list (car ref) (+ (cadr ref) (/ dia 2.0)))
           ;; dragged INSIDE the pipe counts as not dragged: back to the centre
           moved (and lead moved (not (pfp:inside-p lead ends dia)))
           lab   (if moved lead cen)
           out   (not (pfp:inside-p lab ends dia))
           walls (pfp:walls-p obj))
     ;; a pipe left in the dropped in-block leader's state goes back to plain
     ;; WALL ON / WALL OFF
     (if (wcmatch (cond ((pfp:state-now obj)) ("")) "*LEADER*")
       (pfd:set-state obj (if walls *pf-pipe-state-walls* *pf-pipe-state-plain*)))
     (cond
       ((null lead)
        (setq notes (cons (strcat "      ** no " *pf-pipe-lead* " grip -- this is the old "
                                  *pf-pipe-block* ".  Label put inside the pipe, no leader.")
                          notes)))
       ((/= T (setq r (pfp:pt-put e *pf-pipe-lead* lab)))
        (setq notes (cons (strcat "      " *pf-pipe-lead* ": " r) notes))))
     (if out
       (setq right (>= (car lab) (car ref))         ; right of the arrow
             rot   0.0
             just  (if right 'ML 'MR)               ; text grows away from it
             top   (list (car lab) (+ (cadr lab) half))
             bot   (list (car lab) (- (cadr lab) half)))
       (setq rot   ang
             just  'MC
             top   (polar lab nrm half)
             bot   (polar lab nrm (- half))))
     (setq *pfd-stage* "drawing the pipe label's leader")
     (setq notes (append (reverse (pfp:leader-put e (if out (pfp:leader-verts e top right ref
                                                                             (> (cadr lab) (cadr cen))
                                                                             dia walls sf))))
                         notes))
     ;; the rows last: every property write above can shift them
     (pfr:att-place e *pf-pipe-label*  top ht rot just)
     (pfr:att-place e *pf-pipe-label2* bot ht rot just)
     (cond
       ((null lead))
       (moved
        (setq notes (cons "      label dragged out of the pipe by hand -- kept there, on a leader"
                          notes)))
       ;; remembered only when the tool chose the spot, so a dragged label
       ;; stays "dragged" from one refresh to the next
       (T (pfr:pos-put e *pf-pipe-lead* lab ref)))

     ;; does it fit inside the pipe?  The longer row against the run, both
     ;; rows against the drawn diameter.
     (setq w (max (pfl:text-len (car rows) ht (pfr:att-style e *pf-pipe-label*))
                  (pfl:text-len (cdr rows) ht (pfr:att-style e *pf-pipe-label*))))
     (if (and (not out) (or (> w (distance p1 p2)) (> (+ ht (* 2.0 half)) dia)))
       (setq notes (cons (strcat "      label is bigger than the pipe -- drag its " *pf-pipe-lead*
                                 " grip out of the pipe, then PFREFRESH puts it on a leader")
                         notes)))
     (pfr:schema-put e)
     (pfr:stamp-put e (pfp:fp e g (if default-run nil inputs)))
     (cons (strcat (car rows) "  /  " (cdr rows)) (reverse notes)))))


;;; ==========================================================================
;;; SECTION 4  --  PFPIPE
;;; ==========================================================================
;;; The invert rows that used to wait here (pfp:end-at, pfp:inverts ...)
;;; became pf-invert (2026-11-20).

;; The utility of the grid last clicked in, for the material list
(if (not (boundp '*pfp-util*)) (setq *pfp-util* nil))

;; (pfp:inv-row prefix elev size) -> "I.O. 765.43 (15\")"   V5's format
(defun pfp:inv-row (prefix elev size)
  (strcat prefix " " (pfl:fix elev 2)
          (if size (strcat " (" (rtos size 2 0) "\")") "")))

;; (pfp:first-mat g) -> the material a new pipe in grid g starts with: the
;;   table's Default for the grid's utility, else the material PFSETUP
;;   recorded on the grid (if the table has it), else the first offered
(defun pfp:first-mat (g / u)
  (setq u (pfl:g 'util g))
  (cond ((pft:default u))
        ((and (pfl:g 'material g) (pft:mat (pfl:g 'material g))) (car (pft:mat (pfl:g 'material g))))
        ((car (pft:materials u)))))

;; (pfp:pick-size) -> nil   the size, from the current material's sizes
(defun pfp:pick-size ( / sizes s)
  (setq sizes (pft:sizes (if (pft:mat *pfp-mat*) *pfp-mat*)))
  (cond
    ((null sizes) (pfl:say (strcat "No sizes in the pipe table (" (cond ((pft:path)) ("pf-pipes.csv")) ").")))
    (T
     (pfl:say (strcat "Sizes (in)" (if (pft:mat *pfp-mat*) (strcat " for " *pfp-mat*) "") ": "
                      (pfl:join (mapcar '(lambda (x) (rtos x 2 0)) sizes))))
     (setq s (getreal (strcat "\nNominal size, inches <"
                              (if *pfp-size* (rtos *pfp-size* 2 0) "none") ">: ")))
     (cond
       ((null s))
       ((member s sizes) (setq *pfp-size* s))
       (T (pfl:say "That size is not in the pipe table for this material -- add a row to pf-pipes.csv first."))))))

;; (pfp:pick-mat) -> nil   the material, from those offered for the grid's utility
(defun pfp:pick-mat ( / mats i n)
  (setq mats (pft:materials *pfp-util*))
  (cond
    ((null mats) (pfl:say "No materials in the pipe table for this line type."))
    (T
     (setq i 0)
     (foreach m mats (setq i (1+ i)) (pfl:say (strcat "  " (itoa i) "  " m)))
     (setq n (getint (strcat "\nMaterial number <" (cond (*pfp-mat*) ("none")) ">: ")))
     (if (and n (<= 1 n (length mats)))
       (progn
         (setq *pfp-mat* (nth (1- n) mats))
         (if (and *pfp-size* (not (member *pfp-size* (pft:sizes *pfp-mat*))))
           (pfl:say (strcat "  " (rtos *pfp-size* 2 0) "\" isn't listed for " *pfp-mat*
                            " -- pick a size (S)."))))))))

;; (pfp:place p1 p2 g size mat others) -> (pipe label-text note ...) |
;;   explanation string.  The work of PFPIPE, no questions -- what PFSELFTEST
;;   drives (2026-10-30).  p1 p2: WORLD upstream and downstream inverts, in
;;   grid g.  size: inches.  mat: text.  others: the pipes whose label inputs
;;   this one shares -- T = every pipe in the drawing (the command).
(defun pfp:place (p1 p2 g size mat others / e obj sy issue)
  (setq *pfd-stage* "inserting the pipe")
  (cond
    ((setq issue (pfp:grid-issue (list p1 p2) g))
     (strcat "pipe not placed: " issue))
    ((null (setq e (pfd:insert *pf-pipe-block* p1))) "AutoCAD would not insert the block")
    (T
     (setq obj (vlax-ename->vla-object e))
     (pfr:put e *pf-pipe-size* (pfp:size-text size))
     (pfr:put e *pf-pipe-mat*  (cond (mat) ("")))
     ;; PFID / PFOD: filled from the table by pfp:update (pfp:dims-put)
     (pfr:schema-put e)
     ;; the run, then visibility; size and label in pfp:update
     (pfd:dynprop-put obj *pf-pipe-run-x* (- (car p2) (car p1)))
     (pfd:dynprop-put obj *pf-pipe-run-y* (- (cadr p2) (cadr p1)))
     (pfd:dynprop-put obj *pf-pipe-vis* *pf-pipe-state-plain*)
     ;; Production uses drawing defaults and this block's own hand edits.
     ;; An explicit test scope retains the legacy input path.
     (if (not (eq others T))
       (progn
         (setq sy (pfp:sync-in (cons e others)))
         (foreach s (cdr sy) (pfl:say s))))
     (cons e (pfp:update e g (car sy))))))

;; (pfp:main) -> nil   the command body, run inside pfd:run: the clicks,
;;   then pfp:place
(defun pfp:main ( / p1u p2u p1 p2 g go res)
  (cond
    ((= 1 (getvar "BLOCKEDITOR")) (pfl:say "PFPIPE: close the Block Editor first."))
    ((null (tblsearch "BLOCK" *pf-pipe-block*))
     (pfl:say (strcat "PFPIPE: no " *pf-pipe-block* " block in this drawing.  Insert one once, then erase it.")))
    ((null (pft:sizes nil))
     (pfl:say (strcat "PFPIPE: the pipe table has no sizes -- " (car (pft:notes)))))
    (T
     (foreach s (pft:notes) (pfl:say (strcat "  ** " s)))
     (foreach s (pft:default-notes) (pfl:say (strcat "  ** " s)))
     (if (null *pfp-size*) (pfp:pick-size))
     (if *pfp-size*
       (progn
         (setq go T)
         (while go
           (initget "Size Material")
           (setq p1u (getpoint (strcat "\nUpstream invert (" (pfp:size-text *pfp-size*) " "
                                       (cond (*pfp-mat*) ("material from the grid"))
                                       ")  [Size/Material]: ")))
           (cond
             ((= p1u "Size")     (pfp:pick-size))
             ((= p1u "Material") (pfp:pick-mat))
             (T (setq go nil))))
         (cond
           ((null p1u))
           ((null (setq g (pfg:at (setq p1 (trans p1u 1 0))))))
           ((null (setq p2u (getpoint p1u "\nDownstream invert: "))))
            ((< (abs (- (car (setq p2 (trans p2u 1 0))) (car p1))) 1e-6)
            (pfl:say "PFPIPE: both inverts are at the same station."))
            ((setq res (pfp:grid-issue (list p1 p2) g))
             (pfl:say (strcat "PFPIPE: " res ".")))
           (T
            ;; first material: the table's Default for this line type, else
            ;; the one PFSETUP recorded on the grid (pfp:first-mat)
            (setq *pfp-util* (pfl:g 'util g))
            (if (null *pfp-mat*) (setq *pfp-mat* (pfp:first-mat g)))
            (setq res (pfp:place p1 p2 g *pfp-size* *pfp-mat* T))
            (if (= (type res) 'STR)
              (pfl:say (strcat "PFPIPE: " res "."))
              (progn
                (pfl:say (strcat "Placed  " (cadr res)))
                (foreach s (cddr res) (pfl:say s))))))))))
  (princ))

(defun c:PFPIPE ()
  (if (null pfd:run)
    (pfl:say "PFPIPE: load pf-load.lsp first.")
    (pfd:run "PFPIPE" 'pfp:main))
  (princ))


;;; ==========================================================================
;;; SECTION 9  --  Design checks: minimum slope and minimum cover (V6.1)
;;; ==========================================================================
;;; Jake, 2026-11-21.  ONE drawing value each (the palette's Settings tab,
;;; pfv:setting).  Unset = no check.  The checks only REPORT -- they never
;;; move a pipe, write an attribute or change the drawing.
;;;
;;; SLOPE is signed, in the flow direction: the block's base point is the
;;; UPSTREAM invert and PFRUN the downstream one (pf-cfg), so positive = it
;;; falls.  An uphill pipe is negative and fails any minimum -- a large
;;; uphill slope can't pass on its size.  The same numbers as its label.
;;;
;;; COVER is measured to the grid's DESIGN_* TIN only -- never the existing
;;; ground -- from the OUTSIDE TOP of the pipe, invert + (ID + OD) / 24 ft,
;;; at both ends and the middle.  The plan point for a station is Carlson's
;;; (the grid's .cl).  No design surface, a blank PFOD (wall unknown), or a
;;; point off the surface: "can't check", never a pass.
;;; Reading a TIN needs Carlson, so cover is measured only inside a command
;;; (the palette's Refresh Line / Refresh All, pfp:check-cover) and the
;;; answers are kept in memory for the session, each with what it was
;;; measured from.  A pipe changed since shows "not checked yet".

(if (not (boundp '*pfp-cover-memory*)) (setq *pfp-cover-memory* nil)) ; ((handle key verdict text) ...)

;; (pfp:signed-slope e g) -> percent, + = falls from the upstream end | nil
;;   (both ends at one station, or the ends can't be read)
(defun pfp:signed-slope (e g / ends run)
  (if (and (setq ends (pfp:ends e))
           (> (setq run (abs (- (car (cadr ends)) (car (car ends))))) 1e-6))
    (* 100.0 (/ (- (pfl:y->elev (cadr (car ends)) g) (pfl:y->elev (cadr (cadr ends)) g)) run))))

;; (pfp:slope-verdict s smin) -> (verdict text)   pure -- PFSELFTEST's
;;   s: signed slope | nil.  verdict 'pass 'fail 'unknown
(defun pfp:slope-verdict (s smin)
  (cond
    ((null s) (list 'unknown "slope: can't check (both ends at one station)"))
    ((< s (- smin 1e-9))
     (list 'fail (strcat "slope " (pfl:fix s 2) "% below " (pfl:fix smin 2) "% min"
                         (if (< s 0.0) " (runs uphill)" ""))))
    (T (list 'pass (strcat "slope " (pfl:fix s 2) "%")))))

;; (pfp:slope-check e g) -> (verdict text) | nil (no minimum set)
(defun pfp:slope-check (e g / smin)
  (if (setq smin (pfv:setting "PFSLOPEMIN"))
    (pfp:slope-verdict (pfp:signed-slope e g) smin)))

;; (pfp:design-tin g) -> the grid's DESIGN_* TIN, found on disk | nil
(defun pfp:design-tin (g / tin)
  (if (setq tin (pfl:g 'tin-design g))
    (cond ((findfile tin)) ((pff:find-in-std tin "tin")))))

;; (pfp:cover-points e g) -> ((station outside-top-elevation) ...) | why not
;;   (a string).  Both ends and the middle.
(defun pfp:cover-points (e g / ends dims x1 x2 e1 e2 add)
  (setq ends (pfp:ends e) dims (pfp:dims e))
  (cond
    ((null ends) "can't read the pipe's ends")
    ((null dims) "the pipe has no size")
    ((null (cadr dims)) "wall unknown (PFOD blank)")
    (T
     (setq add (/ (+ (car dims) (cadr dims)) 24.0)
           x1  (car (car ends))  x2 (car (cadr ends))
           e1  (pfl:y->elev (cadr (car ends)) g)
           e2  (pfl:y->elev (cadr (cadr ends)) g))
     (mapcar '(lambda (f) (list (pfl:x->sta (+ x1 (* f (- x2 x1))) g)
                                (+ e1 (* f (- e2 e1)) add)))
             '(0.0 0.5 1.0)))))

;; (pfp:cover-verdict covers cmin) -> (verdict text)   pure -- PFSELFTEST's
;;   covers: ((station cover-ft | nil) ...); nil = off the surface there
(defun pfp:cover-verdict (covers cmin / off low)
  (foreach c covers
    (cond
      ((null (cadr c)) (if (null off) (setq off c)))
      ((or (null low) (< (cadr c) (cadr low))) (setq low c))))
  (cond
    (off (list 'unknown (strcat "cover: can't check (off the DESIGN surface at STA "
                                (pfl:fmt-sta (car off)) ")")))
    ((null low) (list 'unknown "cover: can't check"))
    ((< (cadr low) (- cmin 1e-9))
     (list 'fail (strcat "cover " (pfl:fix (cadr low) 2) " ft below " (pfl:fix cmin 2)
                         " ft min at STA " (pfl:fmt-sta (car low)))))
    (T (list 'pass (strcat "cover " (pfl:fix (cadr low) 2) " ft")))))

;; (pfp:cover-key e g) -> what a cover answer depends on, as a fingerprint
(defun pfp:cover-key (e g / tin)
  (setq tin (pfp:design-tin g))
  (pfl:fingerprint
    (list (pfp:ends e) (pfp:dims e) (pfl:g 'cl g) tin (if tin (vl-file-systime tin))
          (pfv:setting-text "PFCOVERMIN")
          (mapcar '(lambda (k) (pfl:g k g)) '(leftx basey sta0 datum vscale hplot)))))

;; (pfp:cover-status e g) -> (verdict text) | nil (no minimum set)
;;   No TIN is read here: what can be told without one, else the answer kept
;;   from the last Refresh, else 'unchecked.  Safe in a palette click.
(defun pfp:cover-status (e g / cmin pts hit)
  (cond
    ((null (setq cmin (pfv:setting "PFCOVERMIN"))) nil)
    ((null (pfl:g 'tin-design g)) (list 'unknown "cover: can't check (no DESIGN surface on this grid)"))
    ((null (pfp:design-tin g)) (list 'unknown "cover: can't check (the DESIGN surface file isn't found)"))
    ((= (type (setq pts (pfp:cover-points e g))) 'STR) (list 'unknown (strcat "cover: can't check (" pts ")")))
    ((and (setq hit (assoc (pfl:handle e) *pfp-cover-memory*))
          (= (cadr hit) (pfp:cover-key e g)))
     (cddr hit))
    (T (list 'unchecked "cover: not checked yet (Refresh Line)"))))

;; (pfp:check-cover pairs) -> (checked failed unknown)   MEASURES cover for
;;   ((pipe . grid) ...) and remembers each answer.  Needs Carlson: run it
;;   inside a command.  One TIN loaded at a time.  Reads only.
(defun pfp:check-cover (pairs / cmin by tin c r pts covers xy z n-chk n-fail n-unk)
  (setq n-chk 0 n-fail 0 n-unk 0)
  (if (setq cmin (pfv:setting "PFCOVERMIN"))
    (progn
      (foreach p pairs
        (setq r (pfp:cover-status (car p) (cdr p)))
        (if (and r (eq (car r) 'unknown))
          (setq n-unk (1+ n-unk))
          (if (setq tin (pfp:design-tin (cdr p)))
            (setq by (if (setq c (assoc tin by))
                       (subst (cons tin (cons p (cdr c))) c by)
                       (cons (list tin p) by))))))
      (foreach c by
        (if (pfc:tin-load (car c))
          (progn
            (foreach p (cdr c)
              (setq pts    (pfp:cover-points (car p) (cdr p))
                    covers (mapcar '(lambda (q)
                                      (list (car q)
                                            (if (and (setq xy (pfc:cl-point (pfg:cl (cdr p)) (car q)))
                                                     (setq z (pfc:tin-z (list (car xy) (cadr xy) 0.0))))
                                              (- z (cadr q)))))
                                   pts)
                    r      (pfp:cover-verdict covers cmin)
                    n-chk  (1+ n-chk))
              (cond ((eq (car r) 'fail) (setq n-fail (1+ n-fail)))
                    ((eq (car r) 'unknown) (setq n-unk (1+ n-unk))))
              (setq *pfp-cover-memory*
                (cons (cons (pfl:handle (car p)) (cons (pfp:cover-key (car p) (cdr p)) r))
                      (vl-remove-if '(lambda (m) (= (car m) (pfl:handle (car p)))) *pfp-cover-memory*))))
            (pfc:tin-unload))
          (progn
            (pfl:say (strcat "  ** could not load " (car c) " -- cover not checked on its pipes"))
            (setq n-unk (+ n-unk (length (cdr c)))))))))
  (list n-chk n-fail n-unk))

;; (pfp:design-report lines) -> (pipes failed unknown)   the checks on every
;;   pipe of these lines (nil = every line): cover measured, then each pipe
;;   that fails or can't be checked named.  Inside a command (Carlson).
(defun pfp:design-report (lines / idx pairs ends g ln r s n-fail n-unk sl cv)
  (setq idx (pfg:index) n-fail 0 n-unk 0)
  (foreach e (pfp:all)
    (if (and (setq ends (pfp:ends e))
             (setq g (pfp:grid-of-ends-in ends idx))
             (setq ln (pfg:line-name g))
             (or (null lines) (member ln lines)))
      (setq pairs (cons (cons e g) pairs))))
  (if (or (pfv:setting "PFSLOPEMIN") (pfv:setting "PFCOVERMIN"))
    (progn
      (pfl:say "")
      (pfl:say "  Design checks (they never move a pipe):")
      (pfp:check-cover pairs)
      (foreach p (reverse pairs)
        (setq sl (pfp:slope-check (car p) (cdr p))
              cv (pfp:cover-status (car p) (cdr p))
              s  nil)
        (foreach r (list sl cv)
          (if (and r (member (car r) '(fail unknown unchecked)))
            (setq s (cons (cadr r) s))))
        (if (vl-some '(lambda (r) (and r (eq (car r) 'fail))) (list sl cv))
          (setq n-fail (1+ n-fail))
          (if s (setq n-unk (1+ n-unk))))
        (if s
          (pfl:say (strcat "  ** pipe " (cond ((pfr:get (car p) *pf-pipe-size*)) ("")) " "
                           (pfp:mat (car p)) " on " (pfg:line-name (cdr p))
                           " STA " (pfl:fmt-sta (min (pfl:x->sta (car (car (pfp:ends (car p)))) (cdr p))
                                                     (pfl:x->sta (car (cadr (pfp:ends (car p)))) (cdr p))))
                           ": " (pfl:join-with "; " (reverse s))))))
      (pfl:say (strcat "  " (itoa (length pairs)) " pipe(s) checked: " (itoa n-fail) " below a minimum, "
                       (itoa n-unk) " can't be checked."))))
  (list (length pairs) n-fail n-unk))


(princ "\npf-pipe loaded.  PFPIPE.")
(princ)
