;;; ==========================================================================
;;; pf-load.lsp  --  load the V6 suite in dependency order.
;;;
;;; APPLOAD this one file.  It finds its own folder and loads the rest, so
;;; there is one path to get right instead of a dozen.
;;;
;;; THE LOAD ORDER IS THE DEPENDENCY ORDER (V5's guardrail): a file may only
;;; use files loaded ABOVE it.  Each module's README.md says what it may
;;; depend on.
;;;
;;;   shared, read only   pf-cfg -> pf-lib -> pf-carlson -> pf-files
;;;   records             pf-record (needs pf-cfg's names AT LOAD TIME)
;;;                       pf-anchor -> pf-index
;;;   the only writer     pf-draw   (plus the one command wrapper, pfd:run)
;;;   commands            pf-assign, pf-struct, pf-pipe, pf-refresh
;;;   reserved, later     pf-grid (draws the grid, makes the anchor)
;;;   workbench           pf-bench -- NOT part of the suite, deleted whole
;;;                       when V6 ships; nothing above may call into it.
;;;
;;; A reserved module is loaded as soon as its file exists.
;;; ==========================================================================

(defun pf:load ( / here f p loaded missing)
  (setq here (vl-filename-directory (findfile "pf-load.lsp")))
  (if (null here)
    (prompt "\npf-load: cannot find myself -- APPLOAD pf-load.lsp by full path.")
    (progn
      (setq loaded 0 missing nil)
      (foreach f '(("pf-cfg"     . "pf-cfg")
                   ("pf-lib"     . "pf-lib")
                   ("pf-carlson" . "pf-carlson")
                   ("pf-files"   . "pf-files")
                   ("pf-record"  . "pf-record")
                   ("pf-anchor"  . "pf-anchor")
                   ("pf-index"   . "pf-index")
                   ("pf-draw"    . "pf-draw")
                   ("pf-assign"  . "pf-assign")
                   ("pf-struct"  . "pf-struct")
                   ("pf-pipe"    . "pf-pipe")
                   ("pf-refresh" . "pf-refresh")
                   ("pf-grid"    . "pf-grid")       ; reserved
                   ("Diagnostic_Tools" . "pf-bench"))
        (setq p (strcat here "\\" (car f) "\\" (cdr f) ".lsp"))
        (cond
          ((findfile p) (load p) (setq loaded (1+ loaded)))
          ((member (cdr f) '("pf-grid")))   ; not written yet
          (T (setq missing (cons (cdr f) missing)))))
      (prompt (strcat "\n\nPFSUITE V6: " (itoa loaded) " file(s) loaded."))
      (if missing
        (progn
          (prompt "\n  NOT FOUND:")
          (foreach f (reverse missing) (prompt (strcat "\n    " f ".lsp")))))
      (prompt "\n  Commands:  PFASSIGN  PFSTRUCT  PFPIPE  PFREFRESH")
      (prompt "\n  Workbench: PFMKATT  PFMKPIPEATT  PFSEL  PFGATE  PFSWAP  PFRECTEST  PFSYNCTEST  PFPIPETEST  PFGRIDTEST  PFLINETEST  PFSELFTEST")))
  (princ))

(pf:load)
(princ)
