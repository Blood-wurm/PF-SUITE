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
;;;   its rim                        PFRIM           -- only if you say so
;;;
;;; A structure moved in plan is re-stationed; one that left a line loses it
;;; (PFREFRESH then erases its copy there).  Headwalls (*pf-count-only*) take
;;; their number but are never assigned.  Anything typed by hand is kept.
;;;
;;; Rims: typed on the plan block (Properties), or read off each grid's TIN
;;; when you say Yes.  Until V5's PFGL comes over.
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
      (setq ans (getkword (strcat "\nRead rims from the grids' TINs?  Rims you typed are kept"
                                  " either way.  [Yes/No] <No>: ")))
      (= ans "Yes"))))

;; (pfa:rims grids ents) -> lines to report.  Every assigned structure's rim
;;   off the TIN of the grid that shows it -- its first line, A-Z, whose grid
;;   has one.  One TIN loaded at a time.  ents: nil = every plan structure.
(defun pfa:rims (grids ents / by e g tin c r out n-w n-k)
  (foreach e (vl-remove-if-not 'pfr:memb-get (cond (ents) ((pfr:all *pf-view-plan*))))
    (setq tin nil)
    (foreach m (pfr:memb-get e)
      (if (and (null tin) (setq g (pfg:grid-for (car m) (cadr m) nil grids)))
        (setq tin (pfa:grid-tin g))))
    (if tin
      (setq by (if (setq c (assoc tin by))
                 (subst (cons tin (cons e (cdr c))) c by)
                 (cons (list tin e) by)))))
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
          (list (strcat "  Rims: " (itoa n-w) " read off a TIN, " (itoa n-k) " typed by hand and kept."))))

;; (pfa:run ents rims grids) -> (assigned updated unchanged off skipped)
;;   The work, no questions -- what PFSELFTEST drives (2026-10-30).
;;   ents: nil = every plan structure in the drawing; else only these are
;;   numbered and written (PFSELFTEST's, on its own test lines).
;;   rims: T = read them off the grids' TINs.
(defun pfa:run (ents rims grids / lt lines tree res n-new n-upd n-same n-off n-skip)
  (setq *pfd-stage* "building the line tree")
  (setq lt    (pfm:lines)
        lines (car lt))
  (foreach s (cdr lt) (pfl:say s))
  (setq tree (pfm:tree lines ents))

  ;; names first, so everything after is reported under the new name
  (setq *pfd-stage* "writing the names")
  (foreach s (pfm:names-put tree) (pfl:say s))

  (setq *pfd-stage* "assigning structures")
  (setq n-new 0 n-upd 0 n-same 0 n-off 0 n-skip 0)
  (foreach row (car tree)
    (if (not (cadddr row))                         ; a headwall: counted only
      (progn
        (setq res (pfm:assign (car row) (pfm:own-hits (cadr row)) lines))
        (foreach s (cdr res) (pfl:say s))
        (cond ((eq (car res) 'new)     (setq n-new  (1+ n-new)))
              ((eq (car res) 'updated) (setq n-upd  (1+ n-upd)))
              ((eq (car res) 'same)    (setq n-same (1+ n-same)))
              ((eq (car res) 'off)     (setq n-off  (1+ n-off)))
              (T                       (setq n-skip (1+ n-skip)))))))

  (if rims
    (progn
      (setq *pfd-stage* "reading rims")
      (foreach s (pfa:rims grids ents) (pfl:say s))))

  (pfl:say "")
  (pfl:say (strcat "  " (itoa n-new) " assigned, " (itoa n-upd) " updated, "
                   (itoa n-same) " unchanged, " (itoa n-off) " on no line, "
                   (itoa n-skip) " skipped."))
  (if (> (+ n-new n-upd) 0)
    (pfl:say "  Next: PFSTRUCT places any not placed yet, then PFREFRESH."))
  (list n-new n-upd n-same n-off n-skip))

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

(defun c:PFASSIGN ()
  (if (null pfd:run)
    (pfl:say "PFASSIGN: load pf-load.lsp first.")
    (pfd:run "PFASSIGN" 'pfa:main))
  (princ))


(princ "\npf-assign loaded.  PFASSIGN.")
(princ)
