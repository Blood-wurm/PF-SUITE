;;; ==========================================================================
;;; pf-struct.lsp  --  PFSTRUCT: place the structures on one profile.
;;; Load position 10: after pf-index, pf-draw.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; ONE command places every structure type (Jake, 2026-10-15).  Was PFDRAW.
;;;
;;; "PLACE STRUCTURES IN PROFILE" (Jake, 2026-10-16).  No grid pick:
;;;   1. pushes the five drafter inputs (STA prefix etc.) drawing-wide
;;;   2. grid by grid: every alpha block on the line with NO profile copy
;;;      yet gets one, on the grid that shows its station
;;;   3. writes each new copy's label rows, puts them at the grid top, and
;;;      fits its station line up to the first row
;;; Copies already placed are left alone.  From then on PFREFRESH carries
;;; them: updates (a plan block re-stationed by PFASSIGN included), clearing
;;; orphans and duplicates.  Says what it did, grouped by grid.  One UNDO takes it back.
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
;;; SECTION 1  --  The drafter inputs, drawing-wide
;;; ==========================================================================
;;; PFSTAPRE / PFSTASUF / PFCONPRE / PFCONSUF / PFELEVSUF live on every
;;; structure and must agree.  Type a new one on ANY structure and the next run
;;; pushes it to all of them.  Two different new values is a disagreement: it
;;; is reported, and the old value stays until someone settles it.

;; (pfs:sync-fmt) -> (fmt-alist . notes)   the shared logic, for structures
(defun pfs:sync-fmt ()
  (pfr:sync-inputs (pfr:all nil) *pf-tags-fmt* *pf-fmt-defaults* *pf-fmt-retired*))


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
(defun pfs:copies-if (keep / out pt plan line)
  (foreach e (pfr:all *pf-view-pro*)
    (setq plan (pfr:deser (pfr:xd-get e *pf-xd-plan*))
          line (pfr:deser (pfr:xd-get e *pf-xd-line*)))
    (if (or (null keep) (apply keep (list e plan line)))
      (setq pt  (pfl:ins e)
            out (cons (list e plan line (pfg:anchor-of pt) (car pt)) out))))
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

;; (pfs:rows plan fmt lname) -> ((tag . text) ...) for the six label rows
;;   V5's pf:build-label-rows: one station row per line the structure is on
;;   (" =" on all but the last), then construction, second text, elevation.
;;   lname is the line of the grid being drawn: its row comes first.
;;     STA. 4+09.69 STORM LINE 'BA' =
;;     STA. 3+00.00 STORM LINE 'BC'
;;     CONST. DRAINAGE MH BA-5/BC-1      no size; ends with PFNAME
;;   The wording is a default -- a drafter types over any row that should
;;   read differently, and it is kept (Jake, 2026-10-16).
(defun pfs:rows (plan fmt lname / memb words sta-rows i n con elev rim out)
  (setq memb  (pfs:memb-order (pfr:memb-get plan) lname)
        words (cdr (assoc (pfr:get plan *pf-tag-type*) *pf-type-words*))
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
        con  (pfl:join (list (pfr:input *pf-tag-con-pre* fmt) (car words)
                             (pfr:get plan *pf-tag-name*)))
        rim  (pfr:get plan *pf-tag-rim*)
        elev (if (caddr words)
               (pfl:join (list (caddr words)
                               (if (pfl:number-p rim) (pfl:fix (distof rim 2) 2) *pf-elev-placeholder*)
                               (pfr:input *pf-tag-elev-suf* fmt)))
               ""))
  (setq i 0)
  (foreach tag (list "PFSTA1" "PFSTA2" "PFSTA3")
    (setq out (cons (cons tag (cond ((nth i sta-rows)) (""))) out) i (1+ i)))
  (reverse (append (list (cons "PFELEV" elev)
                         (cons "PFTEXT2" (cond ((cadr words)) ("")))
                         (cons "PFCON" con))
                   out)))

;; (pfs:copy-fp pe plan g fmt top) -> fingerprint of everything this profile
;;   copy is built from, and of what the tool left on it.  The same answer
;;   next time = nothing changed = PFREFRESH leaves the copy alone.
;;   Built from: where the copy sits; the alpha block's lines, rim, name,
;;   type, face and size; the shared inputs; the grid's numbers; the grid
;;   top at this station; the station line's top; each label row's text and
;;   position (so a row typed over, moved, or reset by ATTSYNC is noticed).
(defun pfs:copy-fp (pe plan g fmt top / px)
  (setq px (car (pfl:ins pe)))
  (pfl:fingerprint
    (list *pf-fp-ver*
          (pfl:ins pe)
          (pfr:memb-get plan)
          (mapcar '(lambda (tg) (pfr:get plan tg))
                  (list *pf-tag-rim* *pf-tag-name* *pf-tag-type* *pf-tag-face*))
          (vl-princ-to-string (pfl:dynprop-get (vlax-ename->vla-object plan) *pf-param-size*))
          fmt
          (mapcar '(lambda (k) (pfl:g k g)) '(leftx basey sta0 datum vscale hplot))
          (pfg:top-at px g top)
          (pfl:end-y pe 'top)
          (mapcar '(lambda (tg) (list (pfr:get pe tg) (pfr:att-pt pe tg))) *pf-tags-row*))))

;; (pfs:struct-update pe plan g ctx fmt) -> notes
;;   Label rows, their place at the grid top, and the station line's top.
;;   Pipes play no part, so nothing about a pipe can stop a structure being
;;   drawn.  The barrel depth is the drafter's (PFDEPTH grip).
(defun pfs:struct-update (pe plan g ctx fmt / notes rows r kept ht px gtop off gap
                            base live i x res row1 moved)
  (setq *pfd-stage* "composing the label rows")
  (setq ht   (pfg:text-ht g)
        px   (car (pfl:ins pe))
        rows (pfs:rows plan fmt (pfg:line-name g))
        ;; which rows a drafter MOVED -- read before anything changes, since a
        ;; parameter change can shift attributes (Jake, 2026-10-16: a CBI row
        ;; moved by hand is left where it is, same as a pipe row)
        ;; measured against the copy's insertion point: rows that travelled
        ;; with the copy (a new rim, a re-station) were not moved by hand
        moved (mapcar '(lambda (tg) (cons tg (pfr:moved-p pe tg (pfl:ins pe)))) *pf-tags-row*))
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

  ;; what PFREFRESH compares against next time
  (pfr:stamp-put pe (pfs:copy-fp pe plan g fmt (pfs:ctx 'top ctx)))
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

;; (pfs:place pe plan lname sta g) -> (pe . note) -- places or moves the copy
;;   and copies the record across.  pe nil = make a new one.
(defun pfs:place (pe plan lname sta g / nm pt obj state sz r1 r2 handle new)
  (setq nm     (pfl:effname plan)
        handle (pfl:handle plan)
        pt     (list (pfl:sta->x sta g)
                     (pfl:elev->y (distof (pfr:get plan *pf-tag-rim*) 2) g)))
  (if pe
    (pfd:move pe pt)
    (setq pe (pfd:insert nm pt) new T))
  (if (null pe)
    (cons nil "AutoCAD would not insert it")
    (progn
      ;; The record, copied from the plan -- not the label rows and inverts
      ;; (composed here), not the drafter inputs (pushed drawing-wide), not
      ;; PFVIEW (this is a PROFILE), not PFSIZE (field-linked to PFSIZE_LU).
      (foreach tag *pf-tags*
        (if (not (or (member tag *pf-tags-visible*) (member tag *pf-tags-fmt*)
                     (= tag *pf-tag-view*) (= tag *pf-tag-size*)))
          (pfr:put pe tag (pfr:get plan tag))))
      (pfr:put pe *pf-tag-view* *pf-view-pro*)
      (pfr:xd-put pe *pf-xd-plan* (pfr:ser handle))
      (pfr:xd-put pe *pf-xd-line* (pfr:ser lname))
      (pfr:schema-put pe)
      (setq obj (vlax-ename->vla-object pe))
      ;; size first -- it sets the slab, which the depth stretch starts from
      (setq sz (pfl:dynprop-get (vlax-ename->vla-object plan) *pf-param-size*))
      (setq r1 (if sz
                 (if (= (vl-princ-to-string sz)
                        (vl-princ-to-string (pfl:dynprop-get obj *pf-param-size*)))
                   T
                   (pfd:dynprop-put obj *pf-param-size* sz))
                 "plan block carries no PFSIZE_LU"))
      (setq state (if (eq (caddr (pfr:row-for nm)) '*pf-states-face*)
                    (pfr:get plan *pf-tag-face*)
                    (car *pf-states-one*)))
      (setq r2 (pfd:set-state obj state))
      (cons pe (pfl:join (list (if new "placed" "")
                               (if (= r1 T) "" (strcat "** size: " r1))
                               (if (= r2 T) "" (strcat "** state: " r2))))))))


;;; ==========================================================================
;;; SECTION 5  --  PFSTRUCT
;;; ==========================================================================

;; (pfs:main) -> nil   the command body, run inside pfd:run
;;   "Place structures in profile" (Jake, 2026-10-16): every alpha block on a
;;   line that has NO profile copy yet gets one, on the grid that shows its
;;   station.  Copies already placed are left alone -- PFREFRESH keeps them up
;;   to date and clears orphans/duplicates.
;;   No grid pick: every line in the drawing (the palette will hand it the
;;   one line clicked there).
(defun pfs:main ( / grids top res fmt plans names nm copies done g lname m pe
                    mine notes n-new n-have n-skip)
  (cond
    ((= 1 (getvar "BLOCKEDITOR")) (pfl:say "PFSTRUCT: close the Block Editor first."))
    (T
     (pfc:load)
     (setq n-new 0 n-have 0 n-skip 0)
     (pfl:say "")
     (pfl:say "=== PFSTRUCT  place structures in profile ===")

     (setq *pfd-stage* "reading the grids")
     (setq grids (pfg:usable)
           top   (pfg:top-lines))
     (if (null grids)
       (pfl:say "  ** no usable profile grids -- each needs an anchor with a .cl on record"))

     ;; 1. drafter inputs, drawing-wide
     (setq *pfd-stage* "pushing the drafter inputs")
     (setq res (pfs:sync-fmt) fmt (car res))
     (foreach s (cdr res) (pfl:say s))

     ;; 2. the alpha blocks on a line
     (setq plans (vl-remove-if-not 'pfr:memb-get (pfr:all *pf-view-plan*)))

     ;; two alpha blocks with one name -- usually a COPY of one
     (foreach e plans
       (setq nm (pfr:get e *pf-tag-name*))
       (if (and nm (/= nm ""))
         (if (assoc nm names)
           (pfl:say (strcat "  ** two alpha blocks are named " nm
                            " -- was one copied?  Rename one in Properties."))
           (setq names (cons (cons nm T) names)))))

     ;; 3. grid by grid: place each structure not placed yet, then label it
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
               ((not (pfl:number-p (pfr:get e *pf-tag-rim*)))
                (setq n-skip (1+ n-skip)
                      notes (cons (strcat "  " (pfr:display-name e) "  " lname "  STA " (pfl:fmt-sta (cadr m))
                                          "  no rim -- type it on the alpha block (Properties), then PFSTRUCT again")
                                  notes)))
               (T
                (setq res (pfs:place nil e lname (cadr m) g))
                (cond
                  ((null (car res))
                   (setq n-skip (1+ n-skip)
                         notes (cons (strcat "  " (pfr:display-name e) "  " (cdr res)) notes)))
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

     ;; on a line no grid shows at that station -- nothing to place it on
     (foreach e plans
       (foreach m (pfr:memb-get e)
         (if (not (member (cons (pfl:handle e) (car m)) done))
           (setq n-skip (1+ n-skip)
                 notes (cons (strcat "  " (pfr:display-name e) "  " (car m) "  STA " (pfl:fmt-sta (cadr m))
                                     "  -- no grid shows this line at this station")
                             notes)))))

     (if notes (pfl:say ""))
     (foreach s (reverse notes) (pfl:say s))
     (pfl:say "")
     (pfl:say (strcat "  " (itoa n-new) " placed, " (itoa n-have) " already placed (left alone"
                      " -- PFREFRESH keeps them up to date), " (itoa n-skip) " skipped."))
     (if (null plans)
       (pfl:say "  No alpha blocks on any line yet -- run PFASSIGN first."))
     (pfl:say "  One UNDO takes this whole run back.")))
  (princ))

(defun c:PFSTRUCT ()
  (if (null pfd:run)
    (pfl:say "PFSTRUCT: load pf-load.lsp first.")
    (pfd:run "PFSTRUCT" 'pfs:main))
  (princ))


(princ "\npf-struct loaded.  PFSTRUCT.")
(princ)
