;;; ==========================================================================
;;; pf-struct.lsp  --  PFSTRUCT: place the structures on one profile.
;;; Load position 10: after pf-index, pf-draw.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; ONE command places every structure type (Jake, 2026-10-15).  Was PFDRAW.
;;;
;;; "PLACE STRUCTURES IN PROFILE" (Jake, 2026-10-16).  No grid pick:
;;;   1. grid by grid: every alpha block on the line with NO profile copy
;;;      yet gets one, on the grid that shows its station
;;;   2. fills each new copy's drafter inputs (STA prefix etc.) from the saved
;;;      defaults -- line, then utility, then drawing, then built-in (pf-defaults)
;;;   3. writes its label rows, puts them at the grid top, and fits its
;;;      station line up to the first row
;;; Copies already placed are left alone.  From then on PFREFRESH carries
;;; them: updates (a plan block re-stationed by PFASSIGN included), erasing
;;; orphans and duplicates (the original copy is kept).  Says what it did,
;;; grouped by grid.  One UNDO takes it back.
;;;
;;; STRUCTURES ONLY (Jake, 2026-10-15).  Pipes play no part: the drafter puts
;;; them in later with PFPIPE, and this neither reads nor changes them.  The
;;; barrel depth is the drafter's too (PFDEPTH grip) and is never touched.
;;;
;;; Nothing on a profile holds facts of its own -- the plan record is the
;;; truth -- so running it again is always safe.  A label row typed over by
;;; hand is kept.
;;; ==========================================================================


;;; ==========================================================================
;;; SECTION 1  --  The drafter inputs
;;; ==========================================================================
;;; PFSTAPRE / PFSTASUF / PFCONPRE / PFCONSUF / PFELEVPRE / PFELEVSUF live on
;;; every profile copy.  Each block type has its own BUILT-IN defaults
;;; (*pf-type-fmt* over *pf-fmt-defaults*).  On top of those, the drawing,
;;; a utility, or one line can carry SAVED defaults (the Defaults dialog,
;;; PFDEFAULTS; pf-defaults resolves them: line, utility, drawing, built-in).
;;; A value typed on one copy stays on that copy only (Jake, 2026-11-17:
;;; keep this; it replaces the 2026-10-27 push to every block of a type).
;;;
;;; Production runs pass fmt nil: each copy resolves its own (pfv:inputs).
;;; PFSELFTEST may still hand in explicit FMTS -- ((type . ((tag . value)
;;; ...)) ...), built by pfs:sync-fmt-in over its own test blocks -- so a
;;; test never reads or writes the drawing's saved defaults.  Whatever builds
;;; a row takes its own type's out with pfs:fmt-for.

;; (pfs:type-of e) -> "CBI" -- the *pf-blocks* key of e's block | nil
(defun pfs:type-of (e / row)
  (if (setq row (pfr:row-for (pfl:effname e))) (vl-symbol-name (car row))))

;; NEVER name a local after a built-in: AutoLISP keeps one value per symbol,
;; so a local TYPE holding "CBI" made every (type x) inside the call "bad
;; function: CBI" (PFSELFTEST, 2026-10-30).  Hence TY.

;; (pfs:fmt-defaults ty) -> ((tag . default) ...) for that block type
(defun pfs:fmt-defaults (ty / over)
  (setq over (cdr (assoc ty *pf-type-fmt*)))
  (mapcar '(lambda (d) (cond ((assoc (car d) over)) (d))) *pf-fmt-defaults*))

;; (pfs:fmt-for e fmts) -> e's type's inputs.  A type no block of carried
;;   (nothing synced) gets its defaults.
(defun pfs:fmt-for (e fmts / ty)
  (setq ty (pfs:type-of e))
  (cond ((cdr (assoc ty fmts))) ((pfs:fmt-defaults ty))))

;; (pfs:sync-fmt) -> (fmts . notes)   every structure in the drawing.
;;   Diagnostic only since 2026-11-17 -- no production command calls it.
(defun pfs:sync-fmt () (pfs:sync-fmt-in (pfr:all nil)))

;; (pfs:sync-fmt-in ents) -> (fmts . notes)   explicit inputs for these
;;   structures, one block type at a time -- what PFSELFTEST hands in.
(defun pfs:sync-fmt-in (ents / groups ty c res fmts notes)
  (foreach e ents
    (if (setq ty (pfs:type-of e))
      (setq groups (if (setq c (assoc ty groups))
                     (subst (cons ty (cons e (cdr c))) c groups)
                     (cons (list ty e) groups)))))
  (foreach g (reverse groups)
    (setq res  (pfr:sync-inputs (cdr g) *pf-tags-fmt* (pfs:fmt-defaults (car g)) *pf-fmt-retired*)
          fmts (cons (cons (car g) (car res)) fmts))
    (foreach s (cdr res) (setq notes (cons (strcat "  [" (car g) "]" s) notes)))
    ;; an input no block of this type carries yet -- its default is used
    (foreach tag *pf-tags-fmt*
      (if (not (vl-some '(lambda (e) (pfr:attr-ent e tag)) (cdr g)))
        (setq notes (cons (strcat "  ** " (car g) " blocks have no " tag " attribute -- using \""
                                  (pfr:input tag (pfs:fmt-defaults (car g)))
                                  "\".  BEDIT the block, PFMKATT, then ATTSYNC.")
                          notes)))))
  (cons (reverse fmts) (reverse notes)))


;;; ==========================================================================
;;; SECTION 2  --  The run's picture of the drawing
;;; ==========================================================================
;;; The run context handed to pfs:struct-update is an alist; today it holds
;;;   'top     the grid-top lines (pfg:top-lines), read once per run
;;; The invert step (pf-pipe, later) adds 'grids / 'copies / 'pipes.

;; (pfs:copies) -> every profile copy, as (ename plan line anchor x)
(defun pfs:copies () (pfs:copies-if nil))

;; (pfs:copies-if keep) -> the profile copies keep says yes to, as above.
;;   keep: nil (all), or a function of (ename plan line) asked BEFORE the
;;   copy's grid is looked up -- the costly part -- so a scoped PFREFRESH
;;   skips it for copies it leaves alone.
;;   The anchors are read once for the whole list (pfg:index, 2026-11-20),
;;   and only when a copy is kept.
(defun pfs:copies-if (keep / out pt plan line xd idx)
  (foreach e (pfr:all *pf-view-pro*)
    (setq xd   (pfr:xd-pairs e)
          plan (pfr:deser (cdr (assoc *pf-xd-plan* xd)))
          line (pfr:deser (cdr (assoc *pf-xd-line* xd))))
    (if (or (null keep) (apply keep (list e plan line)))
      (setq idx (cond (idx) ((pfg:index)))
            pt  (pfl:ins e)
            out (cons (list e plan line (pfg:anchor-of-in pt idx) (car pt)) out))))
  (reverse out))

(defun pfs:ctx (k ctx) (cdr (assoc k ctx)))


;;; ==========================================================================
;;; SECTION 3  --  One structure's label rows
;;; ==========================================================================

;; (pfs:sta-suffix lname fmt) -> the station suffix for this line:
;;   PFSTASUF with [util] and [line] filled in -- "STORM LINE 'AA'".
;;   The split is pfl:line-parts, shared with the line tree.
(defun pfs:sta-suffix (lname fmt / parts)
  (setq parts (pfl:line-parts lname))
  (vl-string-trim " "
    (pfl:subst-all (cdr parts) "[line]"
      (pfl:subst-all (car parts) "[util]" (pfr:input *pf-tag-sta-suf* fmt)))))

;; (pfs:memb-order memb lname) -> MEMB with this grid's line first, then the
;;   other lines A-Z -- the station-row order for a shared structure (Jake's
;;   standard, 2026-10-16; V5's sta-infos did the same).
(defun pfs:memb-order (memb lname)
  (append (vl-remove-if-not '(lambda (m) (= (car m) lname)) memb)
          (vl-sort (vl-remove-if '(lambda (m) (= (car m) lname)) memb)
                   '(lambda (a b) (< (car a) (car b))))))

;; (pfs:rows plan fmts lname) -> ((tag . text) ...) for the six label rows
;;   V5's pf:build-label-rows: one station row per line the structure is on
;;   (" =" on all but the last), then construction, second text, elevation.
;;   lname is the line of the grid being drawn: its row comes first.
;;     STA. 4+09.69 STORM LINE 'BA' =
;;     STA. 3+00.00 STORM LINE 'BC'
;;     CONST. CURB BOX INLET BA-5/BC-1   PFCONPRE + PFNAME + PFCONSUF
;;     G.L. 758.25                       PFELEVPRE + rim + PFELEVSUF
;;   Built from the attributes ONLY -- no wording from a table (Jake,
;;   2026-10-27).  PFTEXT2 is the drafter's: blank unless typed.  A blank
;;   PFELEVPRE draws no elevation row.  HDWL uses that prefix for PFINV1
;;   instead, so its flowline is printed at the headwall, not at the grid top.
;;   A drafter types over any row that should read differently, and it is kept.
(defun pfs:rows (plan fmts lname / fmt memb sta-rows i n con elev rim out)
  (setq fmt   (pfs:fmt-for plan fmts)
        memb  (pfs:memb-order (pfr:memb-get plan) lname)
        n     (length memb)
        i     0)
  (foreach m memb
    (setq i (1+ i)
          sta-rows (cons (strcat (pfl:join (list (pfr:input *pf-tag-sta-pre* fmt)
                                                 (pfl:fmt-sta (cadr m))
                                                 (pfs:sta-suffix (car m) fmt)))
                                 (if (< i n) " =" ""))
                         sta-rows)))
  (setq sta-rows (reverse sta-rows)
        con  (pfl:join (list (pfr:input *pf-tag-con-pre* fmt)
                             (pfr:get plan *pf-tag-name*)
                             (pfr:input *pf-tag-con-suf* fmt)))
        rim  (pfr:get plan *pf-tag-rim*)
        elev (if (and (/= "HDWL" (pfs:type-of plan))
                      (/= "" (vl-string-trim " " (pfr:input *pf-tag-elev-pre* fmt))))
               (pfl:join (list (pfr:input *pf-tag-elev-pre* fmt)
                               (if (pfl:number-p rim) (pfl:fix (distof rim 2) 2) *pf-elev-placeholder*)
                               (pfr:input *pf-tag-elev-suf* fmt)))
               ""))
  (setq i 0)
  (foreach tag (list "PFSTA1" "PFSTA2" "PFSTA3")
    (setq out (cons (cons tag (cond ((nth i sta-rows)) (""))) out) i (1+ i)))
  (reverse (append (list (cons "PFELEV" elev)
                         (cons "PFTEXT2" "")
                         (cons "PFCON" con))
                   out)))

;; (pfs:copy-fp pe plan g fmts top) -> fingerprint of everything this profile
;;   copy is built from, and of what the tool left on it.  The same answer
;;   next time = nothing changed = PFREFRESH leaves the copy alone.
;;   Built from: where the copy sits; the alpha block's lines, rim, name,
;;   type, face and size; its type's shared inputs (another type's change
;;   leaves it alone); the grid's numbers; the grid top at this station; the
;;   station line's top; each label row's text and position (so a row typed
;;   over, moved, or reset by ATTSYNC is noticed).
(defun pfs:copy-fp (pe plan g fmts top / px)
  (setq px (car (pfl:ins pe)))
  (pfl:fingerprint
    (list *pf-fp-ver*
          (pfl:ins pe)
          (pfl:effname plan)
          (pfr:memb-get plan)
          (mapcar '(lambda (tg) (pfr:get plan tg))
                  (list *pf-tag-rim* *pf-tag-name* *pf-tag-type* *pf-tag-face* *pf-tag-size*))
          (vl-princ-to-string (pfl:dynprop-get (vlax-ename->vla-object plan) *pf-param-size*))
          (if fmts (pfs:fmt-for plan fmts)
            (pfv:fp-inputs pe (pfg:line-name g) "STRUCT" (pfs:type-of plan)
                           *pf-tags-fmt* (pfs:fmt-defaults (pfs:type-of plan))))
          (mapcar '(lambda (k) (pfl:g k g)) '(leftx basey sta0 datum vscale hplot))
          (pfg:top-at px g top)
          (pfl:end-y pe 'top)
          (mapcar '(lambda (tg) (list (pfr:get pe tg) (pfr:att-pt pe tg))) *pf-tags-row*)
          (if (= "HDWL" (pfs:type-of plan))
            (list (pfr:get pe "PFINV1") (pfr:att-pt pe "PFINV1"))))))

;; (pfs:headwall-bottom pe) -> WORLD Y of the lowest geometry showing on the
;;   headwall's profile copy: its own lines and its nested profile symbol.
;;   The symbol reaches below the flowline, so the invert label must clear it,
;;   not just the basepoint.  Read off what the insert SHOWS, so no nested
;;   block name is needed here (pf-cfg owns names).  Nothing found: the
;;   basepoint -- the flowline.
(defun pfs:headwall-bottom (pe / ys)
  (setq ys (vl-remove nil (list (pfl:nested-bottom pe) (pfl:geom-bottom pe))))
  (if ys (apply 'min ys) (cadr (pfl:ins pe))))

;; (pfs:struct-update pe plan g ctx fmts) -> notes
;;   fmts nil = this copy's saved defaults (production); explicit = a test's.
;;   Label rows, their place at the grid top, and the station line's top.
;;   Pipes play no part, so nothing about a pipe can stop a structure being
;;   drawn.  Non-headwall barrel depth is the drafter's (PFDEPTH grip).
(defun pfs:struct-update (pe plan g ctx fmt / notes rows r kept ht px gtop off gap
                            base live i x res row1 moved held default-run hw inv-moved inv-held inv-pt inv-r inv-bottom)
  (setq *pfd-stage* "composing the label rows")
  (setq default-run (null fmt))
  (if (null fmt)
    (setq fmt (list (cons (pfs:type-of plan)
                          (pfv:inputs pe (pfg:line-name g) "STRUCT" (pfs:type-of plan)
                                      *pf-tags-fmt* (pfs:fmt-defaults (pfs:type-of plan)))))))
  (setq hw   (= "HDWL" (pfs:type-of plan))
        inv-moved (if hw (pfr:moved-p pe "PFINV1" (pfl:ins pe)))
        inv-held (if inv-moved (pfr:att-pt pe "PFINV1"))
        ht   (pfg:text-ht g)
        px   (car (pfl:ins pe))
        rows (pfs:rows plan fmt (pfg:line-name g))
        ;; which rows a drafter MOVED -- read before anything changes, since a
        ;; parameter change can shift attributes (Jake, 2026-10-16: a CBI row
        ;; moved by hand is left where it is, same as a pipe row)
        ;; measured against the copy's insertion point: rows that travelled
        ;; with the copy (a new rim, a re-station) were not moved by hand
        moved (mapcar '(lambda (tg) (cons tg (pfr:moved-p pe tg (pfl:ins pe)))) *pf-tags-row*)
        ;; and where each of those is now, to put it back after the refit
        held  (vl-remove nil (mapcar '(lambda (m) (if (cdr m) (cons (car m) (pfr:att-pt pe (car m))))) moved)))
  (if (> (length (pfr:memb-get plan)) 3)
    (setq notes (cons "      ** on more than 3 lines -- only 3 station rows fit" notes)))

  ;; the text first -- hand-typed rows are kept
  (setq *pfd-stage* "writing the label text")
  (foreach row rows
    (setq r (pfr:refresh pe (car row) (cdr row) *pf-src-rule*))
    (if (member r '(kept adopted)) (setq kept (cons (car row) kept))))
  (if kept
    (setq notes (cons (strcat "      typed over by hand, kept: " (pfl:join (reverse kept))) notes)))

  ;; geometry: the rows sit on the grid top.  No grid top found at this
  ;; station: say so, and put them *pf-top-default* text heights above the
  ;; structure instead (Jake, 2026-10-16).
  (setq *pfd-stage* "finding the grid top")
  (setq off  (* ht *pf-draw-row-offset*)
        gap  (* ht *pf-draw-row-gap*)
        gtop (pfg:top-at px g (pfs:ctx 'top ctx)))
  (if (null gtop)
    (setq gtop  (+ (cadr (pfl:ins pe)) (* ht *pf-top-default*))
          notes (cons (strcat "      ** no grid top (" *pf-top-layer* ") found at this station"
                              " -- labels put " (rtos (* ht *pf-top-default*) 2 1)
                              "' above the structure")
                      notes)))
  (setq base (+ gtop off)
        live (vl-remove-if '(lambda (t2) (= "" (cond ((pfr:get pe t2)) (""))))
                           (append *pf-tags-row*)))

  ;; parameters BEFORE the attributes: a property change rebuilds the insert
  ;; the line's top: level with the end of the FIRST row's text, " ="
  ;; ignored, as V5 drew it (Jake, 2026-10-16 -- back from longest-row)
  (setq *pfd-stage* "fitting PFTOP")
  (setq row1 (car live))
  (setq res (pfd:fit-end pe *pf-param-top* 'top
              (if row1
                (+ base (pfl:text-len (vl-string-right-trim " =" (pfr:get pe row1))
                                      ht (pfr:att-style pe row1)))
                gtop)))
  (if (/= res T) (setq notes (cons (strcat "      top: " res) notes)))
  ;; PFDEPTH is NOT touched: the barrel depth is the drafter's, set with its
  ;; grip (Jake, 2026-10-15).

  ;; a row moved by hand goes back where the drafter left it: the refit
  ;; rebuilds the insert, and a row can ride it (PFSELFTEST, 2026-10-30)
  (foreach h held
    (if (and (cdr h) (> (distance (pfr:att-pt pe (car h)) (cdr h)) 1e-6))
      (pfr:att-move pe (car h) (cdr h))))

  ;; label rows -- V5's layout: rotated to read up, first row left of the
  ;; station line, the rest to its right.  Blank rows take no column.  A row
  ;; moved by hand is left where it is; where each one went is remembered.
  (setq *pfd-stage* "placing the label rows")
  (setq i 0)
  (foreach tag live
    (setq x (if (= i 0) (- px off) (+ px off (* gap (1- i)))))
    (if (cdr (assoc tag moved))
      (setq notes (cons (strcat "      " tag " moved by hand -- left where it is") notes))
      (progn
        (pfr:att-place pe tag (list x base) ht (/ pi 2.0) 'ML)
        (pfr:pos-put pe tag (list x base) (pfl:ins pe))))
    (setq i (1+ i)))

  ;; A headwall's PFRIM is the flowline invert at its basepoint.  Print it in
  ;; the first invert slot below that point, leaving the top elevation row
  ;; blank.  Other structure inverts await the pipe invert-label step.
  (if hw
    (progn
      (setq inv-r (pfr:refresh pe "PFINV1"
                    (pfl:join (list (pfr:input *pf-tag-elev-pre* (pfs:fmt-for plan fmt))
                                    (if (pfl:number-p (pfr:get plan *pf-tag-rim*))
                                      (pfl:fix (distof (pfr:get plan *pf-tag-rim*) 2) 2)
                                      *pf-elev-placeholder*)
                                    (pfr:input *pf-tag-elev-suf* (pfs:fmt-for plan fmt))))
                    *pf-src-rule*)
            inv-bottom (pfs:headwall-bottom pe)
            inv-pt (list px (- inv-bottom (* ht *pf-inv-drop-factor*))))
      (if (member inv-r '(kept adopted))
        (setq notes (cons "      PFINV1 typed over by hand -- kept" notes)))
      (if inv-moved
        (progn
          (if (and inv-held (> (distance (pfr:att-pt pe "PFINV1") inv-held) 1e-6))
            (pfr:att-move pe "PFINV1" inv-held))
          (setq notes (cons "      PFINV1 moved by hand -- left where it is" notes)))
        (progn
          (pfr:att-place pe "PFINV1" inv-pt ht (/ pi 2.0) 'ML)
          (pfr:pos-put pe "PFINV1" inv-pt (pfl:ins pe))))))

  ;; what PFREFRESH compares against next time
  (pfr:stamp-put pe (pfs:copy-fp pe plan g (if default-run nil fmt) (pfs:ctx 'top ctx)))
  (reverse notes))


;;; ==========================================================================
;;; SECTION 4  --  Placing the copies
;;; ==========================================================================

;; (pfs:find-copy handle lname copies) -> ename | nil   copies from pfs:copies
(defun pfs:find-copy (handle lname copies / hit)
  (foreach c copies
    (if (and (null hit) (= handle (nth 1 c)) (= lname (nth 2 c)))
      (setq hit (car c))))
  hit)

;; (pfs:copy-y plan g x top) -> the Y a copy sits at | nil
;;   At its rim -- or, with no rim yet, on the grid's top line at x (Jake,
;;   2026-11-13: "Structures can be placed on the top grid line until a
;;   elevation is added"); the elevation row reads the placeholder until then.
;;   nil: no rim AND no top line found there -- the copy is skipped, not
;;   guessed (Jake: skip).  top: pfg:top-lines.
(defun pfs:copy-y (plan g x top / rim)
  (setq rim (pfr:get plan *pf-tag-rim*))
  (if (pfl:number-p rim)
    (pfl:elev->y (distof rim 2) g)
    (pfg:top-at x g top)))

;; (pfs:face-for plan lname) -> the face this plan block's copy on line lname
;;   shows (Jake, 2026-11-20): a PFFACE typed by hand on the plan block wins
;;   on every copy; otherwise that line's own face, kept on its MEMB entry by
;;   PFASSIGN; otherwise the plan block's PFFACE.
(defun pfs:face-for (plan lname / m)
  (cond
    ((pfr:asserted-p plan *pf-tag-face*) (pfr:get plan *pf-tag-face*))
    ;; IF, not AND -- AND returns T, not the face (V6.1 static check, 2026-11-21)
    ((if (setq m (assoc lname (pfr:memb-get plan))) (pfm:memb-face m)))
    ((pfr:get plan *pf-tag-face*))))

;; (pfs:cone-state s) -> the *pf-states-cone* name PFSIZE s spells | nil
;;   Any case, spaces ignored: "48 X 36" is 48x36.
(defun pfs:cone-state (s / key)
  (setq key (strcase (vl-list->string (vl-remove 32 (vl-string->list (cond (s) ("")))))))
  (car (vl-remove-if-not '(lambda (st) (= (strcase st) key)) *pf-states-cone*)))

;; (pfs:place pe plan lname sta g top) -> (pe . note) -- places or moves the
;;   copy and copies the record across.  pe nil = make a new one.  (nil .
;;   why) when it can't: no rim and no grid top there, or no insert.
(defun pfs:place (pe plan lname sta g top / nm pt y obj state sz sized r1 r2 handle new mismatch row csz)
  (setq nm     (pfl:effname plan)
        handle (pfl:handle plan)
        y      (pfs:copy-y plan g (pfl:sta->x sta g) top)
        pt     (if y (list (pfl:sta->x sta g) y))
        mismatch (and pe (/= (strcase (pfl:effname pe)) (strcase nm))))
  (cond
    ((null pt))
    (mismatch)
    (pe (pfd:move pe pt))
    (T (setq pe (pfd:insert nm pt) new T)))
  (cond
    (mismatch
     (cons nil (strcat "profile copy uses " (pfl:effname pe) " but plan uses " nm
                       " -- replace the old profile copy before refreshing")))
    ((null pt)
     (cons nil "no rim yet, and no grid top line found at this station -- skipped"))
    ((null pe)
     (cons nil "AutoCAD would not insert it"))
    (T
      ;; The record, copied from the plan -- not the label rows and inverts
      ;; (composed here), not the drafter inputs (resolved per copy), not
      ;; PFVIEW (this is a PROFILE), not PFSIZE (lookup-linked or name-sized).
      (foreach tag *pf-tags*
        (if (not (or (member tag *pf-tags-visible*) (member tag *pf-tags-fmt*)
                     (= tag *pf-tag-view*) (= tag *pf-tag-size*)))
          (pfr:put pe tag (pfr:get plan tag))))
      (pfr:put pe *pf-tag-view* *pf-view-pro*)
      (pfr:xd-put pe *pf-xd-plan* (pfr:ser handle))
      (pfr:xd-put pe *pf-xd-line* (pfr:ser lname))
      (pfr:schema-put pe)
      (setq obj (vlax-ename->vla-object pe))
      ;; A fixed-size definition takes its size from its name.  The sanitary
      ;; block's PFSIZE is its cone, typed on the plan block, and copied from
      ;; there (a size typed on the copy is kept).  Other unsized blocks use
      ;; PFSIZE_LU.
      (setq sized (pfr:size-of nm))
      (setq r1
        (if (/= sized "")
          (if (pfr:put pe *pf-tag-size* sized) T "could not write PFSIZE")
          (if (eq (car (pfr:row-for nm)) 'SMH)
            (progn
              (setq sz (pfr:get plan *pf-tag-size*))
              (if (and sz (/= sz ""))
                (if (member (pfr:refresh pe *pf-tag-size* sz *pf-src-rule*)
                            '(written kept adopted))
                  T "could not write PFSIZE")
                "plan sanitary block has no PFSIZE"))
            (progn
              (setq sz (pfl:dynprop-get (vlax-ename->vla-object plan) *pf-param-size*))
              (if sz
                (if (= (vl-princ-to-string sz)
                       (vl-princ-to-string (pfl:dynprop-get obj *pf-param-size*)))
                  T
                  (pfd:dynprop-put obj *pf-param-size* sz))
                "plan block carries no PFSIZE_LU")))))
      ;; The profile state: a CBI's is its face; the sanitary MH's is its
      ;; cone, read off the copy's own PFSIZE just written (so a size typed
      ;; on the copy shows its own cone).  A size that is no cone: a new copy
      ;; shows the first cone rather than the plan symbol; an old one is left
      ;; as it was.  Either way it is reported.
      (setq row (pfr:row-for nm))
      (cond
        ;; a face per line: this copy's own, also written on its PFFACE
        ((eq (caddr row) '*pf-states-face*)
         (setq state (pfs:face-for plan lname))
         (pfr:put pe *pf-tag-face* (cond (state) ("")))
         (setq r2 (pfd:set-state obj state)))
        ((eq (caddr row) '*pf-states-cone*)
         (setq csz (cond ((pfr:get pe *pf-tag-size*)) ("")))
         (if (setq state (pfs:cone-state csz))
           (setq r2 (pfd:set-state obj state))
           (progn
             (if new (pfd:set-state obj (car *pf-states-cone*)))
             (setq r2 (strcat "PFSIZE \"" csz "\" is not a cone ("
                              (pfl:join-with ", " *pf-states-cone*) ") -- "
                              (if new (strcat "shown as " (car *pf-states-cone*))
                                      "cone left as it was"))))))
        (T
         (setq r2 (pfd:set-state obj (car *pf-states-one*)))))
      (cons pe (pfl:join (list (if new "placed" "")
                               (if (pfl:number-p (pfr:get plan *pf-tag-rim*)) "" "at the grid top -- no rim yet")
                               (if (= r1 T) "" (strcat "** size: " r1))
                               (if (= r2 T) "" (strcat "** state: " r2))))))))


;;; ==========================================================================
;;; SECTION 5  --  PFSTRUCT
;;; ==========================================================================

;; (pfs:run plans grids top fmt) -> (placed already-placed skipped)
;;   The work, no questions -- what PFSELFTEST drives (2026-10-30).
;;   plans: the alpha blocks to place (on a line).  grids: pfg:usable.
;;   top: pfg:top-lines.  fmt: nil = each copy's saved defaults (the
;;   command); PFSELFTEST may hand in its own (pfs:sync-fmt-in).
(defun pfs:run (plans grids top fmt / res names nm copies done g lname m pe
                  mine notes n-new n-have n-skip)
  (setq n-new 0 n-have 0 n-skip 0)

  ;; two alpha blocks with one name -- usually a COPY of one
  (foreach e plans
    (setq nm (pfr:get e *pf-tag-name*))
    (if (and nm (/= nm ""))
      (if (assoc nm names)
        (pfl:say (strcat "  ** two alpha blocks are named " nm
                         " -- was one copied?  Rename one in Properties."))
        (setq names (cons (cons nm T) names)))))

  ;; grid by grid: place each structure not placed yet, then label it
  (setq copies (pfs:copies))
  (foreach g grids
    (setq lname (pfg:line-name g) mine nil)
    (setq *pfd-stage* (strcat "placing the copies on " (pfg:title g)))
    (foreach e plans
      (if (and (setq m (assoc lname (pfr:memb-get e)))
               (not (member (cons (pfl:handle e) lname) done))
               (pfg:on-grid-p (cadr m) g))
        (progn
          (setq done (cons (cons (pfl:handle e) lname) done))
          (cond
            ;; already placed -- PFREFRESH's from here on
            ((pfs:find-copy (pfl:handle e) lname copies)
             (setq n-have (1+ n-have)))
            ;; no rim: on the grid top until one is typed (pfs:copy-y)
            (T
             (setq res (pfs:place nil e lname (cadr m) g top))
             (cond
               ((null (car res))
                (setq n-skip (1+ n-skip)
                      notes (cons (strcat "  " (pfr:display-name e) "  " lname "  STA " (pfl:fmt-sta (cadr m))
                                          "  " (cdr res))
                                  notes)))
               (T
                (setq n-new (1+ n-new)
                      mine  (cons (list (car res) e (cadr m) (cdr res)) mine)))))))))
    (if mine
      (progn
        (pfl:say "")
        (pfl:say (strcat "  " (pfg:title g) "   line " lname))
        (foreach cp (reverse mine)
          (setq res (pfd:try (strcat (pfr:display-name (cadr cp)) " labels")
                             'pfs:struct-update
                             (list (car cp) (cadr cp) g (list (cons 'top top)) fmt)))
          (pfl:say (strcat "    " (pfr:display-name (cadr cp))
                           "  STA " (pfl:fmt-sta (caddr cp))
                           "  rim " (pfr:get (cadr cp) *pf-tag-rim*)
                           (if (/= "" (cadddr cp)) (strcat "  " (cadddr cp)) "")))
          (foreach s res (pfl:say s))))))

  ;; on a line of this run whose grids don't show that station -- nothing to
  ;; place it on.  Only the run's lines: a one-line run (the palette) must not
  ;; report a junction's other line.
  (foreach e plans
    (foreach m (pfr:memb-get e)
      (if (and (vl-some '(lambda (g) (= (pfg:line-name g) (car m))) grids)
               (not (member (cons (pfl:handle e) (car m)) done)))
        (setq n-skip (1+ n-skip)
              notes (cons (strcat "  " (pfr:display-name e) "  " (car m) "  STA " (pfl:fmt-sta (cadr m))
                                  "  -- no grid shows this line at this station")
                          notes)))))

  (if notes (pfl:say ""))
  (foreach s (reverse notes) (pfl:say s))
  (pfl:say "")
  (pfl:say (strcat "  " (itoa n-new) " placed, " (itoa n-have) " already placed (left alone"
                   " -- PFREFRESH keeps them up to date), " (itoa n-skip) " skipped."))
  (if (> n-new 0)
    (pfl:say "  Next: PFREFRESH writes the new copies' invert rows (the palette's New Structure does it for you)."))
  (if (null plans)
    (pfl:say "  No alpha blocks on any line yet -- run PFASSIGN first."))
  (list n-new n-have n-skip))

;; (pfs:main) -> nil   the command body, run inside pfd:run
;;   "Place structures in profile" (Jake, 2026-10-16): every alpha block on a
;;   line that has NO profile copy yet gets one, on the grid that shows its
;;   station.  Copies already placed are left alone -- PFREFRESH keeps them up
;;   to date and clears orphans/duplicates.
;;   No grid pick: every line in the drawing (the palette will hand it the
;;   one line clicked there).
(defun pfs:main () (pfs:main-for nil))

;; (pfs:main-for lname) -> nil   PFSTRUCT on one line (the palette's button,
;;   2026-11-03): its grids and the alpha blocks on it.  nil = every line.
(defun pfs:main-for (lname / grids top res)
  (cond
    ((= 1 (getvar "BLOCKEDITOR")) (pfl:say "PFSTRUCT: close the Block Editor first."))
    (T
     (pfc:load)
     (pfl:say "")
     (pfl:say (strcat "=== PFSTRUCT  place structures in profile"
                      (if lname (strcat ", line " lname) "") " ==="))

     (setq *pfd-stage* "reading the grids")
     (setq grids (pfg:usable)
           top   (pfg:top-lines))
     (if lname (setq grids (vl-remove-if-not '(lambda (g) (= (pfg:line-name g) lname)) grids)))
     (if (null grids)
       (pfl:say (if lname
                  (strcat "  ** " lname " has no usable grid -- anchor it on the Setup tab")
                  "  ** no usable profile grids -- each needs an anchor with a .cl on record")))

     ;; Defaults are resolved for each profile copy; typed values stay local.
     ;; The alpha blocks on a line are placed grid by grid.
     (pfs:run (vl-remove-if-not '(lambda (e / m) (and (setq m (pfr:memb-get e)) (or (null lname) (assoc lname m))))
                                (pfr:all *pf-view-plan*))
              grids top nil)
     (pfl:say "  One UNDO takes this whole run back.")))
  (princ))

(defun c:PFSTRUCT ()
  (if (null pfd:run)
    (pfl:say "PFSTRUCT: load pf-load.lsp first.")
    (pfd:run "PFSTRUCT" 'pfs:main))
  (princ))


(princ "\npf-struct loaded.  PFSTRUCT.")
(princ)
