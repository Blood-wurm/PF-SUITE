;;; ==========================================================================
;;; pf-refresh.lsp  --  PFREFRESH: update every suite block that changed.
;;; Load position 12: after pf-struct, pf-pipe.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; ONE refresh (Jake, 2026-10-16).  For every profile CBI and pipe in scope
;;; it asks: has anything this block is built from changed since the tool
;;; last wrote it?  It compares a fingerprint (pfl:fingerprint) against the
;;; one stored on the block (SEEN).
;;;   same      -> left completely alone
;;;   different -> updated, and the run says which and why
;;;
;;; SCOPE (Jake, 2026-10-27): "Refresh [Selected/Line/Drawing] <Line>".
;;; Refreshing the whole drawing every time would lock up a big one.
;;;   Line      the copies, pipes and leaders on one line's grids -- picked by
;;;             clicking anything on it.  The palette will hand the line over.
;;;   Selected  the profile copies, pipes and leaders picked (a plan
;;;             structure picked brings its copies)
;;;   Drawing   everything
;;; The shared drafter inputs are read drawing-wide whatever the scope.  Each
;;; step's time is printed at the end (MILLISECS).
;;;
;;; PROFILE SIDE ONLY (Jake, 2026-10-27).  The plan side -- which lines a
;;; structure is on, its stations, face and name -- is PFASSIGN's.  A plan
;;; structure moved or new since PFASSIGN last ran is named ("run PFASSIGN
;;; first"), never re-stationed here.
;;;
;;; ALWAYS LEFT ALONE, even on a block that is updated:
;;;   label text typed over by hand            (pfr:refresh keeps it)
;;;   labels moved by hand                     (pfr:moved-p -- but a label
;;;                                             reset by ATTSYNC is put back)
;;;   where a pipe label was dragged OUT of    (its PFLEAD grip.  Its rotation,
;;;   the pipe                                  justification and leader ARE
;;;                                             redone: level on a leader --
;;;                                             2026-10-22.  Dragged INSIDE the
;;;                                             pipe it goes back to the centre
;;;                                             -- 2026-10-27)
;;;   the barrel depth, PFDEPTH                (the drafter's)
;;;   the alpha blocks                         (PFASSIGN's -- never written here)
;;;   pipe ends                                (the truth -- read, never moved)
;;;   anchors                                  (only read)
;;;
;;; IT ERASES ORPHANS AND DUPLICATES (Jake, 2026-10-16): a profile copy whose
;;; alpha block is gone or off the line, and a second copy of the same alpha
;;; block on the same line -- each one named in the run.
;;;
;;; IT DOES NOT PLACE.  Placing new profile copies is PFSTRUCT's ("place
;;; structures in profile" -- it places every structure not placed yet).
;;; Refresh lists any it finds.  PFSTRUCT and PFPIPE place; from then on
;;; PFREFRESH carries everything (Jake, 2026-10-16).
;;; ==========================================================================


;; The grids and the grid for a station are shared with PFSTRUCT: pfg:usable,
;; pfg:grid-for (pf-anchor).  pfm:stale (pf-index) finds plan changes.


;;; ---- scope ----------------------------------------------------------------
;;; A scope is ("Drawing"), ("Line" lname ...) or ("Selected" ename ...).

;; (pfu:line-of-pt pt) -> the line of the grid pt is in | nil
(defun pfu:line-of-pt (pt / a g)
  (if (and pt (setq a (pfg:anchor-of pt)) (setq g (pfg:grid a)))
    (pfg:line-name g)))

;; (pfu:lines-at e pt) -> the line names a clicked object is on | nil
;;   A profile copy: its line.  A plan structure: its lines.  A pipe or its
;;   leader: the line of the grid the pipe is in.  Anything else (a grid
;;   line, text): the grid the click was in.  pt in WORLD coordinates.
(defun pfu:lines-at (e pt / p ln)
  (cond
    ((and (pfr:ours-p e) (= (strcase (cond ((pfr:view e)) (""))) (strcase *pf-view-pro*)))
     (if (setq ln (pfr:deser (pfr:xd-get e *pf-xd-line*))) (list ln)))
    ((and (pfr:ours-p e) (pfr:memb-get e))
     (mapcar 'car (pfr:memb-get e)))
    ((setq p (cond ((pfp:pipe-p e) e) ((pfp:leader-owner e))))
     (if (setq ln (pfu:line-of-pt (car (pfp:ends p)))) (list ln)))
    ((setq ln (pfu:line-of-pt pt)) (list ln))))

;; (pfu:scope) -> a scope | nil when the drafter stops
(defun pfu:scope ( / k es ls ss i out done)
  (initget "Selected Line Drawing")
  (setq k (cond ((getkword "\nRefresh [Selected/Line/Drawing] <Line>: ")) ("Line")))
  (cond
    ((= k "Drawing") (list "Drawing"))
    ((= k "Selected")
     (pfl:say "\nSelect profile structures, pipes or leaders to refresh (a plan structure brings its copies): ")
     (if (setq ss (ssget))
       (progn
         (repeat (setq i (sslength ss)) (setq out (cons (ssname ss (setq i (1- i))) out)))
         (cons "Selected" out))))
    (T
     (while (not done)
       (setvar "ERRNO" 0)
       (setq es (entsel "\nClick anything on the line to refresh -- a structure, a pipe or the grid: "))
       (cond
         ((and (null es) (= 7 (getvar "ERRNO"))) (pfl:say "  Missed -- click again, or Enter to stop."))
         ((null es) (setq done T))
         ((setq ls (pfu:lines-at (car es) (trans (cadr es) 1 0))) (setq done T))
         (T (pfl:say "  That is on no line -- click again, or Enter to stop."))))
     (if ls (cons "Line" ls)))))

;; (pfu:copy-in-p e plan line sc) -> T when a profile copy is in scope.
;;   Asked by pfs:copies-if before the copy's grid is looked up.
(defun pfu:copy-in-p (e plan line sc)
  (cond
    ((= (car sc) "Drawing") T)
    ((= (car sc) "Line") (and (member line (cdr sc)) T))
    (T (or (and (member e (cdr sc)) T)
           (and plan (vl-some '(lambda (s) (= plan (pfl:handle s))) (cdr sc)))))))

;; (pfu:plan-in-p e sc) -> T when a plan structure is in scope: on one of the
;;   lines, or picked, or the plan of a copy picked
(defun pfu:plan-in-p (e sc / h)
  (cond
    ((= (car sc) "Drawing") T)
    ((= (car sc) "Line") (vl-some '(lambda (m) (member (car m) (cdr sc))) (pfr:memb-get e)))
    (T (setq h (pfl:handle e))
       (or (and (member e (cdr sc)) T)
           (vl-some '(lambda (s) (= h (pfr:deser (pfr:xd-get s *pf-xd-plan*)))) (cdr sc))))))

;; (pfu:pipes sc) -> the pipes in a Selected scope: picked, or a picked
;;   leader's pipe.  Line and Drawing: every pipe (Line sorts them by grid).
(defun pfu:pipes (sc / p out)
  (if (= (car sc) "Selected")
    (progn
      (foreach s (cdr sc)
        (if (and (setq p (cond ((pfp:pipe-p s) s) ((pfp:leader-owner s))))
                 (not (member p out)))
          (setq out (cons p out))))
      out)
    (pfp:all)))

;; (pfu:leader-in-p l sc) -> T when a pipe-label leader is in scope
(defun pfu:leader-in-p (l sc)
  (cond
    ((= (car sc) "Drawing") T)
    ((= (car sc) "Line") (and (member (pfu:line-of-pt (cdr (assoc 10 (entget l)))) (cdr sc)) T))
    (T (and (member l (cdr sc)) T))))

;; (pfu:took label t0) -> "label 1.25s"
(defun pfu:took (label t0)
  (strcat label " " (pfl:fix (/ (max 0 (- (getvar "MILLISECS") t0)) 1000.0) 2) "s"))


;;; ---- the run ----------------------------------------------------------------

;; (pfu:main) -> nil   the command body, run inside pfd:run
(defun pfu:main ( / sc t0 tm times grids top sres fmt pres pin n-chk n-upd n-skip n-gone
                    notes plans copies pe h plan lname m g r ends a placed keep key stale)
  (pfc:load)
  (cond
    ((null (setq sc (pfu:scope)))
     (pfl:say "PFREFRESH: nothing picked -- nothing done."))
    (T
     (setq n-chk 0 n-upd 0 n-skip 0 n-gone 0
           t0    (getvar "MILLISECS")
           tm    t0)
     (pfl:say "")
     (pfl:say (strcat "=== PFREFRESH  "
                      (cond ((= (car sc) "Line") (strcat "line " (pfl:join-with ", " (cdr sc))))
                            ((= (car sc) "Selected") (strcat (itoa (length (cdr sc))) " object(s) picked"))
                            ("whole drawing"))
                      " ==="))

     (setq *pfd-stage* "reading the grids")
     (setq grids (pfg:usable)
           top   (pfg:top-lines))
     (setq times (list (pfu:took "grids" tm)) tm (getvar "MILLISECS"))

     ;; 1. the shared drafter inputs -- a change typed on any block goes to
     ;;    all, so these are read drawing-wide whatever the scope
     (setq *pfd-stage* "sharing the drafter inputs")
     (setq sres (pfs:sync-fmt) fmt (car sres)
           pres (pfp:sync)     pin (car pres))
     (foreach s (append (cdr sres) (cdr pres)) (pfl:say s))
     (setq times (cons (pfu:took "inputs" tm) times) tm (getvar "MILLISECS"))

     ;; 2. the plan side is PFASSIGN's (Jake, 2026-10-27).  A plan structure
     ;;    moved, turned or new since PFASSIGN last ran is named here, not
     ;;    re-stationed -- its copies follow once PFASSIGN has run.
     (setq *pfd-stage* "checking the plan")
     (setq plans (vl-remove-if-not '(lambda (e) (pfu:plan-in-p e sc)) (pfm:structures)))
     (if (setq stale (pfm:stale plans))
       (progn
         (pfl:say (strcat "  ** " (itoa (length stale)) " plan structure(s) moved or new since PFASSIGN"
                          " -- run PFASSIGN first, then PFREFRESH:"))
         (foreach e stale (pfl:say (strcat "       " (pfm:who e))))))
     (setq plans (vl-remove-if-not 'pfr:memb-get plans))
     (setq times (cons (pfu:took "plan check" tm) times) tm (getvar "MILLISECS"))

     ;; 3. orphans and duplicates: erased, each one named.  A copy whose alpha
     ;;    block is gone or no longer on the copy's line; a second copy of the
     ;;    same alpha block on the same line.
     (setq *pfd-stage* "clearing orphans and duplicates")
     (foreach c (pfs:copies-if '(lambda (e p l) (pfu:copy-in-p e p l sc)))
       (setq h    (nth 1 c)
             plan (if h (handent h))
             key  (cons h (nth 2 c)))
       (cond
         ((not (and plan (entget plan) (assoc (nth 2 c) (pfr:memb-get plan))))
          (pfl:say (strcat "  erased a profile copy (" (pfr:display-name (car c))
                           ") whose alpha block is gone or off line " (vl-princ-to-string (nth 2 c))))
          (pfd:erase (car c)) (setq n-gone (1+ n-gone)))
         ((member key keep)
          (pfl:say (strcat "  erased a duplicate profile copy of " (pfr:display-name (car c))))
          (pfd:erase (car c)) (setq n-gone (1+ n-gone)))
         (T (setq keep (cons key keep)))))

     ;; 4. profile copies -- only the ones whose source changed
     (setq *pfd-stage* "checking profile copies")
     (setq copies (pfs:copies-if '(lambda (e p l) (pfu:copy-in-p e p l sc))))
     (foreach c copies
       (setq pe    (car c)
             h     (nth 1 c)
             lname (nth 2 c)
             plan  (handent h)
             m     (assoc lname (pfr:memb-get plan))
             n-chk (1+ n-chk))
       (cond
         ((not (pfl:number-p (pfr:get plan *pf-tag-rim*)))
          (setq n-skip (1+ n-skip) notes (cons (strcat "  ** " (pfr:display-name plan) " has no rim -- not updated") notes)))
         ((null (setq g (pfg:grid-for lname (cadr m) (nth 3 c) grids)))
          (setq n-skip (1+ n-skip) notes (cons (strcat "  ** " (pfr:display-name plan) "  STA " (pfl:fmt-sta (cadr m))
                                                       " is on no grid of line " lname " -- not updated")
                                               notes)))
         ((= (pfs:copy-fp pe plan g fmt top) (pfr:stamp-get pe)))      ; unchanged
         (T
          (setq n-upd (1+ n-upd))
          (setq r (pfd:try (strcat (pfr:display-name plan) " (moving)")
                           'pfs:place (list pe plan lname (cadr m) g)))
          (if (and r (car r))
            (progn
              (setq r (pfd:try (strcat (pfr:display-name plan) " labels")
                               'pfs:struct-update (list pe plan g (list (cons 'top top)) fmt)))
              (pfl:say (strcat "  " (pfr:display-name plan) "  " lname "  STA " (pfl:fmt-sta (cadr m))
                               "  updated"))
              (foreach s r (pfl:say s)))))))
     (setq times (cons (pfu:took "structures" tm) times) tm (getvar "MILLISECS"))

     ;; 5. pipes.  In a Line scope a pipe's line is its grid's, so the grid
     ;;    is found first and a pipe on another line is passed over unseen.
     (setq *pfd-stage* "checking pipes")
     (foreach e (pfu:pipes sc)
       (setq ends (pfp:ends e)
             a    (if ends (pfg:anchor-of (car ends)))
             g    (if a (pfg:grid a)))
       (if (or (/= (car sc) "Line") (and g (member (pfg:line-name g) (cdr sc))))
         (progn
           (setq n-chk (1+ n-chk))
           (cond
             ((null ends)
              (setq n-skip (1+ n-skip) notes (cons "  ** a pipe's ends can't be read (PFRUN missing?) -- not updated" notes)))
             ((null g)
              (setq n-skip (1+ n-skip) notes (cons "  ** a pipe is in no grid -- not updated" notes)))
             ((= (pfp:fp e g pin) (pfr:stamp-get e)))                  ; unchanged
             (T
              (setq n-upd (1+ n-upd))
              (if (setq r (pfd:try "a pipe" 'pfp:update (list e g pin)))
                (progn
                  (pfl:say (strcat "  pipe  " (car r) "  updated"))
                  (foreach s (cdr r) (pfl:say s)))))))))

     ;; a pipe label's leader whose pipe is gone (erased, or the leader was
     ;; copied without it) is erased, like an orphan profile copy
     (setq *pfd-stage* "checking pipe label leaders")
     (foreach l (pfp:all-leaders)
       (if (and (null (pfp:leader-owner l)) (pfu:leader-in-p l sc))
         (progn
           (pfd:erase l)
           (setq n-gone (1+ n-gone)
                 notes  (cons "  a pipe label leader with no pipe -- erased" notes)))))
     (setq times (cons (pfu:took "pipes" tm) times) tm (getvar "MILLISECS"))

     ;; 6. what PFSTRUCT still has to place: an alpha block on a line, with no
     ;;    copy on that line's grid yet
     (setq *pfd-stage* "looking for unplaced structures")
     (setq placed (mapcar '(lambda (c) (cons (nth 1 c) (nth 2 c))) copies))
     (foreach e plans
       (foreach m (pfr:memb-get e)
         (if (and (or (/= (car sc) "Line") (member (car m) (cdr sc)))
                  (not (member (cons (pfl:handle e) (car m)) placed))
                  (setq g (pfg:grid-for (car m) (cadr m) nil grids)))
           (setq notes (cons (strcat "  " (pfr:display-name e) "  STA " (pfl:fmt-sta (cadr m))
                                     " not placed on " (pfg:title g) " yet -- run PFSTRUCT")
                             notes)))))

     (foreach s (reverse notes) (pfl:say s))
     (pfl:say "")
     (if (> n-gone 0) (pfl:say (strcat "  " (itoa n-gone) " orphan / duplicate profile copies and leaders erased.")))
     (pfl:say (strcat "  " (itoa n-chk) " block(s) checked: " (itoa n-upd) " updated, "
                      (itoa (- n-chk n-upd n-skip)) " unchanged and left alone, "
                      (itoa n-skip) " skipped (see above)."))
     (pfl:say (strcat "  Time: " (pfl:join-with ", " (reverse times))
                      "  --  total " (pfl:fix (/ (max 0 (- (getvar "MILLISECS") t0)) 1000.0) 2) "s"))
     (pfl:say "  One UNDO takes this whole run back.")))
  (princ))

(defun c:PFREFRESH ()
  (if (null pfd:run)
    (pfl:say "PFREFRESH: load pf-load.lsp first.")
    (pfd:run "PFREFRESH" 'pfu:main))
  (princ))


(princ "\npf-refresh loaded.  PFREFRESH.")
(princ)
