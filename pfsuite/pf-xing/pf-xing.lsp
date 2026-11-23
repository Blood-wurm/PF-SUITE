;;; ==========================================================================
;;; pf-xing.lsp  --  PFXLABEL: crossings, with the clearance checked.
;;; Load position: after pf-invert, before pf-refresh.  Prefix pfk:.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; Jake, 2026-11-20.  On ONE line -- the one picked in the palette, or
;;; clicked at the command line (drawing-wide may come later):
;;;   1. every place another line's .cl crosses this one's (V5's discovery):
;;;      not within *pf-xing-end-tol* of either line's end (a tie-in), not
;;;      within *pf-xing-struct-tol* of a plan structure (a junction)
;;;   2. the crossing pipe from THAT line's PFSUITE_PIPE blocks, on its own
;;;      grid, at its station -- no pipe block there, nothing is drawn
;;;   3. this line's pipe at the crossing, from its pipe blocks
;;;   4. one PFSUITE_CROSSING block per crossing, at the crossing pipe's invert:
;;;      the inside of the pipe (ellipse), its outside (ellipse) and the
;;;      wall between (hatch) -- WALL OFF when the OD isn't known -- and the
;;;      label, "PROP. WATER MAIN 'A'" / the crossing pipe's size and
;;;      material.  (2026-11-22: the block of two ellipses.  V5's station
;;;      line and vertical station text are DEFERRED -- drawn only when an
;;;      insert has PFTOP / PFBOT / PFSTA1.)
;;;   5. the clearance, OUTSIDE to OUTSIDE (the pipe blocks' PFID / PFOD):
;;;        short of PFCLRMIN, or a wall not known   -> RED, and a warning
;;;        within PFCLRWARN of PFCLRMIN (or short)  -> a dimension from the
;;;                    outside of this line's pipe wall, PFCLRMIN long,
;;;                    reading `18" MIN.`, and a tick + note at that wall
;;;      PFCLRMIN / PFCLRWARN are drawing settings (the palette's Settings
;;;      tab, one value per drawing), 18" and 6" built in.
;;; Run again: the same crossings are updated (matched by the crossing line
;;; and station), new ones placed, ones no longer there erased.
;;; From then on PFREFRESH keeps every crossing block up to date when a pipe
;;; changes; only PFXLABEL finds new crossings (a .cl redrawn).
;;;
;;; The label goes RIGHT of the pipe by default (2026-11-22; the block has no
;;; flip grip).  Its side is read off PFLEAD: put PFLEAD near the left-hand
;;; spot and the label goes left.  Dragged anywhere else, it stays where it
;;; was put, on a leader the tool draws -- its arrow 1 unit off the pipe,
;;; half way up (Jake).
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Settings, words, the blocks
;;; ==========================================================================

;; (pfk:setting tag lname) -> the setting as a number.  V6.1: ONE value per
;;   drawing (pfv:setting) -- lname is kept for the callers and ignored, so an
;;   old line or utility value can never override the drawing's.
(defun pfk:setting (tag lname)
  (pfv:setting tag))

;; (pfk:words table util short) -> V5's wording for the crossing line
(defun pfk:words (table util short / w)
  (setq w (cond ((cdr (assoc (strcase util) table)))
                ((eq table *pf-xing-line-words*) (strcat "PROP. " (strcase util) " LINE '[name]'"))
                ((strcat "PROP. " (strcase util) " CROSSING"))))
  (pfl:subst-all short "[name]" w))

;; (pfk:xing-p e) -> T if e is a crossing block
(defun pfk:xing-p (e)
  (and (= "INSERT" (cdr (assoc 0 (entget e))))
       (= (strcase (pfl:effname e)) (strcase *pf-xing-block*))))

;; (pfk:all) -> every crossing block in model space (released ones skipped)
(defun pfk:all ( / ss i e out)
  (if (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 (strcat *pf-xing-block* ",`*U*")) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))))
      (if (and (pfk:xing-p e) (not (pfr:released-p e))) (setq out (cons e out)))))
  out)

;; (pfk:rec e) -> (tline tsta sline ssta) what the block marks | nil
(defun pfk:rec (e / r)
  (if (and (setq r (pfr:val-get e *pf-xd-xing*)) (listp r) (= 4 (length r))) r))

;; (pfk:extras) -> ((block-handle ent ...) ...) everything the tool drew for
;;   a crossing block: dimension, ticks, note, leader
(defun pfk:extras ( / ss i e h c out)
  (if (setq ss (ssget "_X" (list '(410 . "Model") (list -3 (list *pf-app*)))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))))
      (if (and (/= "INSERT" (cdr (assoc 0 (entget e))))
               (= (type (setq h (pfr:val-get e *pf-xd-xing*))) 'STR))
        (setq out (if (setq c (assoc h out))
                    (subst (cons h (cons e (cdr c))) c out)
                    (cons (list h e) out))))))
  out)

;; (pfk:extras-of e extras) -> what was drawn for crossing block e
(defun pfk:extras-of (e extras) (cdr (assoc (pfl:handle e) extras)))


;;; ==========================================================================
;;; SECTION 2  --  Finding the crossings  (V5's .cl x .cl)
;;; ==========================================================================

;; (pfk:segs verts) -> ((a b xmin ymin xmax ymax) ...) a line's segments
(defun pfk:segs (verts / a out)
  (setq a (car verts))
  (foreach b (cdr verts)
    (setq out (cons (list a b (min (car a) (car b)) (min (cadr a) (cadr b))
                          (max (car a) (car b)) (max (cadr a) (cadr b)))
                    out)
          a b))
  (reverse out))

;; (pfk:sta-at a b p) -> the station at point p on segment a-b ((x y sta) ends)
(defun pfk:sta-at (a b p / d)
  (setq d (distance (pfm:pt2 a) (pfm:pt2 b)))
  (if (> d 1e-9)
    (+ (caddr a) (* (/ (distance (pfm:pt2 a) p) d) (- (caddr b) (caddr a))))
    (caddr a)))

;; (pfk:hits l m) -> ((tsta ssta pt) ...) where line m's .cl crosses line l's
(defun pfk:hits (l m / lb mb ms p out)
  (setq lb (pfl:g 'box l) mb (pfl:g 'box m))
  (if (and (<= (car lb) (caddr mb)) (<= (car mb) (caddr lb))
           (<= (cadr lb) (cadddr mb)) (<= (cadr mb) (cadddr lb)))
    (progn
      (setq ms (vl-remove-if-not
                 '(lambda (s) (and (<= (nth 2 s) (caddr lb)) (>= (nth 4 s) (car lb))
                                   (<= (nth 3 s) (cadddr lb)) (>= (nth 5 s) (cadr lb))))
                 (pfk:segs (pfl:g 'verts m))))
      (foreach s (pfk:segs (pfl:g 'verts l))
        (foreach t2 ms
          (if (and (<= (nth 2 s) (nth 4 t2)) (<= (nth 2 t2) (nth 4 s))
                   (<= (nth 3 s) (nth 5 t2)) (<= (nth 3 t2) (nth 5 s))
                   (setq p (inters (pfm:pt2 (car s)) (pfm:pt2 (cadr s))
                                   (pfm:pt2 (car t2)) (pfm:pt2 (cadr t2)) T)))
            (setq out (cons (list (pfk:sta-at (car s) (cadr s) p)
                                  (pfk:sta-at (car t2) (cadr t2) p)
                                  (pfm:pt2 p))
                            out)))))))
  ;; a hit right on a vertex is found twice
  (setq out (vl-sort out '(lambda (a b) (< (car a) (car b)))))
  (pfk:dedupe out))

(defun pfk:dedupe (hits / out)
  (foreach h hits
    (if (not (and out (< (abs (- (car h) (car (car out)))) 0.5)))
      (setq out (cons h out))))
  (reverse out))

;; (pfk:find lname lines plans) -> (crossings . skipped)
;;   crossings: ((tsta sline ssta util short pt) ...) along the line
;;   skipped:   lines saying why a hit is not a crossing
(defun pfk:find (lname lines plans / l rl rm out skip why)
  (if (setq l (pfm:line-entry lname lines))
    (foreach m lines
      (if (/= (pfl:g 'lname m) lname)
        (foreach h (pfk:hits l m)
          (setq rl (pfl:g 'rng l) rm (pfl:g 'rng m)
                why (cond
                      ((or (< (- (car h) (car rl)) *pf-xing-end-tol*) (< (- (cadr rl) (car h)) *pf-xing-end-tol*)
                           (< (- (cadr h) (car rm)) *pf-xing-end-tol*) (< (- (cadr rm) (cadr h)) *pf-xing-end-tol*))
                       "a line ends there (a tie-in)")
                      ((vl-some '(lambda (e) (<= (distance (pfm:pt2 (pfl:ins e)) (caddr h)) *pf-xing-struct-tol*))
                                plans)
                       "a structure is there (a junction)")))
          (if why
            (setq skip (cons (strcat "  " (pfl:g 'lname m) " at STA " (pfl:fmt-sta (car h)) " -- " why) skip))
            (setq out (cons (list (car h) (pfl:g 'lname m) (cadr h) (pfl:g 'util m) (pfl:g 'short m) (caddr h))
                            out)))))))
  (cons (vl-sort out '(lambda (a b) (< (car a) (car b)))) (reverse skip)))


;;; ==========================================================================
;;; SECTION 3  --  The pipes at a crossing, and the clearance
;;; ==========================================================================

;; (pfk:pipe-at lname sta ctx) -> (pipe elev dims g x) of the pipe block on
;;   that line's grid running past station sta | nil.  elev: its invert there.
(defun pfk:pipe-at (lname sta ctx / g x hit p1 p2 y)
  (if (setq g (pfg:grid-for lname sta nil (pfi:c 'grids ctx)))
    (progn
      (setq x (pfl:sta->x sta g))
      (foreach p (pfi:c 'pipes ctx)
        (setq p1 (nth 2 p) p2 (nth 3 p))
        (if (and (null hit) (pfi:same-grid-p (nth 1 p) g)
                 (<= (min (car p1) (car p2)) x (max (car p1) (car p2)))
                 (> (abs (- (car p2) (car p1))) 1e-6))
          (setq y   (+ (cadr p1) (* (- x (car p1)) (/ (- (cadr p2) (cadr p1)) (- (car p2) (car p1)))))
                hit (list (car p) (pfl:y->elev y g) (nth 5 p) g x))))
      hit)))

;; (pfk:clear src tgt) -> (status clr above) for the two pipes at a crossing
;;   src / tgt: (elev id od) -- invert ft, diameters inches, od nil unknown.
;;   status 'ok 'near 'low 'unknown; clr inches (nil when unknown); above T
;;   when the crossing pipe is over this line's.
(defun pfk:clear (src tgt cmin cwarn / zs is os zt it ot ws wt above clr)
  (setq zs (car src) is (cadr src) os (caddr src)
        zt (car tgt) it (cadr tgt) ot (caddr tgt)
        above (> (+ zs (/ is 24.0)) (+ zt (/ it 24.0))))
  (if (and os ot)
    (progn
      (setq ws (/ (- os is) 24.0) wt (/ (- ot it) 24.0)
            clr (* 12.0 (if above
                          (- (- zs ws) (+ zt (/ it 12.0) wt))
                          (- (- zt wt) (+ zs (/ is 12.0) ws)))))
      (list (cond ((< clr cmin) 'low) ((< clr (+ cmin cwarn)) 'near) ('ok)) clr above))
    (list 'unknown nil above)))

;; (pfk:status-text st) -> what the palette and the run say
;;   PASS / FAIL with the clearance (Jake, 2026-11-20); the palette's rows
;;   say the same.
(defun pfk:status-text (st clr cmin)
  (cond
    ((eq st 'ok)      (strcat "PASS  " (pfl:fix clr 1) "\""))
    ((eq st 'near)    (strcat "PASS  " (pfl:fix clr 1) "\"  (within the margin -- dimensioned)"))
    ((eq st 'low)     (strcat "FAIL  " (pfl:fix clr 1) "\"  (minimum " (rtos cmin 2 0) "\")"))
    ;; V6.1: three verdicts -- PASS, FAIL, UNKNOWN.  UNKNOWN is never a pass:
    ;; the block still goes red and the run still warns (pfk:bad-p).
    ((eq st 'unknown) "UNKNOWN  wall not known (PFOD blank)")
    ((eq st 'nopipe)  "UNKNOWN  no pipe on this line")
    ("?")))

;; (pfk:bad-p st) -> T when the block goes red
(defun pfk:bad-p (st) (and (member st '(low unknown)) T))


;;; ==========================================================================
;;; SECTION 4  --  One crossing block
;;; ==========================================================================

;; (pfk:data e ctx) -> everything one block is built from | (nil . why)
;;   An alist: tline tsta sline ssta g x src tgt srcpipe tgtpipe st clr above
;;   cmin cwarn util short
(defun pfk:data (e ctx / rec src tgt g st cl cmin cwarn util)
  (setq rec (pfk:rec e))
  (cond
    ((null rec) (cons nil "no crossing record"))
    ((null (setq g (pfg:grid-for (car rec) (cadr rec) nil (pfi:c 'grids ctx))))
     (cons nil (strcat "no grid of " (car rec) " shows STA " (pfl:fmt-sta (cadr rec)))))
    ((null (setq src (pfk:pipe-at (caddr rec) (cadddr rec) ctx)))
     (cons nil (strcat "no pipe block on " (caddr rec) " at its STA " (pfl:fmt-sta (cadddr rec)))))
    (T
     (setq tgt   (pfk:pipe-at (car rec) (cadr rec) ctx)
           cmin  (cond ((pfk:setting "PFCLRMIN" (car rec))) (18.0))
           cwarn (cond ((pfk:setting "PFCLRWARN" (car rec))) (6.0))
           util  (car (pfl:line-parts (caddr rec))))
     (setq cl (if tgt
                (pfk:clear (list (cadr src) (car (caddr src)) (cadr (caddr src)))
                           (list (cadr tgt) (car (caddr tgt)) (cadr (caddr tgt)))
                           cmin cwarn)
                (list 'nopipe nil nil)))
     (list (cons 'tline (car rec)) (cons 'tsta (cadr rec)) (cons 'sline (caddr rec)) (cons 'ssta (cadddr rec))
           (cons 'g g) (cons 'x (pfl:sta->x (cadr rec) g))
           (cons 'src src) (cons 'tgt tgt) (cons 'st (car cl)) (cons 'clr (cadr cl)) (cons 'above (caddr cl))
           (cons 'cmin cmin) (cons 'cwarn cwarn)
           (cons 'util util) (cons 'short (cdr (pfl:line-parts (caddr rec))))))))

(defun pfk:d (k d) (cdr (assoc k d)))

;; What pfk:update last drew, for the stamp that follows it
(setq *pfk-drawn* nil)

;; (pfk:fp e d extras) -> what the block is built from and what it shows.
;;   extras: the ((handle ent ...) ...) of pfk:extras, or the block's own
;;   list of drawn entities
(defun pfk:fp (e d extras)
  (pfl:fingerprint
    (list *pf-fp-ver*
          (if (car d)
            (list (pfk:d 'tsta d) (pfk:d 'ssta d)
                  (mapcar '(lambda (k) (pfl:g k (pfk:d 'g d))) '(leftx basey sta0 datum vscale hplot))
                  (mapcar '(lambda (p) (if p (list (pfp:ends (car p)) (pfr:get (car p) *pf-pipe-size*)
                                                    (pfr:get (car p) *pf-pipe-mat*) (nth 2 p))))
                          (list (pfk:d 'src d) (pfk:d 'tgt d)))
                  (pfk:d 'cmin d) (pfk:d 'cwarn d))
            d)
          (pfl:ins e)
          (pfp:pt-get e *pf-xing-lead*)
          ;; the two ellipses' radii and the wall state (2026-11-22)
          (mapcar '(lambda (n) (pfl:dynprop-get (vlax-ename->vla-object e) n))
                  (list *pf-xing-id-x* *pf-xing-id-y* *pf-xing-od-x* *pf-xing-od-y*))
          (pfp:state-now (vlax-ename->vla-object e))
          (mapcar '(lambda (tg) (list (pfr:get e tg) (pfr:att-pt e tg))) *pf-xing-tags*)
          ;; in any order: the drawing hands them back in its own
          (vl-sort (vl-remove nil
                     (mapcar '(lambda (x) (if (entget x) (cdr (assoc 10 (entget x)))))
                             ;; the block's own list -- pfk:stamp hands '(nil) when
                             ;; nothing was drawn, and (assoc ... '(nil)) is an error
                             ;; (a clean PASS stopped PFXLABEL here; CAD, 2026-11-22)
                             (if (and extras (or (null (car extras)) (= (type (car extras)) 'ENAME)))
                               (vl-remove nil extras)
                               (pfk:extras-of e extras))))
                   '(lambda (a b) (if (equal (car a) (car b) 1e-6) (< (cadr a) (cadr b)) (< (car a) (car b))))))))

;;; ---- the block's size: two ellipses, the wall, the invert (2026-11-22) -----
;;; Read in CAD from the saved block: PFID_X / PFID_Y and PFOD_X / PFOD_Y are
;;; the ellipses' radii, and a move action on PFID_Y keeps the inner invert at
;;; the insertion point.  BUT its four "X" / "Y" scale actions each scale
;;; BOTH axes (uniform), so setting X and Y together scales twice.  So:
;;;   1. ResetBlock -- every size back to the drafted default
;;;   2. the Y radii only: right for this block on a x10 grid (the drafted
;;;      ellipses are 10 times taller than wide), the invert kept by the move
;;;   3. what is DRAWN is measured; if it isn't the size wanted -- a block
;;;      whose X and Y scales are truly independent, or a grid that isn't x10
;;;      -- the X radii are set too, and measured again
;;;   4. still wrong: said, in the run, never drawn wrong silently.

;; (pfk:ellipses e) -> ((rx ry cx cy) ...) every ellipse the insert DRAWS,
;;   relative to its insertion point, in the block's own order: the INNER
;;   first, as drafted (PFGATE checks it is the smaller at the drafted size).
;;   Not sorted by size -- a doubled inner would swap places.  Read off the
;;   insert's own (anonymous) definition.  The tool's inserts are never
;;   rotated or scaled.
(defun pfk:ellipses (e / blk base sub ed maj a b c out)
  (setq blk  (tblobjname "BLOCK" (cdr (assoc 2 (entget e))))
        base (cdr (assoc 10 (entget blk)))
        sub  blk)
  (while (and (setq sub (entnext sub)) (setq ed (entget sub)) (/= (cdr (assoc 0 ed)) "ENDBLK"))
    (if (= (cdr (assoc 0 ed)) "ELLIPSE")
      (setq maj (cdr (assoc 11 ed))
            a   (distance '(0.0 0.0 0.0) maj)
            b   (* a (cdr (assoc 40 ed)))
            c   (mapcar '- (cdr (assoc 10 ed)) base)
            out (cons (if (> (abs (car maj)) (abs (cadr maj)))
                        (list a b (car c) (cadr c))
                        (list b a (car c) (cadr c)))
                      out))))
  (reverse out))

;; (pfk:size-off e want) -> nil when what is drawn is want | what is off, in
;;   words.  want: (rx ry orx ory) -- orx / ory nil: the OD is not known and
;;   the outer ellipse isn't checked (WALL OFF hides it).  The inner invert
;;   must sit on the insertion point.
(defun pfk:size-off (e want / el in out tol)
  (setq el (pfk:ellipses e) in (car el) out (cadr el) tol 1e-4)
  (cond
    ((null in) "the block draws no ellipse")
    ((or (> (abs (- (car in) (car want))) tol) (> (abs (- (cadr in) (cadr want))) tol))
     (strcat "the inside ellipse is drawn " (pfl:fix (car in) 3) " x " (pfl:fix (cadr in) 3)
             ", wanted " (pfl:fix (car want) 3) " x " (pfl:fix (cadr want) 3)))
    ((> (abs (- (cadddr in) (cadr in))) tol)
     (strcat "the inside invert is " (pfl:fix (- (cadddr in) (cadr in)) 3) " off the insertion point"))
    ((null (caddr want)) nil)
    ((null out) "the block draws no outside ellipse")
    ((or (> (abs (- (car out) (caddr want))) tol) (> (abs (- (cadr out) (cadddr want))) tol))
     (strcat "the outside ellipse is drawn " (pfl:fix (car out) 3) " x " (pfl:fix (cadr out) 3)
             ", wanted " (pfl:fix (caddr want) 3) " x " (pfl:fix (cadddr want) 3)))
    ((> (abs (- (cadddr out) (cadddr in))) tol) "the two ellipses aren't concentric")))

;; (pfk:atts-keep e) -> ((tag . value) ...)   every attribute's text -- kept
;;   across ResetBlock, whatever it does to them
(defun pfk:atts-keep (e / a ed out)
  (setq a (entnext e))
  (while (and a (setq ed (entget a)) (= (cdr (assoc 0 ed)) "ATTRIB"))
    (setq out (cons (cons (cdr (assoc 2 ed)) (cdr (assoc 1 ed))) out)
          a   (entnext a)))
  out)

;; (pfk:size e want) -> T | why not   the ellipses to want (pfk:size-off's)
(defun pfk:size (e want / obj kept r why)
  (setq obj  (vlax-ename->vla-object e)
        kept (pfk:atts-keep e))
  ;; 1. the drafted state
  (vl-catch-all-apply 'vla-ResetBlock (list obj))
  (foreach k kept
    (if (/= (pfr:get e (car k)) (cdr k)) (pfr:put e (car k) (cdr k))))
  ;; 2. the Y radii
  (setq r (pfp:put obj *pf-xing-id-y* (cadr want)))
  (if (and (= r T) (cadddr want)) (setq r (pfp:put obj *pf-xing-od-y* (cadddr want))))
  (cond
    ((/= r T) r)
    ((null (setq why (pfk:size-off e want))) T)
    (T
     ;; 3. the X radii too
     (setq r (pfp:put obj *pf-xing-id-x* (car want)))
     (if (and (= r T) (caddr want)) (setq r (pfp:put obj *pf-xing-od-x* (caddr want))))
     (cond
       ((/= r T) r)
       ((null (setq why (pfk:size-off e want))) T)
       (T (strcat why " -- check PFSUITE_CROSSING's scale actions (PFGATE)"))))))

;; (pfk:wall obj state) -> T | why not   WALL ON / WALL OFF
(defun pfk:wall (obj state / p)
  (cond
    ((null (setq p (pfl:visprop obj))) "the block has no WALL ON / WALL OFF states")
    ((= (strcase (vl-princ-to-string (pfl:prop-get p))) (strcase state)) T)
    (T (pfd:prop-put p state))))

;; (pfk:draw-extras e d layer bad sf ht) -> ents   the dimension, the wall
;;   ticks and note -- only when the clearance is within PFCLRWARN of the
;;   minimum (or under it) and this line's pipe wall is known
(defun pfk:draw-extras (e d bad / g x tgt it ot wt face out up p2 tl ht sf ents en cmin)
  (setq g (pfk:d 'g d) x (pfk:d 'x d) tgt (pfk:d 'tgt d) cmin (pfk:d 'cmin d)
        ht (pfg:text-ht g) sf (/ (pfl:g 'hplot g) *pf-ref-hplot*))
  (if (and (member (pfk:d 'st d) '(low near)) tgt (cadr (nth 2 tgt)))
    (progn
      (setq it (car (nth 2 tgt)) ot (cadr (nth 2 tgt)) wt (/ (- ot it) 24.0)
            up (pfk:d 'above d)
            ;; the wall face toward the crossing pipe, and its outside
            face (pfl:elev->y (if up (+ (cadr tgt) (/ it 12.0)) (cadr tgt)) g)
            out  (pfl:elev->y (if up (+ (cadr tgt) (/ it 12.0) wt) (- (cadr tgt) wt)) g)
            p2   (+ out (* (if up 1.0 -1.0) (/ cmin 12.0) (pfl:g 'vscale g)))
            tl   (/ (* *pf-xing-tick-len* sf) 2.0))
      (foreach y (list face out)
        (if (setq en (pfd:line (list (- x tl) y) (list (+ x tl) y) (cdr (assoc 8 (entget e)))))
          (setq ents (cons en ents))))
      (if (setq en (pfd:text (list (- x tl (* 0.5 sf)) (/ (+ face out) 2.0))
                             (strcat (pfl:fix (* 12.0 wt) 2) "\" WT. ("
                                     (cond ((pfr:get (car tgt) *pf-pipe-size*)) ("")) " "
                                     (pfp:mat (car tgt)) ")")
                             (cdr (assoc 8 (entget e))) (* 0.75 ht) 0.0 'MR nil))
        (setq ents (cons en ents)))
      (if (setq en (pfd:dim-vert (list x out) (list x p2) (+ x tl) (cdr (assoc 8 (entget e)))
                                 (strcat (rtos cmin 2 0) "\" MIN.")))
        (setq ents (cons en ents)))))
  ents)

;; (pfk:update e ctx extras) -> (status-text note ...)
;;   Everything on one crossing block, from its record: the pipes, the
;;   clearance, the ellipse and ticks, the station line, the label and its
;;   leader, the colour, and the dimension.  Text typed over is kept.
(defun pfk:update (e ctx extras / d g x src tgt obj vs is os ws sf ht sv lab lead ref dx cy left-def
                     right-def right dragged half top bot just tip notes r cmin bad ents gtop layer
                     rx ry orx ory vr)
  (setq *pfd-stage* "reading the crossing")
  (setq d (pfk:data e ctx))
  (cond
    ((null (car d))
     (foreach x (pfk:extras-of e extras) (pfd:erase x))
     (list "?" (strcat "      ** " (cdr d) " -- left as it is")))
    (T
     (setq g   (pfk:d 'g d) x (pfk:d 'x d) src (pfk:d 'src d) tgt (pfk:d 'tgt d)
           obj (vlax-ename->vla-object e)
           vs  (pfl:g 'vscale g)
           is  (car (nth 2 src)) os (cadr (nth 2 src))
           ws  (if os (/ (- os is) 24.0))
           sf  (/ (pfl:g 'hplot g) *pf-ref-hplot*)
           ht  (pfg:text-ht g)
           cmin (pfk:d 'cmin d)
           bad (pfk:bad-p (pfk:d 'st d))
           layer (cdr (assoc 8 (entget e))))
     ;; the block at the crossing pipe's invert.  Its grips travel with it;
     ;; the label grip is read after the move and BEFORE any property change
     (setq *pfd-stage* "moving the crossing block")
     (pfd:move e (list x (pfl:elev->y (cadr src) g)))
     (setq ref  (pfl:ins e)
           lead (pfp:pt-get e *pf-xing-lead*))
     ;; the pipe: its inside and outside ellipses, radii X = dia / 24 ft, Y =
     ;; X times the grid's exaggeration; the wall shown only when the OD is
     ;; known -- a wall is never made up (2026-11-22)
     (setq *pfd-stage* "sizing the crossing pipe")
     (setq rx  (/ is 24.0)       ry  (* rx vs)
           orx (if os (/ os 24.0)) ory (if os (* orx vs)))
     (if (/= T (setq r (pfk:size e (list rx ry orx ory))))
       (setq notes (cons (strcat "      ** the crossing block's size: " r) notes)))
     (if (/= T (setq r (pfk:wall obj (if os *pf-xing-state-wall* *pf-xing-state-nowall*))))
       (setq notes (cons (strcat "      ** wall: " r) notes)))
     (if (null ws) (setq notes (cons "      ** the crossing pipe's wall is not known (PFOD blank) -- WALL OFF, clearance UNKNOWN" notes)))
     ;; DEFERRED: V5's station line, up to the grid top and down below the
     ;; grid -- only on an insert that has it (the saved block doesn't yet)
     (if (pfl:dynprop obj *pf-xing-top*)
       (progn
         (setq *pfd-stage* "fitting the station line")
         (setq gtop (pfg:top-at x g (cond ((pfi:c 'top ctx)) ((pfg:top-lines)))))
         (if (/= T (setq r (pfd:fit-end e *pf-xing-top* 'top (cond (gtop) ((pfl:g 'topy g))))))
           (setq notes (cons (strcat "      top: " r) notes)))
         (if (/= T (setq r (pfd:fit-end e *pf-xing-bot* 'bot (- (pfl:g 'basey g) (* *pf-xing-line-ext* sf)))))
           (setq notes (cons (strcat "      bottom: " r) notes)))))
     ;; the text -- typed over is kept
     (setq *pfd-stage* "writing the crossing label")
     (foreach p (append
                  (list (cons *pf-xing-label* (pfk:words *pf-xing-line-words* (pfk:d 'util d) (pfk:d 'short d)))
                        (cons *pf-xing-label2* (pfl:join (list (pfr:get (car src) *pf-pipe-size*) (pfp:mat (car src))))))
                  ;; DEFERRED: the station text, when the insert has it
                  (if (pfr:attr-ent e *pf-xing-sta*)
                    (list (cons *pf-xing-sta* (pfl:join (list (pfl:fmt-sta (pfk:d 'tsta d))
                                                              (pfk:words *pf-xing-sta-words* (pfk:d 'util d) (pfk:d 'short d))))))))
       (if (member (pfr:refresh e (car p) (cdr p) *pf-src-rule*) '(kept adopted))
         (setq notes (cons (strcat "      " (car p) " typed over by hand -- kept") notes))))
     (pfr:put e *pf-xing-type* *pf-xing-typename*)
     (pfr:put e *pf-xing-size* (pfr:get (car src) *pf-pipe-size*))
     (pfr:put e *pf-xing-mat*  (pfp:mat (car src)))
     (pfr:put e *pf-xing-inv*  (pfl:fix (cadr src) 2))
     (pfr:put e *pf-xing-clr*  (cond ((pfk:d 'clr d) (pfl:fix (pfk:d 'clr d) 2))
                                     ((eq (pfk:d 'st d) 'unknown) "UNKNOWN")
                                     ("")))
     ;; DEFERRED: the station text hangs below the line, reading up (V5)
     (if (and (pfr:attr-ent e *pf-xing-sta*) (pfl:dynprop obj *pf-xing-bot*))
       (pfr:att-place e *pf-xing-sta* (list x (pfl:end-y e 'bot)) ht (/ pi 2.0) 'MR))
     ;; the label (2026-11-22): RIGHT of the pipe by default; the side read
     ;; off PFLEAD -- near the left-hand spot, it goes left.  Anywhere else,
     ;; moved by the drafter, it stays there on a leader.  Every offset in
     ;; text heights, so the rows move apart as the text grows.  Worked out
     ;; for the NEW size: a pipe that grew moves the label out with it.
     (setq *pfd-stage* "placing the crossing label")
     (setq vr        (if os orx rx)                 ; the drawn pipe's half width
           cy        (+ (cadr ref) ry)               ; the pipe's centre
           dx        (max (* *pf-xing-lead-dx* ht) (+ vr (* *pf-xing-lead-clear* ht)))
           right-def (list (+ x dx) (- cy (* *pf-xing-lead-dy* ht)))
           left-def  (list (- x dx) (- cy (* *pf-xing-lead-dy* ht)))
           right     (not (and lead (< (car lead) x)))
           lab       (if right right-def left-def)
           dragged   (and lead
                          (> (distance lead lab) (* *pf-xing-side-tol* ht))
                          (pfr:moved-from-p e *pf-xing-lead* lead ref)))
     (if dragged (setq lab lead))
     ;; PFLEAD back where it belongs: the sizing above moved it (it rides the
     ;; block's move action), and a dragged one stays where it was put
     (if (and lead (/= T (setq r (pfp:pt-put e *pf-xing-lead* lab))))
       (setq notes (cons (strcat "      " *pf-xing-lead* ": " r) notes)))
     (if (and lead (not dragged)) (pfr:pos-put e *pf-xing-lead* lab ref))
     (setq half (* *pf-xing-row-dy* ht)
           top  (list (car lab) (+ (cadr lab) half))
           bot  (list (car lab) (- (cadr lab) half))
           just (if (>= (car lab) x) 'ML 'MR))
     (pfr:att-place e *pf-xing-label*  top ht 0.0 just)
     (pfr:att-place e *pf-xing-label2* bot ht 0.0 just)
     (if (null lead)
       (setq notes (cons (strcat "      ** no " *pf-xing-lead* " grip on this block -- the label can't be dragged") notes)))
     ;; what the tool draws: erased and drawn again
     (setq *pfd-stage* "drawing the clearance dimension")
     (foreach x2 (pfk:extras-of e extras) (pfd:erase x2))
     (setq ents (pfk:draw-extras e d bad))
     (if dragged
       (progn
         (setq tip (list (+ x (* (if (> (car lab) x) 1.0 -1.0) (+ vr (* *pf-xing-arrow-off* sf)))) cy))
         (if (setq r (pfd:pline (pfl:leader-path tip top (> (car lab) (car tip)) sf) layer))
           (setq ents (cons r ents)))
         (setq notes (cons "      label dragged by hand -- kept there, on a leader" notes))))
     (foreach x2 ents (pfr:val-put x2 *pf-xd-xing* (pfl:handle e)))
     ;; red when short or unknown
     (pfd:color e (if bad 1 256))
     (foreach x2 ents (pfd:color x2 (if bad 1 256)))
     (setq *pfk-drawn* ents)                 ; for pfk:stamp
     (pfr:schema-put e)
     (cons (strcat (pfk:d 'sline d) " at STA " (pfl:fmt-sta (pfk:d 'tsta d)) "  "
                   (pfk:status-text (pfk:d 'st d) (pfk:d 'clr d) cmin))
           (reverse notes)))))

;; (pfk:stamp e ctx) -> nil   the fingerprint, right after pfk:update wrote
;;   the block and drew *pfk-drawn*
(defun pfk:stamp (e ctx)
  (pfr:stamp-put e (pfk:fp e (pfk:data e ctx) (cond (*pfk-drawn*) ('(nil)))))
  (princ))


;;; ==========================================================================
;;; SECTION 5  --  PFXLABEL on one line
;;; ==========================================================================

;; (pfk:status e ctx) -> (sline tsta status-text bad-p) for the palette
(defun pfk:status (e ctx / d)
  (setq d (pfk:data e ctx))
  (if (car d)
    (list (pfk:d 'sline d) (pfk:d 'tsta d)
          (pfk:status-text (pfk:d 'st d) (pfk:d 'clr d) (pfk:d 'cmin d))
          (or (pfk:bad-p (pfk:d 'st d)) (eq (pfk:d 'st d) 'nopipe)))
    (list (cond ((caddr (pfk:rec e))) ("?")) (cond ((cadr (pfk:rec e))) (0.0)) (cdr d) T)))

;; (pfk:on-line lname) -> the crossing blocks on that line
(defun pfk:on-line (lname)
  (vl-remove-if-not '(lambda (e) (= (car (pfk:rec e)) lname)) (pfk:all)))

;; (pfk:run lname grids) -> (placed updated erased skipped warnings)
;;   PFXLABEL's work, no questions -- what PFSELFTEST and the palette drive.
(defun pfk:run (lname grids / lt lines plans found ctx have done e r n-new n-upd n-gone n-skip warn
                  extras src g)
  (setq n-new 0 n-upd 0 n-gone 0 n-skip 0)
  (pfl:say "")
  (pfl:say (strcat "=== PFXLABEL  crossings on " lname " ==="))
  (cond
    ((not (tblsearch "BLOCK" *pf-xing-block*))
     (pfl:say (strcat "  ** no " *pf-xing-block* " block in this drawing -- insert it once, then erase it.")))
    (T
     (setq *pfd-stage* "reading the lines")
     (setq lt    (pfm:lines)
           lines (car lt)
           plans (pfm:structures)
           ctx   (pfi:ctx grids))
     (cond
       ((null (pfm:line-entry lname lines))
        (pfl:say (strcat "  ** " lname " has no readable .cl -- nothing to cross")))
       (T
        (setq *pfd-stage* "finding the crossings")
        (setq found  (pfk:find lname lines plans)
              have   (pfk:on-line lname)
              extras (pfk:extras))
        (foreach s (cdr found) (pfl:say s))
        (foreach c (car found)
          (setq *pfd-stage* (strcat "the crossing with " (cadr c)))
          (setq src (pfk:pipe-at (cadr c) (caddr c) ctx)
                g   (pfg:grid-for lname (car c) nil grids))
          (cond
            ((null g)
             (setq n-skip (1+ n-skip))
             (pfl:say (strcat "  " (cadr c) " at STA " (pfl:fmt-sta (car c)) " -- no grid of " lname
                              " shows this station")))
            ((null src)
             (setq n-skip (1+ n-skip))
             (pfl:say (strcat "  " (cadr c) " at STA " (pfl:fmt-sta (car c)) " -- no pipe block on " (cadr c)
                              " at its STA " (pfl:fmt-sta (caddr c)) "; nothing drawn")))
            (T
             ;; the same crossing as before: same crossing line, near the station
             (setq e (vl-some '(lambda (x) (if (and (= (caddr (pfk:rec x)) (cadr c))
                                                    (< (abs (- (cadr (pfk:rec x)) (car c))) *pf-xing-match-tol*)
                                                    (not (member x done)))
                                               x))
                              have))
             (if e
               (setq n-upd (1+ n-upd))
               (if (setq e (pfd:insert *pf-xing-block* (list (pfl:sta->x (car c) g) (pfl:elev->y (cadr src) g))))
                 (setq n-new (1+ n-new))
                 (pfl:say (strcat "  ** AutoCAD would not insert " *pf-xing-block*))))
             (if e
               (progn
                 (setq done (cons e done))
                 (pfr:val-put e *pf-xd-xing* (list lname (car c) (cadr c) (caddr c)))
                 (pfr:xd-put e *pf-xd-line* (pfr:ser lname))
                 (setq r (pfd:try (strcat "the crossing with " (cadr c)) 'pfk:update (list e ctx extras)))
                 (if r
                   (progn
                     (pfk:stamp e ctx)
                     (pfl:say (strcat "  " (car r)))
                     (foreach s (cdr r) (pfl:say s))
                     (if (pfk:bad-p (pfk:d 'st (pfk:data e ctx)))
                       (setq warn (cons (car r) warn))))))))))
        ;; crossings that are no longer there
        (setq extras (pfk:extras))
        (foreach x have
          (if (not (member x done))
            (progn
              (foreach x2 (pfk:extras-of x extras) (pfd:erase x2))
              (pfd:erase x)
              (setq n-gone (1+ n-gone))
              (pfl:say (strcat "  erased the crossing with " (cond ((caddr (pfk:rec x))) ("?"))
                               " -- the lines no longer cross there")))))))
     (pfl:say "")
     (pfl:say (strcat "  " (itoa n-new) " placed, " (itoa n-upd) " updated, " (itoa n-gone) " erased, "
                      (itoa n-skip) " not drawn."))
     (if warn
       (progn
         (pfl:say (strcat "  ** " (itoa (length warn)) " CROSSING(S) NEED A LOOK:"))
         (foreach w (reverse warn) (pfl:say (strcat "     " w)))))))
  (list n-new n-upd n-gone n-skip (reverse warn)))

;; (pfk:pick-line) -> the line clicked (anything in its grid) | nil
(defun pfk:pick-line ( / es a g)
  (if (setq es (entsel "\nClick anything in the profile grid of the line to label crossings on: "))
    (if (and (setq a (pfg:anchor-of (trans (cadr es) 1 0))) (setq g (pfg:grid a)))
      (pfg:line-name g)
      (progn (pfl:say "PFXLABEL: that isn't in a profile grid.") nil))))

(defun pfk:main ( / ln)
  (pfc:load)
  (cond
    ((= 1 (getvar "BLOCKEDITOR")) (pfl:say "PFXLABEL: close the Block Editor first."))
    ((null (setq ln (pfk:pick-line))) (pfl:say "PFXLABEL: no line picked -- nothing done."))
    (T (pfk:run ln (pfg:usable)) (pfl:say "  One UNDO takes this whole run back.")))
  (princ))

(defun c:PFXLABEL ()
  (if (null pfd:run)
    (pfl:say "PFXLABEL: load pf-load.lsp first.")
    (pfd:run "PFXLABEL" 'pfk:main))
  (princ))


(princ "\npf-xing loaded.  PFXLABEL.")
(princ)
