;;; ==========================================================================
;;; pf-palette.lsp  --  PFPALETTE: the OpenDCL palette.  Prefix pfw:.
;;; Load position 14: after pf-grid (it calls every command module).
;;; Contract, API and rules: README.md beside this file.
;;;
;;; V5's palette project, edited by Jake in OpenDCL Studio (2026-11-03):
;;; pfsuite-odcl\pfsuite.odcl, form pfsPalette, three tabs --
;;;   Setup  tvwLines -> metaList + lvwLinkage; Anchor Edit New Remove Zoom
;;;          Scan Index
;;;   Run    tarLines -> detailsList + lvwCommand (structures and pipes);
;;;          Assign, New Structure, New Pipe, Refresh Line, Refresh All,
;;;          Edit Attributes (EATTEDIT on the picked structure or pipe),
;;;          Defaults (the pfsDefaults modal form; PFDEFAULTS is its
;;;          command-line twin, also here)
;;;   Tools  room to grow
;;;
;;; THE ONE CHANGE FROM V5: a button that does work has Event Invoke = 1
;;; ("Allow Command") in Studio, so its handler runs AS A COMMAND and calls
;;; the work directly, inside pfd:run (one undo group).  V5 queued commands
;;; with vla-SendCommand and a ticket dispatcher, and its first queued command
;;; of a session died at its own prompt -- that channel is not ported.
;;; (Event Invoke per OpenDCL forum threads and the vendor's AUBlockTool
;;; sample, whose palette button calls getpoint and (command) directly.)
;;;
;;; Kept from V5, each one paid for in CAD (pfsuite-odcl\OPENDCL-WIRING.md):
;;;   - columns are added in OnInitialize ONLY -- AddColumns stacks
;;;   - data is filled AFTER dcl-Form-Show -- OnInitialize fires too early
;;;   - PFPRELOAD after every Studio save -- the project loads once a session
;;;   - an undefined control symbol is nil, and dcl-* on nil does nothing:
;;;     every caption write is guarded
;;;   - never call a property a control type doesn't document: a missing one
;;;     raises a modal no catch can stop
;;;   - tree selection handlers only READ (Event Invoke 0)
;;;   - a refused button always says why
;;; ==========================================================================

(vl-load-com)

(setq *pfw-loaded*    nil    ; nil = the next PFPALETTE re-reads the .odcl
      *pfw-maps*      nil    ; ((setup . map) (run . map))   map: ((key . row) ...)
      *pfw-sel-setup* nil    ; the row picked on each tab
      *pfw-sel-run*   nil
      ;; T while a tree is rebuilt: AddParent / AddChild fire SelChanged as
      ;; they go, against a map not built yet (V5's lesson)
      *pfw-filling*   nil
      *pfw-stage*     nil    ; what a handler is doing, for pfw:guard's message
      *pfw-trail*     nil    ; the steps a handler got through, newest first
      *pfw-depth*     0      ; guards running inside one another
      *pfw-items*    nil    ; lvwCommand's sorted structure and pipe rows
      *pfw-sel-struct* nil   ; the structure picked there (its plan block)
      *pfw-sel-pipe*  nil)   ; the pipe picked there


;;; ==========================================================================
;;; SECTION 1  --  Loading and the toggle
;;; ==========================================================================

(defun pfw:odcl-path () (strcat *pf-root* "\\pfsuite-odcl\\pfsuite.odcl"))

;; (pfw:runtime) -> T | nil   brings OpenDCL up when supported by this host
(defun pfw:runtime ( / ce)
  (if (/= (type dcl-Project-Load) 'EXRXSUBR)
    (progn
      (setq ce (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (command "_OPENDCL")
      (setvar "CMDECHO" ce)))
  (if (= (type dcl-Project-Load) 'EXRXSUBR)
    T
    (progn
      (pfl:say "PFPALETTE: OpenDCL Runtime is unavailable in this AutoCAD version. Install a compatible OpenDCL Studio/Runtime, then restart AutoCAD.")
      nil)))

;; (pfw:reload) -> the project | nil   re-read from disk, FORCED (dcl-
;;   Project-Load's second argument): without it a project already loaded
;;   this session -- V5's, or before a Studio save -- is kept, and PFPALETTE
;;   shows the old form (2026-11-03: a click called V5's btnSetup).  The form
;;   must be closed first.
(defun pfw:reload ( / r)
  (if (pfw:runtime)
    (progn
      (vl-catch-all-apply '(lambda () (if (dcl-Form-IsActive pfsuite/pfsPalette)
                                        (dcl-Form-Close pfsuite/pfsPalette)))
                          nil)
      (setq *pfw-loaded* nil
            r (vl-catch-all-apply 'dcl-Project-Load (list (pfw:odcl-path) T)))
      (if (vl-catch-all-error-p r)
        (progn (pfl:say (strcat "PFPALETTE: reading " (pfw:odcl-path) " FAILED -- " (vl-catch-all-error-message r)))
               nil)
        (setq *pfw-loaded* r)))))

;; (pfw:ensure) -> the project | nil   re-read from disk the first time this
;;   session; after that, the one already loaded
(defun pfw:ensure ()
  (if (pfw:runtime)
    (if *pfw-loaded* *pfw-loaded* (pfw:reload))))

;; Every control the code uses, by tab.  A missing one is named when the
;; palette opens -- the control symbols exist only while the form is open,
;; and reading a symbol's value touches no property, so this is safe.
(setq *pfw-controls*
  '("tvwLines" "metaList" "lvwLinkage" "btnScan" "btnAnchor" "btnEdit" "btnNew" "btnRemove" "btnZoom" "btnIndex"
    "tarLines" "detailsList" "lvwCommand" "btnAssign" "btnStruct" "btnPipe" "btnRefreshLine" "btnRefreshAll"
    "btnEditStruct"))

;; (pfw:ctrl name) -> the control | nil
(defun pfw:ctrl (name) (eval (read (strcat "pfsuite/pfsPalette/" name))))

;; (pfw:census) -> nil   says which controls the loaded form lacks
(defun pfw:census ( / miss)
  (setq miss (vl-remove-if 'pfw:ctrl *pfw-controls*))
  (if miss (pfl:say (strcat "PFPALETTE: the loaded form has no " (pfl:join miss)
                            " -- check the (Name)s in Studio, save, PFPRELOAD.")))
  (if (pfw:ctrl "btnSetup")
    (pfl:say "PFPALETTE: the loaded form still has V5's btnSetup -- it's the old project."))
  (if (null (pfw:ctrl "btnDefaults"))
    (pfl:say "PFPALETTE: add btnDefaults on the Run tab in Studio."))
  (if (null (pfw:ctrl "btnXing"))
    (pfl:say "PFPALETTE: add btnXing (\"Crossings\", Event Invoke 1, Clicked) on the Run tab in Studio."))
  (princ))

;; THE TRAIL: every step of a handler marks itself, so an error can print
;; the steps it got through -- the last one is where it broke.  One stage
;; was not enough: Scan's error carried Scan's last stage, though Scan had
;; finished (2026-11-03).
(defun pfw:mark (s) (setq *pfw-trail* (cons s *pfw-trail*)) nil)

;; (pfw:stage s) -> nil   the current step, for the trail and the message
(defun pfw:stage (s) (setq *pfw-stage* s) (if s (pfw:mark s)) nil)

;; (pfw:guard name fn) -> nil   runs a handler's work; an error is named
;;   with the handler, the trail of steps, and the command's own stage, and
;;   an undo group it left open is closed.  A bare "consp nil :error#2"
;;   said none of that (2026-11-03).
;;   Guards NEST: a tree's SelChanged fires inside a button's repaint (V5:
;;   AddParent dispatches it as it goes), and only the outermost guard may
;;   start a fresh trail -- an inner one would wipe the button's.
(defun pfw:guard (name fn / r steps)
  (if (= 0 *pfw-depth*) (setq *pfw-stage* nil *pfd-stage* nil *pfw-trail* nil))
  (pfw:mark (strcat "[" name "]"))
  (setq *pfw-depth* (1+ *pfw-depth*)
        r           (vl-catch-all-apply fn nil)
        *pfw-depth* (max 0 (1- *pfw-depth*)))
  (if (vl-catch-all-error-p r)
    (progn
      (vl-catch-all-apply 'vla-endundomark (list (vla-get-activedocument (vlax-get-acad-object))))
      (pfl:say (strcat "PFPALETTE: " name " stopped: " (vl-catch-all-error-message r)))
      (pfw:say-trail)
      (if *pfd-stage* (pfl:say (strcat "  the command's last stage: " *pfd-stage*)))))
  (princ))

;; (pfw:say-trail) -> nil   the last ten steps, oldest first
(defun pfw:say-trail ( / steps)
  (setq steps (reverse *pfw-trail*))
  (while (> (length steps) 10) (setq steps (cdr steps)))
  (pfl:say (strcat "  steps: " (if steps (pfl:join-with " > " steps) "(none marked)")))
  (princ))

;; PFPALETTE -- show it if down, close it if up.  Close, not Hide: Close
;;   re-runs OnInitialize on the next open.  Filled AFTER Show.
(defun c:PFPALETTE ()
  (cond
    ((null pfd:run) (pfl:say "PFPALETTE: load pf-load.lsp first."))
    ((not (pfw:ensure))
     (if (= (type dcl-Project-Load) 'EXRXSUBR)
       (pfl:say (strcat "PFPALETTE: could not load " (pfw:odcl-path)))))
    ((dcl-Form-IsActive pfsuite/pfsPalette) (dcl-Form-Close pfsuite/pfsPalette))
    (T
     (setq *pfw-depth* 0)                   ; a guard an uncatchable error left counted
     (pfw:db-forget)                        ; opening reads the drawing fresh
     (dcl-Form-Show pfsuite/pfsPalette)
     (pfw:guard "Open" '(lambda () (pfw:mark "census") (pfw:census) (pfw:refresh)))))
  (princ))

;; PFPRELOAD -- re-read the .odcl from disk.  RUN AFTER EVERY STUDIO SAVE.
(defun c:PFPRELOAD ()
  (if (pfw:reload) (pfl:say "PFPRELOAD: .odcl re-read.  Run PFPALETTE."))
  (princ))

;; COLUMNS ONLY -- see the header
(defun pfw:init ()
  (pfw:stage "metaList columns")
  (dcl-ListView-AddColumns pfsuite/pfsPalette/metaList    (list (list "Property" 0 110) (list "Value" 0 410)))
  (pfw:stage "lvwLinkage columns")
  (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwLinkage  (list (list "Item" 0 90) (list "File" 0 440)))
  (pfw:stage "detailsList columns")
  (dcl-ListView-AddColumns pfsuite/pfsPalette/detailsList (list (list "Property" 0 150) (list "Value" 0 370)))
  (pfw:stage "lvwCommand columns")
  (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwCommand
    (list (list "Item" 0 180) (list "Station(s)" 0 160) (list "Status" 0 135)))
  (pfw:stage nil))

(defun c:pfsuite/pfsPalette#OnInitialize () (pfw:guard "OnInitialize" 'pfw:init))


;;; ==========================================================================
;;; SECTION 2  --  The lines (read only)
;;; ==========================================================================
;;; A row: (util short lname anchor stub)
;;;   anchor  the line's grid anchor | nil (named by Scan, no grid yet)
;;;   stub    (type name cl inv top) -- pfn:place's shape | nil
;;; Read from the anchors and the stubs only: no .cl is opened and no
;;; structure is looked at to draw the tree.

;; (pfw:lines) -> rows, by utility then line.  A fresh read of the drawing;
;;   the palette itself shows the remembered list (pfw:db, Section 2b).
(defun pfw:lines () (pfw:lines-in (pfg:index)))

;; (pfw:lines-in idx) -> the same, from an anchor index (pfg:index)
(defun pfw:lines-in (idx / out seen g ln at st a)
  (foreach x idx
    (if (not (nth 5 x))
      (progn
        (setq a  (car x)
              g  (pfg:grid a)
              at (pfg:atts a)
              ;; IF, not AND: a bodiless cond clause returns its test, and
              ;; AND returns only T -- every gridded line was named T
              ;; (2026-11-03)
              ln (cond ((if g (pfg:line-name g)))
                       ((strcase (strcat (pfg:att *pf-anc-util* at) "_" (pfg:att *pf-anc-line* at))))))
        (if (not (member ln seen))
          (setq seen (cons ln seen)
                out  (cons (list (car (pfl:line-parts ln)) (cdr (pfl:line-parts ln)) ln a nil) out))))))
  (foreach s (pfm:stubs)
    (setq ln (if (pfn:nz (caddr s)) (strcase (vl-filename-base (caddr s))) (strcat (car s) "_" (cadr s))))
    (if (not (member ln seen))
      (setq seen (cons ln seen)
            st   (pfr:stub-get (car s) (cadr s))
            out  (cons (list (car s) (cadr s) ln nil
                             (list (car s) (cadr s) (caddr s)
                                   (pfn:nz (cdr (assoc 4 st))) (pfn:nz (cdr (assoc 5 st)))))
                       out))))
  (vl-sort out '(lambda (a b) (< (strcat (car a) " " (cadr a)) (strcat (car b) " " (cadr b))))))

;; (pfw:file-cell p) -> "name.ext" | "NOT FOUND" | "(not set)"   V5's three
;;   states -- an empty slot and a missing file are different problems
(defun pfw:file-cell (p)
  (cond
    ((null (pfn:nz p)) "(not set)")
    ((null (vl-file-systime p)) "NOT FOUND")
    (T (strcat (vl-filename-base p) (vl-filename-extension p)))))

;; (pfw:meta-rows row) -> (("Property" . "value") ...)   what the line IS
(defun pfw:meta-rows (row / a g r)
  (if row
    (progn
      (setq a (nth 3 row) g (if a (pfg:grid a)))
      (append
        (list (cons "Type" (car row))
              (cons "Line" (cadr row))
              (cons "Grid" (if a "yes" "not yet -- named by Scan; Anchor it")))
        (if g
          (list (cons "Stations" (if (setq r (pfg:sta-range g))
                                   (strcat (pfl:fmt-sta (car r)) " to " (pfl:fmt-sta (cadr r)))
                                   "(width not recorded)"))
                (cons "Datum"    (pfl:fix (pfl:g 'datum g) 2))
                (cons "H plot"   (pfl:fix (pfl:g 'hplot g) 2))
                (cons "V plot"   (pfl:fix (pfl:g 'vplot g) 2))
                (cons "Material" (cond ((pfl:g 'material g)) ("(not set)")))))
        (if (and a (null g))
          (list (cons "Problem" "its station, datum, scales or height can't be read")))))))

;; (pfw:file-rows row) -> (("Item" . "file") ...)   what the line is bound to
(defun pfw:file-rows (row / g st)
  (if row
    (progn
      (setq g (if (nth 3 row) (pfg:grid (nth 3 row))) st (nth 4 row))
      (list (cons "Centerline (.cl)" (pfw:file-cell (if g (pfl:g 'cl g) (caddr st))))
            (cons "Invert _INV .pro" (pfw:file-cell (if g (pfl:g 'pro-inv g) (nth 3 st))))
            (cons "Crown _TOP .pro"  (pfw:file-cell (if g (pfl:g 'pro-top g) (nth 4 st))))
            (cons "Existing .tin"    (pfw:file-cell (if g (pfl:g 'tin-exist g))))
            (cons "DESIGN_* .tin"    (pfw:file-cell (if g (pfl:g 'tin-design g))))))))


;;; ---- the Run list's rows, every line in ONE pass --------------------------
;;; (2026-11-20: a line pick took up to a minute.)  Each kind of block is read
;;; once for the whole drawing and filed under its line: ((lname row ...) ...).
;;; The one-line functions (pfw:struct-rows, pfw:pipe-rows) are fresh reads
;;; for PFSELFTEST; the palette shows the remembered list (pfw:db).

;; (pfw:file-row lname row groups) -> groups with row added under lname
(defun pfw:file-row (lname row groups / g)
  (if (setq g (assoc lname groups))
    (subst (cons lname (cons row (cdr g))) g groups)
    (cons (list lname row) groups)))

;; (pfw:struct-rows-all) -> ((lname (ename name station status copy) ...) ...)
;;   The plan structures on each line (Jake, 2026-11-13: "pick a line then
;;   the structures on that line will populate").  Status, first that
;;   applies:
;;     moved since Assign   its plan stamp no longer matches -- Assign first
;;     placed               a profile copy on this line, at its rim
;;     at grid top (no rim) a copy, parked on the grid's top line until a
;;                          rim is typed (Jake, 2026-11-13)
;;     not placed / not placed (no rim)   no copy on this line yet
;;   copy: its profile copy on that line | nil.  "needs refresh" is added when
;;   a line is picked (pfw:run-rows) -- PFREFRESH's own test, per block.
;;   One search finds the plan structures and their profile copies both.
(defun pfw:struct-rows-all ( / copies plans xd memb name rim stale h m done out c)
  (foreach e (pfr:all nil)
    (if (= (strcase (cond ((pfr:view e)) (""))) (strcase *pf-view-pro*))
      (setq xd     (pfr:xd-pairs e)
            copies (cons (cons (cons (pfr:deser (cdr (assoc *pf-xd-line* xd)))
                                     (pfr:deser (cdr (assoc *pf-xd-plan* xd))))
                               e)
                         copies))
      (setq plans (cons e plans))))
  (foreach e (reverse plans)
    (if (setq memb (pfr:memb-get e))
      (progn
        (setq name  (cond ((pfn:nz (pfr:get e *pf-tag-name*))) ("(unnamed)"))
              rim   (pfl:number-p (pfr:get e *pf-tag-rim*))
              stale (pfm:stale (list e))
              h     (pfl:handle e)
              done  nil)
        (foreach m memb
          (if (not (member (car m) done))
            (setq done (cons (car m) done)
                  c    (cdr (assoc (cons (car m) h) copies))
                  out  (pfw:file-row (car m)
                         (list e name (cadr m)
                               (cond (stale "moved since Assign")
                                     (c (if rim "placed" "at grid top (no rim)"))
                                     (rim "not placed")
                                     ("not placed (no rim)"))
                               c)
                         out)))))))
  out)

;; (pfw:struct-rows lname) -> ((ename name station status copy) ...) by station
(defun pfw:struct-rows (lname)
  (vl-sort (cdr (assoc lname (pfw:struct-rows-all)))
           '(lambda (a b) (< (caddr a) (caddr b)))))

;; A pipe's size and material are its own values, not line label defaults.
;; Only the four formatting inputs and two displayed rows count here.  A
;; missing SRC record cannot prove whether existing text was hand edited.
;; The SRC record is read once per pipe, not once per tag (2026-11-20).
(defun pfw:pipe-label-status (e / tag src cur edited unknown missing all)
  (setq all (pfr:src-all e))
  (foreach tag (append *pf-pipe-tags-fmt* (list *pf-pipe-label* *pf-pipe-label2*))
    (setq src (assoc (strcase tag) all)
          cur (pfr:get e tag))
    (if (null cur)
      (setq missing T)
      (cond
        ((null src) (setq unknown T))
        ((or (= (cadr src) *pf-src-asserted*)
             (/= cur (if (caddr src) (caddr src) "")))
         (setq edited T)))))
  (cond (missing "Missing fields") (edited "Hand edited")
        (unknown "Unverified") ("Uses default")))

;; (pfw:pipe-rows-all idx) -> ((lname (ename sta1 sta2 size mat status) ...) ...)
;;   Each valid pipe under its line.  Both ends must belong to the same
;;   usable grid, as in PFREFRESH/Defaults.  idx: pfg:index, read once.
(defun pfw:pipe-rows-all (idx / out ends g ln s1 s2 size mat)
  (foreach e (pfp:all)
    (if (and (setq ends (pfp:ends e))
             (setq g (pfp:grid-of-ends-in ends idx))
             (setq ln (pfg:line-name g)))
      (progn
        (setq s1 (pfl:x->sta (car (car ends)) g)
              s2 (pfl:x->sta (car (cadr ends)) g)
              size (pfr:get e *pf-pipe-size*)
              mat (pfr:get e *pf-pipe-mat*))
        (setq out (pfw:file-row ln
                    (list e s1 s2
                          (if (and size (/= size "")) size "(blank)")
                          (if (and mat (/= mat "")) mat "(blank)")
                          (pfw:pipe-label-status e))
                    out)))))
  out)

;; (pfw:pipe-rows lname) -> each valid pipe on that line, ordered by station
(defun pfw:pipe-rows (lname)
  (vl-sort (cdr (assoc lname (pfw:pipe-rows-all (pfg:index))))
           '(lambda (a b)
              (if (= (cadr a) (cadr b))
                (< (pfl:handle (car a)) (pfl:handle (car b)))
                (< (cadr a) (cadr b))))))

;; (pfw:xing-rows-all) -> ((lname (ename label station status) ...) ...) the
;;   crossing blocks, under the line each one marks.  Read off the blocks
;;   themselves -- PFCLR and the red PFXLABEL / PFREFRESH gave them -- so the
;;   list costs no recount.  THE PALETTE'S WARNING (Jake, 2026-11-20): a
;;   short or unknown clearance shows "** ..." here.
(defun pfw:xing-rows-all ( / rec clr bad out)
  (foreach e (pfk:all)
    (if (setq rec (pfk:rec e))
      (setq clr (cond ((pfr:get e *pf-xing-clr*)) (""))
            bad (= 1 (cdr (assoc 62 (entget e))))
            out (pfw:file-row (car rec)
                  ;; "Crossing SAN. A  STA 1+00.00": the crossing line's
                  ;; utility and name, and the station ON THAT LINE (this
                  ;; line's station is the next column)
                  (list e
                        (strcat "Crossing "
                                (pfl:join (list (cond ((cdr (assoc (car (pfl:line-parts (caddr rec))) *pf-util-abbrev*)))
                                                      ((car (pfl:line-parts (caddr rec)))))
                                                (cdr (pfl:line-parts (caddr rec)))))
                                "  STA " (pfl:fmt-sta (cadddr rec)))
                        (cadr rec)
                        ;; PASS / FAIL with the clearance (Jake, 2026-11-20)
                        (cond ((= clr "UNKNOWN") "FAIL  wall unknown")
                              ((not (pfl:number-p clr)) "no pipe on this line")
                              (bad (strcat "FAIL  " (pfl:fix (distof clr 2) 1) "\""))
                              ((strcat "PASS  " (pfl:fix (distof clr 2) 1) "\""))))
                  out))))
  out)

;; (pfw:xing-rows lname) -> that line's crossing rows
(defun pfw:xing-rows (lname) (cdr (assoc lname (pfw:xing-rows-all))))

;; (pfw:run-rows-of srows prows xrows) -> one line's Run list, one row shape:
;;   (kind ename label sta1 sta2 status copy), structures and pipes and
;;   crossings in station order.  copy: a structure's profile copy on the
;;   line, else nil.  The entity, not the displayed text, identifies the
;;   clicked item.
(defun pfw:run-rows-of (srows prows xrows / out r)
  (foreach r srows
    (setq out (cons (list 'structure (car r) (cadr r) (caddr r) (caddr r)
                          (cadddr r) (nth 4 r)) out)))
  (foreach r prows
    (setq out (cons (list 'pipe (car r)
                          (strcat "Pipe " (nth 3 r) " " (nth 4 r))
                          (cadr r) (caddr r) (nth 5 r)) out)))
  (foreach r xrows
    (setq out (cons (list 'crossing (car r) (cadr r) (caddr r) (caddr r) (cadddr r)) out)))
  (vl-sort out
    '(lambda (a b)
       (if (= (nth 3 a) (nth 3 b))
         (if (eq (car a) (car b))
           (< (pfl:handle (cadr a)) (pfl:handle (cadr b)))
           (eq (car a) 'structure))
         (< (nth 3 a) (nth 3 b))))))

;; (pfw:run-rows lname) -> that line's Run list, from the remembered list,
;;   with "needs refresh" where PFREFRESH would change the block.  Worked out
;;   the first time the line is picked and remembered with the list.
(defun pfw:run-rows (lname / db cached key hit rows)
  (setq db     (pfw:db)
        cached (eq db *pfw-db*)
        key    (cons 'due lname))
  (cond
    ((setq hit (assoc key db)) (cdr hit))
    (T
     (setq rows (pfw:due-rows lname (cdr (assoc lname (cdr (assoc 'items db)))) db cached))
     (pfw:db-keep cached key rows)
     rows)))

;; (pfw:db-keep cached key val) -> nil   val kept in the remembered list
;;   under key -- only when the list read is the one remembered, and still
;;   is (a change in between emptied it: nothing is kept)
(defun pfw:db-keep (cached key val)
  (if (and cached *pfw-db*) (setq *pfw-db* (cons (cons key val) *pfw-db*)))
  nil)

;; (pfw:due-ctx db cached) -> what PFREFRESH's tests need, read once per list:
;;   ((idx . anchor index) (grids . usable) (top . top lines) (ictx . the
;;   invert context) (xextras . the crossings' drawn extras))
(defun pfw:due-ctx (db cached / hit idx grids r)
  (cond
    ((setq hit (assoc 'due-ctx db)) (cdr hit))
    ((setq hit (assoc 'due-ctx *pfw-db*)) (cdr hit))
    (T
     (setq idx   (pfg:index)
           grids (pfg:usable-in idx)
           r     (list (cons 'idx idx) (cons 'grids grids) (cons 'top (pfg:top-lines))
                       (cons 'ictx (pfi:ctx grids)) (cons 'xextras (pfk:extras))))
     (pfw:db-keep cached 'due-ctx r)
     r)))

;; (pfw:due-p row lname ctx) -> T when PFREFRESH would change this row's block.
;;   The same tests, with the same grid choice, as pfu:run.  An error, or no
;;   grid to test against, is not "needs refresh": the row says what it did.
(defun pfw:due-p (row lname ctx / r)
  (setq r (vl-catch-all-apply
            '(lambda ( / pe plan m g)
               (cond
                 ((eq (car row) 'structure)
                  (setq pe (nth 6 row) plan (cadr row))
                  (and pe
                       (/= (nth 5 row) "moved since Assign")
                       (setq m (assoc lname (pfr:memb-get plan)))
                       (setq g (pfg:grid-for lname (cadr m)
                                             (pfg:anchor-of-in (pfl:ins pe) (cdr (assoc 'idx ctx)))
                                             (cdr (assoc 'grids ctx))))
                       (pfu:copy-due-p pe plan g nil (cdr (assoc 'top ctx)) (cdr (assoc 'ictx ctx)))))
                 ((eq (car row) 'pipe)
                  (and (setq g (pfp:grid-of-ends-in (pfp:ends (cadr row)) (cdr (assoc 'idx ctx))))
                       (pfu:pipe-due-p (cadr row) g nil)))
                 ((eq (car row) 'crossing)
                  (pfu:xing-due-p (cadr row) (cdr (assoc 'ictx ctx)) (cdr (assoc 'xextras ctx))))))
            nil))
  (and (not (vl-catch-all-error-p r)) r T))

;; (pfw:due-rows lname rows db cached) -> rows, "needs refresh" put first in
;;   the status of each block PFREFRESH would change
(defun pfw:due-rows (lname rows db cached / ctx)
  (if rows (setq ctx (pfw:due-ctx db cached)))
  (mapcar '(lambda (r)
             (if (pfw:due-p r lname ctx)
               (list (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r) (nth 4 r) "needs refresh" (nth 6 r))
               r))
          rows))


;;; ==========================================================================
;;; SECTION 2b  --  The remembered list  (Jake, 2026-11-20)
;;; ==========================================================================
;;; The palette read the whole drawing on every click.  Now it reads it ONCE
;;; (pfw:read) and keeps what it found in *pfw-db* -- in memory only, one per
;;; drawing (each drawing has its own LISP variables), nothing saved.  A
;;; click answers from it.
;;;
;;; It is thrown away, never patched, whenever the drawing changes:
;;;   - a drawing-change reactor (pfw:db-watch) empties it on any change --
;;;     MOVE, grips, Properties, UNDO, anything; and switches itself off
;;;     until the next read, so a long command pays for it once
;;;   - the palette's own buttons empty it after their work (pfw:db-forget),
;;;     whenever AutoCAD gets round to the reactor
;;; The next click reads the drawing again.  The commands never use it: they
;;; write, and read the drawing themselves.  The .pro / .cl / .tin "NOT FOUND"
;;; checks stay live -- a file can go missing without the drawing changing.
;;;
;;;   *pfw-db*  ((lines . tree rows) (items (lname . run rows) ...))

(setq *pfw-db* nil)

;; (pfw:read) -> the list, read fresh from the drawing.  Says how long it took.
(defun pfw:read ( / t0 idx lines srows prows xrows names items)
  (setq t0 (getvar "MILLISECS"))
  (pfl:effname-forget)
  (setq idx   (pfg:index)
        lines (pfw:lines-in idx)
        srows (pfw:struct-rows-all)
        prows (pfw:pipe-rows-all idx)
        xrows (pfw:xing-rows-all))
  (foreach g (append srows prows xrows)
    (if (not (member (car g) names)) (setq names (cons (car g) names))))
  (foreach ln names
    (setq items (cons (cons ln (pfw:run-rows-of (cdr (assoc ln srows))
                                                (cdr (assoc ln prows))
                                                (cdr (assoc ln xrows))))
                      items)))
  (pfl:say (strcat "PFPALETTE: drawing read -- " (itoa (length lines)) " lines, "
                   (pfl:fix (/ (max 0 (- (getvar "MILLISECS") t0)) 1000.0) 2) "s"))
  (list (cons 'lines lines) (cons 'items items)))

;; (pfw:db) -> the remembered list; read now if there is none.  Kept only
;;   while the reactor is watching -- without it there is no telling the
;;   drawing changed, so every click reads.
(defun pfw:db ( / r)
  (cond
    (*pfw-db*)
    (T
     (pfw:db-watch)
     (setq r (pfw:read))
     ;; a change during the read (none is expected) switched the watch off:
     ;; don't keep what may already be out of date
     (if (pfw:db-watching-p) (setq *pfw-db* r))
     r)))

(defun pfw:db-get (k) (cdr (assoc k (pfw:db))))

;; (pfw:db-forget) -> nil   the next click reads the drawing again
(defun pfw:db-forget () (setq *pfw-db* nil))

;; --- the drawing-change reactor --------------------------------------------
(setq *pfw-db-tag* "PFSUITE-PALETTE")

;; the callback: anything changed.  Empties the list and switches the reactor
;; off -- the next read switches it back on.  Nothing else: a callback must
;; not touch the drawing.
(defun pfw:db-changed (r args)
  (setq *pfw-db* nil)
  (vl-catch-all-apply 'vlr-remove (list r))
  (princ))

;; (pfw:db-reactors) -> this drawing's palette reactors (normally one)
(defun pfw:db-reactors ( / out)
  (foreach grp (vlr-reactors :vlr-acdb-reactor)
    (foreach r (cdr grp)
      (if (equal (vlr-data r) *pfw-db-tag*) (setq out (cons r out)))))
  out)

;; (pfw:db-reactor-p x) -> T when x is a reactor object
(defun pfw:db-reactor-p (x)
  (and x (not (vl-catch-all-error-p (vl-catch-all-apply 'vlr-type (list x))))))

;; (pfw:db-watch) -> T | nil   ONE reactor, switched on: the one this drawing
;;   already has (a reload of this file keeps it), any other of ours removed.
(defun pfw:db-watch ( / r)
  (setq r (vl-catch-all-apply
            '(lambda ()
               (if (pfw:db-reactor-p *pfw-db-reactor*)
                 (foreach x (pfw:db-reactors) (if (not (eq x *pfw-db-reactor*)) (vlr-remove x)))
                 (progn
                   (foreach x (pfw:db-reactors) (vlr-remove x))
                   (setq *pfw-db-reactor*
                     (vlr-acdb-reactor *pfw-db-tag*
                       '((:vlr-objectAppended   . pfw:db-changed)
                         (:vlr-objectUnAppended . pfw:db-changed)
                         (:vlr-objectReAppended . pfw:db-changed)
                         (:vlr-objectModified   . pfw:db-changed)
                         (:vlr-objectErased     . pfw:db-changed)
                         (:vlr-objectUnErased   . pfw:db-changed))))))
               (if (not (vlr-added-p *pfw-db-reactor*)) (vlr-add *pfw-db-reactor*))
               T)
            nil))
  (if (vl-catch-all-error-p r) (progn (setq *pfw-db-reactor* nil) nil) r))

;; (pfw:db-watching-p) -> T while the reactor is on
(defun pfw:db-watching-p ()
  (and *pfw-db-reactor*
       (not (vl-catch-all-error-p (vl-catch-all-apply 'vlr-added-p (list *pfw-db-reactor*))))
       (vlr-added-p *pfw-db-reactor*)
       T))

;; the reactor this drawing already has survives a reload of this file (the
;; first read switches it back on); only a first load starts with none
(if (not (boundp '*pfw-db-reactor*)) (setq *pfw-db-reactor* nil))

;; Clicked reports a zero-based row number; blank space reports no valid row.
(defun pfw:run-row-at (row)
  (if (and (numberp row) (>= row 0)) (nth row *pfw-items*)))

(defun pfw:run-stations (r)
  (if (eq (car r) 'pipe)
    (strcat (pfl:fmt-sta (nth 3 r)) " to " (pfl:fmt-sta (nth 4 r)))
    (pfl:fmt-sta (nth 3 r))))


;;; ==========================================================================
;;; SECTION 3  --  Filling the controls
;;; ==========================================================================

;; (pfw:list ctrl pairs) -> nil   a two-column List View, V5's row shape
(defun pfw:list (ctrl pairs)
  (if ctrl
    (dcl-ListView-FillList ctrl (mapcar '(lambda (p) (list (car p) -1 (cdr p) -1)) pairs)))
  (princ))

;; (pfw:caption ctrl text) -> nil   only if the control is in the project
(defun pfw:caption (ctrl text)
  (if ctrl (vl-catch-all-apply 'dcl-Control-SetCaption (list ctrl text)))
  (princ))

;; (pfw:fill-tree ctrl rows) -> map   utility parents, line children
;;   Each item marks the trail with its label and keys (2026-11-03: the first
;;   fill stopped "stringp T" inside this function, and the code alone
;;   couldn't say which argument was T).
(defun pfw:fill-tree (ctrl rows / cur pkey map lbl)
  (pfw:mark "Tree-Clear")
  (dcl-Tree-Clear ctrl)
  (foreach r rows
    (if (not (equal (car r) cur))
      (progn
        (setq cur (car r))
        (pfw:mark (strcat "parent " (vl-prin1-to-string cur)))
        (setq pkey (dcl-Tree-AddParent ctrl cur -1 -1 -1))
        (pfw:mark (strcat "  -> key " (vl-prin1-to-string pkey)))))
    (setq lbl (if (= (type (cadr r)) 'STR) (strcat (cadr r) (if (nth 3 r) "" "  -- no grid yet")) (cadr r)))
    (pfw:mark (strcat "child " (vl-prin1-to-string lbl) " under " (vl-prin1-to-string pkey)))
    (setq map (cons (cons (dcl-Tree-AddChild ctrl pkey lbl -1 -1 -1) r) map)))
  map)

;; (pfw:show tab row) -> nil   the panels beside a tab's tree
(defun pfw:show (tab row)
  (if (eq tab 'setup)
    (progn
      (setq *pfw-sel-setup* row)
      (pfw:list pfsuite/pfsPalette/metaList (pfw:meta-rows row))
      (pfw:list pfsuite/pfsPalette/lvwLinkage (pfw:file-rows row)))
    (progn
      (setq *pfw-sel-run* row *pfw-sel-struct* nil *pfw-sel-pipe* nil)
      (pfw:list pfsuite/pfsPalette/detailsList (pfw:meta-rows row))
      (pfw:fill-items row)))
  (princ))

;; lvwCommand now contains structures and pipes in station order.
(defun pfw:fill-items (row / old)
  (setq *pfw-items* (if row (pfw:run-rows (nth 2 row)))
        old *pfw-filling* *pfw-filling* T)
  (if pfsuite/pfsPalette/lvwCommand
    (dcl-ListView-FillList pfsuite/pfsPalette/lvwCommand
      (mapcar '(lambda (r)
                 (list (nth 2 r) -1 (pfw:run-stations r) -1 (nth 5 r) -1))
              *pfw-items*)))
  (setq *pfw-filling* old)
  (princ))

;; (pfw:refresh) -> nil   THE one fill: both trees and the footer.  V5's
;;   shape (Jake, 2026-11-03: "look at how V5 handled the palette"): the
;;   picks are CLEARED first -- a rebuilt tree makes them stale -- and
;;   everything after that runs inside one catch, so a bad drawing can never
;;   stop the palette opening.  The trees come back with nothing picked.
;;   (Re-picking the last line was tried first; the read-back, outside the
;;   catch, stopped every open with "consp nil".)
(defun pfw:refresh ( / rows res)
  (setq *pfw-sel-setup* nil *pfw-sel-run* nil)
  (setq res (vl-catch-all-apply
              '(lambda ( / s r)
                 (pfw:stage "repaint: reading the drawing (or the remembered list)")
                 (setq rows (pfw:db-get 'lines) *pfw-filling* T)
                 (pfw:stage "repaint: filling tvwLines")
                 (setq s (pfw:fill-tree pfsuite/pfsPalette/tvwLines rows))
                 (pfw:stage "repaint: filling tarLines")
                 (setq r (pfw:fill-tree pfsuite/pfsPalette/tarLines rows)
                       *pfw-maps* (list (cons 'setup s) (cons 'run r)))
                 (setq *pfw-filling* nil)
                 (pfw:stage "repaint: lblCounts")
                 (pfw:caption pfsuite/pfsPalette/lblCounts
                              (strcat (itoa (length rows)) " lines  ("
                                      (itoa (length (vl-remove-if-not '(lambda (r) (nth 3 r)) rows)))
                                      " with grids)"))
                 (pfw:stage "repaint: emptying the panels")
                 (pfw:show 'setup nil)
                 (pfw:show 'run nil)
                 (pfw:stage "repaint: done"))
              nil))
  ;; outside the catch: a throw mid-fill must not deaden the trees
  (setq *pfw-filling* nil)
  (if (vl-catch-all-error-p res)
    (progn
      (pfl:say (strcat "PFPALETTE: filling the palette stopped"
                       (if *pfw-stage* (strcat " while " *pfw-stage*) "")
                       ": " (vl-catch-all-error-message res)))
      (pfw:say-trail)))
  (setq *pfw-stage* nil)
  (princ))

;; tree picks: READ ONLY (Event Invoke 0)
(defun pfw:on-pick (tab key)
  (if (not *pfw-filling*) (pfw:show tab (cdr (assoc key (cdr (assoc tab *pfw-maps*))))))
  (princ))

;; the handlers' arguments reach the guarded work through these
(setq *pfw-key* nil)

(defun c:pfsuite/pfsPalette/tvwLines#OnSelChanged (Label Key)
  (setq *pfw-key* Key)
  (pfw:guard "tvwLines" '(lambda () (pfw:on-pick 'setup *pfw-key*))))
(defun c:pfsuite/pfsPalette/tarLines#OnSelChanged (Label Key)
  (setq *pfw-key* Key)
  (pfw:guard "tarLines" '(lambda () (pfw:on-pick 'run *pfw-key*))))

;; An item picked in lvwCommand: READ ONLY (Event Invoke 0).  A List
;; View in this OpenDCL has NO SelChanged event -- its event is Clicked,
;; (Row Column) (Studio's Events tab, 2026-11-13).  Only a real row changes
;; the pick; a click on no row leaves it.  The pick says so -- silence is how
;; an unticked event looks.
(defun pfw:on-item (row / item)
  (if (and (not *pfw-filling*) (setq item (pfw:run-row-at row)))
    (progn
      ;; a crossing edits like a pipe: one dialog, then the line's refresh
      (setq *pfw-sel-struct* (if (eq (car item) 'structure) (cadr item))
            *pfw-sel-pipe* (if (member (car item) '(pipe crossing)) (cadr item)))
      (pfl:say (strcat "PFPALETTE: " (nth 2 item) " picked.")))))

(defun c:pfsuite/pfsPalette/lvwCommand#OnClicked (Row Column)
  (setq *pfw-key* Row)
  (pfw:guard "lvwCommand" '(lambda () (pfw:on-item *pfw-key*))))


;;; ==========================================================================
;;; SECTION 4  --  The buttons
;;; ==========================================================================
;;; A button that changes the drawing needs Event Invoke = 1 in Studio: its
;;; handler then runs as a command, and the work goes through pfd:run (one
;;; undo group, the stage named on an error), then the palette repaints.
;;; The work reads the picked row at run time, so nothing stale is carried.

;; (pfw:need tab want) -> the picked row | nil, saying why not
;;   want: 'any, 'grid (anchored), 'stub (named, no grid yet)
(defun pfw:need (tab want / row)
  (setq row (if (eq tab 'setup) *pfw-sel-setup* *pfw-sel-run*))
  (cond
    ((null row) (pfl:say "PFPALETTE: pick a line in the tree first.") nil)
    ((and (eq want 'grid) (null (nth 3 row)))
     (pfl:say (strcat "PFPALETTE: " (nth 2 row) " has no grid yet -- Anchor it on the Setup tab.")) nil)
    ((and (eq want 'stub) (nth 3 row))
     (pfl:say (strcat "PFPALETTE: " (nth 2 row) " already has a grid -- use Edit.")) nil)
    (T row)))

;; (pfw:act name fn) -> nil   the work, then the repaint
;;   The work changed the drawing: the remembered list is emptied first.
(defun pfw:act (name fn)
  (pfw:mark (strcat name " starting"))
  (pfd:run name fn)
  (pfw:mark (strcat name " closed its undo group"))
  (pfw:db-forget)
  (pfw:refresh)
  (princ))

;; (pfw:reshow) -> nil   after a button's work that keeps the line picked:
;;   the remembered list emptied, the picked line's list filled again
(defun pfw:reshow ()
  (pfw:mark "refilling the list")
  (pfw:db-forget)
  (pfw:show 'run *pfw-sel-run*))

;; (pfw:setup fn) -> nil   PFSETUP's own refusals (metric, no Carlson) first
(defun pfw:setup (fn / why)
  (pfw:mark "checking Carlson")
  (if (setq why (pfn:refusal))
    (pfl:say why)
    (progn (pfw:mark "the work") (apply fn nil) (pfw:mark "the work returned")))
  (princ))

;; --- Setup tab ---------------------------------------------------------------
(defun pfw:do-scan   () (pfw:setup 'pfn:scan-run))
(defun pfw:do-new    () (pfw:setup '(lambda () (pfn:place nil))))
(defun pfw:do-anchor () (pfw:setup '(lambda () (pfn:place (nth 4 *pfw-sel-setup*)))))
(defun pfw:do-edit ( / a)
  (setq a (nth 3 *pfw-sel-setup*))
  (if (pfg:copy-p a)
    (pfl:say "PFPALETTE: that anchor is a COPY of another one -- Remove it.")
    (pfw:setup '(lambda () (pfn:edit (nth 3 *pfw-sel-setup*))))))
(defun pfw:do-remove () (pfn:remove-ask (nth 3 *pfw-sel-setup*)))

;; (pfw:zoom row) -> nil   to the grid, or to the line in plan when it has
;;   no grid yet.  A view change, not a drawing write.
(defun pfw:zoom (row / c geo b m)
  (cond
    ((and (nth 3 row) (setq c (pfn:corners (nth 3 row)))))
    ((and (nth 4 row) (pfm:find-cl (caddr (nth 4 row)))
          (setq geo (pfm:geom (pfm:find-cl (caddr (nth 4 row))))))
     (setq b (cadddr geo) c (list (list (car b) (cadr b)) (list (caddr b) (cadddr b))))))
  (if (null c)
    (pfl:say (strcat "PFPALETTE: nowhere to zoom to for " (nth 2 row) "."))
    (progn
      (setq m (* 0.05 (max (- (car (cadr c)) (car (car c))) (- (cadr (cadr c)) (cadr (car c))))))
      (vla-ZoomWindow (vlax-get-acad-object)
                      (vlax-3d-point (list (- (car (car c)) m) (- (cadr (car c)) m) 0.0))
                      (vlax-3d-point (list (+ (car (cadr c)) m) (+ (cadr (cadr c)) m) 0.0)))))
  (princ))

(defun c:pfsuite/pfsPalette/btnScan#OnClicked ()
  (pfw:guard "Scan" '(lambda () (pfw:act "PFSETUP" 'pfw:do-scan))))
(defun c:pfsuite/pfsPalette/btnNew#OnClicked ()
  (pfw:guard "New" '(lambda () (pfw:act "PFSETUP" 'pfw:do-new))))
(defun c:pfsuite/pfsPalette/btnAnchor#OnClicked ()
  (pfw:guard "Anchor" '(lambda () (if (pfw:need 'setup 'stub) (pfw:act "PFSETUP" 'pfw:do-anchor)))))
(defun c:pfsuite/pfsPalette/btnEdit#OnClicked ()
  (pfw:guard "Edit" '(lambda () (if (pfw:need 'setup 'grid) (pfw:act "PFSETUP" 'pfw:do-edit)))))
(defun c:pfsuite/pfsPalette/btnRemove#OnClicked ()
  (pfw:guard "Remove" '(lambda () (if (pfw:need 'setup 'grid) (pfw:act "PFREMOVE" 'pfw:do-remove)))))
(defun c:pfsuite/pfsPalette/btnZoom#OnClicked ()
  (pfw:guard "Zoom To" '(lambda ( / row) (if (setq row (pfw:need 'setup 'any)) (pfw:zoom row)))))
(defun c:pfsuite/pfsPalette/btnIndex#OnClicked ()
  (pfl:say "PFPALETTE: Index has no V6 job yet.") (princ))

;; --- Run tab -------------------------------------------------------------------
(defun pfw:do-assign  () (pfa:line (nth 2 *pfw-sel-run*)))
;; New Structure: placed, then the line refreshed -- the new copies' invert
;; rows are PFREFRESH's (pf-invert), so they show straight away
(defun pfw:do-struct  ()
  (pfs:main-for (nth 2 *pfw-sel-run*))
  (pfu:run (list "Line" (nth 2 *pfw-sel-run*)) nil nil))
;; Crossings: PFXLABEL on the line picked (Jake, 2026-11-20)
(defun pfw:do-xing ( / r)
  (pfc:load)
  (setq r (pfk:run (nth 2 *pfw-sel-run*) (pfg:usable)))
  (pfw:caption pfsuite/pfsPalette/lblCounts
               (if (nth 4 r)
                 (strcat "** " (itoa (length (nth 4 r))) " crossing(s) on " (nth 2 *pfw-sel-run*) " need a look")
                 (strcat "Crossings on " (nth 2 *pfw-sel-run*) ": none short")))
  (pfl:say "  One UNDO takes this whole run back."))
(defun pfw:do-refresh-line ()
  (pfc:load)
  (pfu:run (list "Line" (nth 2 *pfw-sel-run*)) nil nil)
  (pfl:say "  One UNDO takes this whole run back."))
(defun pfw:do-refresh-all ()
  (pfc:load)
  (pfu:run (list "Drawing") nil nil)
  (pfl:say "  One UNDO takes this whole run back."))

(defun c:pfsuite/pfsPalette/btnAssign#OnClicked ()
  (pfw:guard "Assign" '(lambda () (if (pfw:need 'run 'any) (pfw:act "PFASSIGN" 'pfw:do-assign)))))
(defun c:pfsuite/pfsPalette/btnStruct#OnClicked ()
  (pfw:guard "New Structure" '(lambda () (if (pfw:need 'run 'grid) (pfw:act "PFSTRUCT" 'pfw:do-struct)))))
(defun c:pfsuite/pfsPalette/btnPipe#OnClicked ()
  (pfw:guard "New Pipe" '(lambda () (pfw:act "PFPIPE" 'pfp:main))))
(defun c:pfsuite/pfsPalette/btnRefreshLine#OnClicked ()
  (pfw:guard "Refresh Line" '(lambda () (if (pfw:need 'run 'any) (pfw:act "PFREFRESH" 'pfw:do-refresh-line)))))
(defun c:pfsuite/pfsPalette/btnRefreshAll#OnClicked ()
  (pfw:guard "Refresh All" '(lambda () (pfw:act "PFREFRESH" 'pfw:do-refresh-all))))

;; Crossings keeps the line picked: its list refills with each crossing's
;; status, the palette's warning (no tree rebuild, like Defaults)
(defun c:pfsuite/pfsPalette/btnXing#OnClicked ()
  (pfw:guard "Crossings"
    '(lambda ()
       (if (pfw:need 'run 'grid)
         (progn
           (pfd:run "PFXLABEL" 'pfw:do-xing)
           (pfw:reshow))))))

;; the list is filled again only when edits were saved -- a cancel changed
;; nothing (Jake, 2026-11-20: a canceled Defaults took a full minute)
(defun c:pfsuite/pfsPalette/btnDefaults#OnClicked ()
  (pfw:guard "Defaults"
    '(lambda ()
       (if (pfw:need 'run 'grid)
         (if (pfw:dflt-open (nth 2 *pfw-sel-run*))
           (pfw:reshow))))))

;; --- Defaults: the pfsDefaults modal form, and PFDEFAULTS ---------------------
;; Moved here from pf-defaults (2026-11-17) so the load order holds: this
;; part reads structures, grids and pipes and runs PFREFRESH, so it sits with
;; the palette, which may call every module.  pf-defaults keeps the storage
;; and look-up (pfv:).  Form: pfsuite/pfsDefaults (modal), grdDefaults with
;; seven columns, btnSave and btnCancel.  Grid edits stay in the form until
;; Save.  Contract: pf-defaults README.

;; (pfw:setting-spec) -> the settings as one more group of the catalog:
;;   (kind type tags defaults) -- saved and looked up like the label defaults
(defun pfw:setting-spec ()
  (list *pf-setting-kind* "" (mapcar 'car *pf-settings*) *pf-settings*))

;; (pfw:dflt-catalog) -> every default PFDEFAULTS can edit, as rows
;;   (utility line kind type tag builtin).  Empty line = utility scope; empty
;;   utility and line = drawing scope.  Only block types and utilities that
;;   exist in this drawing.
(defun pfw:dflt-catalog (/ types lines utils ty ln out spec tag e g s u)
  (foreach e (pfr:all nil)
    (if (and (setq ty (pfs:type-of e)) (not (member ty types)))
      (setq types (cons ty types))))
  (foreach g (pfg:usable)
    (if (and (setq ln (pfg:line-name g)) (not (member ln lines)))
      (setq lines (cons ln lines))))
  (foreach ln lines
    (if (not (member (pfv:utility ln) utils))
      (setq utils (cons (pfv:utility ln) utils))))
  (setq spec (mapcar '(lambda (x) (list "STRUCT" x *pf-tags-fmt* (pfs:fmt-defaults x)))
                     (acad_strlsort types)))
  (if (pfp:all)
    (setq spec (append spec (list (list "PIPE" "" *pf-pipe-tags-fmt* *pf-pipe-fmt-defaults*)))))
  ;; the settings (plan label height, crossing clearance -- 2026-11-20)
  (setq spec (append spec (list (pfw:setting-spec))))
  (foreach s spec
    (foreach tag (caddr s)
      (setq out (cons (list "" "" (car s) (cadr s) tag (pfr:input tag (cadddr s))) out))
      (foreach u (acad_strlsort utils)
        (setq out (cons (list u "" (car s) (cadr s) tag (pfr:input tag (cadddr s))) out)))
      (foreach ln (acad_strlsort lines)
        (setq out (cons (list (pfv:utility ln) ln (car s) (cadr s) tag
                              (pfr:input tag (cadddr s))) out)))))
  (reverse out))

;; (pfw:dflt-line-catalog line) -> the same rows, one line only: the types
;;   actually assigned to it, and pipes if one has both ends on one usable
;;   grid of it.  Read off the line's Run list (pfw:db) -- the drawing is not
;;   searched again (2026-11-20: this was half of a minute-long Defaults).
(defun pfw:dflt-line-catalog (line / types pipes ty out spec tag s)
  ;; the plain list -- the "needs refresh" check isn't wanted here
  (foreach r (cdr (assoc line (pfw:db-get 'items)))
    (cond
      ((eq (car r) 'pipe) (setq pipes T))
      ((and (eq (car r) 'structure)
            (setq ty (pfs:type-of (cadr r)))
            (not (member ty types)))
       (setq types (cons ty types)))))
  (setq spec (mapcar '(lambda (x) (list "STRUCT" x *pf-tags-fmt* (pfs:fmt-defaults x)))
                     (acad_strlsort types)))
  (if pipes
    (setq spec (append spec (list (list "PIPE" "" *pf-pipe-tags-fmt* *pf-pipe-fmt-defaults*)))))
  (setq spec (append spec (list (pfw:setting-spec))))
  (foreach s spec
    (foreach tag (caddr s)
      (setq out (cons (list (pfv:utility line) line (car s) (cadr s) tag
                            (pfr:input tag (cadddr s))) out))))
  (reverse out))

(setq *pfw-dflt-inherit* "Use inherited default")

;; Display names only.  The saved keys remain the exact attribute tags.
(setq *pfw-dflt-type-labels*
  '(("CBI" . "Curb box inlet")
    ("CBI-BOX" . "Curb box inlet (box)")
    ("DBI" . "Drop box inlet")
    ("SMH" . "Sanitary manhole")
    ("DMH" . "Drainage manhole")
    ("MH" . "Manhole")
    ("HDWL" . "Headwall")))

(setq *pfw-dflt-setting-labels*
  '(("PFSTAPRE" . "Station Prefix")
    ("PFSTASUF" . "Station Suffix")
    ("PFCONPRE" . "Construction Prefix")
    ("PFCONSUF" . "Construction Suffix")
    ("PFELEVPRE" . "Elevation Prefix")
    ("PFELEVSUF" . "Elevation Suffix")
    ("PFLENPRE" . "Length Prefix")
    ("PFLENSUF" . "Length Suffix")
    ("PFSLOPEPRE" . "Slope Prefix")
    ("PFSLOPESUF" . "Slope Suffix")
    ("PFPLANHT"   . "Plan Label Height (PFASSIGN applies it)")
    ("PFCLRMIN"   . "Crossing Clearance Minimum (inches)")
    ("PFCLRWARN"  . "Dimension When Within (inches)")))

(defun pfw:dflt-type-label (kind ty)
  (cond ((= kind "PIPE") "Pipe")
        ((= kind *pf-setting-kind*) "Settings")
        ((cdr (assoc ty *pfw-dflt-type-labels*)))
        (ty)))

;; A headwall's elevation prefix / suffix label its INVERT (PFINV1).
(defun pfw:dflt-setting-label (tag ty)
  (cond
    ((and (= ty "HDWL") (= tag *pf-tag-elev-pre*)) "Invert Prefix")
    ((and (= ty "HDWL") (= tag *pf-tag-elev-suf*)) "Invert Suffix")
    ((cdr (assoc tag *pfw-dflt-setting-labels*)))
    (tag)))

(setq *pfw-dflt-line* nil *pfw-dflt-doc* nil *pfw-dflt-rows* nil
      *pfw-dflt-grid-rows* nil
      *pfw-dflt-staged* nil *pfw-dflt-ready* nil)

(defun pfw:dflt-fill (/ ctrl item raw row group last-group label)
  (setq ctrl pfsuite/pfsDefaults/grdDefaults)
  (setq *pfw-dflt-ready* nil *pfw-dflt-grid-rows* nil)
  (if (or (null ctrl) (/= 7 (dcl-Grid-GetColumnCount ctrl)))
    (pfl:say "PFDEFAULTS: grdDefaults needs seven columns in Studio.")
    (progn
      (dcl-Control-SetTitleBarText pfsuite/pfsDefaults
                                   (strcat "PFSUITE Defaults - " *pfw-dflt-line*
                                           " - Edit line defaults"))
      (dcl-Control-SetColumnCaptionList ctrl
        '("Scope" "Utility" "Line" "Block type" "Setting"
          "Line Default (edit)" "Inherited Default"))
      (dcl-Control-SetColumnWidthList ctrl '(0 0 0 165 245 170 170))
      (dcl-Grid-Clear ctrl)
      (foreach item *pfw-dflt-rows*
        (setq group (if (member (caddr item) (list "PIPE" *pf-setting-kind*)) (caddr item) (cadddr item))
              label (pfw:dflt-type-label (caddr item) (cadddr item)))
        (if (/= group last-group)
          (progn
            (if last-group
              (progn
                (setq row (dcl-Grid-AddString ctrl ""))
                (dcl-Grid-SetItemStyle ctrl row 5 0)))
            ;; This heading is display-only.  Every following field belongs
            ;; to this block type until the next heading.
            (setq row (dcl-Grid-AddString ctrl
              (strcat "\t\t\t" label "\t\t\t")))
            (dcl-Grid-SetItemStyle ctrl row 5 0)
            (setq last-group group)))
        (setq raw (pfv:raw (car item) (cadr item) (caddr item) (cadddr item) (nth 4 item))
              row (dcl-Grid-AddString ctrl
                    (strcat "Line\t" (car item) "\t" (cadr item) "\t"
                            label "\t" (pfw:dflt-setting-label (nth 4 item) (cadddr item)) "\t"
                            (if raw raw *pfw-dflt-inherit*) "\t"
                            (pfv:effective-for (car item) "" (caddr item)
                                               (cadddr item) (nth 4 item) (nth 5 item)))))
        (dcl-Grid-SetItemStyle ctrl row 5 6)
        (setq *pfw-dflt-grid-rows* (cons (cons row item) *pfw-dflt-grid-rows*)))
      (setq *pfw-dflt-grid-rows* (reverse *pfw-dflt-grid-rows*))
      (setq *pfw-dflt-ready* T))))

(defun c:pfsuite/pfsDefaults#OnInitialize () (pfw:dflt-fill))

(defun c:pfsuite/pfsDefaults/btnSave#OnClicked (/ ctrl item value old pair bad)
  (if (null *pfw-dflt-ready*)
    (pfl:say "PFDEFAULTS: the dialog grid is incomplete; nothing saved.")
    (progn
      (setq ctrl pfsuite/pfsDefaults/grdDefaults *pfw-dflt-staged* nil)
      (foreach pair *pfw-dflt-grid-rows*
        (setq item (cdr pair)
              value (dcl-Grid-GetCellText ctrl (car pair) 5)
              old (pfv:raw (car item) (cadr item) (caddr item) (cadddr item) (nth 4 item))
              old (if old old *pfw-dflt-inherit*))
        (if (null value)
          (setq bad T)
          (if (/= value old)
            (setq *pfw-dflt-staged* (cons (cons item value) *pfw-dflt-staged*)))))
      (if bad
        (progn (setq *pfw-dflt-staged* nil)
               (pfl:say "PFDEFAULTS: a grid value could not be read; nothing saved."))
        (dcl-Form-Close pfsuite/pfsDefaults 1)))))

(defun c:pfsuite/pfsDefaults/btnCancel#OnClicked ()
  (setq *pfw-dflt-staged* nil)
  (dcl-Form-Close pfsuite/pfsDefaults 2))

;; (pfw:dflt-apply) -> (saved failed)   the staged edits written, then the
;;   line refreshed if every one took.  Runs inside pfd:run (one undo group).
(defun pfw:dflt-apply (/ item value saved failed change)
  (foreach change (reverse *pfw-dflt-staged*)
    (setq item (car change) value (cdr change))
    (if (if (or (= value *pfw-dflt-inherit*) (= value "<inherit>"))
          (pfv:reset (car item) (cadr item) (caddr item) (cadddr item) (nth 4 item))
          (pfv:save (car item) (cadr item) (caddr item) (cadddr item) (nth 4 item) value))
      (setq saved (1+ (cond (saved) (0))))
      (setq failed (1+ (cond (failed) (0))))))
  (pfl:say (strcat "PFDEFAULTS: " (itoa (cond (saved) (0))) " saved, "
                   (itoa (cond (failed) (0))) " failed on " *pfw-dflt-line* "."))
  (if (and saved (= (cond (failed) (0)) 0))
    (pfu:run (list "Line" *pfw-dflt-line*) nil nil))
  (list saved failed))

;; (pfw:dflt-open line) -> T | nil   the Defaults button: the modal form for
;;   one line.  T only when edits were saved (and the line refreshed) -- the
;;   button refills its list only then; a cancel left nothing to show
;;   (Jake, 2026-11-20: a canceled Defaults took a full minute).
(defun pfw:dflt-open (line / form status ran)
  (setq form pfsuite/pfsDefaults)
  (cond
    ((null form) (pfl:say "PFDEFAULTS: add the pfsDefaults modal form to pfsuite.odcl, save, and run PFPRELOAD."))
    ((null (setq *pfw-dflt-rows* (pfw:dflt-line-catalog line)))
     (pfl:say (strcat "PFDEFAULTS: no assigned structure types or valid pipes on " line ".")))
    (T
     (setq *pfw-dflt-line* line
           *pfw-dflt-doc* (vla-get-ActiveDocument (vlax-get-acad-object))
           *pfw-dflt-staged* nil *pfw-dflt-ready* nil)
     (setq status (dcl-Form-Show form))
     (cond
       ((/= status 1) (pfl:say "PFDEFAULTS: canceled; no defaults changed."))
       ((not (equal *pfw-dflt-doc* (vla-get-ActiveDocument (vlax-get-acad-object))))
        (pfl:say "PFDEFAULTS: active drawing changed; nothing saved."))
       (*pfw-dflt-staged* (pfd:run "PFDEFAULTS" 'pfw:dflt-apply) (setq ran T))
       (T (pfl:say "PFDEFAULTS: no defaults changed.")))))
  (setq *pfw-dflt-staged* nil *pfw-dflt-doc* nil *pfw-dflt-rows* nil
        *pfw-dflt-grid-rows* nil
        *pfw-dflt-ready* nil)
  ran)

;; (pfw:dflt-command) -> nil   PFDEFAULTS at the command line: drawing,
;;   utility and line scopes.  The catalog is the same as the Grid's.
(defun pfw:dflt-command (/ rows i row value)
  (setq rows (pfw:dflt-catalog) i 0)
  (if (null rows)
    (pfl:say "PFDEFAULTS: no supported structures or pipes in this drawing.")
    (progn
      (foreach row rows
        (setq i (1+ i))
        (pfl:say (strcat "  " (itoa i) ". "
                         (cond ((/= (cadr row) "") (cadr row))
                               ((/= (car row) "") (strcat (car row) " utility"))
                               ("Drawing")) "  " (caddr row) " " (cadddr row)
                         "  " (nth 4 row) " = "
                         (cond ((pfv:raw (car row) (cadr row) (caddr row)
                                         (cadddr row) (nth 4 row))) ("<inherit>")))))
      (initget 6)
      (setq i (getint "\nDefault row number <cancel>: "))
      (if (and i (setq row (nth (1- i) rows)))
        (progn
          (setq value (getstring T "\nNew value (blank saves blank; <inherit> resets): "))
          (if (if (= value "<inherit>")
                (pfv:reset (car row) (cadr row) (caddr row) (cadddr row) (nth 4 row))
                (pfv:save (car row) (cadr row) (caddr row) (cadddr row) (nth 4 row) value))
            (pfl:say "PFDEFAULTS: saved in this drawing. Run PFREFRESH to apply.")
            (pfl:say "PFDEFAULTS: the default could not be saved."))))))
  (princ))

(defun c:PFDEFAULTS () (pfd:run "PFDEFAULTS" 'pfw:dflt-command) (princ))

;; --- Edit Attributes: AutoCAD's own dialog on the picked item ------------------
;; Jake, 2026-11-13: "I'm okay with the palette just opening the enhanced
;; attribute editor" -- and "This needs to edit the profile block as well or
;; you cant change the prefixes and suffixes."  So two dialogs, in turn:
;;   the PLAN block   the record: name, rim, face
;;   its profile copy ON THE PICKED LINE   the prefixes / suffixes and the
;;                    label rows (a row typed over there is kept)
;; Values typed are the drafter's, kept by Assign and Refresh like Properties
;; edits (pfr:refresh adopts them).  Size is PFSIZE_LU, a parameter, so it
;; stays in Properties.  Then the LINE is refreshed: a new rim moves the copy.
;; A prefix typed on the copy stays on that copy only (Jake, 2026-11-17);
;; wording for the whole line is the Defaults button's.  One UNDO takes all
;; of it back.

;; (pfw:need-edit-target) -> picked structure or pipe | nil
(defun pfw:need-edit-target ()
  (cond
    ((null *pfw-sel-run*) (pfl:say "PFPALETTE: pick a line in the tree first.") nil)
    ((null (or *pfw-sel-struct* *pfw-sel-pipe*))
     (pfl:say "PFPALETTE: pick a structure or pipe in its list first.") nil)
    ;; cond, not or: AutoLISP's or returns T, not the item (entget T failed)
    ((not (entget (cond (*pfw-sel-struct*) (*pfw-sel-pipe*))))
     (pfl:say "PFPALETTE: that item is gone -- pick the line again.") nil)
    (T (cond (*pfw-sel-struct*) (*pfw-sel-pipe*)))))

;; (pfw:struct-copy e lname) -> plan block e's profile copy on line lname | nil
(defun pfw:struct-copy (e lname)
  (pfs:find-copy (pfl:handle e) lname (pfs:copies-if '(lambda (c p l) (= l lname)))))

;; (pfw:after-edit lname fmt pin) -> the refresh's counts   the line brought
;;   up to date: PFREFRESH, Line scope.  fmt / pin nil = each block's saved
;;   defaults, as the command does; PFSELFTEST may hand in its own.
(defun pfw:after-edit (lname fmt pin)
  (pfc:load)
  (pfu:run (list "Line" lname) fmt pin))

;; (pfw:eattedit e) -> nil   AutoCAD's dialog on block e.  initdia: a dialog
;;   command started from code may fall back to prompts without it.
(defun pfw:eattedit (e)
  (initdia)
  (command "_.EATTEDIT" e)
  (princ))

;; (pfw:do-edit-struct) -> nil   both dialogs, then the line's refresh
(defun pfw:do-edit-struct ( / e lname pe)
  (setq e     *pfw-sel-struct*
        lname (nth 2 *pfw-sel-run*)
        pe    (pfw:struct-copy e lname))
  (pfw:mark "EATTEDIT plan")
  (pfw:eattedit e)
  (if pe
    (progn (pfw:mark "EATTEDIT profile") (pfw:eattedit pe))
    (pfl:say (strcat "  No profile copy on " lname " yet -- New Structure places one; plan block edited only.")))
  (pfw:mark "refreshing the line")
  (pfw:after-edit lname nil nil)
  (princ))

;; Per-pipe label inputs and material can be edited here.  Pipe size is the
;; PFSIZE_LU dynamic property and must be changed in AutoCAD Properties.
(defun pfw:do-edit-pipe ( / lname)
  (setq lname (nth 2 *pfw-sel-run*))
  (pfw:mark "EATTEDIT pipe")
  (pfw:eattedit *pfw-sel-pipe*)
  (pfw:mark "refreshing the line")
  (pfw:after-edit lname nil nil)
  (princ))

;; After the edit the line's list is refilled (statuses may change) but the
;; trees are left alone, so the line stays picked; pick the structure again.
(defun c:pfsuite/pfsPalette/btnEditStruct#OnClicked ()
  (pfw:guard "Edit Attributes"
             '(lambda ()
                (if (pfw:need-edit-target)
                  (progn
                    (pfd:run "Edit Attributes"
                             (if *pfw-sel-pipe* 'pfw:do-edit-pipe 'pfw:do-edit-struct))
                    (pfw:reshow))))))

;; --- the footer, if the form still has V5's ------------------------------------
;; Refresh reads the drawing again, whatever the list remembers
(defun c:pfsuite/pfsPalette/btnRefresh#OnClicked ()
  (pfw:guard "Refresh" '(lambda () (pfw:db-forget) (pfw:refresh) (pfl:say "PFPALETTE: refreshed."))))
(defun c:pfsuite/pfsPalette/btnHelp#OnClicked ()
  (pfl:say "PFPALETTE: there is no V6 help page yet.")
  (princ))


(princ "\npf-palette loaded.  PFPALETTE, PFDEFAULTS (PFPRELOAD after a Studio save).")
(princ)
