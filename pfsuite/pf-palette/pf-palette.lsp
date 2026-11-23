;;; ==========================================================================
;;; pf-palette.lsp  --  PFPALETTE: the OpenDCL palette, V6.1.  Prefix pfw:.
;;; Load position: after pf-grid and pf-export (it calls every command module).
;;; Contract, API and rules: README.md beside this file.
;;;
;;; V6.1 (2026-11-21): pfsuite-odcl\pfsuiteV6_1.odcl -- its own project, key
;;; "pfsuite", form pfsPalette.  Three tabs, and a footer every tab shows:
;;;   Setup     Anchor Grid (the blank grid dialog, then the two corners),
;;;             Assign Structures, Edit Anchor (the filled dialog -- Delete
;;;             Line is in it).  metaList: one row per line -- utility, line,
;;;             status.  lblSetupNext: the picked line's status in words,
;;;             "9 structures assigned to Line 'BA'."
;;;   Run       tarLines picks the line.  lvwCommand lists its structures,
;;;             pipes AND crossings by station -- read only, never a menu.
;;;             The work is the buttons: New Structure, New Pipe, Refresh
;;;             Line, Find Crossings, Edit Attributes, Defaults, Zoom To,
;;;             Refresh All.
;;;   Settings  one value per drawing (pf-defaults): minimum slope, minimum
;;;             cover, crossing clearance and its warning band, plan label
;;;             height.  Materials Table opens the shared pf-cfg\pf-pipes.csv.
;;;   footer    lblStatus -- one line, starting Done / Warning / Error /
;;;             Canceled -- and txtFeedback (read only), what the runs said.
;;;             Every line still goes to the command line too.
;;;
;;; THE PICKS.  The LINE is one pick for both tabs, kept by its NAME
;;; (*pfw-sel-line*, "STORM_BA") -- never by an entity, so a repaint or a
;;; change to the drawing can't leave it pointing at something gone.  The
;;; ITEM picked in lvwCommand is kept by its kind and HANDLE and checked
;;; again (still there, still that kind, still ours) before anything acts on
;;; it.  A crossing has its own edit path; it never takes the pipe's.
;;;
;;; Kept from V6.0 / V5, each one paid for in CAD (OPENDCL-WIRING.md):
;;;   - a button that writes has Event Invoke = 1 ("asynchronous" -- the
;;;     vendor's page: only then may its handler run AutoCAD commands); its
;;;     work goes through pfd:run (one undo group), then the palette repaints
;;;   - selection handlers only READ (Event Invoke 0)
;;;   - columns are added in OnInitialize ONLY -- AddColumns stacks
;;;   - data is filled AFTER dcl-Form-Show -- OnInitialize fires too early
;;;   - PFPRELOAD after every Studio save -- the project loads once a session
;;;   - an undefined control symbol is nil, and dcl-* on nil does nothing:
;;;     every caption write is guarded
;;;   - never call a property a control type doesn't document; a function
;;;     the installed runtime may lack (colour, Enabled, scrolling) is asked
;;;     for first (pfw:fn-p) -- a symbol-table read, calling nothing
;;;   - a refused button always says why
;;; ==========================================================================

(vl-load-com)

(setq *pfw-loaded*    nil    ; nil = the next PFPALETTE re-reads the .odcl
      *pfw-maps*      nil    ; ((run . ((key . row) ...)))  the tree's items
      ;; T while a list is refilled or a pick is set by code: the controls
      ;; fire their events as they go (V5's lesson)
      *pfw-filling*   nil
      *pfw-stage*     nil    ; what a handler is doing, for pfw:guard's message
      *pfw-trail*     nil    ; the steps a handler got through, newest first
      *pfw-depth*     0      ; guards running inside one another
      *pfw-lines*     nil    ; the line rows metaList shows, in its order
      *pfw-items*     nil    ; lvwCommand's rows for the picked line
      *pfw-sel-line*  nil    ; THE picked line, by name: "STORM_BA"
      *pfw-sel-item*  nil    ; (kind handle line) picked in lvwCommand
      *pfw-status*    nil    ; (kind . text) lblStatus gets when this run ends
      *pfw-painted*   nil    ; T from a repaint until the drawing changes
      *pfw-edit-target* nil  ; the checked item Edit Attributes works on
      *pfw-result*    nil)   ; a button's work hands its counts back here

;; The footer's lines live with the drawing's LISP (one list per drawing):
;; reloading the palette keeps them.
(if (not (boundp '*pfw-feedback*)) (setq *pfw-feedback* nil))   ; newest first
(setq *pfw-feedback-max* 150)   ; lines kept

;; lblStatus's colours.  -19 is Windows' button text (follows the theme); an
;; error is AutoCAD colour 1, red.  NOT an (R G B) list: the installed 9.3
;; runtime refuses one with an uncatchable "Invalid argument type" box (V6.1
;; CAD pass, 2026-11-21).  Turn *pfw-use-color* off if it misbehaves.
(setq *pfw-use-color* T
      *pfw-error-color* 1)


;;; ==========================================================================
;;; SECTION 1  --  Loading, the guard and the footer
;;; ==========================================================================

;; The V6.1 project.  Its key inside the file is "pfsuite", so every control
;; is pfsuite/pfsPalette/<name> and every handler c:pfsuite/pfsPalette/...
(defun pfw:odcl-path () (strcat *pf-root* "\\pfsuite-odcl\\pfsuiteV6_1.odcl"))

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


;; Every control the code uses.  A missing one is named when the palette
;; opens -- reading a symbol's value touches no property, so this is safe.
(setq *pfw-controls*
  '("tabMain" "lblStatus" "txtFeedback" "btnHelp"
    "btnAnchorGrid" "btnAssignStructures" "btnEditAnchor" "lblLinesHeader" "metaList" "lblSetupNext"
    "tarLines" "lblLineHeading" "lblNextAction" "lvwCommand"
    "btnStruct" "btnPipe" "btnRefreshLine" "btnXing" "btnEditStruct" "btnDefaults" "btnZoom" "btnRefreshAll"
    "lblSettingsScope" "txtMinSlope" "txtMinCover" "txtMinClearance" "txtClearanceWarn"
    "txtPlanLabelHeight" "btnSaveSettings" "btnMaterialsTable"))

;; (pfw:ctrl name) -> the control | nil
(defun pfw:ctrl (name) (eval (read (strcat "pfsuite/pfsPalette/" name))))


;; (pfw:fn-p sym) -> T when the loaded OpenDCL runtime defines sym.  Reads
;;   the symbol table only -- PFPAPI's rule; it calls nothing.  The colour,
;;   Enabled and scrolling calls are asked for this way: the installed
;;   runtime (9.3) is older than the reference they were read from (10.1).
(defun pfw:fn-p (sym) (and (member (type (eval sym)) '(SUBR EXRXSUBR)) T))

;; (pfw:census) -> nil   says which controls the loaded form lacks, and
;;   whether it is an older project (V6.0's or V5's controls in it)
(defun pfw:census ( / miss old)
  (setq miss (vl-remove-if 'pfw:ctrl *pfw-controls*))
  (if miss (pfl:say (strcat "PFPALETTE: the loaded form has no " (pfl:join miss)
                            " -- check the (Name)s in Studio, save, PFPRELOAD.")))
  (if (setq old (vl-remove-if-not 'pfw:ctrl '("tvwLines" "detailsList" "lvwLinkage" "btnScan" "lblCounts" "btnSetup")))
    (pfl:say (strcat "PFPALETTE: the loaded form still has " (pfl:join old)
                     " -- an older project is loaded, not " (pfw:odcl-path) ".  PFPRELOAD.")))
  (princ))

;; THE TRAIL: every step of a handler marks itself, so an error can print
;; the steps it got through -- the last one is where it broke.  One stage
;; was not enough: Scan's error carried Scan's last stage, though Scan had
;; finished (2026-11-03).
(defun pfw:mark (s) (setq *pfw-trail* (cons s *pfw-trail*)) nil)

;; (pfw:stage s) -> nil   the current step, for the trail and the message
(defun pfw:stage (s) (setq *pfw-stage* s) (if s (pfw:mark s)) nil)

;; (pfw:say-trail) -> nil   the last ten steps, oldest first
(defun pfw:say-trail ( / steps)
  (setq steps (reverse *pfw-trail*))
  (while (> (length steps) 10) (setq steps (cdr steps)))
  (pfl:say (strcat "  steps: " (if steps (pfl:join-with " > " steps) "(none marked)")))
  (princ))


;; --- the footer --------------------------------------------------------------

(setq *pfw-status-words*
  '((done . "Done: ") (warn . "Warning: ") (error . "Error: ") (cancel . "Canceled: ") (info . "")))

;; (pfw:status kind text) -> nil   what lblStatus says when this run ends.
;;   kind: done warn error cancel info.  The last one set wins.
(defun pfw:status (kind text) (setq *pfw-status* (cons kind text)) nil)

;; (pfw:refuse text) -> nil   a button that won't act says why: the command
;;   line, the feedback box, and lblStatus
(defun pfw:refuse (text)
  (pfl:say (strcat "PFPALETTE: " text))
  (pfw:status 'warn text)
  nil)

;; (pfw:status-paint kind text) -> nil   lblStatus, red only for an error
(defun pfw:status-paint (kind text / ctrl)
  (if (setq ctrl (pfw:ctrl "lblStatus"))
    (progn
      (pfw:caption ctrl (strcat (cond ((cdr (assoc kind *pfw-status-words*))) ("")) text))
      (if (and *pfw-use-color* (pfw:fn-p 'dcl-Control-SetForeColor))
        (vl-catch-all-apply 'dcl-Control-SetForeColor
                            (list ctrl (if (eq kind 'error) *pfw-error-color* -19))))))
  (princ))

;; (pfw:first-n l n) -> l's first n items
(defun pfw:first-n (l n / out)
  (while (and l (> n 0)) (setq out (cons (car l) out) l (cdr l) n (1- n)))
  (reverse out))

;; txtFeedback is a LIST BOX, not a Text Box (V6.1 CAD pass, 2026-11-21):
;; the installed 9.3 runtime's Text Box is single-line -- given 18 lines it
;; reported 1 (dcl-TextBox-GetLineCount), and Studio has no multi-line
;; property for it.  A List Box shows many lines, can't be typed in (read
;; only), and scrolls; it doesn't wrap, so long lines are wrapped here.  The
;; name stays txtFeedback, as the V6.1 spec names it.
(setq *pfw-feedback-width* 84)   ; characters per line before wrapping

;; (pfw:wrap s width) -> s as lines of at most width characters, broken at
;;   spaces; continuation lines indented
(defun pfw:wrap (s width / out cut lead w)
  (setq lead "" w (max 20 width))
  (while (> (strlen s) w)
    (setq cut w)
    (while (and (> cut (/ w 2)) (/= (substr s cut 1) " ")) (setq cut (1- cut)))
    (if (<= cut (/ w 2)) (setq cut w))
    (setq out  (cons (strcat lead (substr s 1 cut)) out)
          s    (vl-string-left-trim " " (substr s (1+ cut)))
          lead "    "
          w    (- (max 20 width) 4)))      ; continuation lines: once narrower, never less
  (reverse (cons (strcat lead s) out)))

;; (pfw:feedback-paint) -> nil   txtFeedback shows the lines, newest at the
;;   bottom, scrolled to it
(defun pfw:feedback-paint ( / ctrl rows)
  (if (and (setq ctrl (pfw:ctrl "txtFeedback")) (pfw:fn-p 'dcl-ListBox-Clear) (pfw:fn-p 'dcl-ListBox-AddList))
    (progn
      (setq rows (apply 'append (mapcar '(lambda (s) (pfw:wrap s *pfw-feedback-width*))
                                        (reverse *pfw-feedback*))))
      (vl-catch-all-apply 'dcl-ListBox-Clear (list ctrl))
      (if rows (vl-catch-all-apply 'dcl-ListBox-AddList (list ctrl rows)))
      ;; the newest line in view: the list scrolls as far as it can
      (if (and rows (pfw:fn-p 'dcl-ListBox-SetTopIndex))
        (vl-catch-all-apply 'dcl-ListBox-SetTopIndex (list ctrl (1- (length rows)))))))
  (princ))

;; (pfw:feedback-add lines) -> nil   lines (oldest first) added and shown
(defun pfw:feedback-add (lines)
  (foreach s lines
    (if (and s (/= (vl-string-trim " " s) ""))
      (setq *pfw-feedback* (cons s *pfw-feedback*))))
  (setq *pfw-feedback* (pfw:first-n *pfw-feedback* *pfw-feedback-max*))
  (pfw:feedback-paint))

;; (pfw:now) -> "14:32"
(defun pfw:now () (menucmd "M=$(edtime,$(getvar,date),HH:MM)"))

;; (pfw:footer-publish name lines quiet) -> nil   a run's end: lblStatus
;;   gets the status the run set, else one read off what it said; the
;;   feedback box gets what it said.  quiet: a pick (metaList, the tree, the
;;   list) -- nothing is added unless it said something or set a status.
(defun pfw:footer-publish (name lines quiet / warn st)
  (setq warn 0)
  (foreach s lines
    (if (wcmatch s "*`*`* *,*REFUSED*,*FAILED*") (setq warn (1+ warn))))
  (setq st (cond
             (*pfw-status*)
             ((vl-some '(lambda (s) (wcmatch (strcase s) "*CANCELLED*,*CANCELED*")) lines)
              (cons 'cancel "nothing was changed."))
             ((> warn 0) (cons 'warn (strcat name " finished with " (itoa warn) " warning(s) -- see below.")))
             (quiet nil)
             (T (cons 'done (strcat name " finished.")))))
  (if st (pfw:status-paint (car st) (cdr st)))
  (if (or lines (and st (not quiet)))
    (pfw:feedback-add
      (append (list (strcat "--- " (pfw:now) "  " name " ---"))
              lines
              (if st (list (strcat "=> " (cond ((cdr (assoc (car st) *pfw-status-words*))) ("")) (cdr st)))))))
  (princ))

;; --- the guard -----------------------------------------------------------------

;; (pfw:doc-name) -> the drawing this LISP belongs to
(defun pfw:doc-name () (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))

;; (pfw:doc-moved-p) -> T when the palette last showed ANOTHER drawing.  The
;;   palette is one window for every drawing; the blackboard (vl-bb-*) is the
;;   one place every drawing's LISP can read.
(defun pfw:doc-moved-p ( / was)
  (and (setq was (vl-bb-ref '*pfw-painted-doc*)) (/= was (pfw:doc-name))))

;; (pfw:doc-refuse) -> nil   a click that arrived while the palette still
;;   showed another drawing: show this one, act on nothing
(defun pfw:doc-refuse ()
  (pfw:db-forget)
  (pfw:settings-fill)
  (pfw:feedback-paint)
  (pfw:repaint nil)
  (pfw:refuse "the palette was showing another drawing. It now shows this one -- pick again."))

;; (pfw:guard name fn) / (pfw:guard-read name fn) -> nil   run a handler's
;;   work.  An error is named with the handler, the trail of steps and the
;;   command's own stage, and an undo group it left open is closed.  The
;;   OUTERMOST guard also copies what the run says (pfl:say) and hands it to
;;   the footer; guards nest (a pick's event fires inside a button's repaint)
;;   and an inner one never starts a fresh trail.  An outer caller capturing
;;   pfl:say (such as PFSELFTEST) keeps the handler's lines too.  guard-read: a pick --
;;   quiet unless it says something.
(defun pfw:guard (name fn) (pfw:guard-run name fn nil))
(defun pfw:guard-read (name fn) (pfw:guard-run name fn T))

(defun pfw:guard-run (name fn quiet / r outer lines msg parent-copying parent-copied)
  (setq outer (= 0 *pfw-depth*))
  (if outer
    (setq parent-copying *pfl-copying* parent-copied *pfl-copied*
          *pfw-stage* nil *pfd-stage* nil *pfw-trail* nil *pfw-status* nil
          *pfl-copying* T *pfl-copied* nil))
  (pfw:mark (strcat "[" name "]"))
  (setq *pfw-depth* (1+ *pfw-depth*)
        r (vl-catch-all-apply
            (if (and outer (not (member name '("Open" "OnInitialize" "Drawing switched"))) (pfw:doc-moved-p))
              'pfw:doc-refuse
              fn)
            nil)
        *pfw-depth* (max 0 (1- *pfw-depth*)))
  (if (vl-catch-all-error-p r)
    (progn
      (setq msg (vl-catch-all-error-message r))
      (vl-catch-all-apply 'vla-endundomark (list (vla-get-activedocument (vlax-get-acad-object))))
      (setq *pfw-filling* nil)
      (if (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")
        (progn
          (pfl:say (strcat "PFPALETTE: " name " cancelled."))
          (pfw:status 'cancel "stopped part way -- one UNDO takes back anything this run changed."))
        (progn
          (pfl:say (strcat "PFPALETTE: " name " stopped: " msg))
          (pfw:say-trail)
          (if *pfd-stage* (pfl:say (strcat "  the command's last stage: " *pfd-stage*)))
          (pfw:status 'error (strcat name " stopped: " msg))))))
  (if outer
    (progn
      (setq lines (reverse *pfl-copied*)
            *pfl-copying* parent-copying
            *pfl-copied* (if parent-copying
                           (append (reverse lines) parent-copied)
                           parent-copied))
      (vl-catch-all-apply 'pfw:footer-publish (list name lines quiet))))
  (princ))

;; --- open, reload, columns ------------------------------------------------------

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
     (pfw:guard "Open" 'pfw:on-open)))
  (princ))

;; (pfw:on-open) -> nil   what opening does, after the window exists
(defun pfw:on-open ( / ign)
  (pfw:mark "census") (pfw:census)
  (pfw:mark "watching commands") (pfw:watch-commands)
  (pfw:mark "settings") (pfw:settings-fill)
  (pfw:feedback-paint)
  (pfw:repaint nil)
  (if (setq ign (pfv:ignored-settings)) (pfw:legacy-warning ign))
  (if (null *pfw-status*)
    (pfw:status 'info (if *pfw-lines*
                        (strcat (itoa (length *pfw-lines*)) " line(s) in this drawing. Pick one, or Anchor Grid to add one.")
                        "no lines yet -- Anchor Grid anchors your first profile grid."))))

;; PFPRELOAD -- re-read the .odcl from disk.  RUN AFTER EVERY STUDIO SAVE.
(defun c:PFPRELOAD ()
  (if (pfw:reload) (pfl:say "PFPRELOAD: .odcl re-read.  Run PFPALETTE."))
  (princ))


;; COLUMNS ONLY -- see the header
(defun pfw:init ()
  (pfw:stage "metaList columns")
  (dcl-ListView-AddColumns pfsuite/pfsPalette/metaList
    (list (list "Utility" 0 90) (list "Line" 0 70) (list "Status" 0 280)))
  (pfw:stage "lvwCommand columns")
  (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwCommand
    (list (list "Item" 0 130) (list "Station(s)" 0 120) (list "Status" 0 300)))
  (pfw:stage nil))

(defun c:pfsuite/pfsPalette#OnInitialize () (pfw:guard-read "OnInitialize" 'pfw:init))

;; Drawing switched: this drawing's own list, settings and feedback.  The
;; handler exists only in drawings that loaded the suite (per-drawing LISP).
(defun c:pfsuite/pfsPalette#OnDocActivated ()
  (pfw:guard-read "Drawing switched"
    '(lambda ()
       (pfw:db-forget)
       (pfw:settings-fill)
       (pfw:feedback-paint)
       (pfw:repaint nil))))

;; The start screen: no drawing, nothing to show
(defun c:pfsuite/pfsPalette#OnEnteringNoDocState ()
  (vl-catch-all-apply '(lambda () (if (dcl-Form-IsActive pfsuite/pfsPalette) (dcl-Form-Close pfsuite/pfsPalette))) nil)
  (princ))

;; --- "the drawing changed" --------------------------------------------------------
;; The remembered list is emptied by its reactor on any change (Section 2b).
;; When a command ends with the palette showing a list that is now out of
;; date, lblStatus says so -- captions only, nothing is read in a reactor --
;; and the next click reads the drawing again.  Never a count presented as
;; current when it isn't.
(setq *pfw-cmd-tag* "PFSUITE-PALETTE-COMMANDS")
(if (not (boundp '*pfw-cmd-reactor*)) (setq *pfw-cmd-reactor* nil))

;; (pfw:form-open-p) -> T while the palette is up
(defun pfw:form-open-p ()
  (and pfsuite/pfsPalette (pfw:fn-p 'dcl-Form-IsActive) (dcl-Form-IsActive pfsuite/pfsPalette) T))

(defun pfw:on-command-ended (r args)
  (vl-catch-all-apply
    '(lambda ()
       (if (and *pfw-painted* (null *pfw-db*) (= 0 *pfw-depth*) (pfw:form-open-p))
         (progn
           (setq *pfw-painted* nil)
           (pfw:caption (pfw:ctrl "lblStatus")
                        "The drawing changed since this list was read -- click a line to bring it up to date."))))
    nil)
  (princ))

;; (pfw:watch-commands) -> nil   ONE command-ended reactor per drawing
(defun pfw:watch-commands ()
  (vl-catch-all-apply
    '(lambda ()
       (if (not (pfw:db-reactor-p *pfw-cmd-reactor*))
         (progn
           (foreach grp (vlr-reactors :vlr-editor-reactor)
             (foreach x (cdr grp) (if (equal (vlr-data x) *pfw-cmd-tag*) (vlr-remove x))))
           (setq *pfw-cmd-reactor*
             (vlr-editor-reactor *pfw-cmd-tag* '((:vlr-commandEnded . pfw:on-command-ended)))))))
    nil)
  (princ))


;;; ==========================================================================
;;; SECTION 2  --  The lines and their lists (read only)
;;; ==========================================================================
;;; A line row: (util short lname anchor stub anchors)
;;;   anchor   its first grid anchor | nil (named by an old Scan, no grid)
;;;   stub     (type name cl inv top) -- pfn:place's shape | nil
;;;   anchors  EVERY non-copy anchor of the line (a V5 line may have several
;;;            sheets); nil for a stub
;;; Read from the anchors and the stubs only: no .cl is opened and no
;;; structure is looked at to list the lines.

;; (pfw:lines) -> rows, by utility then line.  A fresh read of the drawing;
;;   the palette itself shows the remembered list (pfw:db, Section 2b).
(defun pfw:lines () (pfw:lines-in (pfg:index)))


;; (pfw:lines-in idx) -> the same, from an anchor index (pfg:index)
(defun pfw:lines-in (idx / groups g at a ln hit out st)
  (foreach x idx
    (if (not (nth 5 x))
      (setq a  (car x)
            g  (pfg:grid a)
            at (pfg:atts a)
            ;; IF, not AND: a bodiless cond clause returns its test, and AND
            ;; returns only T -- every gridded line was named T (2026-11-03)
            ln (cond ((if g (pfg:line-name g)))
                     ((strcase (strcat (pfg:att *pf-anc-util* at) "_" (pfg:att *pf-anc-line* at)))))
            groups (if (setq hit (assoc ln groups))
                     (subst (cons ln (append (cdr hit) (list a))) hit groups)
                     (cons (list ln a) groups)))))
  (foreach gr (reverse groups)
    (setq out (cons (list (car (pfl:line-parts (car gr))) (cdr (pfl:line-parts (car gr)))
                          (car gr) (cadr gr) nil (cdr gr))
                    out)))
  (foreach s (pfm:stubs)
    (setq ln (if (pfn:nz (caddr s)) (strcase (vl-filename-base (caddr s))) (strcat (car s) "_" (cadr s))))
    (if (not (assoc ln groups))
      (setq groups (cons (list ln) groups)
            st     (pfr:stub-get (car s) (cadr s))
            out    (cons (list (car s) (cadr s) ln nil
                               (list (car s) (cadr s) (caddr s)
                                     (pfn:nz (cdr (assoc 4 st))) (pfn:nz (cdr (assoc 5 st))))
                               nil)
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


;; (pfw:pipe-checks e g) -> the design checks' words for one pipe | ""
;;   (V6.1).  Only what needs a look: below a minimum, can't be checked, not
;;   checked yet.  Slope is worked out here; cover is remembered from the
;;   last Refresh (pf-pipe) -- no TIN is read in a click.
(defun pfw:pipe-checks (e g / out)
  (foreach r (list (pfp:slope-check e g) (pfp:cover-status e g))
    (if (and r (member (car r) '(fail unknown unchecked)))
      (setq out (cons (cadr r) out))))
  (pfl:join-with "; " (reverse out)))

;; (pfw:pipe-rows-all idx) -> ((lname (ename sta1 sta2 size mat status) ...) ...)
;;   Each valid pipe under its line, sta1 the LOWER station.  Both ends must
;;   belong to the same usable grid, as in PFREFRESH/Defaults.  idx:
;;   pfg:index, read once.  status: the design checks (V6.1), then the label.
(defun pfw:pipe-rows-all (idx / out ends g ln s1 s2 size mat)
  (foreach e (pfp:all)
    (if (and (setq ends (pfp:ends e))
             (setq g (pfp:grid-of-ends-in ends idx))
             (setq ln (pfg:line-name g)))
      (progn
        (setq s1   (pfl:x->sta (car (car ends)) g)
              s2   (pfl:x->sta (car (cadr ends)) g)
              size (pfr:get e *pf-pipe-size*)
              mat  (pfr:get e *pf-pipe-mat*))
        (setq out (pfw:file-row ln
                    (list e (min s1 s2) (max s1 s2)
                          (if (and size (/= size "")) size "(blank)")
                          (if (and mat (/= mat "")) mat "(blank)")
                          (pfl:join-with "; " (list (pfw:pipe-checks e g) (pfw:pipe-label-status e))))
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
;;   list costs no recount.  THE THREE VERDICTS (V6.1): PASS, FAIL, UNKNOWN.
;;   UNKNOWN is never a pass -- the block is red and the run warns.
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
                        (cond ((= clr "UNKNOWN") "UNKNOWN  wall not known")
                              ((not (pfl:number-p clr)) "UNKNOWN  no pipe on this line")
                              (bad (strcat "FAIL  " (pfl:fix (distof clr 2) 1) "\""))
                              ((strcat "PASS  " (pfl:fix (distof clr 2) 1) "\""))))
                  out))))
  out)

;; (pfw:xing-rows lname) -> that line's crossing rows
(defun pfw:xing-rows (lname) (cdr (assoc lname (pfw:xing-rows-all))))


;; (pfw:item-sta r) -> the row's sort station: a pipe's lower end
(defun pfw:item-sta (r) (min (nth 3 r) (nth 4 r)))

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
       (if (equal (pfw:item-sta a) (pfw:item-sta b) 1e-6)
         (if (eq (car a) (car b))
           (< (pfl:handle (cadr a)) (pfl:handle (cadr b)))
           (eq (car a) 'structure))
         (< (pfw:item-sta a) (pfw:item-sta b))))))

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


;; (pfw:due-rows lname rows db cached) -> rows, "needs refresh; " put in front
;;   of the status of each block PFREFRESH would change.  The status itself
;;   stays: a crossing still says PASS / FAIL / UNKNOWN -- what it was when
;;   last refreshed (V6.1).
(defun pfw:due-rows (lname rows db cached / ctx)
  (if rows (setq ctx (pfw:due-ctx db cached)))
  (mapcar '(lambda (r)
             (if (pfw:due-p r lname ctx)
               (list (nth 0 r) (nth 1 r) (nth 2 r) (nth 3 r) (nth 4 r)
                     (strcat "needs refresh"
                             (cond ((= (nth 5 r) "") "")
                                   ((eq (car r) 'crossing) (strcat "; last " (nth 5 r)))
                                   ((strcat "; " (nth 5 r)))))
                     (nth 6 r))
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
;;;   *pfw-db*  ((lines . rows) (items (lname . run rows) ...) (free . n))

(setq *pfw-db* nil)

;; (pfw:read) -> the list, read fresh from the drawing.  Says how long it took.
;;   free (V6.1): plan structures on no line at all -- Setup's hint.
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
  (list (cons 'lines lines) (cons 'items items)
        (cons 'free (length (vl-remove-if 'pfr:memb-get (pfm:structures))))))

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
;;; SECTION 3  --  A line's state, in words
;;; ==========================================================================
;;; Everything here is worked out from the drawing (the remembered list), not
;;; from what the last command counted: "9 structures assigned" is the 9
;;; plan blocks whose record names the line now.

;; (pfw:line-items lname) -> the line's rows, without the "needs refresh" test
(defun pfw:line-items (lname) (if lname (cdr (assoc lname (pfw:db-get 'items)))))

;; (pfw:count-if test l) -> how many of l pass test
(defun pfw:count-if (test l / n)
  (setq n 0)
  (foreach x l (if (apply test (list x)) (setq n (1+ n))))
  n)

;; (pfw:assigned lname) / (pfw:moved lname) / (pfw:unplaced lname)
(defun pfw:assigned (lname)
  (pfw:count-if '(lambda (r) (eq (car r) 'structure)) (pfw:line-items lname)))
(defun pfw:moved (lname)
  (pfw:count-if '(lambda (r) (and (eq (car r) 'structure) (= (nth 5 r) "moved since Assign")))
                (pfw:line-items lname)))
(defun pfw:unplaced (lname)
  (pfw:count-if '(lambda (r) (and (eq (car r) 'structure) (wcmatch (nth 5 r) "not placed*")))
                (pfw:line-items lname)))

;; (pfw:row-grid row) -> the line's first readable grid | nil
(defun pfw:row-grid (row) (if row (vl-some 'pfg:grid (nth 5 row))))

;; (pfw:sel-row) -> the picked line's row | nil
(defun pfw:sel-row ()
  (if *pfw-sel-line* (vl-some '(lambda (r) (if (= (nth 2 r) *pfw-sel-line*) r)) *pfw-lines*)))

;; (pfw:proper s) -> "Storm" for "STORM"
(defun pfw:proper (s)
  (if (and s (> (strlen s) 0)) (strcat (substr s 1 1) (strcase (substr s 2) T)) ""))

;; (pfw:line-word row) -> metaList's Status column -- cheap: no file is
;;   looked for, no "needs refresh" test
(defun pfw:line-word (row / n m)
  (cond
    ((null (nth 5 row)) "No grid (named by an old Scan)")
    ((null (pfw:row-grid row)) "Grid problem -- Edit Anchor")
    ((= 0 (setq n (pfw:assigned (nth 2 row)))) "Not assigned -- Assign Structures")
    ((> (setq m (pfw:moved (nth 2 row))) 0)
     (strcat (itoa n) " assigned, " (itoa m) " moved -- Assign again"))
    (T (strcat "Ready -- " (itoa n) " assigned"))))

;; Anchor checks remembered for the session: ((lname . findings) ...).
;; Written where they run (Anchor Grid, Assign Structures, Edit Anchor), read
;; on a pick -- a check reads files and the grid, too slow for every click.
(if (not (boundp '*pfw-checks*)) (setq *pfw-checks* nil))

;; (pfw:checks-run lname) -> findings   the anchor checks on the line's grids,
;;   said and remembered.  Inside a command (Carlson).
(defun pfw:checks-run (lname / out top gl)
  (setq top (pfg:top-lines) gl (pfn:grid-lines))
  (foreach a (pfn:line-anchors lname)
    (if (not (pfg:copy-p a))
      (setq out (append out (pfn:checks a top gl)))))
  (foreach s out (pfl:say (strcat "  ** check: " s)))
  (setq *pfw-checks* (cons (cons lname out)
                           (vl-remove-if '(lambda (c) (= (car c) lname)) *pfw-checks*)))
  out)

;; (pfw:due-count lname) -> items PFREFRESH would change on the line
(defun pfw:due-count (lname)
  (pfw:count-if '(lambda (r) (wcmatch (nth 5 r) "needs refresh*")) (pfw:run-rows lname)))

;; (pfw:problem-count lname) -> items flagged: a crossing FAIL / UNKNOWN, a
;;   pipe below a minimum or not checkable
(defun pfw:problem-count (lname)
  (pfw:count-if '(lambda (r) (wcmatch (nth 5 r) "*FAIL*,*UNKNOWN*,*below*,*can't check*"))
                (pfw:run-rows lname)))

;; (pfw:setup-text) -> lblSetupNext: the picked line's status, in words
(defun pfw:setup-text ( / row short g n m due checks)
  (setq row (pfw:sel-row))
  (cond
    ((null *pfw-lines*) "No lines yet. Click Anchor Grid to anchor your first profile grid.")
    ((null row) "Select a line to see its status. Anchor Grid adds another line at any time.")
    (T
     (setq short (cadr row)
           checks (cdr (assoc (nth 2 row) *pfw-checks*)))
     (cond
       ((null (nth 5 row))
        (strcat "Line '" short "' was named by an old Scan but has no grid. Click Anchor Grid and enter "
                (car row) " '" short "'."))
       ((null (setq g (pfw:row-grid row)))
        (strcat "Line '" short "': its anchor can't be read (station, datum or scales missing). Click Edit Anchor."))
       ((null (pfg:cl g))
        (strcat "Line '" short "': its centerline file " (cond ((pfl:g 'cl g)) ("(none)"))
                " isn't found. Click Edit Anchor to pick it."))
       (T
        (setq n (pfw:assigned (nth 2 row)) m (pfw:moved (nth 2 row)))
        (strcat (itoa n) " structure" (if (= n 1) "" "s") " assigned to Line '" short "'. "
                (cond
                  ((= n 0)
                   (strcat (itoa (cond ((pfw:db-get 'free)) (0)))
                           " plan structure(s) in this drawing are on no line yet. Place this line's"
                           " structure blocks in plan, then click Assign Structures."))
                  ((> m 0)
                   (strcat (itoa m) " moved in plan since they were assigned -- click Assign Structures again."))
                  (T
                   (setq due (pfw:due-count (nth 2 row)))
                   (strcat "Setup complete -- go to the Run tab to place and label it."
                           (if (> due 0) (strcat " " (itoa due) " item(s) there need refresh.") ""))))
                (if checks (strcat " Check: " (car checks)) "")))))))

;; (pfw:run-heading row) -> lblLineHeading
(defun pfw:run-heading (row / items)
  (if (null row)
    "No line selected"
    (progn
      (setq items (pfw:line-items (nth 2 row)))
      (strcat (pfw:proper (car row)) " Line '" (cadr row) "': "
              (itoa (pfw:count-if '(lambda (r) (eq (car r) 'structure)) items)) " structures, "
              (itoa (pfw:count-if '(lambda (r) (eq (car r) 'pipe)) items)) " pipes, "
              (itoa (pfw:count-if '(lambda (r) (eq (car r) 'crossing)) items)) " crossings"))))

;; (pfw:next-action row) -> lblNextAction: the next useful step, first that applies
(defun pfw:next-action (row / ln n due bad items)
  (cond
    ((null *pfw-lines*) "No lines yet. Anchor a grid on the Setup tab.")
    ((null row) "Select a line.")
    ((null (nth 5 row)) "This line has no grid yet. See the Setup tab.")
    ((null (pfw:row-grid row)) "This line's grid needs fixing on the Setup tab (Edit Anchor).")
    ((= 0 (setq n (pfw:assigned (setq ln (nth 2 row)))))
     "No structures are assigned to this line. Use Assign Structures on the Setup tab.")
    ((> (pfw:moved ln) 0)
     (strcat (itoa (pfw:moved ln)) " structure(s) moved in plan since they were assigned. Assign Structures"
             " (Setup tab), then Refresh Line."))
    ((> (pfw:unplaced ln) 0)
     (strcat (itoa (pfw:unplaced ln)) " structure(s) not placed in the profile yet: New Structure."))
    ((> (setq due (pfw:due-count ln)) 0) (strcat (itoa due) " item(s) need refresh: Refresh Line."))
    ((= 0 (pfw:count-if '(lambda (r) (eq (car r) 'pipe)) (setq items (pfw:line-items ln))))
     "No pipes yet: New Pipe.")
    ((> (setq bad (pfw:problem-count ln)) 0)
     (strcat (itoa bad) " item(s) flagged in the Status column (crossing or pipe check)."))
    ((= 0 (pfw:count-if '(lambda (r) (eq (car r) 'crossing)) items))
     "No crossing marks yet. Find Crossings looks for lines crossing this one.")
    (T (strcat "Line '" (cadr row) "' is up to date. Find Crossings looks for new crossings;"
               " Refresh Line updates existing ones."))))


;;; ==========================================================================
;;; SECTION 4  --  Painting the palette
;;; ==========================================================================

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


;; (pfw:enable name on) -> nil   a button greyed out or not.  The handlers
;;   check again and say why -- this is a hint, never the rule.
(defun pfw:enable (name on / c)
  (if (and (setq c (pfw:ctrl name)) (pfw:fn-p 'dcl-Control-SetEnabled))
    (vl-catch-all-apply 'dcl-Control-SetEnabled (list c (if on T nil))))
  (princ))

;; (pfw:any-grid-p) -> T when some line has a readable grid
(defun pfw:any-grid-p () (and (vl-some 'pfw:row-grid *pfw-lines*) T))

;; (pfw:paint-enabled row) -> nil
(defun pfw:paint-enabled (row / g)
  (setq g (pfw:row-grid row))
  (pfw:enable "btnAnchorGrid" T)
  (pfw:enable "btnAssignStructures" g)
  (pfw:enable "btnEditAnchor" (and row (nth 5 row)))
  (pfw:enable "btnStruct" (and g (> (pfw:assigned (nth 2 row)) 0)))
  (foreach b '("btnRefreshLine" "btnXing" "btnDefaults") (pfw:enable b g))
  (pfw:enable "btnZoom" row)
  (pfw:enable "btnEditStruct" (and *pfw-sel-item* (= (caddr *pfw-sel-item*) *pfw-sel-line*)))
  (pfw:enable "btnPipe" (pfw:any-grid-p))
  (pfw:enable "btnRefreshAll" (pfw:any-grid-p))
  (princ))

;; (pfw:paint-texts row) -> nil   the labels on both tabs
(defun pfw:paint-texts (row)
  (pfw:caption (pfw:ctrl "lblLinesHeader") (strcat "Lines in this drawing (" (itoa (length *pfw-lines*)) ")"))
  (pfw:caption (pfw:ctrl "lblSetupNext") (pfw:setup-text))
  (pfw:caption (pfw:ctrl "lblLineHeading") (pfw:run-heading row))
  (pfw:caption (pfw:ctrl "lblNextAction") (pfw:next-action row)))

;; (pfw:fill-lines) -> nil   metaList: one row per line
(defun pfw:fill-lines ( / ctrl)
  (if (setq ctrl (pfw:ctrl "metaList"))
    (dcl-ListView-FillList ctrl
      (if *pfw-lines*
        (mapcar '(lambda (r) (list (car r) -1 (cadr r) -1 (pfw:line-word r) -1)) *pfw-lines*)
        (list (list "" -1 "" -1 "No lines yet -- click Anchor Grid" -1)))))
  (princ))

;; (pfw:fill-items row) -> nil   lvwCommand: the line's structures, pipes
;;   and crossings in station order, with "needs refresh" worked out
(defun pfw:fill-items (row)
  (setq *pfw-items* (if row (pfw:run-rows (nth 2 row))))
  (if (pfw:ctrl "lvwCommand")
    (dcl-ListView-FillList (pfw:ctrl "lvwCommand")
      (mapcar '(lambda (r) (list (nth 2 r) -1 (pfw:run-stations r) -1 (nth 5 r) -1)) *pfw-items*)))
  (princ))

;; (pfw:item-index sel) -> the row number of the picked item | nil -- found
;;   by kind and HANDLE; an item erased since is not found
(defun pfw:item-index (sel / i hit)
  (setq i 0)
  (foreach r *pfw-items*
    (if (and (null hit) (eq (car r) (car sel)) (entget (cadr r)) (= (pfl:handle (cadr r)) (cadr sel)))
      (setq hit i))
    (setq i (1+ i)))
  hit)

;; (pfw:reselect-item) -> nil   the picked item shown picked again, or the
;;   pick dropped when its item is gone or belongs to another line
(defun pfw:reselect-item ( / i)
  (if *pfw-sel-item*
    (if (and (= (caddr *pfw-sel-item*) *pfw-sel-line*) (setq i (pfw:item-index *pfw-sel-item*)))
      (if (pfw:fn-p 'dcl-ListView-SetCurSel)
        (vl-catch-all-apply 'dcl-ListView-SetCurSel (list (pfw:ctrl "lvwCommand") i)))
      (setq *pfw-sel-item* nil)))
  (princ))

;; (pfw:paint-selection from) -> nil   the picked line shown on BOTH tabs,
;;   its list, the labels and the buttons.  from: 'setup / 'run -- the
;;   control the pick came from is not set again by code.
(defun pfw:paint-selection (from / row key old)
  (setq row (pfw:sel-row) old *pfw-filling* *pfw-filling* T)
  (if (and (not (eq from 'setup)) (pfw:ctrl "metaList") (pfw:fn-p 'dcl-ListView-SetCurSel))
    (vl-catch-all-apply 'dcl-ListView-SetCurSel
                        (list (pfw:ctrl "metaList") (if row (vl-position row *pfw-lines*) -1))))
  (if (and (not (eq from 'run)) row (pfw:ctrl "tarLines") (pfw:fn-p 'dcl-Tree-SelectItem)
           (setq key (car (vl-some '(lambda (x) (if (eq (cdr x) row) x)) (cdr (assoc 'run *pfw-maps*))))))
    (vl-catch-all-apply 'dcl-Tree-SelectItem (list (pfw:ctrl "tarLines") key)))
  (pfw:fill-items row)
  (pfw:reselect-item)
  (pfw:paint-texts row)
  (pfw:paint-enabled row)
  (setq *pfw-filling* old)
  (princ))

;; (pfw:line-names rows) -> their names, in order
(defun pfw:line-names (rows) (mapcar '(lambda (r) (nth 2 r)) rows))

;; (pfw:repaint from) -> nil   THE fill: both lists, the picks, the labels,
;;   the buttons.  The picks are KEPT (by name and handle) -- V6.0 cleared
;;   them; re-picking is done here, inside the catch, so a bad drawing can
;;   never stop the palette opening (V5's lesson, 2026-11-03).
;;   from: 'setup / 'run when a pick on that control asked for it -- that
;;   control is not refilled under the click unless its lines changed.
(defun pfw:repaint (from / res)
  (setq res (vl-catch-all-apply 'pfw:repaint-work (list from)))
  ;; outside the catch: a throw mid-fill must not deaden the lists
  (setq *pfw-filling* nil)
  (if (vl-catch-all-error-p res)
    (progn
      (pfl:say (strcat "PFPALETTE: filling the palette stopped"
                       (if *pfw-stage* (strcat " while " *pfw-stage*) "")
                       ": " (vl-catch-all-error-message res)))
      (pfw:say-trail)
      (pfw:status 'error (strcat "the palette could not be filled: " (vl-catch-all-error-message res)))))
  (setq *pfw-stage* nil)
  (princ))

(defun pfw:repaint-work (from / rows same)
  (pfw:stage "repaint: reading the drawing (or the remembered list)")
  (setq rows (pfw:db-get 'lines)
        same (equal (pfw:line-names rows) (pfw:line-names *pfw-lines*))
        *pfw-lines* rows
        *pfw-filling* T)
  (if (and *pfw-sel-line* (null (pfw:sel-row)))
    (progn
      (pfl:say (strcat "PFPALETTE: line " *pfw-sel-line* " is no longer in this drawing."))
      (setq *pfw-sel-line* nil *pfw-sel-item* nil)))
  (if (not (and same (eq from 'setup)))
    (progn (pfw:stage "repaint: filling metaList") (pfw:fill-lines)))
  (if (not (and same (eq from 'run)))
    (progn
      (pfw:stage "repaint: filling tarLines")
      (setq *pfw-maps* (list (cons 'run (pfw:fill-tree pfsuite/pfsPalette/tarLines rows))))))
  (pfw:stage "repaint: the picked line")
  (pfw:paint-selection from)
  (setq *pfw-filling* nil
        *pfw-painted* T)
  (vl-bb-set '*pfw-painted-doc* (pfw:doc-name))
  (pfw:stage "repaint: done"))


;;; ==========================================================================
;;; SECTION 5  --  The picks (read only, Event Invoke 0)
;;; ==========================================================================

;; the handlers' arguments reach the guarded work through this
(setq *pfw-key* nil)

;; (pfw:pick-line name from) -> nil   a line picked on either tab
(defun pfw:pick-line (name from)
  (if (/= name *pfw-sel-line*) (setq *pfw-sel-item* nil))
  (setq *pfw-sel-line* name)
  (pfw:repaint from))

;; metaList: a List View has Clicked (Row Column), row from 0, -1 = no row
(defun c:pfsuite/pfsPalette/metaList#OnClicked (Row Column)
  (setq *pfw-key* Row)
  (pfw:guard-read "metaList"
    '(lambda ( / r)
       (if (and (not *pfw-filling*) (numberp *pfw-key*) (>= *pfw-key* 0)
                (setq r (nth *pfw-key* *pfw-lines*)))
         (pfw:pick-line (nth 2 r) 'setup)))))

;; tarLines: a Tree's SelChanged is (Label Key).  A utility (parent) is no line.
(defun c:pfsuite/pfsPalette/tarLines#OnSelChanged (Label Key)
  (setq *pfw-key* Key)
  (pfw:guard-read "tarLines"
    '(lambda ( / r)
       (if (and (not *pfw-filling*) (setq r (cdr (assoc *pfw-key* (cdr (assoc 'run *pfw-maps*))))))
         (pfw:pick-line (nth 2 r) 'run)))))

;; (pfw:edit-words kind) -> what Edit Attributes will do with this kind
(defun pfw:edit-words (kind)
  (cond
    ((eq kind 'structure) "Edit Attributes opens its plan block, then its profile copy on this line.")
    ((eq kind 'pipe) "Edit Attributes opens this pipe's attributes.")
    ((eq kind 'crossing) "Edit Attributes opens this crossing mark (its label rows keep hand edits).")
    ("")))

;; (pfw:on-item row) -> nil   an item picked in lvwCommand: kept by kind and
;;   HANDLE.  A click on no row leaves the pick (V6.0's rule).
(defun pfw:on-item (row / item)
  (if (and (not *pfw-filling*) (setq item (pfw:run-row-at row)))
    (progn
      (setq *pfw-sel-item* (list (car item) (pfl:handle (cadr item)) *pfw-sel-line*))
      (pfw:paint-enabled (pfw:sel-row))
      (pfl:say (strcat "PFPALETTE: " (nth 2 item) " picked."))
      (pfw:status 'info (strcat (nth 2 item) " (" (pfw:run-stations item) ") selected. "
                                (pfw:edit-words (car item))))))
  (princ))

(defun c:pfsuite/pfsPalette/lvwCommand#OnClicked (Row Column)
  (setq *pfw-key* Row)
  (pfw:guard-read "lvwCommand" '(lambda () (pfw:on-item *pfw-key*))))


;;; ==========================================================================
;;; SECTION 6  --  The buttons
;;; ==========================================================================
;;; A button that changes the drawing has Event Invoke = 1 in Studio: its
;;; handler then runs as a command, and the work goes through pfd:run (one
;;; undo group, the stage named on an error), then the palette repaints with
;;; the picks kept.  Every handler checks the pick again when it runs.

;; (pfw:require want) -> the picked line's row | nil, saying why not
;;   want: 'line (any), 'anchor (it has one), 'grid (a readable grid),
;;   'assigned (a grid and at least one structure on it)
(defun pfw:require (want / row)
  (if (null *pfw-db*) (setq *pfw-lines* (pfw:db-get 'lines)))   ; the drawing changed: read it
  (setq row (pfw:sel-row))
  (cond
    ((null row)
     (pfw:refuse (if *pfw-sel-line*
                   (strcat "line " *pfw-sel-line* " is no longer in this drawing -- pick a line.")
                   "pick a line first (the Setup list or the Run tree).")))
    ((and (member want '(anchor grid assigned)) (null (nth 5 row)))
     (pfw:refuse (strcat "Line '" (cadr row) "' has no grid yet -- Anchor Grid first.")))
    ((and (member want '(grid assigned)) (null (pfw:row-grid row)))
     (pfw:refuse (strcat "Line '" (cadr row) "''s anchor can't be read -- Edit Anchor first.")))
    ((and (eq want 'assigned) (= 0 (pfw:assigned (nth 2 row))))
     (pfw:refuse (strcat "no structures are assigned to Line '" (cadr row)
                         "' -- Assign Structures on the Setup tab.")))
    (T row)))

;; (pfw:act name fn) -> nil   the work, then the repaint.  The work changed
;;   the drawing: the remembered list is emptied first.
(defun pfw:act (name fn)
  (pfw:mark (strcat name " starting"))
  (pfd:run name fn)
  (pfw:mark (strcat name " closed its undo group"))
  (pfw:db-forget)
  (pfw:repaint nil)
  (princ))

;; (pfw:setup-ok) -> T | nil   PFSETUP's own refusals (metric, no Carlson)
(defun pfw:setup-ok ( / why)
  (pfw:mark "checking Carlson")
  (if (setq why (pfn:refusal)) (pfw:refuse why) T))

;; --- Setup tab ---------------------------------------------------------------

;; Anchor Grid: the blank grid dialog, then the two corners.  Always there --
;; the first line, or another one.
(defun pfw:do-anchor-grid ( / a)
  (if (and (pfw:setup-ok) (setq a (pfn:place nil)))
    (progn
      (setq *pfw-sel-line* (pfn:anchor-line a) *pfw-sel-item* nil)
      (pfw:checks-run *pfw-sel-line*)
      (pfw:status 'done (strcat "Line '" (cdr (pfl:line-parts *pfw-sel-line*)) "' anchored. Next: place its"
                                " structure blocks in plan, then Assign Structures.")))))

(defun c:pfsuite/pfsPalette/btnAnchorGrid#OnClicked ()
  (pfw:guard "Anchor Grid" '(lambda () (pfw:act "PFSETUP" 'pfw:do-anchor-grid))))

;; Assign Structures: PFASSIGN for the picked line, then the count READ OFF
;; THE DRAWING -- not the command's own counts -- and what was skipped, apart.
(defun pfw:do-assign ( / ln)
  (setq ln *pfw-sel-line* *pfw-result* nil)
  (pfc:load)
  (if (pfc:ready-p) (pfw:checks-run ln))
  (setq *pfw-result* (pfa:line ln)))

;; (pfw:assign-status row r) -> nil   lblStatus after Assign Structures
(defun pfw:assign-status (row r / n skips near count)
  (setq n (pfw:assigned (nth 2 row)))
  (if (null r)
    ;; refused (no Carlson, a metric drawing) or stopped: it did NOT run -- the
    ;; CAD pass caught "Done: ... finished" here (2026-11-21)
    (pfw:status 'warn "Assign Structures did not run -- see below.")
    (progn
      (setq skips (nth 5 r) near (cond ((nth 6 r)) (0)) count (cond ((nth 7 r)) (0)))
      (pfw:status (if (> (length skips) 0) 'warn 'done)
        (strcat (itoa n) " structure" (if (= n 1) "" "s") " assigned to Line '" (cadr row) "'."
                (if (> (length skips) 0) (strcat " Skipped: " (itoa (length skips)) " (see below).") "")
                (if (> near 0) (strcat " Near the line but not on it: " (itoa near) ".") "")
                (if (> count 0) (strcat " Legacy headwalls counted for numbering only: " (itoa count) ".") ""))))))

(defun c:pfsuite/pfsPalette/btnAssignStructures#OnClicked ()
  (pfw:guard "Assign Structures"
    '(lambda ( / row)
       (if (setq row (pfw:require 'grid))
         (progn
           (pfw:act "PFASSIGN" 'pfw:do-assign)
           (pfw:assign-status row *pfw-result*))))))

;; (pfw:pick-anchor lname) -> the anchor Edit Anchor works on | nil
;;   A line with several grids (V5's sheets): the drafter clicks the one.
(defun pfw:pick-anchor (lname / all orig pt hit)
  (setq all (pfn:line-anchors lname) orig (vl-remove-if 'pfg:copy-p all))
  (cond
    ((null all) (pfw:refuse (strcat "line " lname " has no anchor.")))
    ((null orig) (car all))
    ((null (cdr orig)) (car orig))
    (T
     (pfl:say (strcat "  Line " lname " has " (itoa (length orig)) " grids."))
     (if (and (setq pt (getpoint "\nClick inside the grid to edit: "))
              (setq hit (pfg:nearest (trans pt 1 0)))
              (member (car hit) orig))
       (car hit)
       (pfw:refuse "that click wasn't in one of this line's grids -- nothing changed.")))))

;; Edit Anchor: the dialog filled with the anchor's record.  Delete Line is in
;; the dialog (pfn:edit -> pfn:delete-line-ask).
(defun pfw:do-edit-anchor ( / ln short a r)
  (setq ln *pfw-sel-line* short (cdr (pfl:line-parts ln)))
  (cond
    ((not (pfw:setup-ok)))
    ((null (setq a (pfw:pick-anchor ln))))
    ((pfg:copy-p a)
     (pfw:refuse "that anchor is a COPY of another one -- erase the copy, then edit the original."))
    (T
     (setq r (pfn:edit a))
     (cond
       ((eq r 'deleted)
        (setq *pfw-sel-line* nil *pfw-sel-item* nil
              *pfw-checks* (vl-remove-if '(lambda (c) (= (car c) ln)) *pfw-checks*))
        (pfw:status 'done (strcat "Line '" short "' deleted. Its drawing objects stay in place,"
                                  " released from PFSUITE. One UNDO restores it.")))
       ((eq r 'updated)
        (setq *pfw-sel-line* (pfn:anchor-line a))
        (pfw:checks-run *pfw-sel-line*)
        (pfw:status 'done (strcat "Line '" short "' updated. Assign Structures, then Refresh Line,"
                                  " bring the profile along.")))
       ((eq r 'refused) (pfw:status 'warn "the change was refused -- see below."))
       (T (pfw:status 'cancel "nothing was changed."))))))

(defun c:pfsuite/pfsPalette/btnEditAnchor#OnClicked ()
  (pfw:guard "Edit Anchor"
    '(lambda () (if (pfw:require 'anchor) (pfw:act "PFSETUP" 'pfw:do-edit-anchor)))))

;; --- Run tab -------------------------------------------------------------------

;; New Structure: placed, then the line refreshed -- the new copies' invert
;; rows are PFREFRESH's (pf-invert), so they show straight away
(defun pfw:do-struct ()
  (pfs:main-for *pfw-sel-line*)
  (pfu:run (list "Line" *pfw-sel-line*) nil nil))

(defun c:pfsuite/pfsPalette/btnStruct#OnClicked ()
  (pfw:guard "New Structure"
    '(lambda ( / row before)
       (if (setq row (pfw:require 'assigned))
         (progn
           (setq before (pfw:unplaced (nth 2 row)))
           (pfw:act "PFSTRUCT" 'pfw:do-struct)
           (pfw:status 'done (strcat "Line '" (cadr row) "': "
                                     (itoa (max 0 (- before (pfw:unplaced (nth 2 row)))))
                                     " structure(s) placed in profile; "
                                     (itoa (pfw:unplaced (nth 2 row))) " still not placed.")))))))

(defun c:pfsuite/pfsPalette/btnPipe#OnClicked ()
  (pfw:guard "New Pipe"
    '(lambda ()
       (if (null *pfw-db*) (setq *pfw-lines* (pfw:db-get 'lines)))
       (if (pfw:any-grid-p)
         (pfw:act "PFPIPE" 'pfp:main)
         (pfw:refuse "no line has a readable grid yet -- Anchor Grid first.")))))

;; Refresh Line / Refresh All: PFREFRESH, then the design checks (slope and
;; cover -- cover is measured here, inside the command, where Carlson runs)
(defun pfw:do-refresh-line ()
  (pfc:load)
  (setq *pfw-result* (list (pfu:run (list "Line" *pfw-sel-line*) nil nil)
                           (pfp:design-report (list *pfw-sel-line*))))
  (pfl:say "  One UNDO takes this whole run back."))

(defun pfw:do-refresh-all ()
  (pfc:load)
  (setq *pfw-result* (list (pfu:run (list "Drawing") nil nil) (pfp:design-report nil)))
  (pfl:say "  One UNDO takes this whole run back."))

;; (pfw:refresh-status what r) -> nil   lblStatus after a refresh
;;   r: ((checked updated skipped erased failed) (pipes below unknown))
(defun pfw:refresh-status (what r / u d)
  (if (setq u (car r))
    (progn
      (setq d (cadr r))
      (pfw:status (if (or (> (nth 4 u) 0) (and d (> (cadr d) 0))) 'warn 'done)
        (strcat what " refreshed: " (itoa (nth 1 u)) " updated, "
                (itoa (- (nth 0 u) (nth 1 u) (nth 2 u) (nth 4 u))) " unchanged, "
                (itoa (nth 4 u)) " failed."
                (if (and d (> (cadr d) 0)) (strcat " " (itoa (cadr d)) " pipe(s) below a minimum.") ""))))))

(defun c:pfsuite/pfsPalette/btnRefreshLine#OnClicked ()
  (pfw:guard "Refresh Line"
    '(lambda ( / row)
       (if (setq row (pfw:require 'grid))
         (progn
           (setq *pfw-result* nil)
           (pfw:act "PFREFRESH" 'pfw:do-refresh-line)
           (pfw:refresh-status (strcat "Line '" (cadr row) "'") *pfw-result*))))))

(defun c:pfsuite/pfsPalette/btnRefreshAll#OnClicked ()
  (pfw:guard "Refresh All"
    '(lambda ()
       (if (null *pfw-db*) (setq *pfw-lines* (pfw:db-get 'lines)))
       (if (pfw:any-grid-p)
         (progn
           (setq *pfw-result* nil)
           (pfw:act "PFREFRESH" 'pfw:do-refresh-all)
           (pfw:refresh-status "The drawing" *pfw-result*))
         (pfw:refuse "no line has a readable grid yet -- Anchor Grid first.")))))

;; Find Crossings: PFXLABEL on the picked line -- it FINDS crossings (places
;; new marks, updates the ones still there, erases ones no longer crossing).
;; Refresh only keeps existing marks up to date.
(defun pfw:do-xing ()
  (pfc:load)
  (setq *pfw-result* (pfk:run *pfw-sel-line* (pfg:usable)))
  (pfl:say "  One UNDO takes this whole run back."))

(defun c:pfsuite/pfsPalette/btnXing#OnClicked ()
  (pfw:guard "Find Crossings"
    '(lambda ( / row r)
       (if (setq row (pfw:require 'grid))
         (progn
           (setq *pfw-result* nil)
           (pfw:act "PFXLABEL" 'pfw:do-xing)
           (if (and (setq r *pfw-result*) (> (+ (nth 0 r) (nth 1 r) (nth 2 r)) 0))
             (pfw:status (if (nth 4 r) 'warn 'done)
               (strcat "crossings on Line '" (cadr row) "': " (itoa (nth 0 r)) " placed, "
                       (itoa (nth 1 r)) " updated, " (itoa (nth 2 r)) " erased (no longer crossing)."
                       (if (nth 4 r) (strcat " " (itoa (length (nth 4 r))) " need a look.") "")))))))))

;; --- Edit Attributes: AutoCAD's own dialog, by the picked item's KIND ---------
;; Jake, 2026-11-13: "I'm okay with the palette just opening the enhanced
;; attribute editor" -- and "This needs to edit the profile block as well or
;; you cant change the prefixes and suffixes."  So, by kind:
;;   structure  its PLAN block (name, rim, face), then its profile copy ON THE
;;              PICKED LINE (prefixes / suffixes, label rows)
;;   pipe       the pipe (label inputs, material; size is PFSIZE_LU in
;;              Properties)
;;   crossing   the crossing mark (V6.1) -- its own path, never the pipe's.
;;              Its label rows keep a hand edit; clearance, size, material
;;              and invert are worked out again by the refresh after.
;; Then that line is refreshed: a new rim moves the copy.  One UNDO.

;; (pfw:edit-target) -> the picked item's entity, checked | nil, saying why
(defun pfw:edit-target ( / sel e)
  (setq sel *pfw-sel-item*)
  (cond
    ((null (pfw:require 'line)) nil)
    ((or (null sel) (/= (caddr sel) *pfw-sel-line*))
     (pfw:refuse "pick a structure, pipe or crossing in the list first."))
    ((not (and (setq e (handent (cadr sel))) (entget e)))
     (setq *pfw-sel-item* nil)
     (pfw:refuse "that item is gone (erased, or undone) -- pick it again."))
    ((not (cond ((eq (car sel) 'structure) (pfr:ours-p e))
                ((eq (car sel) 'pipe) (pfp:pipe-p e))
                ((eq (car sel) 'crossing) (pfk:xing-p e))))
     (setq *pfw-sel-item* nil)
     (pfw:refuse "that item is no longer what was picked -- pick it again."))
    ((pfr:released-p e)
     (setq *pfw-sel-item* nil)
     (pfw:refuse "that item was released from PFSUITE (its line was deleted) -- edit it by hand."))
    (T e)))

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
  (setq e     *pfw-edit-target*
        lname *pfw-sel-line*
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
(defun pfw:do-edit-pipe ()
  (pfw:mark "EATTEDIT pipe")
  (pfw:eattedit *pfw-edit-target*)
  (pfw:mark "refreshing the line")
  (pfw:after-edit *pfw-sel-line* nil nil)
  (princ))

;; (pfw:do-edit-crossing) -> nil   the crossing mark's own dialog, then the
;;   refresh of the line it marks
(defun pfw:do-edit-crossing ( / e rec)
  (setq e *pfw-edit-target* rec (pfk:rec e))
  (pfw:mark "EATTEDIT crossing")
  (pfw:eattedit e)
  (pfl:say "  A crossing mark keeps a hand edit on its label rows (PFLABEL, PFLABEL2, PFSTA1);")
  (pfl:say "  its clearance, size, material and invert are worked out again by the refresh.")
  (pfw:mark "refreshing the crossing's line")
  (pfw:after-edit (cond ((car rec)) (*pfw-sel-line*)) nil nil)
  (princ))

;; (pfw:edit-work kind) -> the edit function for the picked kind -- the ONE
;;   dispatch; a kind with no path is refused, never sent down another's
(defun pfw:edit-work (kind)
  (cond
    ((eq kind 'structure) 'pfw:do-edit-struct)
    ((eq kind 'pipe) 'pfw:do-edit-pipe)
    ((eq kind 'crossing) 'pfw:do-edit-crossing)))

(defun c:pfsuite/pfsPalette/btnEditStruct#OnClicked ()
  (pfw:guard "Edit Attributes"
    '(lambda ( / e kind label i)
       (if (setq e (pfw:edit-target))
         (progn
           (setq kind  (car *pfw-sel-item*)
                 i     (pfw:item-index *pfw-sel-item*)
                 label (cond ((if i (nth 2 (nth i *pfw-items*)))) ("The item"))
                 *pfw-edit-target* e)
           (if (pfw:edit-work kind)
             (progn
               (pfw:act "Edit Attributes" (pfw:edit-work kind))
               (pfw:status 'done (strcat label " edited; Line '" (cdr (pfl:line-parts *pfw-sel-line*))
                                         "' refreshed.")))
             (pfw:refuse "that kind of item has no edit path.")))))))

;; --- Defaults: the line's label wording (the pfsDefaults modal form) ----------
;; the list is filled again only when edits were saved -- a cancel changed
;; nothing (Jake, 2026-11-20: a canceled Defaults took a full minute)
(defun c:pfsuite/pfsPalette/btnDefaults#OnClicked ()
  (pfw:guard "Defaults"
    '(lambda ( / row)
       (if (setq row (pfw:require 'grid))
         (if (pfw:dflt-open (nth 2 row))
           (progn
             (pfw:db-forget)
             (pfw:repaint nil)
             (pfw:status 'done (strcat "Line '" (cadr row) "' defaults saved; the line was refreshed."))))))))

;; --- Zoom To: the picked item, else the line's grid (a view change only) -------

;; (pfw:zoom-box p1 p2 m) -> nil   ZoomWindow around p1-p2, m margin
(defun pfw:zoom-box (p1 p2 m)
  (vla-ZoomWindow (vlax-get-acad-object)
                  (vlax-3d-point (list (- (min (car p1) (car p2)) m) (- (min (cadr p1) (cadr p2)) m) 0.0))
                  (vlax-3d-point (list (+ (max (car p1) (car p2)) m) (+ (max (cadr p1) (cadr p2)) m) 0.0))))

;; (pfw:zoom-item) -> T when it zoomed to the picked item
(defun pfw:zoom-item ( / sel e i row r mn mx)
  (setq sel *pfw-sel-item*)
  (if (and sel (= (caddr sel) *pfw-sel-line*)
           (setq i (pfw:item-index sel))
           (setq row (nth i *pfw-items*))
           ;; a structure: its profile copy on this line when it has one
           (setq e (cond ((and (eq (car row) 'structure) (nth 6 row) (entget (nth 6 row))) (nth 6 row))
                         ((cadr row))))
           (not (vl-catch-all-error-p
                  (setq r (vl-catch-all-apply 'vla-GetBoundingBox
                                              (list (vlax-ename->vla-object e) 'mn 'mx))))))
    (progn
      (setq mn (vlax-safearray->list mn) mx (vlax-safearray->list mx))
      (pfw:zoom-box mn mx (max 10.0 (* 2.0 (distance mn mx))))
      T)))

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


(defun c:pfsuite/pfsPalette/btnZoom#OnClicked ()
  (pfw:guard-read "Zoom To"
    '(lambda ( / row)
       (if (setq row (pfw:require 'line))
         (if (not (pfw:zoom-item)) (pfw:zoom row))))))


;;; ==========================================================================
;;; SECTION 7  --  Settings: one value per drawing (pf-defaults)
;;; ==========================================================================
;;; The boxes are filled when the palette opens, after Save, and when the
;;; drawing is switched -- never by a repaint, so typing isn't wiped.

(setq *pfw-setting-boxes*
  '(("PFSLOPEMIN" . "txtMinSlope")
    ("PFCOVERMIN" . "txtMinCover")
    ("PFCLRMIN"   . "txtMinClearance")
    ("PFCLRWARN"  . "txtClearanceWarn")
    ("PFPLANHT"   . "txtPlanLabelHeight")))

;; (pfw:setting-label tag) -> "Minimum pipe slope"
(defun pfw:setting-label (tag) (cond ((cadr (assoc tag *pf-drawing-setting-words*))) (tag)))
;; (pfw:setting-unit tag) -> "%"
(defun pfw:setting-unit (tag) (cond ((caddr (assoc tag *pf-drawing-setting-words*))) ("")))

;; (pfw:settings-state) -> lblSettingsScope: where the values come from
(defun pfw:settings-state ( / f)
  (setq f (pfv:settings-format))
  (cond
    ((null f) "One value for every line. Not saved yet: showing the V6.0 drawing values or built-ins. Blank slope or cover = no check.")
    ((> f *pf-settings-format*) "Saved by a newer PFSUITE -- shown here, but Save won't write over it.")
    (T "One value for every line in this drawing, saved with it. Blank slope or cover = no check.")))

;; (pfw:settings-fill) -> nil
(defun pfw:settings-fill ()
  (foreach p *pfw-setting-boxes*
    (if (pfw:ctrl (cdr p))
      (vl-catch-all-apply 'dcl-Control-SetText
                          (list (pfw:ctrl (cdr p)) (cond ((pfv:setting-text (car p))) (""))))))
  (pfw:caption (pfw:ctrl "lblSettingsScope") (pfw:settings-state))
  (princ))

;; (pfw:settings-input) -> ((tag . text) ...) as typed, trimmed
(defun pfw:settings-input ( / c v out)
  (foreach p *pfw-setting-boxes*
    (setq c (pfw:ctrl (cdr p))
          v (if c (dcl-Control-GetText c))
          out (cons (cons (car p) (if (= (type v) 'STR) (vl-string-trim " \t" v) "")) out)))
  (reverse out))

;; (pfw:settings-problem entries) -> what's wrong, in words | nil
(defun pfw:settings-problem (entries / bad n label)
  (foreach p entries
    (setq label (pfw:setting-label (car p)))
    (if (and (null bad) (/= (cdr p) ""))
      (cond
        ((null (setq n (pft:num (cdr p))))
         (setq bad (strcat label " must be a number, or blank.")))
        ((and (member (car p) '("PFCLRMIN" "PFPLANHT")) (<= n 0.0))
         (setq bad (strcat label " must be more than 0 (blank uses the built-in).")))
        ((< n 0.0) (setq bad (strcat label " can't be negative."))))))
  bad)

;; (pfw:legacy-warning rows) -> nil   the V6.0 line / utility settings V6.1
;;   no longer uses, said -- never silently
(defun pfw:legacy-warning (rows)
  (pfl:say (strcat "  ** " (itoa (length rows)) " line/utility setting(s) from V6.0 are no longer used --"
                   " V6.1 uses one value per drawing:"))
  (foreach r rows
    (pfl:say (strcat "       " (if (/= (cadr r) "") (cadr r) (strcat (car r) " utility")) "  "
                     (pfw:setting-label (nth 2 r)) " = " (cond ((nth 3 r)) ("")))))
  (pfl:say "     Check the Settings tab, then Save Settings: that retires them (kept on record).")
  (pfw:status 'warn "old line-specific settings are ignored -- check the Settings tab, then Save."))

(setq *pfw-save-entries* nil)

;; (pfw:save-settings) -> nil   Save: checked, written in one undo group,
;;   each change said with what it means
(defun pfw:save-settings ( / entries bad before after was)
  (setq entries (pfw:settings-input))
  (cond
    ((setq bad (pfw:settings-problem entries))
     (pfl:say (strcat "Settings: " bad "  Nothing saved."))
     (pfw:status 'error (strcat bad " Nothing saved.")))
    ((and (pfv:settings-format) (> (pfv:settings-format) *pf-settings-format*))
     (pfw:refuse "this drawing's settings were saved by a newer PFSUITE -- not written over."))
    (T
     (setq before (mapcar '(lambda (p) (cons (car p) (pfv:setting-text (car p)))) entries)
           was    (pfv:ignored-settings)
           *pfw-save-entries* entries)
     (pfd:run "PFSETTINGS" '(lambda () (pfv:settings-save *pfw-save-entries*)))
     (foreach p entries
       (if (/= (cond ((cdr (assoc (car p) before))) ("")) (cond ((pfv:setting-text (car p))) ("")))
         (setq after (cons (car p) after))
         )
       (if (member (car p) after)
         (pfl:say (strcat "  " (pfw:setting-label (car p)) ": "
                          (cond ((cdr (assoc (car p) before))) ("(none)")) " -> "
                          (cond ((pfv:setting-text (car p))) ("(none)")) " " (pfw:setting-unit (car p))))))
     (if (or (member "PFCLRMIN" after) (member "PFCLRWARN" after))
       (pfl:say "  Crossing marks show \"needs refresh\" until Refresh Line / Refresh All redraws them."))
     (if (member "PFPLANHT" after) (pfl:say "  The plan label height applies at the next Assign Structures."))
     (if (member "PFSLOPEMIN" after) (pfl:say "  Pipe slopes are checked against it in the Run list now."))
     (if (member "PFCOVERMIN" after) (pfl:say "  Pipe cover is measured against it at the next Refresh Line."))
     (if was (pfl:say (strcat "  " (itoa (length was)) " old line/utility setting(s) retired (kept on record).")))
     (pfw:db-forget)
     (pfw:settings-fill)
     (pfw:repaint nil)
     (pfw:status 'done (if after
                         (strcat "drawing settings saved (" (itoa (length after)) " changed).")
                         "drawing settings saved (no value changed).")))))

(defun c:pfsuite/pfsPalette/btnSaveSettings#OnClicked ()
  (pfw:guard "Save Settings" 'pfw:save-settings))

;; Materials Table: the ONE shared pipe table, opened in Windows' program for
;; it.  Not a copy for this drawing -- every drawing that loads this PFSUITE
;; folder reads it.  pf-mats reads it again when the file changes.
(defun pfw:open-materials ( / path)
  (setq path (pft:path))
  (cond
    ((or (null path) (null (findfile path)))
     (pfl:say (strcat "Materials Table: the shared pipe table isn't found at "
                      (cond (path) ("(the PFSUITE folder is unknown)")) "."))
     (pfw:status 'error "the shared pipe table (pf-pipes.csv) isn't found -- see below."))
    (T
     (startapp "explorer.exe" (strcat "\"" path "\""))
     (pfl:say (strcat "Opened " path))
     (pfl:say "  This one table is shared by every drawing that uses this PFSUITE folder.")
     (pfl:say "  Save it as CSV. The next New Pipe or Refresh reads the change -- nothing to reload.")
     (pfw:status 'done "opened the shared pipe table (pf-pipes.csv)."))))

(defun c:pfsuite/pfsPalette/btnMaterialsTable#OnClicked ()
  (pfw:guard "Materials Table" 'pfw:open-materials))

;; --- Help: the three tabs, in a few lines, in the feedback box -----------------
(defun pfw:help ()
  (foreach s '("SETUP: 1. Anchor Grid -- the grid dialog, then pick the grid's lower-left and top-right corners."
               "  2. Place the line's structure blocks in plan.  3. Pick the line, then Assign Structures."
               "  Edit Anchor changes a line's grid record; Delete Line (in that dialog) takes the line out of"
               "  PFSUITE and leaves every drawing object in place, released.  One UNDO restores it."
               "RUN: pick the line.  New Structure places its structures in profile; New Pipe draws pipes;"
               "  Refresh Line / Refresh All bring labels up to date; Find Crossings looks for crossings"
               "  (Refresh only updates the ones already marked).  The list is read only -- pick a row, then"
               "  Edit Attributes or Zoom To.  Status: needs refresh, PASS / FAIL / UNKNOWN, slope / cover checks."
               "SETTINGS: one value per drawing.  Blank slope or cover = no check.  Checks only flag -- they"
               "  never move a pipe.  Materials Table opens the shared pf-cfg\\pf-pipes.csv.")
    (pfl:say s))
  (pfw:status 'info "help is in the box below."))

(defun c:pfsuite/pfsPalette/btnHelp#OnClicked ()
  (pfw:guard "Help" 'pfw:help))


;;; ==========================================================================
;;; SECTION 8  --  Defaults: the pfsDefaults modal form, and PFDEFAULTS
;;; ==========================================================================
;;; Moved here from pf-defaults (2026-11-17) so the load order holds: this
;;; part reads structures, grids and pipes and runs PFREFRESH, so it sits with
;;; the palette, which may call every module.  pf-defaults keeps the storage
;;; and look-up (pfv:).  Form: pfsuite/pfsDefaults (modal), grdDefaults with
;;; seven columns, btnSave and btnCancel.  Grid edits stay in the form until
;;; Save.  Contract: pf-defaults README.
;;; V6.1: the drawing settings are NOT here any more -- one value per drawing,
;;; on the Settings tab -- so no line or utility setting can be saved again.

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
  ;; Drawing-wide criteria now live on Settings, not in this Defaults catalog.
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
  ;; Drawing-wide criteria now live on Settings, not in this Defaults catalog.
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
    ("PFSLOPESUF" . "Slope Suffix")))

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



(princ "\npf-palette loaded (V6.1).  PFPALETTE, PFDEFAULTS (PFPRELOAD after a Studio save).")
(princ)
