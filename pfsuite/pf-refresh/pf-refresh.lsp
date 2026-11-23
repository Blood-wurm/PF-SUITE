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
;;; Each block's drafter inputs come from the saved defaults (line, utility,
;;; drawing, built-in -- pf-defaults); a value typed on a block stays on it.
;;; Each step's time is printed at the end (MILLISECS).
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
;;; IT ERASES ORPHANS AND DUPLICATES (Jake, 2026-10-16; restored 2026-11-17
;;; after the 2026-11 work had narrowed it to "hold for review"): a profile
;;; copy whose alpha block is gone or off the line, and a second copy of the
;;; same alpha block on the same line -- the ORIGINAL (oldest handle) is kept.
;;; Each one named in the run.  A copy with no plan link, or one whose plan
;;; block exists but doesn't name that line yet, is held and named for review.
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

;; (pfu:copy-fp pe plan g fmt top ictx) -> a profile copy's whole fingerprint:
;;   its label rows (pf-struct) and its invert rows (pf-invert)
(defun pfu:copy-fp (pe plan g fmt top ictx)
  (strcat (pfs:copy-fp pe plan g fmt top) "/" (pfi:fp pe plan g ictx)))

;;; ---- "would PFREFRESH change this?" -------------------------------------------
;;; THE test PFREFRESH makes before it touches a block: its fingerprint of what
;;; the block would be built from, against the one stamped on it last time.
;;; Shared with the palette's "needs refresh" (Jake, 2026-11-20: "We need the
;;; refresh for any change that would need pfrefresh") -- one test, so the
;;; palette and the command can never disagree.

;; (pfu:copy-due-p pe plan g fmt top ictx) -> T when a profile copy would be
;;   updated: its rim, name, size, face, prefixes, grid, inverts ...
(defun pfu:copy-due-p (pe plan g fmt top ictx)
  (/= (pfu:copy-fp pe plan g fmt top ictx) (pfr:stamp-get pe)))

;; (pfu:pipe-due-p e g pin) -> T when a pipe would be updated
(defun pfu:pipe-due-p (e g pin) (/= (pfp:fp e g pin) (pfr:stamp-get e)))

;; (pfu:xing-due-p x ictx xextras) -> T when a crossing block would be updated
(defun pfu:xing-due-p (x ictx xextras)
  (/= (pfk:fp x (pfk:data x ictx) xextras) (pfr:stamp-get x)))

;; (pfu:xing-in-p x sc) -> T when a crossing block is in scope: on a line of
;;   the scope, or crossed BY one (its pipe there may have changed), or picked
(defun pfu:xing-in-p (x sc / rec)
  (setq rec (pfk:rec x))
  (cond
    ((= (car sc) "Drawing") T)
    ((= (car sc) "Line") (and rec (or (member (car rec) (cdr sc)) (member (caddr rec) (cdr sc))) T))
    (T (and (member x (cdr sc)) T))))

;; (pfu:took label t0) -> "label 1.25s"
(defun pfu:took (label t0)
  (strcat label " " (pfl:fix (/ (max 0 (- (getvar "MILLISECS") t0)) 1000.0) 2) "s"))

;; Only an assigned, readable PLAN record can prove a line was deliberately
;; removed.  A missing handle or unreadable membership is not deletion proof.
(defun pfu:confirmed-line-removed-p (plan line)
  (and plan (entget plan) line
       (pfr:ours-p plan)
       (= (strcase (cond ((pfr:view plan)) (""))) (strcase *pf-view-plan*))
       (pfr:xd-get plan *pf-xd-memb*)
       (pfr:schema-get plan)
       (null (pfm:stale (list plan)))
       (not (assoc line (pfr:memb-get plan)))))


;; (pfu:handle< a b) -> T if handle a is older than b.  Handles are hex and
;;   grow as entities are made, so a COPY has a higher handle than the
;;   original it was copied from.  Shorter = smaller; same length, A-Z.
(defun pfu:handle< (a b)
  (setq a (strcase a) b (strcase b))
  (if (/= (strlen a) (strlen b)) (< (strlen a) (strlen b)) (< a b)))

;; (pfu:erase-copy e msg) -> T | nil   erase one orphan / duplicate profile
;;   copy and say msg.  Counts into pfu:run's n-gone and notes.
(defun pfu:erase-copy (e msg)
  (if (pfd:erase e)
    (progn (setq n-gone (1+ n-gone)) (pfl:say msg) T)
    (progn (setq notes (cons "  ** failed to erase an orphan or duplicate profile copy" notes)) nil)))


;;; ---- the run ----------------------------------------------------------------

;; (pfu:run sc fmt pin) -> (checked updated skipped erased failed)
;;   The work, no questions -- what PFSELFTEST drives (2026-10-30).
;;   sc: a scope.  fmt / pin: explicit inputs for structures and pipes --
;;   nil = each block resolves its own saved defaults, as the command does.
;;   PFSELFTEST may hand in its own (pfs:sync-fmt-in, pfp:sync-in).
(defun pfu:run (sc fmt pin / t0 tm times grids top sres pres n-chk n-upd n-skip n-gone n-fail
                  notes plans copies pe h plan lname m g r ends a placed keep key stale
                  held previous issue before ictx xextras xs warn aidx)
  (progn
     (setq n-chk 0 n-upd 0 n-skip 0 n-gone 0 n-fail 0
           t0    (getvar "MILLISECS")
           tm    t0)
     (pfl:say "")
     (pfl:say (strcat "=== PFREFRESH  "
                      (cond ((= (car sc) "Line") (strcat "line " (pfl:join-with ", " (cdr sc))))
                            ((= (car sc) "Selected") (strcat (itoa (length (cdr sc))) " object(s) picked"))
                            ("whole drawing"))
                      " ==="))
     ;; V6.1: drawing settings are one value per drawing.  Say so while old
     ;; line / utility values are still stored (Save Settings retires them).
     (if (setq xs (pfv:ignored-settings))
       (pfl:say (strcat "  ** " (itoa (length xs)) " line/utility setting(s) from V6.0 are ignored --"
                        " V6.1 uses one value per drawing (palette Settings tab; Save retires them).")))
     (setq xs nil)

     (setq *pfd-stage* "reading the grids")
     (setq grids (pfg:usable)
           top   (pfg:top-lines))
     (setq times (list (pfu:took "grids" tm)) tm (getvar "MILLISECS"))
     ;; the pipes, copies and walls the invert rows are read from
     (setq *pfd-stage* "reading the pipes for the invert rows")
     (setq ictx (pfi:ctx grids))

     ;; Explicit fmt/pin are for diagnostic runs.  Production resolves saved
     ;; defaults and hand edits on each block when it is updated.
     (setq *pfd-stage* "reading per-block defaults")
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

      ;; 3. Orphans and duplicates (Jake, 2026-10-16; restored 2026-11-17):
      ;;    ERASED, each one named --
      ;;      a copy whose plan structure is gone (erased),
      ;;      a copy whose plan record proves its line was removed,
      ;;      a second copy of the same plan structure on the same line: the
      ;;      ORIGINAL (oldest handle) is kept, the newer one erased.
      ;;    HELD for review, not guessed at: a copy with no plan link, or one
      ;;    whose plan block exists but isn't ours or doesn't name that line
      ;;    yet (e.g. moved, PFASSIGN not run).
      (setq *pfd-stage* "checking orphans and duplicates")
     (foreach c (pfs:copies-if '(lambda (e p l) (pfu:copy-in-p e p l sc)))
       (setq h    (nth 1 c)
             plan (if h (handent h))
             key  (if (and h (nth 2 c)) (cons h (nth 2 c))))
       (cond
          ((null key)
           (setq held (cons (car c) held)
                 notes (cons (strcat "  ** profile copy " (pfl:handle (car c))
                                     " has no plan link -- kept for review") notes)))
          ((not (and plan (entget plan)))
           (pfu:erase-copy (car c) (strcat "  erased a profile copy on " (nth 2 c)
                                           " -- its plan structure (" h ") is gone")))
          ((pfu:confirmed-line-removed-p plan (nth 2 c))
           (pfu:erase-copy (car c) (strcat "  erased the old profile copy of "
                                           (pfr:display-name plan) " on " (nth 2 c))))
          ((not (and (pfr:ours-p plan) (assoc (nth 2 c) (pfr:memb-get plan))))
           (setq held (cons (car c) held)
                 notes (cons (strcat "  ** profile copy " (pfl:handle (car c))
                                     " has an unresolved plan/line link -- kept for review") notes)))
          ((setq previous (assoc key keep))
           (setq keep (subst (cons key (cons (car c) (cdr previous))) previous keep)))
          (T (setq keep (cons (list key (car c)) keep)))))
     ;; duplicates: keep the oldest copy, erase the rest
     (foreach k keep
       (if (cdr (cdr k))
         (foreach e (cdr (vl-sort (cdr k) '(lambda (a b) (pfu:handle< (pfl:handle a) (pfl:handle b)))))
           (pfu:erase-copy e (strcat "  erased a duplicate profile copy of "
                                     (pfr:display-name (handent (car (car k)))) " on " (cdr (car k))
                                     " -- the original is kept")))))

     ;; 4. profile copies -- only the ones whose source changed
     (setq *pfd-stage* "checking profile copies")
      (setq copies (vl-remove-if '(lambda (c) (member (car c) held))
                                 (pfs:copies-if '(lambda (e p l) (pfu:copy-in-p e p l sc)))))
     (foreach c copies
       (setq pe    (car c)
             h     (nth 1 c)
             lname (nth 2 c)
             plan  (handent h)
             m     (assoc lname (pfr:memb-get plan))
             n-chk (1+ n-chk))
       ;; no rim is no longer a skip: the copy sits on the grid top until a
       ;; rim is typed, then moves to it (Jake, 2026-11-13; pfs:copy-y)
       (cond
         ((null (setq g (pfg:grid-for lname (cadr m) (nth 3 c) grids)))
          (setq n-skip (1+ n-skip) notes (cons (strcat "  ** " (pfr:display-name plan) "  STA " (pfl:fmt-sta (cadr m))
                                                       " is on no grid of line " lname " -- not updated")
                                               notes)))
         ((not (pfu:copy-due-p pe plan g fmt top ictx)))                    ; unchanged
         (T
           (setq before *pfr-write-failures*)
          (setq r (pfd:try (strcat (pfr:display-name plan) " (moving)")
                           'pfs:place (list pe plan lname (cadr m) g top)))
           (cond
             ((or *pfd-try-failed* (> *pfr-write-failures* before))
              (setq n-fail (1+ n-fail)))
             ((or (null r) (null (car r)))
              (setq n-skip (1+ n-skip))
              (if r (setq notes (cons (strcat "  ** " (pfr:display-name plan) "  " lname
                                               "  STA " (pfl:fmt-sta (cadr m)) "  " (cdr r)
                                               " -- not updated") notes))))
             (T
              ;; it may have moved: its walls and its grid's pipe ends again
              (pfi:forget pe g)
              (setq r (pfd:try (strcat (pfr:display-name plan) " labels")
                               'pfs:struct-update (list pe plan g (list (cons 'top top)) fmt)))
              ;; the invert rows (pf-invert), then the whole fingerprint
              (if (not *pfd-try-failed*)
                (setq r (append r (pfd:try (strcat (pfr:display-name plan) " inverts")
                                           'pfi:update (list pe plan g ictx)))))
              (if (or *pfd-try-failed* (> *pfr-write-failures* before))
                (setq n-fail (1+ n-fail))
                (progn
                  (pfr:stamp-put pe (pfu:copy-fp pe plan g fmt top ictx))
                  (setq n-upd (1+ n-upd))
                  (pfl:say (strcat "  " (pfr:display-name plan) "  " lname
                                   "  STA " (pfl:fmt-sta (cadr m)) "  updated"))
                  (foreach s r (pfl:say s)))))))))
     (setq times (cons (pfu:took "structures" tm) times) tm (getvar "MILLISECS"))

     ;; 5. pipes.  In a Line scope a pipe's line is its grid's, so the grid
     ;;    is found first and a pipe on another line is passed over unseen.
     (setq *pfd-stage* "checking pipes")
     ;; the anchors read once for every pipe -- this loop writes pipes and
     ;; leaders, never an anchor (2026-11-20)
     (setq aidx (pfg:index))
     (foreach e (pfu:pipes sc)
        (setq ends (pfp:ends e)
              issue (pfp:grid-issue-in ends nil aidx)
              g    (if (null issue) (pfp:grid-of-ends-in ends aidx)))
        (setq a (if ends (pfg:anchor-of-in (car ends) aidx)))
        (if (or (/= (car sc) "Line")
                (and (or g (if a (pfg:grid a)))
                     (member (pfg:line-name (if g g (pfg:grid a))) (cdr sc))))
         (progn
           (setq n-chk (1+ n-chk))
           (cond
             ((null ends)
              (setq n-skip (1+ n-skip) notes (cons "  ** a pipe's ends can't be read (PFRUN missing?) -- not updated" notes)))
              (issue
               (setq n-skip (1+ n-skip)
                     notes (cons (strcat "  ** pipe " (pfl:handle e) ": " issue " -- not updated") notes)))
             ((not (pfu:pipe-due-p e g pin)))                          ; unchanged
             (T
               (setq before *pfr-write-failures*
                     r (pfd:try "a pipe" 'pfp:update (list e g pin)))
               (if (or *pfd-try-failed* (> *pfr-write-failures* before) (null r))
                 (setq n-fail (1+ n-fail))
                 (progn
                   (setq n-upd (1+ n-upd))
                   (pfl:say (strcat "  pipe  " (car r) "  updated"))
                   (foreach s (cdr r) (pfl:say s)))))))))

     ;; a pipe label's leader whose pipe is gone (erased, or the leader was
     ;; copied without it) is erased, like an orphan profile copy
     (setq *pfd-stage* "checking pipe label leaders")
     (foreach l (pfp:all-leaders)
       (if (and (null (pfp:leader-owner l)) (pfu:leader-in-p l sc))
         (if (pfd:erase l)
           (setq n-gone (1+ n-gone)
                 notes  (cons "  a pipe label leader with no pipe -- erased" notes))
           (setq n-fail (1+ n-fail)
                 notes  (cons "  ** failed to erase a pipe label leader with no pipe" notes)))))
     (setq times (cons (pfu:took "pipes" tm) times) tm (getvar "MILLISECS"))

     ;; 5b. crossings (PFXLABEL's blocks): kept up to date when a pipe at
     ;;     one changes.  Never found here -- that is PFXLABEL's.  The pipes
     ;;     are read again: step 5 may have just written their PFID / PFOD.
     (setq *pfd-stage* "checking crossings")
     (if (setq xs (vl-remove-if-not '(lambda (x) (pfu:xing-in-p x sc)) (pfk:all)))
       (progn
         (setq ictx    (pfi:ctx grids)
               xextras (pfk:extras))
         (foreach x xs
           (setq n-chk (1+ n-chk))
           (if (pfu:xing-due-p x ictx xextras)
             (progn
               (setq before *pfr-write-failures*
                     r (pfd:try "a crossing" 'pfk:update (list x ictx xextras)))
               (if (or *pfd-try-failed* (> *pfr-write-failures* before) (null r))
                 (setq n-fail (1+ n-fail))
                 (progn
                   (pfk:stamp x ictx)
                   (setq n-upd (1+ n-upd))
                   (pfl:say (strcat "  crossing  " (car r) "  updated"))
                   (foreach s (cdr r) (pfl:say s)))))))
         ;; every crossing in scope that needs a look, changed or not
         (foreach x xs
           (setq r (pfk:status x ictx))
           (if (cadddr r)
             (setq warn (cons (strcat (cond ((car (pfk:rec x))) ("?")) ": " (car r) " at STA "
                                      (pfl:fmt-sta (cadr r)) "  " (caddr r))
                              warn))))))
     ;; what the tool drew for a crossing whose block is gone
     (foreach c (cond (xextras) ((pfk:extras)))
       (if (not (and (handent (car c)) (entget (handent (car c)))))
         (foreach x (cdr c)
           (if (and (not (pfr:released-p x)) (pfd:erase x))
             (setq n-gone (1+ n-gone))))))
     (setq times (cons (pfu:took "crossings" tm) times) tm (getvar "MILLISECS"))

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
     (if warn
       (progn
         (pfl:say "")
         (pfl:say (strcat "  ** " (itoa (length warn)) " CROSSING(S) NEED A LOOK:"))
         (foreach w (reverse warn) (pfl:say (strcat "     " w)))))
     (pfl:say "")
      (if held (pfl:say "  Profile copies with unresolved plan/line links were held for review."))
     (if (> n-gone 0) (pfl:say (strcat "  " (itoa n-gone) " orphan / duplicate profile copies and leaders erased.")))
      (pfl:say (strcat "  " (itoa n-chk) " block(s) checked: " (itoa n-upd) " updated, "
                       (itoa (- n-chk n-upd n-skip n-fail)) " unchanged and left alone, "
                       (itoa n-skip) " skipped, " (itoa n-fail) " failed (see above)."))
     (pfl:say (strcat "  Time: " (pfl:join-with ", " (reverse times))
                      "  --  total " (pfl:fix (/ (max 0 (- (getvar "MILLISECS") t0)) 1000.0) 2) "s")))
   (list n-chk n-upd n-skip n-gone n-fail))

;; (pfu:main) -> nil   the command body, run inside pfd:run: the scope
;;   question, then pfu:run
(defun pfu:main ( / sc)
  (pfc:load)
  (cond
    ((null (setq sc (pfu:scope)))
     (pfl:say "PFREFRESH: nothing picked -- nothing done."))
    (T
     (pfu:run sc nil nil)
     (pfl:say "  One UNDO takes this whole run back.")))
  (princ))

(defun c:PFREFRESH ()
  (if (null pfd:run)
    (pfl:say "PFREFRESH: load pf-load.lsp first.")
    (pfd:run "PFREFRESH" 'pfu:main))
  (princ))


(princ "\npf-refresh loaded.  PFREFRESH.")
(princ)
