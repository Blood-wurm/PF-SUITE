;;; ==========================================================================
;;; pf-palette.lsp  --  PFPALETTE: the OpenDCL palette.  Prefix pfw:.
;;; Load position 14: after pf-grid (it calls every command module).
;;; Contract, API and rules: README.md beside this file.
;;;
;;; V5's palette project, edited by Jake in OpenDCL Studio (2026-11-03):
;;; pfsuite-odcl\pfsuite.odcl, form pfsPalette, three tabs --
;;;   Setup  tvwLines -> metaList + lvwLinkage; Anchor Edit New Remove Zoom
;;;          Scan Index
;;;   Run    tarLines -> detailsList (+ lvwCommand, empty for now); Assign,
;;;          New Structure, New Pipe, Refresh Line, Refresh All
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
      *pfw-depth*     0)     ; guards running inside one another


;;; ==========================================================================
;;; SECTION 1  --  Loading and the toggle
;;; ==========================================================================

(defun pfw:odcl-path () (strcat *pf-root* "\\pfsuite-odcl\\pfsuite.odcl"))

;; (pfw:runtime) -> nil   brings OpenDCL up, quietly
(defun pfw:runtime ( / ce)
  (setq ce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_OPENDCL")
  (setvar "CMDECHO" ce)
  (princ))

;; (pfw:reload) -> the project | nil   re-read from disk, FORCED (dcl-
;;   Project-Load's second argument): without it a project already loaded
;;   this session -- V5's, or before a Studio save -- is kept, and PFPALETTE
;;   shows the old form (2026-11-03: a click called V5's btnSetup).  The form
;;   must be closed first.
(defun pfw:reload ( / r)
  (pfw:runtime)
  (vl-catch-all-apply '(lambda () (if (dcl-Form-IsActive pfsuite/pfsPalette)
                                    (dcl-Form-Close pfsuite/pfsPalette)))
                      nil)
  (setq *pfw-loaded* nil
        r (vl-catch-all-apply 'dcl-Project-Load (list (pfw:odcl-path) T)))
  (if (vl-catch-all-error-p r)
    (progn (pfl:say (strcat "PFPALETTE: reading " (pfw:odcl-path) " FAILED -- " (vl-catch-all-error-message r)))
           nil)
    (setq *pfw-loaded* r)))

;; (pfw:ensure) -> the project | nil   re-read from disk the first time this
;;   session; after that, the one already loaded
(defun pfw:ensure ()
  (if *pfw-loaded* (progn (pfw:runtime) *pfw-loaded*) (pfw:reload)))

;; Every control the code uses, by tab.  A missing one is named when the
;; palette opens -- the control symbols exist only while the form is open,
;; and reading a symbol's value touches no property, so this is safe.
(setq *pfw-controls*
  '("tvwLines" "metaList" "lvwLinkage" "btnScan" "btnAnchor" "btnEdit" "btnNew" "btnRemove" "btnZoom" "btnIndex"
    "tarLines" "detailsList" "lvwCommand" "btnAssign" "btnStruct" "btnPipe" "btnRefreshLine" "btnRefreshAll"))

;; (pfw:ctrl name) -> the control | nil
(defun pfw:ctrl (name) (eval (read (strcat "pfsuite/pfsPalette/" name))))

;; (pfw:census) -> nil   says which controls the loaded form lacks
(defun pfw:census ( / miss)
  (setq miss (vl-remove-if 'pfw:ctrl *pfw-controls*))
  (if miss (pfl:say (strcat "PFPALETTE: the loaded form has no " (pfl:join miss)
                            " -- check the (Name)s in Studio, save, PFPRELOAD.")))
  (if (pfw:ctrl "btnSetup")
    (pfl:say "PFPALETTE: the loaded form still has V5's btnSetup -- it's the old project."))
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
    ((not (pfw:ensure)) (pfl:say (strcat "PFPALETTE: could not load " (pfw:odcl-path))))
    ((dcl-Form-IsActive pfsuite/pfsPalette) (dcl-Form-Close pfsuite/pfsPalette))
    (T
     (setq *pfw-depth* 0)                   ; a guard an uncatchable error left counted
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
  (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwCommand  (list (list "Item" 0 150) (list "Station" 0 110)
                                                                (list "Status" 0 110)))
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

;; (pfw:lines) -> rows, by utility then line
(defun pfw:lines ( / out seen g ln at st)
  (foreach a (pfg:all)
    (if (not (pfg:copy-p a))
      (progn
        (setq g  (pfg:grid a)
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
      (setq *pfw-sel-run* row)
      (pfw:list pfsuite/pfsPalette/detailsList (pfw:meta-rows row))
      (pfw:list pfsuite/pfsPalette/lvwCommand nil)))
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
                 (pfw:stage "repaint: reading the anchors and stubs")
                 (setq rows (pfw:lines) *pfw-filling* T)
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
(defun pfw:act (name fn)
  (pfw:mark (strcat name " starting"))
  (pfd:run name fn)
  (pfw:mark (strcat name " closed its undo group"))
  (pfw:refresh)
  (princ))

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
(defun pfw:do-struct  () (pfs:main-for (nth 2 *pfw-sel-run*)))
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

;; --- the footer, if the form still has V5's ------------------------------------
(defun c:pfsuite/pfsPalette/btnRefresh#OnClicked ()
  (pfw:guard "Refresh" '(lambda () (pfw:refresh) (pfl:say "PFPALETTE: refreshed."))))
(defun c:pfsuite/pfsPalette/btnHelp#OnClicked ()
  (pfl:say "PFPALETTE: there is no V6 help page yet.")
  (princ))


(princ "\npf-palette loaded.  PFPALETTE (PFPRELOAD after a Studio save).")
(princ)
