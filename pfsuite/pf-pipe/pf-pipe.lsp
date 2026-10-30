;;; ==========================================================================
;;; pf-pipe.lsp  --  PFPIPE: the profile pipe block.
;;; Load position 11: after pf-anchor, pf-record, pf-draw, pf-struct.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; PFPIPE  click the upstream invert, then the downstream invert, inside a
;;;         profile grid.  Before the first click, S = size, M = material.
;;;         Uses the last size / material.  Walls are left off.
;;;
;;; Replaces the standalone pfpipe.lsp in the V6 folder -- do not load both.
;;;   - the grid comes from the anchor you click in: its exaggeration, its
;;;     text height, and its pipe material as the first default.  No fixed x10.
;;;   - the label is written by pfp:update, which the pipe-label step will
;;;     rerun, so placing a pipe and refreshing one cannot disagree.
;;;
;;; THE PIPE'S ENDS ARE THE TRUTH (first version, 2026-10-13).  Nothing about
;;; which structures it connects is stored: it is worked out from where the
;;; ends are, so a grip-stretched pipe is simply re-read.
;;;
;;; Size and material are attributes on the pipe (PFSIZE, PFMAT).
;;;
;;; THE LABEL'S GRIP IS PFLEAD (2026-10-22).  Drag it out of the pipe and the
;;; next PFREFRESH turns the label level and draws a leader to it -- a
;;; polyline of the tool's, tagged with the pipe's handle.  Drag it back in
;;; and the label lies along the pipe again, the leader erased.
;;;
;;; Reads Carlson's own libraries at run time (nothing is copied here):
;;;   USER\pipesize.dta   size in inches = 3rd field, wall thickness = LAST
;;;   USER\pipen.dta      n, Material, typecode
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfp-size*)) (setq *pfp-size* nil))   ; inches
(if (not (boundp '*pfp-mat*))  (setq *pfp-mat*  nil))   ; material name


;;; ==========================================================================
;;; SECTION 1  --  Carlson's pipe libraries
;;; ==========================================================================

;; folder that holds pipesize.dta, NO trailing backslash, or nil.
;;   usrdir$ ends in a backslash; callers add their own, so it is trimmed
;;   here -- a doubled one made findfile miss the file.
(defun pfp:userdir ( / hit root d)
  (setq d (if (and (boundp 'usrdir$) (= (type usrdir$) 'STR))
            (vl-string-right-trim "\\/" usrdir$)))
  (cond
    ((and d (findfile (strcat d "\\" *pf-lib-pipesize*)))
     d)
    (T
     (setq root (strcat (getenv "AppData") "\\Carlson Software"))
     ;; newest-looking folder first.  NOT (or list '()) -- or returns T.
     (foreach y (reverse (vl-sort (vl-directory-files root "Carlson*" -1) '<))
       (foreach r (reverse (vl-sort (vl-directory-files (strcat root "\\" y) "R*" -1) '<))
         (setq d (strcat root "\\" y "\\" r "\\USER"))
         (if (and (null hit) (findfile (strcat d "\\" *pf-lib-pipesize*))) (setq hit d))))
     hit)))

;; -> ((size-inches . wall-inches) ...) sorted.  Skips headers / short rows.
;;   Older 4-field files still exist on some machines; same rule reads both.
;;   ROUND PIPE ONLY: the first field is the shape -- 0 round, then box,
;;   elliptical and arch rows (1 2 3) whose third field is not a diameter.
(defun pfp:sizes ( / d out f)
  (if (setq d (pfp:userdir))
    (foreach l (pfl:readlines (strcat d "\\" *pf-lib-pipesize*))
      (setq f (pfl:split l))
      (if (and (>= (length f) 4)
               (= 0.0 (distof (car f)))
               (numberp (distof (nth 2 f)))
               (numberp (distof (last f)))
               (> (distof (nth 2 f)) 0.0))
        (setq out (cons (cons (distof (nth 2 f)) (distof (last f))) out)))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

;; -> ("Concrete" "RCP III" ...)
(defun pfp:mats ( / d out f)
  (if (setq d (pfp:userdir))
    (foreach l (pfl:readlines (strcat d "\\" *pf-lib-pipen*))
      (setq f (pfl:split l))
      (if (and (>= (length f) 2) (numberp (distof (car f))))
        (setq out (cons (cadr f) out)))))
  (reverse out))

;; (pfp:wall size) -> wall thickness in inches | nil
(defun pfp:wall (size) (cdr (assoc size (pfp:sizes))))


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

;; (pfp:size e) -> inches as a number | nil    PFSIZE reads like 15"
(defun pfp:size (e / s n)
  (setq s (pfr:get e *pf-pipe-size*))
  (if (and s (> (setq n (atof s)) 0.0)) n))

;; (pfp:mat e) -> material text, "" when blank
(defun pfp:mat (e / s)
  (if (setq s (pfr:get e *pf-pipe-mat*)) s ""))

(defun pfp:size-text (n) (strcat (rtos n 2 0) "\""))


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
          inputs
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
(defun pfp:leader-verts (e top right mid up dia walls sf / obj dir tip land bend back)
  (setq obj  (vlax-ename->vla-object e)
        dir  (if right -1.0 1.0)            ; from the text toward the arrow
        tip  (if up
               (list (car mid) (+ (cadr mid) dia
                                  (if walls (cond ((pfl:dynprop-get obj *pf-pipe-wt*)) (0.0)) 0.0)))
               (list (car mid) (- (cadr mid)
                                  (if walls (cond ((pfl:dynprop-get obj *pf-pipe-wb*)) (0.0)) 0.0))))
        land (list (+ (car top) (* dir sf *pf-pipe-land-gap*)) (cadr top))
        bend (list (+ (car land) (* dir sf *pf-pipe-land-len*)) (cadr land))
        back (polar tip (angle tip bend) (* sf *pf-pipe-arrow-len*)))
  (list (list tip  0.0 (* sf *pf-pipe-arrow-wid*))
        (list back 0.0 0.0)
        (list bend 0.0 0.0)
        (list land 0.0 0.0)))

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
                     rot just top bot notes w)
  (setq *pfd-stage* "reading the pipe")
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
     (setq p1  (car ends) p2 (cadr ends)
           e1  (pfl:y->elev (cadr p1) g)
           e2  (pfl:y->elev (cadr p2) g)
           run (abs (- (car p2) (car p1)))
           dia (* (/ size 12.0) vs))

     ;; the drawn diameter follows PFSIZE; walls too, when the library has them
     (setq *pfd-stage* "setting the diameter and walls")
     (if (> (abs (- dia (cond ((pfl:dynprop-get obj *pf-pipe-dia*)) (0.0)))) 1e-4)
       (if (/= T (setq r (pfd:dynprop-put obj *pf-pipe-dia* dia)))
         (setq notes (cons (strcat "      diameter: " r) notes))))
     (if (and (setq wall (pfp:wall size)) (> wall 0.0))   ; 0 = library has none
       (foreach prm (list *pf-pipe-wt* *pf-pipe-wb*)
         (if (> (abs (- (* (/ wall 12.0) vs) (cond ((pfl:dynprop-get obj prm)) (0.0)))) 1e-4)
           (pfd:dynprop-put obj prm (* (/ wall 12.0) vs)))))

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
     (pfr:stamp-put e (pfp:fp e g inputs))          ; what PFREFRESH compares
     (cons (strcat (car rows) "  /  " (cdr rows)) (reverse notes)))))


;;; ==========================================================================
;;; SECTION 4  --  For the invert-label step (NOT CALLED YET)
;;; ==========================================================================
;;; Moved here from the old PFDRAW, which drew inverts until 2026-10-15 when
;;; placing structures became structures-only.  Kept for the invert/pipe-label
;;; step (workflow step 4).  ctx is pf-struct's run context plus a 'pipes key:
;;;   ((ename anchor p1 p2 up-copy down-copy) ...)
;;; An unexplained "consp nil" was hit in the old invert step and never found.
;;; V5's rules to port then are in its pfinvert.lsp and pftools-cfg.lsp
;;; (fan drop 4.0 x text height, column gap 2.0 x, first-structure shift).

;; (pfp:end-at pt anchor copies) -> the copy this pipe end sits at | nil
(defun pfp:end-at (pt anchor copies / best bd d)
  (foreach c copies
    (if (and anchor (eq (nth 3 c) anchor))
      (progn
        (setq d (abs (- (car pt) (nth 4 c))))
        (if (and (<= d *pf-pipe-snap*) (or (null bd) (< d bd)))
          (setq best (car c) bd d)))))
  best)

;; (pfp:end-elev pipe which ctx) -> elevation of the 'up or 'down end | nil
(defun pfp:end-elev (pipe which ctx / g)
  (if (setq g (cdr (assoc (nth 1 pipe) (pfs:ctx 'grids ctx))))
    (pfl:y->elev (cadr (if (eq which 'up) (nth 2 pipe) (nth 3 pipe))) g)))

;; (pfp:inverts copy ctx) -> ((prefix elev size) ...) at this copy, I.O. first
(defun pfp:inverts (copy ctx / outs ins z)
  (foreach p (pfs:ctx 'pipes ctx)
    (if (and (eq (nth 4 p) copy) (setq z (pfp:end-elev p 'up ctx)))
      (setq outs (cons (list *pf-inv-out* z (pfp:size (car p))) outs)))
    (if (and (eq (nth 5 p) copy) (setq z (pfp:end-elev p 'down ctx)))
      (setq ins (cons (list *pf-inv-in* z (pfp:size (car p))) ins))))
  (append (reverse outs) (reverse ins)))

;; (pfp:lowest plan ctx) -> the lowest invert at this STRUCTURE, across every
;;   line it is on | nil
(defun pfp:lowest (plan ctx / low z)
  (foreach c (pfs:ctx 'copies ctx)
    (if (= (nth 1 c) plan)
      (foreach r (pfp:inverts (car c) ctx)
        (setq z (cadr r))
        (if (or (null low) (< z low)) (setq low z)))))
  low)

;; (pfp:inv-row prefix elev size) -> "I.O. 765.43 (15\")"   V5's format
(defun pfp:inv-row (prefix elev size)
  (strcat prefix " " (pfl:fix elev 2)
          (if size (strcat " (" (rtos size 2 0) "\")") "")))


;;; ==========================================================================
;;; SECTION 5  --  PFPIPE
;;; ==========================================================================

(defun pfp:pick-size ( / sizes s)
  (setq sizes (pfp:sizes))
  (cond
    ((null sizes) (pfl:say "No sizes found in Carlson's pipesize.dta."))
    (T
     (pfl:say (strcat "Sizes (in): "
                      (apply 'strcat (mapcar '(lambda (x) (strcat (rtos (car x) 2 0) "  ")) sizes))))
     (setq s (getreal (strcat "\nInside diameter, inches <"
                              (if *pfp-size* (rtos *pfp-size* 2 0) "none") ">: ")))
     (cond
       ((null s))
       ((assoc s sizes) (setq *pfp-size* s))
       (T (pfl:say "That size is not in the library.  Add it in Carlson first."))))))

(defun pfp:pick-mat ( / mats i n)
  (setq mats (pfp:mats))
  (cond
    ((null mats) (pfl:say "No materials found in Carlson's pipen.dta."))
    (T
     (setq i 0)
     (foreach m mats (setq i (1+ i)) (pfl:say (strcat "  " (itoa i) "  " m)))
     (setq n (getint (strcat "\nMaterial number <" (cond (*pfp-mat*) ("none")) ">: ")))
     (if (and n (<= 1 n (length mats))) (setq *pfp-mat* (nth (1- n) mats))))))

;; (pfp:place p1 p2 g size mat others) -> (pipe label-text note ...) |
;;   explanation string.  The work of PFPIPE, no questions -- what PFSELFTEST
;;   drives (2026-10-30).  p1 p2: WORLD upstream and downstream inverts, in
;;   grid g.  size: inches.  mat: text.  others: the pipes whose label inputs
;;   this one shares -- T = every pipe in the drawing (the command).
(defun pfp:place (p1 p2 g size mat others / e obj sy)
  (setq *pfd-stage* "inserting the pipe")
  (cond
    ((null (setq e (pfd:insert *pf-pipe-block* p1))) "AutoCAD would not insert the block")
    (T
     (setq obj (vlax-ename->vla-object e))
     (pfr:put e *pf-pipe-size* (pfp:size-text size))
     (pfr:put e *pf-pipe-mat*  (cond (mat) ("")))
     (pfr:schema-put e)
     ;; the run, then visibility; size and label in pfp:update
     (pfd:dynprop-put obj *pf-pipe-run-x* (- (car p2) (car p1)))
     (pfd:dynprop-put obj *pf-pipe-run-y* (- (cadr p2) (cadr p1)))
     (pfd:dynprop-put obj *pf-pipe-vis* *pf-pipe-state-plain*)
     ;; the shared label inputs: this pipe gets what every pipe holds, and a
     ;; change typed on any pipe goes to all
     (setq *pfd-stage* "sharing the label inputs")
     (setq sy (pfp:sync-in (if (eq others T) (pfp:all) (cons e others))))
     (foreach s (cdr sy) (pfl:say s))
     (cons e (pfp:update e g (car sy))))))

;; (pfp:main) -> nil   the command body, run inside pfd:run: the clicks,
;;   then pfp:place
(defun pfp:main ( / p1u p2u p1 p2 g go res)
  (cond
    ((= 1 (getvar "BLOCKEDITOR")) (pfl:say "PFPIPE: close the Block Editor first."))
    ((null (tblsearch "BLOCK" *pf-pipe-block*))
     (pfl:say (strcat "PFPIPE: no " *pf-pipe-block* " block in this drawing.  Insert one once, then erase it.")))
    ((null (pfp:sizes)) (pfl:say "PFPIPE: can't read Carlson's pipesize.dta."))
    (T
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
           (T
            ;; first material default: the one PFSETUP recorded on the grid
            (if (null *pfp-mat*) (setq *pfp-mat* (cond ((pfl:g 'material g)) ((car (pfp:mats))))))
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


(princ "\npf-pipe loaded.  PFPIPE.")
(princ)
