;;; ==========================================================================
;;; pf-invert.lsp  --  the invert rows on each profile copy (PFINV1..5).
;;; Load position: after pf-pipe, before pf-xing and pf-refresh.  Prefix pfi:.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; Port step 4 (Jake, 2026-11-13 and 2026-11-20).  NO COMMAND: PFREFRESH
;;; writes the rows, changed copies only, like everything else on a profile.
;;; Each row is V5's:  I.O. 745.10 (15")
;;;   a pipe attached     that pipe END's elevation -- the pipe block is the
;;;                       truth (a pipe can come in above the floor: a drop)
;;;   no pipe on a side   the structure's BOTTOM on that side, read off the
;;;                       copy (the drafter's PFDEPTH grip; on the sanitary MH
;;;                       the left side is its PFFLOORDWN corner), no size --
;;;                       only where the line carries on past it that way
;;; A pipe belongs to a structure when its end sits at the structure's wall
;;; (within *pf-inv-wall-tol* sideways) anywhere from the bottom up to the
;;; rim.  Downstream is LEFT: an end at the left wall is the outlet, I.O.; at
;;; the right wall the inlet, I.I.  An end exactly at the station line (a
;;; pipe drawn to the centre) goes by which end it is: the pipe's upstream
;;; end leaves the structure.  An end BELOW the bottom is reported, never moved.
;;; At a junction the other lines' pipes -- read on their own grids -- fill
;;; the middle columns; one leaving takes the I.O. column when this line has
;;; none (V5's pfinvert).
;;;
;;; Layout, V5's (pfinvert.lsp, pftools-cfg.lsp): every row turned to read
;;; up, hanging down from one baseline *pf-inv-drop-factor* text heights
;;; below the lowest invert, *pf-inv-gap-factor* text heights apart, centred
;;; on the station; I.O. leftmost, I.I. rightmost.  The most downstream
;;; structure on the line is pushed right (*pf-inv-first-shift*).
;;; A row typed over is kept; a row dragged is left where it is.  The
;;; headwall keeps its own PFINV1 (its flowline, pf-struct).
;;; ==========================================================================

(vl-load-com)

;; Per run: each copy's walls, each grid's pipe ends -- reset by pfi:ctx
(setq *pfi-geo* nil *pfi-atts* nil)


;;; ==========================================================================
;;; SECTION 1  --  The run's picture: grids, pipes, copies
;;; ==========================================================================

;; (pfi:in-grid-p pt g) -> T when pt is inside grid g's box
(defun pfi:in-grid-p (pt g)
  (and pt
       (>= (car pt)  (- (pfl:g 'leftx g) 0.01))
       (or (null (pfl:g 'rightx g)) (<= (car pt) (+ (pfl:g 'rightx g) 0.01)))
       (>= (cadr pt) (- (pfl:g 'basey g) 0.01))
       (<= (cadr pt) (+ (pfl:g 'topy g) 0.01))))

;; (pfi:grid-of pt grids) -> the grid whose box holds pt | nil
(defun pfi:grid-of (pt grids)
  (vl-some '(lambda (g) (if (pfi:in-grid-p pt g) g)) grids))

;; (pfi:same-grid-p a b) -> T when two grid alists are the same grid
(defun pfi:same-grid-p (a b) (and a b (eq (pfl:g 'anchor a) (pfl:g 'anchor b))))

;; (pfi:pipes grids) -> ((pipe g p1 p2 size dims) ...) every pipe whose two
;;   ends are in ONE grid.  p1 upstream (the base point), p2 downstream.
;;   dims: pfp:dims, (id od) inches.  Read once per run.
(defun pfi:pipes (grids / ends g out)
  (foreach e (pfp:all)
    (if (and (setq ends (pfp:ends e))
             (setq g (pfi:grid-of (car ends) grids))
             (pfi:in-grid-p (cadr ends) g))
      (setq out (cons (list e g (car ends) (cadr ends) (pfp:size e) (pfp:dims e)) out))))
  (reverse out))

;; (pfi:copies grids) -> ((copy plan-handle line ins g) ...) every profile
;;   copy, with the grid that holds it (nil when none does)
(defun pfi:copies (grids / ins out)
  (foreach e (pfr:all *pf-view-pro*)
    (setq ins (pfl:ins e))
    (setq out (cons (list e (pfr:deser (pfr:xd-get e *pf-xd-plan*))
                          (pfr:deser (pfr:xd-get e *pf-xd-line*))
                          ins (pfi:grid-of ins grids))
                    out)))
  (reverse out))

;; (pfi:line-mins) -> ((lname . lowest station) ...) of every plan structure
;;   on each line -- which one is the line's most downstream
(defun pfi:line-mins ( / out c)
  (foreach e (pfm:structures)
    (foreach m (pfr:memb-get e)
      (setq c (assoc (car m) out))
      (cond
        ((null c) (setq out (cons (cons (car m) (cadr m)) out)))
        ((< (cadr m) (cdr c)) (setq out (subst (cons (car m) (cadr m)) c out))))))
  out)

;; (pfi:ctx grids) -> the run context: 'grids 'pipes 'copies 'lmin 'top
;;   (top: the grid-top lines, pfg:top-lines)
(defun pfi:ctx (grids)
  (setq *pfi-geo* nil *pfi-atts* nil)
  (list (cons 'grids  grids)
        (cons 'pipes  (pfi:pipes grids))
        (cons 'copies (pfi:copies grids))
        (cons 'lmin   (pfi:line-mins))
        (cons 'top    (pfg:top-lines))))

(defun pfi:c (k ctx) (cdr (assoc k ctx)))


;;; ==========================================================================
;;; SECTION 2  --  A copy's walls and its bottom
;;; ==========================================================================

;; (pfi:barrel-r e) -> the barrel's half-width as the block states it | nil
;;   PFBARREL_R on a lookup block; the sanitary MH's fixed 48" barrel.
(defun pfi:barrel-r (e / v)
  (cond
    ((numberp (setq v (pfl:dynprop-get (vlax-ename->vla-object e) *pf-param-barrel*))) v)
    ((eq (car (pfr:row-for (pfl:effname e))) 'SMH) *pf-smh-barrel-r*)))

;; (pfi:geo e) -> (left-bottom-y right-bottom-y half-width) WORLD | nil.
;;   Read off what the copy shows (pfl:walls) -- nothing is nudged.  No walls
;;   found: the lowest line both sides, width unknown.  Kept for the run.
(defun pfi:geo (e / c r gb)
  (cond
    ((setq c (assoc e *pfi-geo*)) (cdr c))
    (T
     (setq r (pfl:walls e (pfi:barrel-r e)))
     (if (and (null r) (setq gb (pfl:geom-bottom e))) (setq r (list gb gb nil)))
     (setq *pfi-geo* (cons (cons e r) *pfi-geo*))
     r)))


;;; ==========================================================================
;;; SECTION 3  --  Which pipe ends sit at which structure
;;; ==========================================================================

;; (pfi:owner pt g ctx) -> the copy (its ctx row) on grid g that pipe end pt
;;   belongs to | nil.  At its wall within *pf-inv-wall-tol*, not above its
;;   rim; the nearest wall wins.
(defun pfi:owner (pt g ctx / vs best bd geo hw dx lim ins)
  (setq vs (pfl:g 'vscale g))
  (foreach c (pfi:c 'copies ctx)
    (if (and (pfi:same-grid-p (nth 4 c) g) (entget (car c)))
      (progn
        ;; where the copy is NOW -- a refresh may have just moved it
        (setq ins (pfl:ins (car c))
              geo (pfi:geo (car c))
              hw  (if geo (caddr geo))
              dx  (abs (- (car pt) (car ins)))
              lim (if hw (+ hw *pf-inv-wall-tol*) *pf-pipe-snap*))
        (if (and (<= dx lim)
                 (<= (cadr pt) (+ (cadr ins) (* *pf-inv-rim-tol* vs)))
                 (or (null bd) (< (- dx (cond (hw) (0.0))) bd)))
          (setq best c bd (- dx (cond (hw) (0.0))))))))
  best)

;; (pfi:forget pe g) -> nil   a copy just moved or rebuilt: its walls and its
;;   grid's pipe ends are worked out again
(defun pfi:forget (pe g)
  (setq *pfi-geo*  (vl-remove-if '(lambda (c) (eq (car c) pe)) *pfi-geo*)
        *pfi-atts* (if g (vl-remove-if '(lambda (c) (eq (car c) (pfl:g 'anchor g))) *pfi-atts*) nil))
  (princ))

;; (pfi:grid-atts g ctx) -> ((copy . attachments) ...) for every copy on grid
;;   g.  An attachment: (role elev size end-pt pipe which)
;;     role  'out (I.O.) or 'in (I.I.)    which  'up or 'down (the pipe's end)
;;   Worked out once per grid per run.
(defun pfi:grid-atts (g ctx / key c out own dx role)
  (setq key (pfl:g 'anchor g))
  (cond
    ((setq c (assoc key *pfi-atts*)) (cdr c))
    (T
     (foreach p (pfi:c 'pipes ctx)
       (if (pfi:same-grid-p (nth 1 p) g)
         (foreach end (list (cons (nth 2 p) 'up) (cons (nth 3 p) 'down))
           (if (setq own (pfi:owner (car end) g ctx))
             (progn
               (setq dx   (- (car (car end)) (car (pfl:ins (car own))))
                     role (cond ((< dx -0.001) 'out)
                                ((> dx 0.001) 'in)
                                ((eq (cdr end) 'up) 'out)
                                ('in))
                     c    (assoc (car own) out)
                     out  (if c
                            (subst (cons (car own) (cons (list role (pfl:y->elev (cadr (car end)) g) (nth 4 p)
                                                               (car end) (car p) (cdr end))
                                                         (cdr c)))
                                   c out)
                            (cons (list (car own) (list role (pfl:y->elev (cadr (car end)) g) (nth 4 p)
                                                        (car end) (car p) (cdr end)))
                                  out))))))))
     (setq *pfi-atts* (cons (cons key out) *pfi-atts*))
     out)))

;; (pfi:atts e g ctx) -> copy e's attachments, left to right
(defun pfi:atts (e g ctx)
  (vl-sort (cdr (assoc e (pfi:grid-atts g ctx)))
           '(lambda (a b) (< (car (nth 3 a)) (car (nth 3 b))))))


;;; ==========================================================================
;;; SECTION 4  --  The rows
;;; ==========================================================================

;; (pfi:carries-on cl sta) -> (down-p . up-p): the line runs on below / above
;;   this station.  Can't read the .cl: both (rows shown rather than lost).
(defun pfi:carries-on (cl sta / geo rng)
  (if (and cl (setq geo (pfm:geom cl)) (setq rng (cadr geo)))
    (cons (> (- sta (car rng)) *pf-range-eps*) (> (- (cadr rng) sta) *pf-range-eps*))
    (cons T T)))

;; (pfi:row r) -> "I.O. 745.10 (15\")"   an attachment as a row
(defun pfi:row (r)
  (pfp:inv-row (if (eq (car r) 'out) *pf-inv-out* *pf-inv-in*) (cadr r) (caddr r)))

;; (pfi:rows pe plan g ctx) -> (rows elevs dn-x notes)
;;   rows   the texts, left to right (at most *pf-inv-max*)
;;   elevs  their elevations
;;   dn-x   world X of the downstream invert (the first-structure shift)
(defun pfi:rows (pe plan g ctx / lname m sta geo own outs ins on io mid ii elevs notes
                   x hw dn-x vs cm atts)
  (setq lname (pfg:line-name g)
        m     (assoc lname (pfr:memb-get plan))
        sta   (if m (cadr m) (pfl:x->sta (car (pfl:ins pe)) g))
        geo   (pfi:geo pe)
        hw    (if geo (caddr geo))
        x     (car (pfl:ins pe))
        vs    (pfl:g 'vscale g)
        own   (pfi:atts pe g ctx)
        outs  (vl-remove-if-not '(lambda (r) (eq (car r) 'out)) own)
        ins   (vl-remove-if-not '(lambda (r) (eq (car r) 'in)) own)
        on    (pfi:carries-on (pfg:cl g) sta))
  ;; this line: pipes, or the bottom where the line carries on and no pipe is
  (setq io (mapcar '(lambda (r) (list (pfi:row r) (cadr r))) outs)
        ii (mapcar '(lambda (r) (list (pfi:row r) (cadr r))) ins))
  (if (and (null io) (car on) geo)
    (setq io (list (list (pfp:inv-row *pf-inv-out* (pfl:y->elev (car geo) g) nil)
                         (pfl:y->elev (car geo) g)))))
  (if (and (null ii) (cdr on) geo)
    (setq ii (list (list (pfp:inv-row *pf-inv-in* (pfl:y->elev (cadr geo) g) nil)
                         (pfl:y->elev (cadr geo) g)))))
  ;; a pipe end below the bottom on its side is reported, never moved
  (if geo
    (foreach r own
      (if (< (cadr (nth 3 r)) (- (if (eq (car r) 'out) (car geo) (cadr geo)) (* *pf-inv-below-tol* vs)))
        (setq notes (cons (strcat "      ** a pipe's " (if (eq (car r) 'out) "outlet" "inlet") " invert "
                                  (pfl:fix (cadr r) 2) " is BELOW the structure's bottom "
                                  (pfl:fix (pfl:y->elev (if (eq (car r) 'out) (car geo) (cadr geo)) g) 2)
                                  " -- drag the bottom down, or fix the pipe")
                          notes)))))
  ;; a junction: the other lines' pipes, on their own copies and grids
  (foreach om (vl-sort (vl-remove-if '(lambda (k) (= (car k) lname)) (pfr:memb-get plan))
                       '(lambda (a b) (< (car a) (car b))))
    (if (setq cm (vl-some '(lambda (c) (if (and (= (nth 1 c) (pfl:handle plan)) (= (nth 2 c) (car om))) c))
                          (pfi:c 'copies ctx)))
      (if (nth 4 cm)
        (foreach r (pfi:atts (car cm) (nth 4 cm) ctx)
          (if (and (eq (car r) 'out) (null io))
            (setq io (list (list (pfi:row r) (cadr r))))
            (setq mid (append mid (list (list (pfi:row r) (cadr r))))))))))
  ;; the downstream invert's X, for the first-structure shift
  (setq dn-x (cond (outs (car (nth 3 (car outs))))
                   (ins  (car (nth 3 (car ins))))
                   (hw   (- x hw))
                   (x)))
  (setq atts (append io mid ii))
  (if (> (length atts) *pf-inv-max*)
    (setq notes (cons (strcat "      ** " (itoa (length atts)) " invert rows -- only "
                              (itoa *pf-inv-max*) " fit; the rest are not shown")
                      notes)
          atts  (reverse (cdr (reverse atts)))))
  (while (> (length atts) *pf-inv-max*) (setq atts (reverse (cdr (reverse atts)))))
  (list (mapcar 'car atts) (mapcar 'cadr atts) dn-x (reverse notes)))

;; (pfi:layout pe g rows elevs dn-x ctx) -> ((tag . pt) ...) where each row goes
;;   V5's fan: one baseline below the lowest invert, centred on the station,
;;   the line's most downstream structure pushed right.
(defun pfi:layout (pe g rows elevs dn-x ctx / ht gapn n halfw basey x draw sta lmin rule target i out)
  (setq ht    (pfg:text-ht g)
        gapn  (* ht *pf-inv-gap-factor*)
        n     (length rows)
        halfw (* 0.5 gapn (float (max 0 (1- n))))
        basey (- (pfl:elev->y (apply 'min elevs) g) (* ht *pf-inv-drop-factor*))
        x     (car (pfl:ins pe))
        draw  x
        sta   (pfl:x->sta x g)
        lmin  (cdr (assoc (pfg:line-name g) (pfi:c 'lmin ctx))))
  (if (and lmin (equal sta lmin 0.05))
    (progn
      (setq rule   (cond ((cdr (assoc (pfl:g 'util g) *pf-inv-first-shift*)))
                         (*pf-inv-first-shift-default*))
            target (if (eq (car rule) 'INVERT)
                     (+ dn-x (cadr rule))
                     (+ (pfl:g 'leftx g) (cadr rule))))
      (setq draw (+ x (max 0.0 (- target (- x halfw)))))))
  (setq i 0)
  (foreach r rows
    (setq out (cons (cons (nth i *pf-tags-inv*) (list (+ (- draw halfw) (* i gapn)) basey)) out)
          i   (1+ i)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 5  --  Writing them
;;; ==========================================================================

;; (pfi:skip-p plan) -> T for a block whose PFINV1 is its own (the headwall)
(defun pfi:skip-p (plan) (eq (car (pfr:row-for (pfl:effname plan))) 'HDWL))

;; (pfi:ref pe) -> what the invert rows ride: the copy's right-hand bottom.
;;   The rows are in PFDEPTH's stretch, so a dragged bottom carries them --
;;   measured from the bottom, that is not a hand move.
(defun pfi:ref (pe / geo)
  (if (setq geo (pfi:geo pe))
    (list (car (pfl:ins pe)) (cadr geo))
    (pfl:ins pe)))

;; (pfi:fp pe plan g ctx) -> what the rows are built from and where they sit,
;;   for PFREFRESH's fingerprint
(defun pfi:fp (pe plan g ctx / r)
  (if (pfi:skip-p plan)
    ""
    (progn
      (setq r (pfi:rows pe plan g ctx))
      (pfl:fingerprint
        (list (car r) (cadr r) (caddr r) (pfi:geo pe)
              (cdr (assoc (pfg:line-name g) (pfi:c 'lmin ctx)))
              (mapcar '(lambda (tg) (list (pfr:get pe tg) (pfr:att-pt pe tg))) *pf-tags-inv*))))))

;; (pfi:update pe plan g ctx) -> notes   the rows written and placed
(defun pfi:update (pe plan g ctx / r rows pts tag txt res kept ref ht n notes i)
  (cond
    ((pfi:skip-p plan) nil)
    ((null (pfr:attr-ent pe (car *pf-tags-inv*)))
     (list (strcat "      ** no " (car *pf-tags-inv*) " on this block -- invert rows not written")))
    (T
     (setq *pfd-stage* "invert rows")
     (setq r     (pfi:rows pe plan g ctx)
           rows  (car r)
           notes (cadddr r)
           ref   (pfi:ref pe)
           ht    (pfg:text-ht g)
           pts   (if rows (pfi:layout pe g rows (cadr r) (caddr r) ctx)))
     ;; the text -- a row typed over is kept; the unused slots blank
     (setq i 0)
     (foreach tag *pf-tags-inv*
       (setq txt (cond ((nth i rows)) (""))
             res (pfr:refresh pe tag txt *pf-src-rule*)
             i   (1+ i))
       (if (member res '(kept adopted)) (setq kept (cons tag kept))))
     (if kept (setq notes (cons (strcat "      inverts typed over by hand, kept: " (pfl:join (reverse kept))) notes)))
     ;; where they sit -- one dragged is left there
     (foreach p pts
       (if (pfr:moved-p pe (car p) ref)
         (setq notes (cons (strcat "      " (car p) " moved by hand -- left where it is") notes))
         (progn
           (pfr:att-place pe (car p) (cdr p) ht (/ pi 2.0) 'MR)
           (pfr:pos-put pe (car p) (cdr p) ref))))
     (if (null rows) (setq notes (cons "      no invert rows: no pipes, and the line goes no further" notes)))
     (reverse notes))))


(princ "\npf-invert loaded.")
(princ)
