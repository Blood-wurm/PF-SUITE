;;; ==========================================================================
;;; pf-bench.lsp  --  the workbench.  NOT a V6 module.
;;;
;;; Deliberately ONE file.  V5 grew thirteen diagnostic commands across the
;;; palette and ~700 lines of scaffolding that ended up on a deletion list --
;;; every one of them useful the week it was written.  Everything that exists
;;; to BUILD or CHECK the suite, rather than to run it, goes here and nowhere
;;; else.  When V6 ships, this file is deleted whole; no suite module may
;;; ever call into it.
;;;
;;; Loaded LAST by pf-load.lsp.  It calls the suite's shared code (pf-lib,
;;; pf-record, pf-draw ...) and keeps no copies of it -- only the bench's own
;;; reporting helpers live here.  Commands:
;;;
;;;   PFMKATT   inside BEDIT -- builds the nine ATTDEFs from *pf-tags*, so a
;;;             tag cannot be mistyped into a block.
;;;   PFMKPIPEATT inside BEDIT on PFSUITE_PIPE -- adds PFLABEL2 and the four
;;;             label inputs (PFLENPRE PFLENSUF PFSLOPEPRE PFSLOPESUF).
;;;   PFSEL     inside BEDIT -- selects a nested profile symbol by state name.
;;;   PFGATE    pick a placed PFSUITE_CBI or PFSUITE_PIPE -- checks its tags,
;;;             parameters and states against pf-cfg, and for a CBI dry-runs
;;;             PFTOP / PFDEPTH, a label move, and every size's profile
;;;             width.  "Ready to test" or not.
;;;   PFRECTEST pick a TEST insert -- round-trips pf-record against it.
;;;   PFSYNCTEST two runs around a hand-run ATTSYNC -- snapshots every suite
;;;             block in the drawing (read only), then shows what ATTSYNC lost.
;;;   PFPIPETEST pick two inverts -- places PFPIPE by code, checks it followed.
;;;   PFGRIDTEST lists the grid anchors (PFSUITE_ANCHOR or V5's), then reads one you click in and
;;;             reports station/elevation at your clicks, plus the folders.
;;;   PFLINETEST what the line tree sees: every line, every structure on it in
;;;             station order with its built name.  Reads only.
;;;   PFSELFTEST the test sheet's checks run by code: makes its own test
;;;             blocks, drives the real suite code, PASS / FAIL, erases them.
;;;
;;; Between them they cover the only boundary in this project that nothing
;;; else checks: the same strings live in the Block Editor and in pf-cfg.lsp,
;;; with no compiler in between.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  bench reporting helpers
;;; ==========================================================================

;; (pfb:missing a b) -> everything in a that is not in b, case-insensitive
(defun pfb:missing (a b / out x)
  (foreach x a
    (if (not (member (strcase x) (mapcar 'strcase b)))
      (setq out (cons x out))))
  (reverse out))

;; (pfb:report label want got) -> T if they agree, and says why if they do not
(defun pfb:report (label want got / miss extra)
  (setq miss  (pfb:missing want got)
        extra (pfb:missing got want))
  (pfl:say "")
  (pfl:say (strcat "  " label))
  (cond
    ((and (null miss) (null extra))
     (pfl:say (strcat "    OK -- all " (itoa (length want)) " present, nothing extra")))
    (T
      (if miss
        (progn
          (pfl:say "    MISSING from the block:")
          (foreach x miss (pfl:say (strcat "      " x)))))
      (if extra
        (progn
          (pfl:say "    IN THE BLOCK but not in pf-cfg:")
          (foreach x extra (pfl:say (strcat "      " x)))))))
  (and (null miss) (null extra)))


;;; ==========================================================================
;;; SECTION 2  --  PFMKATT.  Build the attribute set without picking.
;;; ==========================================================================
;;; ATTDEF's dialog is where the name contract breaks: nine tags, typed by
;;; hand, across sixty-odd blocks.  Building them from *pf-tags* means the
;;; spelling cannot drift, because it is the same list pf-record reads with.
;;;
;;; Every attribute is INVISIBLE and PRESET (group 70 = 1 + 8 = 9):
;;;   invisible -- still reads and edits in Properties, still comes out in
;;;                data extraction, just does not draw.  Nine tags of text on
;;;                a storm sheet is not a record, it is a mess.
;;;   preset    -- no prompt on insert.  The tool fills these in; a drafter
;;;                answering nine prompts per structure would not last a day.
;;;
;;; Stacked vertically so each is individually selectable in the editor.  The
;;; spacing is editor convenience only -- it draws nothing.

;; (pfb:idx x lst) -> 0-based position of x in lst, or nil
(defun pfb:idx (x lst / i n)
  (setq i 0 n nil)
  (foreach e lst
    (if (and (null n) (= (strcase e) (strcase x))) (setq n i))
    (setq i (1+ i)))
  n)

;; (pfb:attdef tag ty ht n) -> the ATTDEF entmake list
;;   Three kinds of attribute, and they are built differently:
;;
;;   ROW slots   visible, horizontal, stacked UP from the origin.  These are
;;               the label at the grid top: station rows, then the
;;               construction row, then the second text row, then elevation.
;;   INVERT slots visible, rotated 90 and reading up, in a row hanging BELOW
;;               the origin -- V5's fan, all columns off one baseline.
;;   everything else  INVISIBLE: the record, and the drafter inputs.  They
;;               still read and edit in Properties and still come out in data
;;               extraction; they must never print.
;;
;;   Group 70:  1 = invisible, 8 = preset.  Preset on all of them -- the tool
;;   fills these in, and a drafter answering two dozen prompts per structure
;;   would not last a day.
;;
;;   Positions here are DRAFT-TIME ONLY.  The tool sets every visible
;;   attribute's position, rotation and height per copy from the anchor's
;;   scale.  These just make the block legible while you build it.
;; botpt -- where the invert fan hangs from (the drawn barrel bottom), NOT
;; the block origin.  toppt -- where the label rows hang from (a point near
;; the drawn top of grid / PFTOP's upper end), NOT the block origin either.
;; On a true-scale block both the barrel bottom and the grid top sit real
;; feet away from origin, so anchoring either one to (0,0) put it nowhere
;; near the geometry it belongs with -- and nowhere near a Stretch/Move
;; action's frame or pick point either.  Both are picked once, in the
;; drawing, when PFMKATT runs, same reasoning for both.
(defun pfb:attdef (tag ty ht n botpt toppt / i pt rot flags just)
  (cond
    ;; label rows -- V5's convention: rotated 90 reading up, one shared
    ;; baseline, columns not rows.  PFSTA1 (i=0) sits LEFT of the station
    ;; line; every row after it sits RIGHT, spaced out from there.
    ((setq i (pfb:idx tag *pf-tags-row*))
     (setq pt    (list (+ (car toppt)
                         (if (= i 0)
                           (- (* ht *pf-draw-row-offset*))
                           (+ (* ht *pf-draw-row-offset*)
                              (* ht *pf-draw-row-gap* (1- i)))))
                       (cadr toppt)
                       0.0)
           rot   (/ pi 2.0)
           flags 8
           just  0))

    ;; invert fan -- rotated 90, columns spaced, hanging below botpt
    ((setq i (pfb:idx tag *pf-tags-inv*))
     (setq pt    (list (+ (car botpt) (* ht *pf-inv-gap-factor* (float i)))
                       (- (cadr botpt) (* ht *pf-inv-drop-factor*))
                       0.0)
           rot   (/ pi 2.0)
           flags 8
           just  0))

    ;; the record and the inputs -- invisible, stacked out of the way
    (T
     (setq pt    (list 0.0 (* n ht -1.6) 0.0)
           rot   0.0
           flags 9
           just  0)))

  (list
    '(0 . "ATTDEF")
    '(100 . "AcDbEntity")
    '(8 . "0")
    '(100 . "AcDbText")
    (cons 10 pt)
    (cons 40 ht)
    (cons 50 rot)
    (cons 1 (if (= tag *pf-tag-type*) ty ""))    ; default value
    '(100 . "AcDbAttributeDefinition")
    (cons 3 tag)                                 ; prompt
    (cons 2 tag)                                 ; tag
    (cons 70 flags)
    (cons 72 just)
    (cons 11 pt)
    '(74 . 0)))

;; LockPosition (DXF 280) does not reliably take through entmake -- confirmed
;; against Autodesk's own forum, an attempt to entmake '(280 . 1) on an ATTDEF
;; was reported not to work.  vla-Put-LockPosition DOES work, but only on the
;; ATTDEF (Attribute) object sitting in a block DEFINITION -- it is read-only
;; on an ATTRIB (AttributeReference) after insertion.  Since PFMKATT only ever
;; runs inside BEDIT, on the definition, this is the right side of that split.
;; Locking matters because it is NOT just a Properties-palette nicety: an
;; unlocked attribute gets silently FILTERED OUT of a Stretch or Move action's
;; selection set at pick time ("N unlocked AttDefs filtered from selection").
;; Every visible attribute -- the row tags and the invert fan -- has to ride
;; inside PFTOP's or PFDEPTH's action, so every visible attribute has to be
;; locked or PFMKATT is quietly building attributes those actions can't use.
(defun pfb:lock (e)
  (if e (vla-put-LockPosition (vlax-ename->vla-object e) :vlax-true)))

(defun c:PFMKATT ( / ty ht n made dupes tag ex botpt toppt e eline p1 p2)
  (cond
    ((not (boundp '*pf-tags*))
     (pfl:say "PFMKATT: pf-cfg.lsp is not loaded.  Load it first."))

    ;; Refuse outside the Block Editor.  entmake builds into whatever space is
    ;; current, so from model space this would scatter nine loose ATTDEFs into
    ;; the drawing, and the duplicate check below would scan the wrong space.
    ((/= 1 (getvar "BLOCKEDITOR"))
     (pfl:say "PFMKATT: not in the Block Editor.  BEDIT the block first."))

    (T
      ;; PFTYPE gets a real default so a hand-placed block already knows what
      ;; it is.  Everything else defaults empty -- the tool fills them.
      (setq ty (strcase (getstring "\nPFTYPE default for this block (CBI/DBI/SMH/DMH/MH/HDWL): ")))
      (setq ht (getdist "\nAttribute text height <0.2>: "))
      (if (or (null ht) (<= ht 0.0)) (setq ht 0.2))

      ;; botpt/toppt come off the station line itself, not a manual pick --
      ;; its two ends ARE the barrel bottom and the top of grid by
      ;; definition (the same line PFDEPTH and PFTOP stretch from opposite
      ;; ends of), so reading them off the line keeps the labels locked to
      ;; it instead of drifting if the line gets redrawn.  vlax-curve-* reads
      ;; either end of a LINE or an LWPOLYLINE the same way, so it does not
      ;; matter which one the station line turns out to be.
      (setq eline (car (entsel "\nSelect the station line: ")))
      (if (null eline)
        (progn
          (pfl:say "PFMKATT: nothing selected -- botpt/toppt default to origin.")
          (setq botpt (list 0.0 0.0 0.0)  toppt (list 0.0 0.0 0.0)))
        (progn
          (setq p1 (vlax-curve-getStartPoint eline)
                p2 (vlax-curve-getEndPoint eline))
          (if (> (cadr p1) (cadr p2))
            (setq toppt p1  botpt p2)
            (setq toppt p2  botpt p1))))

      (setq n 0  made 0  dupes nil)

      (foreach tag *pf-tags*
        ;; Refuse a second ATTDEF with a tag already here -- duplicates are
        ;; legal in DXF and silently break every tag lookup.
        (setq ex (ssget "_X" (list '(0 . "ATTDEF") (cons 2 tag))))
        (if ex
          (setq dupes (cons tag dupes))
          (progn
            (setq e (entmakex (pfb:attdef tag ty ht n botpt toppt)))
            (if (member tag *pf-tags-visible*) (pfb:lock e))
            (setq made (1+ made))))
        (setq n (1+ n)))

      (pfl:say (strcat "PFMKATT: " (itoa made) " of " (itoa (length *pf-tags*))
                       " attributes created."))
      (if dupes
        (progn
          (pfl:say "  ALREADY PRESENT, not duplicated:")
          (foreach tag (reverse dupes) (pfl:say (strcat "    " tag)))))
      (pfl:say (strcat "  " (itoa (length *pf-tags-visible*))
                       " visible (label rows + invert fan), the rest invisible."))
      (pfl:say "  Visible ones are LockPosition = Yes, so Stretch/Move actions can pick them up.")
      (pfl:say "  All preset.  BSAVE to keep them.")))
  (princ))


;;; ==========================================================================
;;; SECTION 2b  --  PFMKPIPEATT.  The pipe's label row 2 and its inputs.
;;; ==========================================================================
;;; Run INSIDE BEDIT on PFSUITE_PIPE.  Adds what is missing, skips what is
;;; there, changes nothing else:
;;;   PFLABEL2  a copy of PFLABEL (layer, style, height, justification,
;;;             rotation, lock) one row below it -- the label's second row
;;;   PFLENPRE PFLENSUF PFSLOPEPRE PFSLOPESUF  hidden + preset, defaults
;;;             filled from *pf-pipe-fmt-defaults*
;;; Then BSAVE, SAVE the drawing, and redefine PFSUITE_PIPE where it is used.
;;; Pipes placed before need ATTSYNC to get the new attributes (ATTSYNC was
;;; tested safe on the pipe, 2026-10-15).

;; (pfb:find-attdef tag) -> the ATTDEF with this tag in the Block Editor | nil
(defun pfb:find-attdef (tag / ss)
  (if (setq ss (ssget "_X" (list '(0 . "ATTDEF") (cons 2 tag)))) (ssname ss 0)))

;; (pfb:attdef-like src tag default flags dx dy) -> entmake list
;;   An ATTDEF built from src's own list -- same layer, style, height,
;;   justification and rotation -- with a new tag, default and flags, shifted
;;   by (dx dy).  Identity groups (ename, handle, owner, reactors, extension
;;   dictionary) are dropped so entmake makes a new one.
(defun pfb:attdef-like (src tag default flags dx dy / out g)
  (foreach g src
    (cond
      ((member (car g) '(-1 5 330 360 102 -3)))                 ; identity: drop
      ((member (car g) '(10 11))
       (setq out (cons (list (car g) (+ (cadr g) dx) (+ (caddr g) dy) (cadddr g)) out)))
      ((= (car g) 2) (setq out (cons (cons 2 tag) out)))
      ((= (car g) 3) (setq out (cons (cons 3 tag) out)))
      ((= (car g) 1) (setq out (cons (cons 1 default) out)))
      ((= (car g) 70) (setq out (cons (cons 70 flags) out)))
      (T (setq out (cons g out)))))
  (reverse out))

(defun c:PFMKPIPEATT ( / lab ld ht rot e made have row dx dy i)
  (cond
    ((not (boundp '*pf-pipe-fmt-defaults*))
     (pfl:say "PFMKPIPEATT: load pf-load.lsp first."))
    ((/= 1 (getvar "BLOCKEDITOR"))
     (pfl:say "PFMKPIPEATT: not in the Block Editor.  BEDIT PFSUITE_PIPE first."))
    ((null (setq lab (pfb:find-attdef *pf-pipe-label*)))
     (pfl:say (strcat "PFMKPIPEATT: no " *pf-pipe-label* " here -- is this PFSUITE_PIPE?")))
    (T
     (setq ld   (entget lab)
           ht   (cdr (assoc 40 ld))
           rot  (cond ((cdr (assoc 50 ld))) (0.0))
           made 0)
     ;; "one row below" in the text's own direction, 1.5 x its height
     (setq row (* 1.5 ht)
           dx  (* row (sin rot))
           dy  (- (* row (cos rot))))

     ;; PFLABEL2 -- visible, like PFLABEL, one row below it
     (if (pfb:find-attdef *pf-pipe-label2*)
       (setq have (cons *pf-pipe-label2* have))
       (if (setq e (entmakex (pfb:attdef-like ld *pf-pipe-label2* ""
                                              (cdr (assoc 70 ld)) dx dy)))
         (progn
           ;; LockPosition does not reliably take through entmake (see
           ;; pfb:lock) -- copy PFLABEL's through ActiveX instead
           (vl-catch-all-apply 'vla-put-LockPosition
             (list (vlax-ename->vla-object e)
                   (vla-get-LockPosition (vlax-ename->vla-object lab))))
           (setq made (1+ made)))))

     ;; the four inputs -- hidden + preset (70 = 9), stacked further below
     (setq i 2)
     (foreach pair *pf-pipe-fmt-defaults*
       (if (pfb:find-attdef (car pair))
         (setq have (cons (car pair) have))
         (if (entmakex (pfb:attdef-like ld (car pair) (cdr pair) 9 (* i dx) (* i dy)))
           (setq made (1+ made))))
       (setq i (1+ i)))

     (pfl:say (strcat "PFMKPIPEATT: " (itoa made) " attribute(s) added."))
     (if have
       (pfl:say (strcat "  Already there, left alone: " (pfl:join (reverse have)))))
     (pfl:say "  Check them in Properties, then BSAVE and SAVE the drawing.")))
  (princ))


;;; ==========================================================================
;;; SECTION 3  --  PFSEL.  Grab one nested profile symbol out of the stack.
;;; ==========================================================================
;;; Filling the nine face states means nine profile blocks inserted at the
;;; same base point, stacked on top of each other, and then shown in exactly
;;; one state each.  Picking the right one of nine coincident inserts by hand
;;; is the miserable part; selecting it by NAME is not.
;;;
;;; Setting the current visibility state is a dialog and is not scriptable, so
;;; the flow is:  set the state from the dropdown, run PFSEL, type the state,
;;; then BVSHOW.  PFSEL leaves the block as the pickfirst selection, so BVSHOW
;;; picks it up without another pick.
;;;
;;; PFSEL ALL selects all nine at once, for the initial BVHIDE / All states.

;; The nested profile-symbol prefix.  Asked for only when it is wrong, not on
;; every run -- it is the part that never changes.  PFSEL's Prefix option
;; resets it.
(if (not (boundp '*pfb-prefix*)) (setq *pfb-prefix* "PF-GRATE_CBI-"))

(defun c:PFSEL ( / kw ans ss i e nm want hits)
  (cond
    ((not (boundp '*pf-states-face*))
     (pfl:say "PFSEL: pf-cfg.lsp is not loaded."))
    ((/= 1 (getvar "BLOCKEDITOR"))
     (pfl:say "PFSEL: not in the Block Editor."))
    (T
      ;; getkword, not getstring: the state is the ONLY input, and a typo here
      ;; is a selection of nothing rather than an error, which reads as "the
      ;; blocks are missing" and sends you looking in the wrong place.
      (setq kw (apply 'strcat
                      (mapcar '(lambda (s) (strcat s " ")) *pf-states-face*)))
      (initget (strcat kw "ALL Prefix"))
      (setq ans (getkword (strcat "\nShow state ["
                                  (vl-string-right-trim "/"
                                    (vl-string-translate " " "/" kw))
                                  "/ALL/Prefix] <using " *pfb-prefix* ">: ")))
      (cond
        ((null ans)
         (pfl:say "  cancelled."))

        ((= ans "Prefix")
         (setq nm (getstring T (strcat "\nNested block prefix <" *pfb-prefix* ">: ")))
         (if (/= nm "") (setq *pfb-prefix* nm))
         (pfl:say (strcat "  prefix is now " *pfb-prefix* " -- run PFSEL again.")))

        (T
          (setq want (if (= ans "ALL")
                       (mapcar '(lambda (s) (strcase (strcat *pfb-prefix* s)))
                               *pf-states-face*)
                       (list (strcase (strcat *pfb-prefix* ans)))))

          (setq ss (ssadd) i 0)
          (if (setq hits (ssget "_X" '((0 . "INSERT"))))
            (while (< i (sslength hits))
              (setq e  (ssname hits i)
                    nm (strcase (pfl:effname e)))
              (if (member nm want) (ssadd e ss))
              (setq i (1+ i))))

          (cond
            ((zerop (sslength ss))
             (pfl:say "  NOTHING MATCHED.  Looked for:")
             (foreach nm want (pfl:say (strcat "    " nm)))
             (pfl:say "  Either the blocks are not inserted yet, or the prefix is")
             (pfl:say "  wrong -- run PFSEL and choose Prefix to change it."))
            (T
              (sssetfirst nil ss)
              (pfl:say (strcat "  " (itoa (sslength ss)) " selected -- now "
                               (if (= ans "ALL")
                                 "BVHIDE, All states"
                                 "BVSHOW, Current state")))))))))
  (princ))


;;; ==========================================================================
;;; SECTION 4  --  PFGATE.  Does the block agree with pf-cfg?
;;; ==========================================================================
;;; Works on an INSERT rather than the definition on purpose: what matters is
;;; what the block does when placed, and a copy has to be placed anyway to
;;; check it comes in as PLAN.


;; (pfb:tags e) -> the ATTRIB tags on this insert, in order
;;   Invisible and preset attributes still exist as ATTRIB sub-entities, so
;;   this sees all nine.  A CONSTANT attribute would not appear -- none of
;;   ours are constant, and if one reads as missing, that is why.
(defun pfb:tags (e / has sub sd out)
  (setq has (cdr (assoc 66 (entget e))))
  (if (and has (= has 1))
    (progn
      (setq sub (entnext e))
      (while (and sub
                  (setq sd (entget sub))
                  (/= (cdr (assoc 0 sd)) "SEQEND"))
        (if (= (cdr (assoc 0 sd)) "ATTRIB")
          (setq out (cons (cdr (assoc 2 sd)) out)))
        (setq sub (entnext sub)))))
  (reverse out))



;; (pfb:visprop obj) -> (name statelist currentvalue property) | nil
;;   pfl:visprop's answer, unpacked for a report.  pfl:visprop finds the
;;   parameter even when it is not called PFVIS, so a "Visibility1" still
;;   gets checked, and still gets reported.
(defun pfb:visprop (obj / p nm)
  (if (setq p (pfl:visprop obj))
    (progn
      (setq nm (vl-catch-all-apply 'vla-get-propertyname (list p)))
      (list (if (vl-catch-all-error-p nm) "?" nm) (pfl:allowed p) (pfl:prop-get p) p))))

;; (pfb:state-extents obj states) -> ((state minx miny maxx maxy) ...)
;;   Cycles the insert through every state and measures each one, then puts it
;;   back.  The nine face states were drawn separately, so nothing guarantees
;;   they agree vertically -- and a state drawn half a foot low produces a
;;   profile symbol that floats, on a sheet, with no error anywhere.  The eye
;;   cannot catch this across sixty blocks; a number can.
;;   TEMPORARILY restates the picked insert.  It is restored before returning.
(defun pfb:state-extents (obj p states was / out s bb ip)
  ;; relative to the insertion point -- world numbers do not fit the columns
  (setq ip (vlax-safearray->list (vlax-variant-value (vla-get-insertionpoint obj))))
  (foreach s states
    (if (= T (pfd:prop-put p s))
      (progn
        (setq bb (pfl:bbox obj))
        (if bb (setq out (cons (cons s (list (- (car bb) (car ip)) (- (cadr bb) (cadr ip))
                                             (- (caddr bb) (car ip)) (- (cadddr bb) (cadr ip))))
                               out))))))
  (pfd:prop-put p was)
  (reverse out))

;; (pfb:report-extents rows origin-tol) -> T if every state agrees
;;   Compares each state's extents against the FIRST one and reports drift.
(defun pfb:report-extents (rows tol / base ok r d)
  (pfl:say "")
  (pfl:say "  State geometry (extents relative to the block origin)")
  (cond
    ((null rows)
     (pfl:say "    could not measure -- skipped")
     T)
    (T
      (setq base (cdr (car rows)) ok T)
      (pfl:say "      state     minY      maxY     height")
      (foreach r rows
        (setq d (cdr r))
        (pfl:say (strcat "      " (pfl:pad (car r) 9)
                         (pfl:pad (rtos (cadr d) 2 3) 10)
                         (pfl:pad (rtos (cadddr d) 2 3) 10)
                         (rtos (- (cadddr d) (cadr d)) 2 3))))
      ;; Vertical agreement is the one that matters: a state whose top or
      ;; bottom sits at a different height than its siblings will not line up
      ;; when pf-draw places it at a rim elevation.
      (foreach r rows
        (setq d (cdr r))
        (if (or (> (abs (- (cadr d)   (cadr base)))   tol)
                (> (abs (- (cadddr d) (cadddr base))) tol))
          (progn
            (setq ok nil)
            (pfl:say (strcat "      ^ " (car r)
                             " differs vertically from " (car (car rows)))))))
      (if ok
        (pfl:say "    OK -- every state agrees vertically")
        (pfl:say "    MISMATCH -- these will not sit at the same rim elevation."))
      ok)))


;; (pfb:param-report label names obj) -> T if every named dynamic property is
;;   on the insert.  Spaces ignored, same as pf-draw ("PFRUN X" = "PFRUNX").
(defun pfb:param-report (label names obj / miss)
  (foreach n names
    (if (null (pfl:dynprop obj n)) (setq miss (cons n miss))))
  (pfl:say "")
  (pfl:say (strcat "  " label))
  (if miss
    (progn
      (pfl:say "    MISSING from the block:")
      (foreach n (reverse miss) (pfl:say (strcat "      " n))))
    (pfl:say (strcat "    OK -- all " (itoa (length names)) " present")))
  (null miss))

;; (pfb:end-moves e param) -> (barrel-bottom-moved . station-top-moved) when
;;   param is nudged by 1, or a string saying why it could not be tried.  Put
;;   back after.  Uses pf-draw's own finders, so it measures what PFSTRUCT will.
(defun pfb:end-moves (e param / obj p v0 a1 a2 b1 b2 r)
  (setq obj (vlax-ename->vla-object e))
  (cond
    ((null (setq p (pfl:dynprop obj param))) "not in this block")
    ((not (numberp (setq v0 (pfl:prop-get p)))) "has no readable value")
    ((not (and (setq a1 (pfl:end-y e 'bot)) (setq a2 (pfl:end-y e 'top))))
     "no station line or no barrel found")
    (T
     (if (/= T (setq r (pfd:prop-put p (+ v0 1.0))))
       (setq r (pfd:prop-put p (- v0 1.0))))
     (if (/= T r)
       r
       (progn
         (setq b1 (pfl:end-y e 'bot)
               b2 (pfl:end-y e 'top))
         (pfd:prop-put p v0)
         (if (and b1 b2)
           (cons (- b1 a1) (- b2 a2))
           "the geometry vanished after the change"))))))

;; (pfb:fit-check e param which) -> T when param moves its end, and only it.
;;   'top: PFTOP should move the station line's top, not the barrel bottom.
;;   'bot: PFDEPTH should move the barrel bottom, not the station line's top.
(defun pfb:fit-check (e param which / r mine other me them)
  (setq r    (pfb:end-moves e param)
        me   (if (eq which 'top) "the station line's top" "the barrel bottom")
        them (if (eq which 'top) "the barrel bottom" "the station line's top"))
  (cond
    ((= (type r) 'STR)
     (pfl:say (strcat "    FAIL  " param ": " r)) nil)
    (T
     (setq mine  (abs (if (eq which 'top) (cdr r) (car r)))
           other (abs (if (eq which 'top) (car r) (cdr r))))
     (cond
       ((and (> mine 1e-4) (< other 1e-4))
        (pfl:say (strcat "    PASS  " param " moves " me)) T)
       ((and (> mine 1e-4) (> other 1e-4))
        (pfl:say (strcat "    FAIL  " param " moves " me " AND " them)) nil)
       ((> other 1e-4)
        (pfl:say (strcat "    FAIL  " param " moves " them " instead of " me)) nil)
       (T
        (pfl:say (strcat "    FAIL  " param " does not move " me)) nil)))))

;; (pfb:fit-report e) -> T if PFSTRUCT can fit this insert's top and depth.
;;   Call with the insert in a PROFILE state.
(defun pfb:fit-report (e / sl y0 bot a b)
  (setq y0 (cadr (cdr (assoc 10 (entget e)))))
  (pfl:say "")
  (pfl:say "  PFTOP and PFDEPTH  (each nudged by 1, then put back)")
  (cond
    ((null (setq sl (pfl:station-line e)))
     (pfl:say "    FAIL  no station line.  PFSTRUCT looks for a vertical LINE (or")
     (pfl:say "          2-point polyline) at the block's X origin, drawn in the block itself.")
     nil)
    (T
     ;; PFDEPTH is judged the way PFSTRUCT fits it: by the lowest line end it
     ;; actually moves, not by the lowest line in the block.
     (setq bot (pfd:depth-probe e *pf-param-depth*))
     (pfl:say (strcat "    station line " (rtos (- (car sl) y0) 2 2) " to " (rtos (- (cadr sl) y0) 2 2)
                      ",  barrel bottom " (if (listp bot) (rtos (- (car bot) y0) 2 2) "?")
                      "   (Y from the insertion point)"))
     (setq a (pfb:fit-check e *pf-param-top* 'top))
     (if (listp bot)
       (progn
         (pfl:say (strcat "    PASS  " *pf-param-depth* " moves the barrel bottom ("
                          (rtos (abs (cadr bot)) 2 2) " per 1, "
                          (if (< (cadr bot) 0.0) "down" "up") " as it grows)"))
         (setq b T))
       (progn
         (pfl:say (strcat "    FAIL  " bot))
         (setq b nil)))
     (and a b))))

;; (pfb:att-move-check e tag) -> T if a LockPosition label can be moved by
;;   code and stays put through a REGEN.  Put back after.
(defun pfb:att-move-check (e tag / a ed was now ok)
  (pfl:say "")
  (pfl:say (strcat "  Moving a locked label by code (" tag ", moved 1 and put back)"))
  (cond
    ((null (setq a (pfr:attr-ent e tag)))
     (pfl:say (strcat "    FAIL  no " tag " on this insert")) nil)
    (T
     (setq ed  (entget a)
           was (pfr:att-pt e tag))
     (pfr:att-place e tag (list (+ (car was) 1.0) (+ (cadr was) 1.0))
                    (cdr (assoc 40 ed)) (cdr (assoc 50 ed)) 'ML)
     (vla-regen (vla-get-activedocument (vlax-get-acad-object)) acActiveViewport)
     (setq now (pfr:att-pt e tag)
           ok  (and now (< (abs (- (distance was now) (sqrt 2.0))) 0.01)))
     (entmod ed)
     (entupd e)
     (pfl:say (if ok
                "    PASS  it moves, and stays after a REGEN"
                "    FAIL  it did not move, or snapped back on REGEN"))
     ok)))



;; (pfb:inventory e) -> prints what is drawn directly in the insert as it
;;   shows now: entities by type, how many the state hides, and the longest
;;   vertical lines.  A nested block counts as one INSERT -- its insides
;;   cannot stretch.  "hidden 0" on a ten-state block would mean hidden
;;   entities are not flagged the way the dry runs assume.
(defun pfb:inventory (e / ty counts hidden a n)
  (setq hidden 0)
  (foreach sd (pfl:block-ents e T)
    (if (= 1 (cdr (assoc 60 sd)))
      (setq hidden (1+ hidden))
      (progn
        (setq ty (cdr (assoc 0 sd)))
        (if (setq a (assoc ty counts))
          (setq counts (subst (cons ty (1+ (cdr a))) a counts))
          (setq counts (cons (cons ty 1) counts))))))
  (pfl:say "  Drawn directly in the block, as it shows now:")
  (pfl:say (strcat "    " (pfl:join (mapcar '(lambda (c) (strcat (car c) " " (itoa (cdr c))))
                                    (reverse counts)))
                   "    hidden by the state: " (itoa hidden)))
  (pfl:say "    longest vertical lines:   X        from      to")
  (setq n 0)
  (foreach v (pfl:vlines e)
    (if (< n 5)
      (pfl:say (strcat "                              " (pfl:pad (rtos (car v) 2 2) 9)
                       (pfl:pad (rtos (cadr v) 2 2) 10) (rtos (caddr v) 2 2))))
    (setq n (1+ n)))
  (if (= n 0) (pfl:say "                              (none)"))
  (princ))

;; (pfb:x-range e) -> (left right) X of the block's own lines and polylines,
;;   from the block origin | nil.  Lines inside a nested block do not count --
;;   which is the point: nested geometry cannot stretch.
(defun pfb:x-range (e / sx xs)
  (setq sx (cond ((cdr (assoc 41 (entget e)))) (1.0))
        xs (mapcar 'car (pfl:geom-pts e)))
  (if xs (list (* sx (apply 'min xs)) (* sx (apply 'max xs)))))

;; (pfb:size-check e) -> T if the profile slab/barrel width changes with size.
;;   Call with the insert in a PROFILE state.  Every size is tried, then the
;;   original size is put back.
(defun pfb:size-check (e / obj lu was gx w widths ok r)
  (setq obj (vlax-ename->vla-object e)
        lu  (pfl:dynprop obj *pf-param-size*)
        ok  T)
  (pfl:say "")
  (pfl:say (strcat "  Profile width at each size  (" *pf-param-size*
                   " stepped through, then put back)"))
  (cond
    ((null lu) (pfl:say "    skipped -- no size lookup on this block") T)
    (T
     (setq was (pfl:prop-get lu))
     (pfl:say (strcat "      size    left     right    width    centred   " *pf-param-barrel*))
     (foreach v (pfl:allowed lu)
       (setq r (pfd:dynprop-put obj *pf-param-size* v))
       (cond
         ((/= T r)
          (setq ok nil)
          (pfl:say (strcat "      " (pfl:pad v 8) "could not set: " r)))
         ((null (setq gx (pfb:x-range e)))
          (setq ok nil)
          (pfl:say (strcat "      " (pfl:pad v 8) "no lines found")))
         (T
          (setq w (- (cadr gx) (car gx))
                widths (cons w widths))
          (pfl:say (strcat "      " (pfl:pad v 8)
                           (pfl:pad (rtos (car gx) 2 2) 9)
                           (pfl:pad (rtos (cadr gx) 2 2) 9)
                           (pfl:pad (rtos w 2 2) 9)
                           (pfl:pad (if (equal (- (car gx)) (cadr gx) 0.01) "yes" "NO") 10)
                           ;; the lookup's own answer -- if this changes and
                           ;; the width does not, the stretches are at fault
                           (vl-princ-to-string (pfl:dynprop-get obj *pf-param-barrel*)))))))
     (pfd:dynprop-put obj *pf-param-size* (vl-princ-to-string was))
     (setq widths (reverse widths))
     (cond
       ((null widths))
       ((< (- (apply 'max widths) (apply 'min widths)) 0.01)
        (setq ok nil)
        (pfl:say "    FAIL  the width is the same at every size.  Read the last column:")
        (pfl:say (strcat "          " *pf-param-barrel* " changes  -> the lookup works; the two stretches"))
        (pfl:say "                                 are not moving the walls")
        (pfl:say (strcat "          " *pf-param-barrel* " the same -> it is not a column in the lookup table,"))
        (pfl:say "                                 or every row holds the same value"))
       ((not (apply 'and (mapcar '(lambda (a b) (<= a (+ b 0.01)))
                                 widths (cdr widths))))
        (pfl:say "    NOTE  the width does not grow steadily with size -- check the lookup values"))
       (T (pfl:say "    PASS  the width follows the size")))
     (pfl:say "    \"centred NO\" = one side moves more than the other -- check the")
     (pfl:say "    180 offset on the left-hand stretch.  Not failed: it can also be a")
     (pfl:say "    one-sided line that is meant to be there.")
     ok)))

;; (pfb:gate-pipe e obj) -> T if the PFPIPE insert has what pf-pipe uses
(defun pfb:gate-pipe (e obj / ok vis n)
  (setq ok T)
  (if (not (pfb:report "Attribute tags" *pf-pipe-tags* (pfb:tags e)))
    (setq ok nil))
  (if (not (pfb:param-report "Dynamic properties PFPIPE sets"
                             (list *pf-pipe-run-x* *pf-pipe-run-y* *pf-pipe-dia*
                                   *pf-pipe-wt* *pf-pipe-wb*)
                             obj))
    (setq ok nil))
  ;; the label's grip (2026-10-22).  The leader itself is drawn by the tool.
  (if (not (pfb:param-report "Label grip"
                             (list (strcat *pf-pipe-lead* " X") (strcat *pf-pipe-lead* " Y"))
                             obj))
    (setq ok nil))
  (setq vis (pfb:visprop obj))
  (pfl:say "")
  (pfl:say "  Visibility parameter")
  (cond
    ((null vis)
     (setq ok nil)
     (pfl:say "    NONE FOUND"))
    (T
     (pfl:say (strcat "    name in block   " (car vis) "   (pf-cfg expects "
                      *pf-pipe-vis* ")"))
     (if (not (pfb:report "Visibility states"
                          (list *pf-pipe-state-plain* *pf-pipe-state-walls*)
                          (cadr vis)))
       (setq ok nil))))
  (pfl:say "")
  (pfl:say "  Carlson libraries")
  (if (setq n (length (pfp:sizes)))
    (if (> n 0)
      (pfl:say (strcat "    pipesize.dta  " (itoa n) " round sizes"))
      (progn (setq ok nil)
             (pfl:say "    pipesize.dta  NOT READ -- PFPIPE will refuse to run"))))
  (pfl:say (strcat "    pipen.dta     "
                   (if (pfp:mats)
                     (strcat (itoa (length (pfp:mats))) " materials")
                     "none -- material comes from the grid, or stays blank")))
  ok)

;; (pfb:gate-struct e obj nm) -> T if the structure insert agrees with pf-cfg
(defun pfb:gate-struct (e obj nm / ok row root size lu lu-val sz-att want-states
                          states vis was r now)
  (setq ok T row (if nm (pfr:row-for nm)))
  (cond
    ((null row)
     (pfl:say "")
     (pfl:say "  NOT IN pf-cfg -- no *pf-blocks* row matches this name.")
     (pfl:say "  Either the block is misnamed or the config is missing a row.")
     nil)
    (T
      (setq root (cadr row)
            size (pfr:size-of nm)
            lu   (pfl:dynprop obj *pf-param-size*))
      (pfl:say (strcat "  matches row    " (vl-princ-to-string (car row))
                       "   (" root ")"))

      ;; Size: the one-block CBI carries it in a lookup, older blocks in the name.
      (cond
        (lu
         (setq lu-val (vl-princ-to-string (pfl:prop-get lu))
               sz-att (cond ((pfr:get e *pf-tag-size*)) ("")))
         (pfl:say (strcat "  size           " *pf-param-size* " = " lu-val
                          "   choices: " (pfl:join (pfl:allowed lu))))
         ;; PFSIZE the attribute is a field on the lookup.  The CONST row
         ;; reads it, so a dead field loses the size on the label.
         (cond
           ((= (strcase lu-val) "CUSTOM")
            (pfl:say "    NOTE: \"Custom\" = this insert's sizes match no row of the lookup table.")
            (pfl:say "          Pick a size in Properties.  A FRESH insert showing Custom means the")
            (pfl:say "          block's default values match no row -- fix the defaults in BEDIT."))
           ((/= (strcase lu-val) (strcase sz-att))
            (pfl:say (strcat "    NOTE: PFSIZE reads \"" sz-att "\", not \"" lu-val
                             "\".  REGEN and PFGATE again; still different = the field is broken.")))))
        ((/= size "")
         (pfl:say (strcat "  size suffix    " size)))
        (T
         (setq ok nil)
         (pfl:say (strcat "  size           NONE -- no " *pf-param-size*
                          " lookup and no size on the name"))))

      (if (not (pfb:report "Attribute tags" *pf-tags* (pfb:tags e)))
        (setq ok nil))

      (if (not (pfb:param-report "Dynamic parameters"
                                 (append (if (= size "") (list *pf-param-size* *pf-param-barrel*))
                                         (list *pf-param-top* *pf-param-depth*))
                                 obj))
        (setq ok nil))

      (setq vis (pfb:visprop obj))
      (pfl:say "")
      (cond
        ((null vis)
         (setq ok nil)
         (pfl:say "  Visibility parameter")
         (pfl:say "    NONE FOUND -- the block is not dynamic, or has no")
         (pfl:say "    visibility parameter at all."))
        (T
          (pfl:say "  Visibility parameter")
          (pfl:say (strcat "    name in block   " (car vis)))
          (pfl:say (strcat "    pf-cfg expects  " *pf-vis-param*))
          (if (/= (strcase (car vis)) (strcase *pf-vis-param*))
            (pfl:say "    ^ differs.  Not fatal (pf-record discovers it), but worth knowing.")
            (pfl:say "    ^ match"))
          (setq states      (eval (caddr row))
                want-states (cons *pf-state-plan* states)
                was         (vl-princ-to-string (caddr vis)))
          (if (not (pfb:report "Visibility states" want-states (cadr vis)))
            (setq ok nil))

          ;; Only worth doing when the names already agree -- cycling
          ;; through states that do not exist just fails.
          (if (null (pfb:missing want-states (cadr vis)))
            (progn
              ;; PROFILE states only -- PLAN is a plan symbol and is meant
              ;; to differ from them.
              (if (not (pfb:report-extents
                         (pfb:state-extents obj (cadddr vis) states was)
                         1e-6))
                (setq ok nil))
              ;; the dry runs, in the first profile state, then put back.
              ;; Read the state BACK -- if the switch did not take, every
              ;; check below is measuring the plan symbol.
              (setq r   (pfd:set-state obj (car states))
                    now (vl-princ-to-string (pfl:prop-get (pfl:visprop obj))))
              (pfl:say "")
              (if (= (strcase now) (strcase (car states)))
                (pfl:say (strcat "  Dry runs below are in state " now))
                (progn
                  (setq ok nil)
                  (pfl:say (strcat "  FAIL  could not switch to " (car states) " -- still " now
                                   (if (= (type r) 'STR) (strcat ": " r) "")))
                  (pfl:say "        So the checks below are measuring the PLAN symbol.")))
              ;; CAUGHT: an error in any dry run must never leave the insert
              ;; in a profile state.  It is put back whatever happens
              ;; (Jake, 2026-10-16: a plan CBI was left in a face state).
              (setq r (vl-catch-all-apply
                        '(lambda ()
                           (setq *pfd-stage* "listing the block's geometry")
                           (pfb:inventory e)
                           (setq *pfd-stage* "the PFTOP / PFDEPTH dry run")
                           (if (not (pfb:fit-report e)) (setq ok nil))
                           (setq *pfd-stage* "the label-move dry run")
                           (if (not (pfb:att-move-check e "PFCON")) (setq ok nil))
                           (setq *pfd-stage* "the size dry run")
                           (if (not (pfb:size-check e)) (setq ok nil)))))
              (if (vl-catch-all-error-p r)
                (progn
                  (setq ok nil)
                  (pfl:say (strcat "  FAIL  stopped with an error during " *pfd-stage*
                                   ": " (vl-catch-all-error-message r)))))
              (pfd:set-state obj was)))

          ;; read the state BACK, never just repeat what it was
          (setq now (vl-princ-to-string (pfl:prop-get (pfl:visprop obj))))
          (pfl:say "")
          (pfl:say (strcat "  This insert is now in state: " now))
          (if (/= (strcase now) (strcase was))
            (progn
              (setq ok nil)
              (pfl:say (strcat "  FAIL  it was in " was " before PFGATE and could not be put back"
                               " -- set Visibility to " was " in Properties."))))
          (if (/= (strcase was) (strcase *pf-state-plan*))
            (pfl:say (strcat "    NOTE: a fresh insert should come in as "
                             *pf-state-plan*
                             ".\n    If this one was not restated by hand,"
                             " BSAVE happened on the wrong state.")))))
      ok)))

(defun c:PFGATE ( / e obj nm ok)
  (cond
    ((not (boundp '*pf-blocks*))
     (pfl:say "PFGATE: pf-cfg.lsp is not loaded.  Load it first."))
    ((null pfl:station-line)
     (pfl:say "PFGATE: load pf-load.lsp first -- it uses PFSTRUCT's own code."))
    ((= 1 (getvar "BLOCKEDITOR"))
     (pfl:say "PFGATE: close the Block Editor first."))
    ((null (setq e (car (entsel (strcat "\nPick a placed PFSUITE_CBI or " *pf-pipe-block* ": ")))))
     (pfl:say "PFGATE: nothing picked."))
    ((/= "INSERT" (cdr (assoc 0 (entget e))))
     (pfl:say "PFGATE: that is not a block insert."))
    (T
      (setq obj (vlax-ename->vla-object e)
            nm  (pfl:effname e))
      (pfl:say "")
      (pfl:say "=== PFGATE ===========================================")
      (pfl:say (strcat "  DXF name       " (cdr (assoc 2 (entget e)))))
      (pfl:say (strcat "  EffectiveName  " (if nm nm "(unreadable)")))
      (setq ok (if (and nm (= (strcase nm) (strcase *pf-pipe-block*)))
                 (pfb:gate-pipe e obj)
                 (pfb:gate-struct e obj nm)))
      (pfl:say "")
      (pfl:say (if ok
                 "  RESULT: ready to test."
                 "  RESULT: NOT READY -- see FAIL / MISSING above."))
      (pfl:say "======================================================")))
  (princ))


;;; ==========================================================================
;;; SECTION 4b  --  PFSWAP.  Repoint nested blocks inside a definition.
;;; ==========================================================================
;;; Building a new size = BSAVEAS the _04 block, then swap every nested
;;; PF-GRATE_CBI-* (and the plan symbol) for that size's version.
;;;
;;; entmod changes group 2 on the nested INSERT -- the SAME object, now pointing
;;; at a different block.  Visibility-state membership is recorded against the
;;; object, not the name it points at, so the nine state assignments should
;;; survive the swap and PFSEL/BVSHOW does not have to be repeated.
;;; CONFIRMED IN CAD 2026-09-15: all seven CBI sizes built this way, state
;;; assignments intact.  Only the slab changes per size; the nine profile
;;; symbols are shared.
;;;
;;; Runs OUTSIDE the Block Editor: it edits the real definition, and BEDIT
;;; works on a temporary copy that would overwrite this on BSAVE.
;;; Shows every change first and asks before writing anything.

(if (not (boundp '*pfb-swap-blk*)) (setq *pfb-swap-blk* ""))

(defun c:PFSWAP ( / blk old new bdef e ed nm newnm plan miss ans n)
  (cond
    ((= 1 (getvar "BLOCKEDITOR"))
     (pfl:say "PFSWAP: close the Block Editor first -- this edits the real definition."))
    (T
      (setq blk (getstring T (strcat "\nBlock definition to edit <" *pfb-swap-blk* ">: ")))
      (if (= blk "") (setq blk *pfb-swap-blk*))
      (cond
        ((or (= blk "") (null (setq bdef (tblobjname "BLOCK" blk))))
         (pfl:say (strcat "PFSWAP: no block definition called \"" blk "\".")))
        (T
          (setq *pfb-swap-blk* blk)
          (setq old (strcase (getstring T "\nReplace this text in nested block names: ")))
          (setq new (strcase (getstring T "\nWith: ")))
          (if (= old "")
            (pfl:say "PFSWAP: nothing to replace.")
            (progn
              ;; Pass 1: work out every change without touching anything.
              (setq e (entnext bdef))
              (while (and e (/= "ENDBLK" (cdr (assoc 0 (setq ed (entget e))))))
                (if (= "INSERT" (cdr (assoc 0 ed)))
                  (progn
                    (setq nm (strcase (cdr (assoc 2 ed))))
                    (if (vl-string-search old nm)
                      (progn
                        (setq newnm (vl-string-subst new old nm))
                        (if (tblsearch "BLOCK" newnm)
                          (setq plan (cons (list e nm newnm) plan))
                          (setq miss (cons (strcat nm "  ->  " newnm) miss)))))))
                (setq e (entnext e)))
              (setq plan (reverse plan) miss (reverse miss))

              (pfl:say "")
              (pfl:say (strcat "=== PFSWAP  " blk " ==="))
              (foreach p plan (pfl:say (strcat "  " (cadr p) "  ->  " (caddr p))))
              (if miss
                (progn
                  (pfl:say "  NOT DEFINED IN THIS DRAWING -- would be skipped:")
                  (foreach m miss (pfl:say (strcat "    " m)))
                  (pfl:say "  Insert or load those blocks first.")))

              (cond
                ((null plan)
                 (pfl:say "  Nothing to swap."))
                (T
                  (initget "Yes No")
                  (setq ans (getkword (strcat "\nSwap " (itoa (length plan))
                                              " nested block(s)? [Yes/No] <No>: ")))
                  (if (/= ans "Yes")
                    (pfl:say "  Cancelled.  Nothing changed.")
                    (progn
                      ;; Pass 2: write.
                      (setq n 0)
                      (foreach p plan
                        (setq ed (entget (car p)))
                        (if (entmod (subst (cons 2 (caddr p)) (assoc 2 ed) ed))
                          (setq n (1+ n))))
                      (vla-regen (vla-get-activedocument (vlax-get-acad-object)) 1)
                      (pfl:say (strcat "  " (itoa n) " swapped.  Insert a FRESH copy of "
                                       blk " and run PFGATE."))
                      (pfl:say "  Old inserts may still show the old symbols -- RESETBLOCK them.")))))))))))
  (princ))


;;; ==========================================================================
;;; SECTION 5  --  PFRECTEST.  Does pf-record round-trip?
;;; ==========================================================================
;;; One command instead of lines pasted at the command line.  Pasting is how
;;; the first attempt went wrong: every space in a padded line is Enter, and
;;; Enter repeats the last command.
;;;
;;; WRITES TO THE PICKED INSERT.  Use a throwaway test copy, not a real one.

(defun pfb:check (label got want / ok)
  ;; 1e-8, not tighter: rtos may cap precision below 15 on some builds, and a
  ;; station agreeing to a hundred-millionth of a foot is agreeing.
  (setq ok (equal got want 1e-8))
  (pfl:say (strcat "  " (if ok "PASS  " "FAIL  ") label))
  (if (not ok)
    (progn
      (pfl:say (strcat "          wanted " (vl-prin1-to-string want)))
      (pfl:say (strcat "          got    " (vl-prin1-to-string got)))))
  ok)

(defun c:PFRECTEST ( / e ok memb rec)
  (cond
    ((not (boundp '*pf-tags*))
     (pfl:say "PFRECTEST: pf-cfg.lsp is not loaded."))
    ;; Test the VALUE, not the symbol: this file names pfr:refresh, so the
    ;; symbol exists in atoms-family whether pf-record is loaded or not.  And
    ;; not (type ...) = USUBR either -- this AutoCAD/Carlson reports something
    ;; else for a loaded defun (CAD, 2026-09-15).  Bound-or-not is the question.
    ((null pfr:refresh)
     (pfl:say "PFRECTEST: pf-record.lsp is not loaded.  Load pf-cfg, then pf-record."))
    ((null (setq e (car (entsel "\nPick a TEST copy of a PFSUITE block: "))))
     (pfl:say "PFRECTEST: nothing picked."))
    ((not (pfr:ours-p e))
     (pfl:say "PFRECTEST: that is not a PFSUITE block."))
    (T
      (setq ok T)
      (pfl:say "")
      (pfl:say "=== PFRECTEST ========================================")

      ;; Say it plainly when the insert has no attributes at all.  An insert
      ;; placed BEFORE the ATTDEFs were added to the definition does not get
      ;; them until ATTSYNC -- and every attribute test below then reads as a
      ;; pf-record bug when it is not one.
      (if (null (pfb:tags e))
        (progn
          (pfl:say "  THIS INSERT CARRIES NO ATTRIBUTES.")
          (pfl:say "  It was placed before the ATTDEFs existed.  Run ATTSYNC on")
          (pfl:say "  the block, or insert a fresh copy, and test again.")
          (pfl:say "  (The XDATA tests below are still meaningful.)")
          (pfl:say "")))

      (if (not (pfb:check "all nine tags present" (pfr:tags-ok-p e) T)) (setq ok nil))

      (pfr:put e *pf-tag-name* "CB-1")
      (if (not (pfb:check "put / get PFNAME" (pfr:get e *pf-tag-name*) "CB-1")) (setq ok nil))

      ;; Clear any provenance from an earlier run so the sequence starts clean.
      (pfr:xd-put e *pf-xd-src* (pfr:ser nil))

      (if (not (pfb:check "refresh a derived rim -> written"
                          (pfr:refresh e *pf-tag-rim* "769.13" *pf-src-tin*) 'written))
        (setq ok nil))
      (if (not (pfb:check "  rim value" (pfr:get e *pf-tag-rim*) "769.13")) (setq ok nil))
      (if (not (pfb:check "  rim provenance" (pfr:src-get e *pf-tag-rim*) *pf-src-tin*))
        (setq ok nil))

      ;; A drafter edits in Properties, never through pfr:assert.  Simulate
      ;; that with a bare put, and the next refresh must notice and keep it.
      (pfr:put e *pf-tag-rim* "771.00")
      (if (not (pfb:check "hand edit, then refresh -> adopted"
                          (pfr:refresh e *pf-tag-rim* "769.13" *pf-src-tin*) 'adopted))
        (setq ok nil))
      (if (not (pfb:check "  rim still the hand-typed 771.00"
                          (pfr:get e *pf-tag-rim*) "771.00"))
        (setq ok nil))

      (pfr:assert e *pf-tag-rim* "770.00")
      (if (not (pfb:check "assert a rim -> provenance ASSERTED"
                          (pfr:src-get e *pf-tag-rim*) *pf-src-asserted*))
        (setq ok nil))

      ;; THE ONE THAT MATTERS.  A re-run must not overwrite what a human typed.
      (if (not (pfb:check "refresh again -> kept"
                          (pfr:refresh e *pf-tag-rim* "769.13" *pf-src-tin*) 'kept))
        (setq ok nil))
      (if (not (pfb:check "  rim still the asserted 770.00"
                          (pfr:get e *pf-tag-rim*) "770.00"))
        (setq ok nil))

      (setq memb '(("STORM_DA" 209.299293 -12.381585)))
      (pfr:memb-put e memb)
      (if (not (pfb:check "MEMB round-trips exactly" (pfr:memb-get e) memb)) (setq ok nil))

      ;; Long enough to force several XDATA chunks -- a single 1000 group holds
      ;; 255 bytes and AutoCAD truncates silently past that.
      (setq memb nil)
      (repeat 12
        (setq memb (cons (list "STORM_LONG_ALIGNMENT_NAME" 1234.567891 -12.345678) memb)))
      (pfr:memb-put e memb)
      (if (not (pfb:check (strcat "long MEMB survives chunking ("
                                  (itoa (strlen (pfr:ser memb))) " chars)")
                          (pfr:memb-get e) memb))
        (setq ok nil))

      (pfr:schema-put e)
      (if (not (pfb:check "SCHEMA" (pfr:schema-get e) *pf-schema*)) (setq ok nil))

      (setq rec (pfr:read e))
      (if (not (pfb:check "pfr:read carries PFNAME" (pfr:val rec *pf-tag-name*) "CB-1"))
        (setq ok nil))
      (pfl:say (strcat "        read -> type " (vl-princ-to-string (cdr (assoc 'type rec)))
                       "  size " (vl-princ-to-string (cdr (assoc 'size rec)))))

      (pfl:say "")
      (pfl:say (if ok "  RESULT: pf-record round-trips." "  RESULT: FAILURES above."))
      (pfl:say "======================================================")))
  (princ))


;;; ==========================================================================
;;; SECTION 7  --  PFSYNCTEST.  What does ATTSYNC lose?
;;; ==========================================================================
;;; Autodesk's ATTSYNC page says it "deletes any extended data associated with
;;; the block, and might affect dynamic blocks".  It does not say WHICH.  The
;;; suite keeps things ATTSYNC could take: XDATA on every block (MEMB, SRC --
;;; what marks a hand-typed value -- SCHEMA, PLAN, LINE, POS), and on an
;;; anchor its stored records (the .cl, surfaces, copy stamp).  Jake wants this
;;; run PERIODICALLY (2026-10-15), so it is READ ONLY and drawing-wide:
;;;
;;;   Run 1 -- snapshots EVERY suite block in the drawing: structures, pipes,
;;;            anchors (PFSUITE_ANCHOR and V5's).  Writes nothing.
;;;   (you)  -- run ATTSYNC on whichever blocks you like.
;;;   Run 2 -- compares every one against its snapshot, and says what was
;;;            lost, by block type and by kind of data.
;;;
;;; Two runs, not one, because the ATTSYNC prompts were never verified and
;;; scripting a guessed answer sequence is how a padded line becomes a wall
;;; of _HELP.  ATTSYNC itself is what changes the drawing -- try it on a COPY
;;; of a real drawing, never the only one.

(setq *pfb-sync* nil)               ; ((handle . snapshot) ...) between the two runs

;; (pfb:attribs e) -> the entget list of every ATTRIB on this insert
(defun pfb:attribs (e / sub sd out)
  (if (equal 1 (cdr (assoc 66 (entget e))))
    (progn
      (setq sub (entnext e))
      (while (and sub
                  (setq sd (entget sub))
                  (/= (cdr (assoc 0 sd)) "SEQEND"))
        (if (= (cdr (assoc 0 sd)) "ATTRIB") (setq out (cons sd out)))
        (setq sub (entnext sub)))))
  (reverse out))

;; (pfb:attrpairs e) -> ((TAG . value) ...)
(defun pfb:attrpairs (e)
  (mapcar '(lambda (d) (cons (strcase (cdr (assoc 2 d))) (cdr (assoc 1 d))))
          (pfb:attribs e)))

;; (pfb:dynvals obj) -> ((propname . value-as-string) ...)
;;   Points come back as safearrays, which print as an address -- unwrap them
;;   first or two identical values would compare as different.
;;   Names are NOT unique: PFSUITE_CBI has three parameters all called "Origin".
;;   The second and third get "#2" / "#3", so each compares against itself.
(defun pfb:dynvals (obj / p n v out names c k)
  (foreach p (pfl:dynprops obj)
    (setq n (vl-catch-all-apply 'vla-get-propertyname (list p))
          v (vl-catch-all-apply 'vla-get-value (list p)))
    (if (not (or (vl-catch-all-error-p n) (vl-catch-all-error-p v)))
      (progn
        (setq v (vlax-variant-value v))
        (if (= (type v) 'SAFEARRAY) (setq v (vlax-safearray->list v)))
        (setq c     (1+ (length (vl-remove-if-not '(lambda (x) (= x n)) names)))
              names (cons n names)
              k     (if (> c 1) (strcat n "#" (itoa c)) n)
              out   (cons (cons k (vl-princ-to-string v)) out)))))
  (reverse out))

;; (pfb:xdict-keys e) -> the names in this insert's extension dictionary
;;   (an anchor's PFLEDGER / PFXLEDGER lives there), or nil
(defun pfb:xdict-keys (e / xd out)
  (if (setq xd (pfg:extdict e))
    (foreach p (entget xd)
      (if (= 3 (car p)) (setq out (cons (cdr p) out)))))
  (reverse out))

;; (pfb:suite-inserts) -> every suite block in the drawing: structures,
;;   pipes and anchors, by their REAL name (dynamic ones sit under *U)
(defun pfb:suite-inserts ( / ss i e nm out)
  (if (setq ss (ssget "_X" '((0 . "INSERT"))))
    (repeat (setq i (sslength ss))
      (setq e  (ssname ss (setq i (1- i)))
            nm (strcase (cond ((pfl:effname e)) (""))))
      (if (or (pfr:ours-p e)
              (= nm (strcase *pf-pipe-block*))
              (wcmatch nm (strcase *pf-anchor-blocks*)))
        (setq out (cons e out)))))
  out)

;; (pfb:snap e) -> everything ATTSYNC might touch, as an assoc list
(defun pfb:snap (e / obj)
  (setq obj (vlax-ename->vla-object e))
  (list
    (cons 'name   (cond ((pfl:effname e)) ("?")))
    (cons 'attrs  (pfb:attrpairs e))
    (cons 'fmt    (mapcar '(lambda (d)
                             (list (strcase (cdr (assoc 2 d)))
                                   (cdr (assoc 10 d)) (cdr (assoc 40 d)) (cdr (assoc 50 d))))
                          (pfb:attribs e)))
    (cons 'xd     (pfr:xd-pairs e))
    (cons 'apps   (mapcar 'car (cdr (assoc -3 (entget e '("*"))))))
    (cons 'xdict  (pfb:xdict-keys e))
    (cons 'ledger (list (cons *pf-anc-meta*  (vl-princ-to-string (pfg:rec e *pf-anc-meta*)))
                        (cons *pf-anc-files* (vl-princ-to-string (pfg:rec e *pf-anc-files*)))))
    (cons 'dyn    (pfb:dynvals obj))
    (cons 'box    (pfl:bbox obj))))

;; (pfb:diff before after) -> the keys whose value changed or vanished
(defun pfb:diff (b a / bad)
  (foreach p b
    (if (not (equal (cdr p) (cdr (assoc (car p) a)) 1e-8))
      (setq bad (cons (car p) bad))))
  (reverse bad))

;; (pfb:sync-report label hits) -> T when nothing was hit.
;;   hits: ((block-name handle what) ...).  At most 12 lines printed.
(defun pfb:sync-report (label hits / n)
  (cond
    ((null hits) (pfl:say (strcat "  PASS  " label)) T)
    (T
     (pfl:say (strcat "  FAIL  " label " -- on " (itoa (length hits)) " block(s):"))
     (setq n 0)
     (foreach x (reverse hits)
       (if (< n 12)
         (pfl:say (strcat "          " (pfl:pad (car x) 16) "#" (pfl:pad (cadr x) 9) (caddr x))))
       (setq n (1+ n)))
     (if (> n 12) (pfl:say (strcat "          ... and " (itoa (- n 12)) " more")))
     nil)))

(defun c:PFSYNCTEST ( / snaps s e snap aft h nm d c counts gone h-attr h-xd h-apps
                       h-xdict h-ledger h-dyn n-fmt n-box n-new ok)
  (cond
    ((or (not (boundp '*pf-tags*)) (null pfg:extdict) (null pfr:xd-pairs))
     (pfl:say "PFSYNCTEST: load pf-load.lsp first."))

    ;; ---- run 1: snapshot everything.  Writes nothing. ----------------------
    ((or (null *pfb-sync*)
         (progn
           (initget "Compare Restart")
           (= "Restart" (getkword "\nPFSYNCTEST -- a snapshot exists.  [Compare/Restart] <Compare>: "))))
     (setq *pfb-sync* nil)
     (foreach e (pfb:suite-inserts)
       (setq *pfb-sync* (cons (cons (cdr (assoc 5 (entget e))) (pfb:snap e)) *pfb-sync*)))
     (foreach s *pfb-sync*
       (setq nm (cdr (assoc 'name (cdr s))))
       (if (setq c (assoc nm counts))
         (setq counts (subst (cons nm (1+ (cdr c))) c counts))
         (setq counts (cons (cons nm 1) counts))))
     (pfl:say "")
     (pfl:say (strcat "PFSYNCTEST: snapshot of " (itoa (length *pfb-sync*))
                      " suite block(s).  Nothing in the drawing was changed."))
     (foreach c (reverse counts)
       (pfl:say (strcat "    " (pfl:pad (car c) 18) (itoa (cdr c)))))
     (pfl:say "  Now run ATTSYNC on the block(s) you want to test, then PFSYNCTEST again."))

    ;; ---- run 2: compare every block against its snapshot -------------------
    (T
     (setq snaps *pfb-sync* *pfb-sync* nil n-fmt 0 n-box 0 n-new 0 ok T)
     (foreach s snaps
       (setq h (car s) snap (cdr s) nm (cdr (assoc 'name snap)))
       (cond
         ((not (and (setq e (handent h)) (entget e)))
          (setq gone (cons (list nm h "no longer in the drawing") gone)))
         (T
          (setq aft (pfb:snap e))
          ;; what a drafter or the tool typed into attributes
          (if (setq d (pfb:diff (cdr (assoc 'attrs snap)) (cdr (assoc 'attrs aft))))
            (setq h-attr (cons (list nm h (pfl:join d)) h-attr)))
          ;; the tool's own XDATA, key by key
          (if (setq d (pfb:diff (cdr (assoc 'xd snap)) (cdr (assoc 'xd aft))))
            (setq h-xd (cons (list nm h (pfl:join d)) h-xd)))
          (if (setq d (pfb:missing (cdr (assoc 'apps snap)) (cdr (assoc 'apps aft))))
            (setq h-apps (cons (list nm h (pfl:join d)) h-apps)))
          ;; an anchor's stored records
          (if (setq d (pfb:missing (cdr (assoc 'xdict snap)) (cdr (assoc 'xdict aft))))
            (setq h-xdict (cons (list nm h (pfl:join d)) h-xdict)))
          (if (setq d (pfb:diff (cdr (assoc 'ledger snap)) (cdr (assoc 'ledger aft))))
            (setq h-ledger (cons (list nm h (pfl:join d)) h-ledger)))
          ;; size, PFTOP, PFDEPTH, barrel, state ...
          (if (setq d (pfb:diff (cdr (assoc 'dyn snap)) (cdr (assoc 'dyn aft))))
            (setq h-dyn (cons (list nm h (pfl:join d)) h-dyn)))
          ;; expected to change -- counted, never failed
          (if (not (equal (cdr (assoc 'fmt snap)) (cdr (assoc 'fmt aft)) 1e-8))
            (setq n-fmt (1+ n-fmt)))
          (if (not (equal (cdr (assoc 'box snap)) (cdr (assoc 'box aft)) 1e-6))
            (setq n-box (1+ n-box)))
          (if (pfb:missing (mapcar 'car (cdr (assoc 'attrs aft)))
                           (mapcar 'car (cdr (assoc 'attrs snap))))
            (setq n-new (1+ n-new))))))

     (pfl:say "")
     (pfl:say "=== PFSYNCTEST =======================================")
     (pfl:say (strcat "  " (itoa (length snaps)) " block(s) compared with the snapshot"))
     (pfl:say "")
     (foreach r (list (list "attribute values (names, rims, label text, inputs)" h-attr)
                      (list "suite XDATA (MEMB / SRC / SCHEMA / PLAN / LINE / POS)" h-xd)
                      (list "XDATA owners" h-apps)
                      (list "extension dictionary (an anchor's stored records)" h-xdict)
                      (list "anchor records (.cl, surfaces, copy stamp)" h-ledger)
                      (list "dynamic properties (size, PFTOP, PFDEPTH, barrel, state)" h-dyn)
                      (list "blocks still in the drawing" gone))
       (if (not (pfb:sync-report (car r) (cadr r))) (setq ok nil)))
     (pfl:say "")
     (pfl:say (strcat "  INFO  attribute position/height reset on " (itoa n-fmt)
                      " block(s) -- expected.  PFREFRESH puts them back."))
     (pfl:say (strcat "  INFO  outline changed on " (itoa n-box)
                      " block(s) -- expected where labels were reset"))
     (pfl:say (strcat "  INFO  new attributes added on " (itoa n-new)
                      " block(s) -- from the block definition"))
     (pfl:say "")
     (pfl:say (if ok
                "  RESULT: ATTSYNC took nothing the tool or a drafter put on these blocks."
                "  RESULT: ATTSYNC LOST DATA -- see the FAIL lines above."))
     (pfl:say "======================================================")))
  (princ))


;;; ==========================================================================
;;; SECTION 8  --  PFPIPETEST.  Can code drive PFPIPE the way a grip does?
;;; ==========================================================================
;;; The future PFPIPE command never drags a grip: it writes the dynamic
;;; properties by name, then regens.  This places one pipe that way between
;;; two picked inverts and reports what the block did with it.
;;;
;;; Three open questions it answers:
;;;   1. Do PFRUNX / PFRUNY / PFDIA / PFWT / PFWB take values from code, and
;;;      does the geometry follow?  (By hand it does -- this is the code path.)
;;;   2. Does the label's rotation (parallel to the pipe) survive a regen?
;;;   3. Does it survive a dynamic-property change after that (walls on/off)?
;;;      If not, the real command has to set the label LAST, every time.
;;;
;;; Needs pf-cfg for the two state names.  Inserts into the current space;
;;; erase the test pipes when done.

;; Profile vertical exaggeration.  The suite reads it from Carlson at run
;; time; the bench just needs a number.
(if (not (boundp '*pfb-ve*)) (setq *pfb-ve* 10.0))

(defun pfb:near (a b) (and (numberp a) (numberp b) (equal a b 1e-6)))




;; (pfb:dynset obj name val) -> T | nil, and says which and why when nil.
;;   The write is pf-draw's; this only reports it the bench's way.
(defun pfb:dynset (obj name val / r)
  (if (= T (setq r (pfd:dynprop-put obj name val)))
    T
    (progn
      (pfl:say (strcat "  FAIL  " name " " (vl-princ-to-string val) ": " r))
      nil)))

;; (pfb:attref obj tag) -> the AttributeReference with this tag, or nil
(defun pfb:attref (obj tag / hit)
  (foreach a (vlax-invoke obj 'GetAttributes)
    (if (and (null hit) (= (strcase (vla-get-tagstring a)) (strcase tag)))
      (setq hit a)))
  hit)


;; (pfb:label-state att) -> (rotation (x y)) as it stands now
(defun pfb:label-state (att)
  (list (vla-get-rotation att)
        (reverse (cdr (reverse (vlax-safearray->list
                                 (vlax-variant-value
                                   (vla-get-textalignmentpoint att))))))))

;; (pfb:label-check label att want) -> T if rotation and position are still `want`
(defun pfb:label-check (label att want / now ok)
  (setq now (pfb:label-state att)
        ok  (and (equal (car now) (car want) 1e-6)
                 (equal (cadr now) (cadr want) 1e-6)))
  (pfl:say (strcat "  " (if ok "PASS  " "FAIL  ") label))
  (if (not ok)
    (progn
      (pfl:say (strcat "          wanted rotation "
                       (angtos (car want) 0 2) "  at " (vl-princ-to-string (cadr want))))
      (pfl:say (strcat "          got    rotation "
                       (angtos (car now) 0 2) "  at " (vl-princ-to-string (cadr now))))))
  ok)

(defun c:PFPIPETEST ( / doc spc p1u p2u p1 p2 dx dy dia wall walls obj ok
                        att ht sty txt wid run ang mid want vis other pr f)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (cond
    ((= 1 (getvar "BLOCKEDITOR"))
     (pfl:say "PFPIPETEST: close the Block Editor first."))
    ((null (tblsearch "BLOCK" *pf-pipe-block*))
     (pfl:say (strcat "PFPIPETEST: no " *pf-pipe-block* " block in this drawing.  Insert one once, then erase it.")))
    ((null (setq p1u (getpoint "\nUpstream invert: ")))
     (pfl:say "PFPIPETEST: cancelled."))
    ((null (setq p2u (getpoint p1u "\nDownstream invert: ")))
     (pfl:say "PFPIPETEST: cancelled."))
    (T
      (setq p1 (trans p1u 1 0)
            p2 (trans p2u 1 0)
            dx (- (car p2) (car p1))
            dy (- (cadr p2) (cadr p1)))
      (cond
        ((< (abs dx) 1e-6)
         (pfl:say "PFPIPETEST: the two inverts are at the same station -- no length, no slope."))
        (T
          (setq dia (getreal "\nTest inside diameter, inches <15>: "))
          (if (or (null dia) (<= dia 0.0)) (setq dia 15.0))
          (setq wall (getreal "\nTest wall thickness, inches <2.25>: "))
          (if (or (null wall) (< wall 0.0)) (setq wall 2.25))
          (initget "Yes No")
          (setq walls (/= "No" (getkword "\nWalls on? [Yes/No] <Yes>: ")))

          (setq spc (if (or (= 1 (getvar "TILEMODE")) (> (getvar "CVPORT") 1))
                      (vla-get-modelspace doc)
                      (vla-get-paperspace doc))
                obj (vla-insertblock spc (vlax-3d-point p1) *pf-pipe-block* 1.0 1.0 1.0 0.0)
                ok  T)

          (pfl:say "")
          (pfl:say "=== PFPIPETEST =======================================")
          (pfl:say (strcat "  picks: run " (rtos dx 2 3) "   rise " (rtos dy 2 3)
                           "   (drawing units)"))

          ;; Sizes first, then the run: the order the real command will use.
          ;; Inches -> feet -> drawn at the exaggeration.
          (foreach pr (list (list "PFDIA" (* (/ dia 12.0) *pfb-ve*))
                            (list "PFWT"  (* (/ wall 12.0) *pfb-ve*))
                            (list "PFWB"  (* (/ wall 12.0) *pfb-ve*))
                            (list "PFRUNX" dx)
                            (list "PFRUNY" dy))
            (if (not (pfb:dynset obj (car pr) (cadr pr))) (setq ok nil)))
          (if (not (pfb:dynset obj "PFVIS" (if walls *pf-pipe-state-walls* *pf-pipe-state-plain*)))
            (setq ok nil))

          ;; 1. Did every value take?
          (pfl:say "")
          (pfl:say "  1. Values read back")
          (foreach pr (list (list "PFRUNX" dx)
                            (list "PFRUNY" dy)
                            (list "PFDIA" (* (/ dia 12.0) *pfb-ve*))
                            (list "PFWT"  (* (/ wall 12.0) *pfb-ve*))
                            (list "PFWB"  (* (/ wall 12.0) *pfb-ve*)))
            (if (not (pfb:check (car pr) (pfl:dynprop-get obj (car pr)) (cadr pr)))
              (setq ok nil)))

          ;; The label, the way the real command will write it.  Length is the
          ;; horizontal run (not exaggerated); slope is the rise taken back out
          ;; of the exaggeration, over that run.
          (setq run (abs dx)
                txt (strcat (rtos dia 2 0) "\" TEST  L="
                            (rtos run 2 2) "'  S="
                            (rtos (* 100.0 (/ (/ dy *pfb-ve*) run)) 2 2) "%")
                ang (pfl:readable (angle p1 p2))
                ;; centred: midpoint of the flowline, half the diameter up
                mid (list (/ (+ (car p1) (car p2)) 2.0)
                          (+ (/ (+ (cadr p1) (cadr p2)) 2.0)
                             (/ (* (/ dia 12.0) *pfb-ve*) 2.0))))

          (pfl:say "")
          (pfl:say "  2. Label")
          (cond
            ((null (setq att (pfb:attref obj "PFLABEL")))
             (setq ok nil)
             (pfl:say "  FAIL  no PFLABEL attribute on this insert"))
            (T
              (vla-put-textstring att txt)
              (vla-put-textalignmentpoint att (vlax-3d-point (list (car mid) (cadr mid) 0.0)))
              (vla-put-rotation att ang)
              (setq want (pfb:label-state att))
              (pfl:say (strcat "        text  " txt))
              (pfl:say (strcat "        angle " (angtos ang 0 2) " deg"))

              ;; Fit: the label goes out on a leader if it is wider than the
              ;; drawn pipe or taller than the inside of it.  Informational --
              ;; the leader is not built yet.
              (setq ht  (vla-get-height att)
                    sty (vla-get-stylename att)
                    wid (textbox (list (cons 1 txt) (cons 40 ht) (cons 7 sty)))
                    wid (- (car (cadr wid)) (car (car wid))))
              (pfl:say (strcat "  INFO  label " (rtos wid 2 2) " wide x " (rtos ht 2 2)
                               " high;  pipe " (rtos (distance p1 p2) 2 2) " long x "
                               (rtos (* (/ dia 12.0) *pfb-ve*) 2 2) " inside"))
              (pfl:say (if (and (< wid (distance p1 p2)) (< ht (* (/ dia 12.0) *pfb-ve*)))
                         "        fits inside -- stays centred"
                         "        does NOT fit -- the real command would put it on a leader"))

              (vla-regen doc 1)
              (if (not (pfb:label-check "rotation + position survive a REGEN" att want))
                (setq ok nil))

              ;; Flip walls and back: a dynamic-property change makes AutoCAD
              ;; rebuild the insert.  Reported, not failed -- if it resets, the
              ;; answer is simply "write the label last".
              (setq vis   (if walls *pf-pipe-state-walls* *pf-pipe-state-plain*)
                    other (if walls *pf-pipe-state-plain* *pf-pipe-state-walls*))
              (pfb:dynset obj "PFVIS" other)
              (pfb:dynset obj "PFVIS" vis)
              (vla-regen doc 1)
              (setq att (pfb:attref obj "PFLABEL"))
              (if (not (pfb:label-check "...and survive walls off/on" att want))
                (pfl:say "        -> the real command must set the label LAST, after any property change."))))

          (pfl:say "")
          (pfl:say "  3. Look at it: walls along the full length, label inside the pipe,")
          (pfl:say "     parallel to it.  Every dynamic property, as the block holds them:")
          (foreach f (pfb:dynvals obj)
            (pfl:say (strcat "        " (pfl:pad (car f) 12) (cdr f))))
          (pfl:say "")
          (pfl:say (if ok "  RESULT: code drives PFPIPE." "  RESULT: FAILURES above."))
          (pfl:say "======================================================")))))
  (princ))


;;; ==========================================================================
;;; SECTION 9  --  PFGRIDTEST: do we read the V5 anchors right?
;;; ==========================================================================
;;; Read only -- changes nothing in the drawing.
;;;   1. Lists every anchor: which line, copy or not, stations, scales, .cl.
;;;   2. Click inside one grid: shows everything V6 read off its anchor.
;;;   3. Click points on that grid (Enter ends): prints the station and
;;;      elevation V6 thinks each one is.  Compare with the grid's own labels --
;;;      if they agree, the transform is right.
;;;   4. Shows where the .cl / .pro / .tin dialogs would open.

(defun pfb:yn (x) (if x x "(none)"))

(defun pfb:file-line (label p)
  (pfl:say (strcat "      " (pfl:pad label 12)
                   (cond ((null p) "(none)")
                         ((findfile p) p)
                         (T (strcat p "   ** FILE NOT FOUND"))))))

(defun c:PFGRIDTEST ( / all g r pt w cl ft)
  (cond
    ((null pfg:grid) (pfl:say "PFGRIDTEST: load pf-load.lsp first."))
    (T
      (pfl:say "")
      (pfl:say "=== PFGRIDTEST ===================================")
      (setq all (pfg:all))
      (pfl:say (strcat "  1. Anchors in model space: " (itoa (length all))
                       "   (looking for " *pf-anchor-blocks* ")"))
      (foreach a all
        (setq g (pfg:grid a))
        (pfl:say (strcat "    "
                         (pfl:pad (pfl:effname a) 16)
                         (pfl:pad (if g (pfg:title g)
                                    (strcat "'" (pfg:att *pf-anc-line* (pfg:atts a)) "'"))
                                  20)
                         (if (pfg:copy-p a) "COPY -- ignored  " "")
                         (cond
                           ((null g) "** numbers unreadable")
                           ((setq r (pfg:sta-range g))
                            (strcat (pfl:fmt-sta (car r)) " to " (pfl:fmt-sta (cadr r))))
                           (T (strcat "from " (pfl:fmt-sta (pfl:g 'sta0 g)) "  (width unknown)")))
                         (if g (strcat "   1\"=" (rtos (pfl:g 'hplot g) 2 0)
                                       "'/" (rtos (pfl:g 'vplot g) 2 0) "'")
                           "")
                         (if (and g (null (pfl:g 'cl g))) "   ** no .cl on record" ""))))

      (pfl:say "")
      (if (and all (setq g (pfg:pick "\n  2. Click inside a profile grid: ")))
        (progn
          (pfl:say (strcat "  2. Grid " (pfg:title g)
                           "   anchor handle " (cdr (assoc 5 (entget (pfl:g 'anchor g))))))
          (pfl:say (strcat "      left edge X   " (rtos (pfl:g 'leftx g) 2 2)
                           "   = STA " (pfl:fmt-sta (pfl:g 'sta0 g))))
          (pfl:say (strcat "      bottom Y      " (rtos (pfl:g 'basey g) 2 2)
                           "   = elev " (pfl:fix (pfl:g 'datum g) 2)))
          (pfl:say (strcat "      top Y         " (rtos (pfl:g 'topy g) 2 2)
                           "   = elev " (pfl:fix (pfl:y->elev (pfl:g 'topy g) g) 2)))
          (pfl:say (strcat "      right X       "
                           (if (pfl:g 'rightx g)
                             (strcat (rtos (pfl:g 'rightx g) 2 2) "   = STA "
                                     (pfl:fmt-sta (pfl:x->sta (pfl:g 'rightx g) g)))
                             "(unknown -- old anchor)")))
          (pfl:say (strcat "      scales        1\"=" (rtos (pfl:g 'hplot g) 2 0)
                           "' H, 1\"=" (rtos (pfl:g 'vplot g) 2 0)
                           "' V   exaggeration x" (pfl:fix (pfl:g 'vscale g) 1)
                           "   text ht " (pfl:fix (pfg:text-ht g) 2)))
          (pfl:say (strcat "      line name     " (pfb:yn (pfg:line-name g))
                           "   (what PFASSIGN files structures under)"))
          (pfb:file-line ".cl" (pfl:g 'cl g))
          (if (pfl:g 'cl g)
            (pfl:say (strcat "      .cl read from "
                             (if (pfg:cl-att (pfg:atts (pfl:g 'anchor g)))
                               (strcat "the anchor's " *pf-anc-cl* " attribute")
                               "V5's stored records (ledger)"))))
          (setq cl (pfg:cl g))
          (if (and cl (pfl:g 'cl g) (/= (strcase cl) (strcase (pfl:g 'cl g))))
            (pfl:say (strcat "      ...found instead at " cl)))
          (pfb:file-line "INV .pro"   (pfl:g 'pro-inv g))
          (pfb:file-line "TOP .pro"   (pfl:g 'pro-top g))
          (pfb:file-line "exist TIN"  (pfl:g 'tin-exist g))
          (pfb:file-line "design TIN" (pfl:g 'tin-design g))
          (pfl:say (strcat "      material      " (pfb:yn (pfl:g 'material g))))

          (pfl:say "")
          (pfl:say "  3. Click points on the grid -- compare with its labels.  Enter ends.")
          (while (setq pt (getpoint "\n     Point: "))
            (setq w (trans pt 1 0))
            (pfl:say (strcat "     STA " (pfl:fmt-sta (pfl:x->sta (car w) g))
                             "   elev " (pfl:fix (pfl:y->elev (cadr w) g) 2)
                             (if (pfg:on-grid-p (pfl:x->sta (car w) g) g) "" "   (off the grid)"))))))

      (pfl:say "")
      (pfl:say (strcat "  4. Project root (tmpdir$): " (pfb:yn (pff:root))))
      (foreach ft '("cl" "pro" "tin")
        (pfl:say (strcat "      ." (pfl:pad ft 4)
                         " firm folder " (pfb:yn (pff:std-dir ft))))
        (pfl:say (strcat "            dialog opens " (pfb:yn (pff:dir ft)))))
      (pfl:say "==================================================")))
  (princ))


;;; ==========================================================================
;;; SECTION 10  --  PFLINETEST: what does the line tree see?
;;; ==========================================================================
;;; READS ONLY -- nothing is written, names included.  For each line: where it
;;; came from (grid or V5 stub), whether its .cl was READ or had to be WALKED
;;; through Carlson, and every structure on it in station order with the name
;;; the tree builds.  A "*" marks a PFNAME that differs from the built one --
;;; PFASSIGN not run since, or typed by hand.  Then everything near a line but not
;;; on it, and every structure on no line.  Lay it next to V5's labels on the
;;; same drawing: the names should match.  A *pf-count-only* block (HDWL, not
;;; ours yet) shows its number in brackets and "(not ours)" -- it is counted,
;;; never named.

(defun c:PFLINETEST ( / lt lines tree index on rows nm cur off none pt)
  (cond
    ((null pfm:lines) (pfl:say "PFLINETEST: load pf-load.lsp first."))
    (T
     (pfc:load)
     (pfl:say "")
     (pfl:say "=== PFLINETEST  (reads only -- changes nothing) =====")
     (setq lt    (pfm:lines)
           lines (car lt))
     (pfl:say (strcat "  " (itoa (length lines)) " line(s)"))
     (foreach l lines
       (pfl:say (strcat "    " (pfl:pad (pfl:g 'lname l) 18)
                        (pfl:pad (pfl:g 'from l) 6)
                        (pfl:pad (if (eq (pfl:g 'kind l) 'read) "read" "WALKED") 8)
                        "STA " (pfl:fmt-sta (car (pfl:g 'rng l))) " to " (pfl:fmt-sta (cadr (pfl:g 'rng l)))
                        "   " (itoa (length (pfl:g 'verts l))) " pts")))
     (foreach s (cdr lt) (pfl:say s))
     (setq tree  (pfm:tree lines)
           index (cdr tree))
     ;; each line, its structures in station order
     (foreach l lines
       (setq rows nil)
       (foreach row (car tree)
         (foreach h (cadr row)
           (if (= (car h) (pfl:g 'lname l))
             (setq rows (cons (list (cadr h) (car row) (caddr h) (cadr row) (cadddr row)) rows)))))
       (if rows
         (progn
           (pfl:say "")
           (pfl:say (strcat "  " (pfl:g 'lname l)))
           (foreach r (mapcar '(lambda (i) (nth i rows)) (vl-sort-i (mapcar 'car rows) '<))
             (if (nth 4 r)
               ;; count-only: takes its number, never named
               (setq nm  (strcat "(" (itoa (pfm:rank (car r) (cdr (assoc (pfl:g 'lname l) index)))) ")")
                     cur (strcat "  " (pfl:effname (nth 1 r)) " (not ours)"))
               (setq nm  (cond ((pfm:name (nth 3 r) index)) ("--"))
                     cur (cond ((pfr:get (nth 1 r) *pf-tag-name*)) (""))
                     cur (strcat (if (/= (strcase cur) (strcase nm)) "* " "  ")
                                 "PFNAME " (if (= cur "") "(blank)" cur))))
             (pfl:say (strcat "    " (pfl:pad (pfl:fmt-sta (car r)) 11)
                              (pfl:pad nm 18)
                              (pfl:pad cur 26)
                              "off " (pfl:fix (nth 2 r) 2)
                              "   " (cdr (assoc 5 (entget (nth 1 r))))))))))
     ;; near a line but not on it, and on no line at all
     (pfl:say "")
     (pfl:say (strcat "  Near a line but NOT on it (within " (pfl:fix *pf-near-tol* 2)
                      "', limit " (pfl:fix *pf-memb-tol* 2) "'):"))
     (setq none T)
     (foreach row (car tree)
       (foreach n (caddr row)
         (setq none nil)
         (pfl:say (strcat "    " (pfm:who (car row)) "  " (pfl:fix (cadr n) 2) "' from " (car n)))))
     (if none (pfl:say "    (none)"))
     (pfl:say "")
     (pfl:say "  On no line:")
     (setq none T)
     (foreach row (car tree)
       (if (null (cadr row))
         (progn
           (setq none nil
                 pt   (cdr (assoc 10 (entget (car row))))
                 off  (pfm:nearest pt lines))
           (pfl:say (strcat "    " (pfm:who (car row))
                            "   at X " (pfl:fix (car pt) 2) "  Y " (pfl:fix (cadr pt) 2)
                            (if off
                              (strcat "   nearest " (car off) ", " (pfl:fix (cadr off) 2) "' away")
                              ""))))))
     (if none (pfl:say "    (none)"))
     (pfl:say "")
     (pfl:say (strcat "  Stacked -- two within " (pfl:fix *pf-stack-tol* 2) "', one on top of the other:"))
     (setq none T)
     (foreach s (pfm:stacked (car tree))
       (setq none nil)
       (pfl:say (strcat "    " (pfm:who (car s)) "  and  " (pfm:who (cadr s))
                        "   " (pfl:fix (caddr s) 2) "' apart")))
     (if none (pfl:say "    (none)"))
     (pfl:say "==================================================")))
  (princ))


;;; ==========================================================================
;;; SECTION 11  --  PFSELFTEST: the test sheet's checks, run by code
;;; ==========================================================================
;;; One command, no picks (Jake, 2026-10-27: "is there a better way to test
;;; this?").  It makes its own test blocks -- two plan CBIs far out in model
;;; space and a pipe inside the first grid -- drives the REAL suite code
;;; against them, and prints PASS / FAIL per check with what it got.  Then it
;;; erases everything it made.  The real drawing's blocks are only READ.
;;; One undo group around the lot, as a backstop.
;;;
;;; Headless testing was tried first (AutoCAD Core Console, 2026-10-27): its
;;; ActiveX is off, so no dynamic block is recognised -- this is why it runs
;;; here, in the real AutoCAD.  ADD A GROUP HERE WITH EVERY NEW FEATURE.

;; (pfb:st label got want tol) -> T | nil.  Counts into the caller's n-pass /
;;   n-fail (PFSELFTEST's locals, seen through dynamic scope).
(defun pfb:st (label got want tol / ok)
  (setq ok (if tol (equal got want tol) (equal got want)))
  (if ok (setq n-pass (1+ n-pass)) (setq n-fail (1+ n-fail)))
  (pfl:say (strcat "  " (if ok "PASS  " "FAIL  ") label))
  (if (not ok)
    (progn
      (pfl:say (strcat "          wanted " (vl-prin1-to-string want)))
      (pfl:say (strcat "          got    " (vl-prin1-to-string got)))))
  ok)

;; (pfb:st-run label fn) -> fn's result | nil.  A group that errors is a FAIL
;;   with the error, and the run goes on.
(defun pfb:st-run (label fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r)
    (progn
      (setq n-fail (1+ n-fail))
      (pfl:say (strcat "  FAIL  " label " -- stopped: " (vl-catch-all-error-message r)))
      nil)
    r))

;; (pfb:st-cbi pt name) -> a test plan CBI at pt, on line STORM_ZZ | nil
(defun pfb:st-cbi (pt name / e)
  (if (setq e (pfd:insert (cadr (assoc 'CBI *pf-blocks*)) pt))
    (progn
      (setq made (cons e made))
      (pfr:put e *pf-tag-view* *pf-view-plan*)
      (pfr:put e *pf-tag-name* name)
      (pfr:put e *pf-tag-rim* "750.00")
      (pfr:memb-put e '(("STORM_ZZ" 100.0 0.0)))))
  e)

;; --- group 1: label rows from the attributes, per block type ---------------
(defun pfb:st-labels ( / far a b def rows fmts res)
  (pfl:say "")
  (pfl:say "  1. Structure label rows (prefix / suffix attributes, per type)")
  (setq far (list 1.0e7 1.0e7)
        a   (pfb:st-cbi far "ZZ-1")
        b   (pfb:st-cbi (list (+ (car far) 50.0) (cadr far)) "ZZ-2"))
  (cond
    ((not (and a b)) (setq n-fail (1+ n-fail)) (pfl:say "  FAIL  could not insert test CBIs"))
    (T
     (setq def (pfs:fmt-defaults "CBI"))
     (pfb:st "CBI default PFCONPRE" (pfr:input *pf-tag-con-pre* def) "CONST. CURB BOX INLET" nil)
     (pfb:st "CBI default PFELEVPRE" (pfr:input *pf-tag-elev-pre* def) "G.L." nil)
     (pfb:st "HDWL default PFELEVPRE (no row)" (pfr:input *pf-tag-elev-pre* (pfs:fmt-defaults "HDWL")) "" nil)
     (pfb:st "type of a CBI insert" (pfs:type-of a) "CBI" nil)

     (setq fmts (list (cons "CBI" def))
           rows (pfs:rows a fmts "STORM_ZZ"))
     (pfb:st "PFCON = PFCONPRE + PFNAME" (cdr (assoc "PFCON" rows)) "CONST. CURB BOX INLET ZZ-1" nil)
     (pfb:st "PFELEV = PFELEVPRE + rim" (cdr (assoc "PFELEV" rows)) "G.L. 750.00" nil)
     (pfb:st "PFTEXT2 blank" (cdr (assoc "PFTEXT2" rows)) "" nil)
     (pfb:st "PFSTA1" (cdr (assoc "PFSTA1" rows)) "STA. 1+00.00 STORM LINE 'ZZ'" nil)

     (setq fmts (list (cons "CBI" (subst (cons *pf-tag-con-pre* "CONST. 4' DRAINAGE MH")
                                         (assoc *pf-tag-con-pre* def) def)))
           rows (pfs:rows a fmts "STORM_ZZ"))
     (pfb:st "new PFCONPRE -- no type wording added" (cdr (assoc "PFCON" rows)) "CONST. 4' DRAINAGE MH ZZ-1" nil)

     (setq fmts (list (cons "CBI" (subst (cons *pf-tag-con-suf* "(PROP.)")
                                         (assoc *pf-tag-con-suf* def) def)))
           rows (pfs:rows a fmts "STORM_ZZ"))
     (pfb:st "PFCONSUF at the end" (cdr (assoc "PFCON" rows)) "CONST. CURB BOX INLET ZZ-1 (PROP.)" nil)

     (setq fmts (list (cons "CBI" (subst (cons *pf-tag-elev-pre* "")
                                         (assoc *pf-tag-elev-pre* def) def)))
           rows (pfs:rows a fmts "STORM_ZZ"))
     (pfb:st "blank PFELEVPRE -- no elevation row" (cdr (assoc "PFELEV" rows)) "" nil)

     (setq fmts (list (cons "DBI" (pfs:fmt-defaults "DBI")) (cons "CBI" def)))
     (pfb:st "a CBI takes the CBI inputs, not another type's"
             (pfr:input *pf-tag-con-pre* (pfs:fmt-for a fmts)) "CONST. CURB BOX INLET" nil)

     ;; the sync, on the two test CBIs only
     (pfr:put a *pf-tag-con-pre* "CONST.") (pfr:src-put a *pf-tag-con-pre* *pf-src-rule* "CONST.")
     (pfr:put b *pf-tag-con-pre* "CONST.") (pfr:src-put b *pf-tag-con-pre* *pf-src-rule* "CONST.")
     (setq res (pfr:sync-inputs (list a b) *pf-tags-fmt* def *pf-fmt-retired*))
     (pfb:st "retired CONST. -> the type's new default" (pfr:get b *pf-tag-con-pre*) "CONST. CURB BOX INLET" nil)

     (pfr:put a *pf-tag-con-pre* "CONST. 4' DRAINAGE MH")
     (setq res (pfr:sync-inputs (list a b) *pf-tags-fmt* def *pf-fmt-retired*))
     (pfb:st "PFCONPRE typed on one goes to the other" (pfr:get b *pf-tag-con-pre*) "CONST. 4' DRAINAGE MH" nil)

     (pfr:put a *pf-tag-con-pre* "ONE") (pfr:put b *pf-tag-con-pre* "TWO")
     (setq res (pfr:sync-inputs (list a b) *pf-tags-fmt* def *pf-fmt-retired*))
     (pfb:st "two different typed -- old one kept" (pfr:input *pf-tag-con-pre* (car res)) "CONST. 4' DRAINAGE MH" nil)
     (pfb:st "two different typed -- reported"
             (and (vl-some '(lambda (s) (wcmatch s "*typed differently*")) (cdr res)) T) T nil)

     (pfb:st "PFELEVPRE on the block (else PFMKATT + ATTSYNC)"
             (and (pfr:attr-ent a *pf-tag-elev-pre*) T) T nil)

     (pfb:st "typed PFCON keeps its words, prefix swapped"
             (pfs:swap-prefix "CONST. MY WORDS ZZ-1" "CONST." "CONST. CURB BOX INLET")
             "CONST. CURB BOX INLET MY WORDS ZZ-1" nil)
     (pfb:st "typed PFCON not starting with the old prefix -- left alone"
             (pfs:swap-prefix "MY WORDS ZZ-1" "CONST." "CONST. CURB BOX INLET") nil nil))))

;; --- group 2: pipe label inside / outside the pipe ------------------------
(defun pfb:st-pipe ( / g p1 p2 e obj ends mid dia cen inside outside lead)
  (pfl:say "")
  (pfl:say "  2. Pipe label (inside goes back to the centre, outside stays on a leader)")
  (cond
    ((null (tblsearch "BLOCK" *pf-pipe-block*))
     (pfl:say (strcat "  SKIP  no " *pf-pipe-block* " in this drawing")))
    ((null (setq g (car (pfg:usable))))
     (pfl:say "  SKIP  no usable grid"))
    (T
     (setq p1 (list (+ (pfl:g 'leftx g) 40.0) (+ (pfl:g 'basey g) 30.0))
           p2 (list (+ (car p1) 80.0) (- (cadr p1) 2.0)))
     (if (null (setq e (pfd:insert *pf-pipe-block* p1)))
       (progn (setq n-fail (1+ n-fail)) (pfl:say "  FAIL  could not insert a test pipe"))
       (progn
         (setq made (cons e made)
               obj  (vlax-ename->vla-object e))
         (pfr:put e *pf-pipe-size* "15\"")
         (pfd:dynprop-put obj *pf-pipe-run-x* (- (car p2) (car p1)))
         (pfd:dynprop-put obj *pf-pipe-run-y* (- (cadr p2) (cadr p1)))
         (pfd:dynprop-put obj *pf-pipe-vis* *pf-pipe-state-plain*)
         (pfp:update e g *pf-pipe-fmt-defaults*)
         (setq ends (pfp:ends e)
               mid  (pfp:mid ends)
               dia  (* (/ 15.0 12.0) (pfl:g 'vscale g))
               cen  (list (car mid) (+ (cadr mid) (/ dia 2.0)))
               inside  (list (+ (car mid) 20.0) (+ (cadr mid) (/ dia 2.0) -0.5))
               outside (list (+ (car mid) 15.0) (+ (cadr mid) dia 12.0)))
         (pfb:st "never dragged -- at the centre" (pfp:pt-get e *pf-pipe-lead*) cen 0.01)
         (pfb:st "never dragged -- no leader" (length (pfp:leaders e)) 0 nil)

         (pfp:pt-put e *pf-pipe-lead* inside)
         (pfp:update e g *pf-pipe-fmt-defaults*)
         (pfb:st "dragged inside -- back to the centre" (pfp:pt-get e *pf-pipe-lead*) cen 0.01)

         (pfp:pt-put e *pf-pipe-lead* outside)
         (pfp:update e g *pf-pipe-fmt-defaults*)
         (pfb:st "dragged outside -- stays" (pfp:pt-get e *pf-pipe-lead*) outside 0.01)
         (pfb:st "dragged outside -- one leader" (length (pfp:leaders e)) 1 nil)
         (setq made (append (pfp:leaders e) made))
         (pfb:st "dragged outside -- level" (cdr (assoc 50 (entget (pfr:attr-ent e *pf-pipe-label*)))) 0.0 1e-6)

         (pfp:update e g *pf-pipe-fmt-defaults*)
         (pfb:st "refreshed again -- still where it was put" (pfp:pt-get e *pf-pipe-lead*) outside 0.01)

         (pfp:pt-put e *pf-pipe-lead* inside)
         (pfp:update e g *pf-pipe-fmt-defaults*)
         (pfb:st "dragged back inside -- centre again" (pfp:pt-get e *pf-pipe-lead*) cen 0.01)
         (pfb:st "dragged back inside -- leader gone" (length (pfp:leaders e)) 0 nil)

         ;; group 3 needs a pipe in a grid -- hand it over
         (list e g))))))

;; --- group 3: refresh scope -------------------------------------------------
(defun pfb:st-scope (cbi pipe-g / sc)
  (pfl:say "")
  (pfl:say "  3. PFREFRESH scope")
  (setq sc '("Line" "STORM_AA"))
  (pfb:st "Line: a copy on that line is in"   (pfu:copy-in-p nil "1A" "STORM_AA" sc) T nil)
  (pfb:st "Line: a copy on another line is out" (pfu:copy-in-p nil "1A" "STORM_BA" sc) nil nil)
  (pfb:st "Drawing: everything is in" (pfu:copy-in-p nil "1A" "STORM_BA" '("Drawing")) T nil)
  (if cbi
    (progn
      (pfb:st "Selected: a picked copy is in" (pfu:copy-in-p cbi nil "STORM_BA" (list "Selected" cbi)) T nil)
      (pfb:st "Selected: a picked plan brings its copies"
              (pfu:copy-in-p nil (pfl:handle cbi) "STORM_ZZ" (list "Selected" cbi)) T nil)
      (pfb:st "Line pick on a plan structure -> its lines" (pfu:lines-at cbi nil) '("STORM_ZZ") nil)
      (pfb:st "Plan structure on the line is in" (and (pfu:plan-in-p cbi '("Line" "STORM_ZZ")) T) T nil)
      (pfb:st "Plan structure on another line is out" (and (pfu:plan-in-p cbi '("Line" "STORM_AA")) T) nil nil)))
  (if pipe-g
    (pfb:st "Line pick on a pipe -> its grid's line"
            (pfu:lines-at (car pipe-g) nil) (list (pfg:line-name (cadr pipe-g))) nil)))

;; --- group 4: line tree pieces ----------------------------------------------
(defun pfb:st-tree ( / ss h)
  (pfl:say "")
  (pfl:say "  4. Line tree (numbers, names, headwalls)")
  (pfb:st "rank: 4 below -> 5" (pfm:rank 409.69 '(115.59 151.41 320.0 342.04 409.69)) 5 nil)
  (pfb:st "junction name, lines A-Z"
          (pfm:name '(("STORM_BC" 300.0 0.0 "STORM" "BC") ("STORM_BA" 409.69 0.0 "STORM" "BA"))
                    '(("STORM_BA" 115.59 151.41 320.0 342.04 409.69) ("STORM_BC" 300.0 322.08)))
          "BA-5/BC-1" nil)
  (pfb:st "a crossing utility is not in the name"
          (pfm:name '(("STORM_BA" 409.69 0.0 "STORM" "BA") ("WATER_A" 900.0 0.1 "WATER" "A"))
                    '(("STORM_BA" 409.69) ("WATER_A" 900.0)))
          "BA-1" nil)
  (pfb:st "MEMB same to the thousandth" (pfm:memb-same-p '(("A" 1.0 0.0)) '(("A" 1.0004 0.0))) T nil)
  (pfb:st "MEMB moved" (pfm:memb-same-p '(("A" 1.0 0.0)) '(("A" 1.5 0.0))) nil nil)
  (if (setq ss (ssget "_X" '((0 . "INSERT") (2 . "HDWL,HDWL_*"))))
    (pfb:st (strcat "headwall " (pfl:effname (ssname ss 0)) " counts")
            (pfm:count-only-p (ssname ss 0)) T nil)
    (pfl:say "  SKIP  no HDWL block in this drawing")))

;; (c:PFSELFTEST) -- run every group, clean up, total
(defun c:PFSELFTEST ( / n-pass n-fail made doc cbi pipe-g t0)
  (cond
    ((null pfu:copy-in-p) (pfl:say "PFSELFTEST: load pf-load.lsp first."))
    ((= 1 (getvar "BLOCKEDITOR")) (pfl:say "PFSELFTEST: close the Block Editor first."))
    (T
     (setq n-pass 0 n-fail 0 t0 (getvar "MILLISECS")
           doc (vla-get-activedocument (vlax-get-acad-object)))
     (pfc:load)
     (vla-startundomark doc)
     (pfl:say "")
     (pfl:say "=== PFSELFTEST  (makes its own test blocks, erases them after) ===")
     (pfb:st-run "label rows" 'pfb:st-labels)
     (setq cbi    (car (vl-remove-if-not '(lambda (e) (pfr:ours-p e)) made))
           pipe-g (pfb:st-run "pipe label" 'pfb:st-pipe))
     (pfb:st-run "scope" '(lambda () (pfb:st-scope cbi pipe-g)))
     (pfb:st-run "line tree" 'pfb:st-tree)
     ;; clean up -- everything this run made, and any leader a test pipe
     ;; still has (a group that stopped part-way may leave one)
     (foreach e made
       (if (and (entget e) (pfp:pipe-p e))
         (foreach l (pfp:leaders e) (vl-catch-all-apply 'pfd:erase (list l)))))
     (foreach e made (vl-catch-all-apply 'pfd:erase (list e)))
     (vla-endundomark doc)
     (pfl:say "")
     (pfl:say (strcat "  " (itoa n-pass) " passed, " (itoa n-fail) " failed   ("
                      (itoa (length made)) " test object(s) made and erased, "
                      (pfl:fix (/ (max 0 (- (getvar "MILLISECS") t0)) 1000.0) 2) "s)"))
     (pfl:say "==================================================")))
  (princ))


(prompt "\npf-bench loaded (workbench, not a module).  PFMKATT / PFSEL / PFGATE / PFSWAP / PFRECTEST / PFSYNCTEST / PFPIPETEST / PFGRIDTEST / PFLINETEST / PFSELFTEST.")
(princ)
