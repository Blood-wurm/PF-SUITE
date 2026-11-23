;;; ==========================================================================
;;; pf-assign.lsp  --  PFASSIGN: the plan side, drawing-wide.
;;; Load position 9: after pf-index, pf-draw.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; No grid pick, no selection (Jake, 2026-10-27).  It goes by line
;;; membership: pf-index's line tree finds every line every plan structure is
;;; on, and PFASSIGN WRITES DOWN, on each block that changed:
;;;   its name                       PFNAME  -- "BA-5/BC-1", the line tree's
;;;   where it sits on its lines     MEMB    (line station offset) per line
;;;   what it is                     PFTYPE, PFSIZE  -- from the block name
;;;   which faces the line uses      PFFACE          -- CBI only
;;;   its reference elevation        PFRIM           -- only if you say so
;;;
;;; A structure moved in plan is re-stationed; one that left a line loses it
;;; (PFREFRESH then erases its copy there).  Legacy HDWL_* blocks
;;; (*pf-count-only*) take their number but are never assigned; suite
;;; PFSUITE_HDWL_* blocks are assigned like other structures.  Anything
;;; typed by hand is kept.
;;;
;;; Rims: typed on the plan block (Properties), or read off each grid's TIN
;;; when you say Yes.  A headwall's PFRIM is its flowline at the block
;;; basepoint and is never read from a TIN.
;;;
;;; The run: PFASSIGN, PFSTRUCT, PFREFRESH.  After a plan edit: PFASSIGN,
;;; then PFREFRESH.
;;; ==========================================================================


;; (pfa:grid-tin g) -> the grid's TIN file, found on disk | nil
(defun pfa:grid-tin (g / tin)
  (setq tin (cond ((pfl:g 'tin-design g)) ((pfl:g 'tin-exist g))))
  (if tin (cond ((findfile tin)) ((pff:find-in-std tin "tin")))))

;; (pfa:ask-tins grids) -> T when rims are to be read off the grids' TINs.
;;   Asked once, only when some grid has a TIN that can be found.
(defun pfa:ask-tins (grids / ans)
  (if (vl-some 'pfa:grid-tin grids)
    (progn
      (initget "Yes No")
      (setq ans (getkword (strcat "\nRead rims from the grids' TINs?  Typed rims are kept;"
                                  " headwall flowlines are never read.  [Yes/No] <No>: ")))
      (= ans "Yes"))))

;; (pfa:rims grids ents) -> lines to report.  Every assigned structure's rim
;;   off the TIN of the grid that shows it -- its first line, A-Z, whose grid
;;   has one.  One TIN loaded at a time.  ents: nil = every plan structure.
(defun pfa:rims (grids ents / by e g tin c r out n-w n-k n-h)
  (setq n-h 0)
  (foreach e (vl-remove-if-not 'pfr:memb-get (cond (ents) ((pfr:all *pf-view-plan*))))
    (if (pfm:headwall-p e)
      (setq n-h (1+ n-h))
      (progn
        (setq tin nil)
        (foreach m (pfr:memb-get e)
          (if (and (null tin) (setq g (pfg:grid-for (car m) (cadr m) nil grids)))
            (setq tin (pfa:grid-tin g))))
        (if tin
          (setq by (if (setq c (assoc tin by))
                     (subst (cons tin (cons e (cdr c))) c by)
                     (cons (list tin e) by)))))))
  (setq n-w 0 n-k 0)
  (foreach c by
    (if (pfc:tin-load (car c))
      (progn
        (foreach e (cdr c)
          (setq r (pfm:rim-put e))
          (cond
            ((eq r 'written) (setq n-w (1+ n-w)))
            ((eq r 'kept)    (setq n-k (1+ n-k)))
            ((eq r 'adopted)
             (setq n-k (1+ n-k)
                   out (cons (strcat "  " (pfm:who e) "  rim changed by hand since last run -- now kept") out)))
            ((eq r 'outside)
             (setq out (cons (strcat "  " (pfm:who e) "  outside " (vl-filename-base (car c))
                                     ".tin -- rim left as it is")
                             out)))))
        (pfc:tin-unload))
      (setq out (cons (strcat "  ** could not load " (car c) " -- its rims skipped") out))))
  (append (reverse out)
          (list (strcat "  Rims: " (itoa n-w) " read off a TIN, " (itoa n-k) " typed by hand and kept."))
          (if (> n-h 0)
            (list (strcat "  Headwalls: " (itoa n-h)
                          " flowline elevation(s) left for PFRIM at the block basepoint.")))))

;; (pfa:run ents rims grids) -> (assigned updated unchanged off skipped)
;;   The work, no questions -- what PFSELFTEST drives (2026-10-30).
;;   ents: nil = every plan structure in the drawing; else only these are
;;   numbered and written (PFSELFTEST's, on its own test lines).
;;   rims: T = read them off the grids' TINs.
(defun pfa:run (ents rims grids) (pfa:run-for ents rims grids nil))

;; (pfa:run-for ents rims grids lname) -> the same five counts, then what
;;   the palette reports apart from them (V6.1, 2026-11-21):
;;     (new updated unchanged off skipped skip-notes near-count count-only)
;;   skip-notes: why each skipped structure was skipped.  near-count: plan
;;   structures near line lname but not on it.  count-only: legacy blocks
;;   that take a number on lname but are never assigned.  Both 0 when lname
;;   is nil.
;;   lname: one line (the palette's Assign, 2026-11-03) -- the tree is still
;;   built as above, so a junction's other line still numbers it, but only
;;   the structures ON that line are written: the ones the tree finds on it,
;;   and the ones whose record still names it (so one moved off it is
;;   caught).  nil = all.
(defun pfa:run-for (ents rims grids lname / lt lines tree res n-new n-upd n-same n-off n-skip
                      n-nolab n-restored lab skips n-near n-count)
  (setq *pfd-stage* "building the line tree")
  (setq lt    (pfm:lines)
        lines (car lt))
  (foreach s (cdr lt) (pfl:say s))
  (setq tree   (pfm:tree lines ents)
        n-near 0
        n-count 0)
  (if lname
    (progn
      ;; counted over the whole tree, before it is cut down to the line
      (foreach row (car tree)
        (cond
          ((and (cadddr row) (assoc lname (cadr row))) (setq n-count (1+ n-count)))
          ((and (not (cadddr row)) (not (assoc lname (cadr row))) (assoc lname (caddr row)))
           (setq n-near (1+ n-near)))))
      (setq tree (cons (vl-remove-if-not '(lambda (row) (or (assoc lname (cadr row))
                                                            (assoc lname (pfr:memb-get (car row)))))
                                         (car tree))
                       (cdr tree)))))

  ;; names first, so everything after is reported under the new name
  (setq *pfd-stage* "writing the names")
  (foreach s (pfm:names-put tree) (pfl:say s))

  (setq *pfd-stage* "assigning structures")
  (setq n-new 0 n-upd 0 n-same 0 n-off 0 n-skip 0)
  (foreach row (car tree)
    (if (not (cadddr row))                         ; a legacy count-only block
      (progn
        (setq res (pfm:assign (car row) (pfm:own-hits (cadr row)) lines))
        (foreach s (cdr res) (pfl:say s))
        (cond ((eq (car res) 'new)     (setq n-new  (1+ n-new)))
              ((eq (car res) 'updated) (setq n-upd  (1+ n-upd)))
              ((eq (car res) 'same)    (setq n-same (1+ n-same)))
              ((eq (car res) 'off)     (setq n-off  (1+ n-off)))
              (T                       (setq n-skip (1+ n-skip)
                                             skips  (append skips
                                                            (cond ((cdr res))
                                                                  ((list (strcat "  " (pfm:who (car row))
                                                                                 "  not a suite structure")))))))))))

  (if rims
    (progn
      (setq *pfd-stage* "reading rims")
      (foreach s (pfa:rims grids ents) (pfl:say s))))

  ;; the plan label: the name on every plan structure of the run, the
  ;; setting's height, a dragged one put back after ATTSYNC (Jake, 2026-11-20)
  (setq *pfd-stage* "plan labels")
  (setq n-nolab 0 n-restored 0)
  (foreach row (car tree)
    (if (and (not (cadddr row)) (pfr:ours-p (car row)) (pfr:memb-get (car row)))
      (progn
        (setq lab (pfm:plan-label (car row)))
        (cond ((eq lab 'none) (setq n-nolab (1+ n-nolab)))
              ((member 'restored lab)
               (setq n-restored (1+ n-restored))
               (pfl:say (strcat "  " (pfm:who (car row)) "  plan label put back where it was dragged (ATTSYNC)")))))))
  (if (> n-nolab 0)
    (pfl:say (strcat "  ** " (itoa n-nolab) " plan structure(s) have no " *pf-tag-plan-label*
                     " attribute -- BEDIT the block, PFMKPLABEL, BSAVE, ATTSYNC")))

  (pfl:say "")
  (pfl:say (strcat "  " (itoa n-new) " assigned, " (itoa n-upd) " updated, "
                   (itoa n-same) " unchanged, " (itoa n-off) " on no line, "
                   (itoa n-skip) " skipped."))
  (if (> (+ n-new n-upd) 0)
    (pfl:say "  Next: PFSTRUCT places any not placed yet, then PFREFRESH."))
  (list n-new n-upd n-same n-off n-skip skips n-near n-count))

;; (pfa:main) -> nil   the command body, run inside pfd:run: the question,
;;   then pfa:run over the whole drawing
(defun pfa:main ( / grids rims)
  (pfc:load)
  (cond
    ((pfc:metric-p)
     (pfl:say "PFASSIGN: this is a METRIC drawing.  V6 is english-only and refuses."))
    ((not (pfc:ready-p))
     (pfl:say "PFASSIGN: Carlson isn't loaded."))
    (T
      (setq *pfd-stage* "reading the grids")
      (setq grids (pfg:usable)
            rims  (pfa:ask-tins grids))
      (pfl:say "")
      (pfl:say "=== PFASSIGN  every plan structure, every line ===")
      (pfa:run nil rims grids)
      (pfl:say "  One UNDO takes this whole run back.")))
  (princ))

;; (pfa:line lname) -> pfa:run-for's result | nil (refused)   the palette's
;;   Assign: one line, no questions.  Rims from the TIN are their own job
;;   (port step 5).
(defun pfa:line (lname / r)
  (pfc:load)
  (cond
    ((pfc:metric-p) (pfl:say "PFASSIGN: this is a METRIC drawing.  V6 is english-only and refuses."))
    ((not (pfc:ready-p)) (pfl:say "PFASSIGN: Carlson isn't loaded."))
    (T
     (pfl:say "")
     (pfl:say (strcat "=== PFASSIGN  line " lname " ==="))
     (setq r (pfa:run-for nil nil nil lname))
     (pfl:say "  One UNDO takes this whole run back.")))
  r)

;; (pfa:drop-line lname) -> (dropped junctions)   Delete Line's plan side
;;   (V6.1, 2026-11-21).  Run AFTER the line's anchors and stub are gone, so
;;   the line table no longer has it.
;;   - Every plan structure whose MEMB names lname loses that entry now, not
;;     at the next PFASSIGN.  Its other lines are left exactly as they were
;;     (not re-stationed).
;;   - Its stamp is renewed only if it was current: one already moved since
;;     PFASSIGN stays "moved since Assign".
;;   - A junction (other lines left) is renamed against the WHOLE remaining
;;     line table -- BA-5/BC-1 becomes BC-1 -- and its plan label follows; a
;;     name typed by hand is kept (pfr:refresh).  A structure on no line now
;;     keeps its name, as PFASSIGN leaves one that went off every line.
;;   dropped: every structure changed.  junctions: those still on a line.
(defun pfa:drop-line (lname / dropped junctions current left tree rows)
  (foreach e (pfm:structures)
    (if (assoc lname (pfr:memb-get e))
      (progn
        (setq current (equal (pfr:stamp-get e) (pfm:plan-fp e))
              left    (vl-remove-if '(lambda (m) (= (car m) lname)) (pfr:memb-get e)))
        (pfr:memb-put e left)
        (if current (pfr:stamp-put e (pfm:plan-fp e)))
        (setq dropped (cons e dropped))
        (if left (setq junctions (cons e junctions))))))
  (if junctions
    (progn
      (setq *pfd-stage* "renaming the junctions")
      (setq tree (pfm:tree (car (pfm:lines)) nil)
            rows (vl-remove-if-not '(lambda (r) (member (car r) junctions)) (car tree)))
      (foreach s (pfm:names-put (cons rows (cdr tree))) (pfl:say s))
      (foreach e junctions (if (pfr:ours-p e) (pfm:plan-label e)))))
  (list (reverse dropped) (reverse junctions)))

(defun c:PFASSIGN ()
  (if (null pfd:run)
    (pfl:say "PFASSIGN: load pf-load.lsp first.")
    (pfd:run "PFASSIGN" 'pfa:main))
  (princ))


(princ "\npf-assign loaded.  PFASSIGN.")
(princ)
