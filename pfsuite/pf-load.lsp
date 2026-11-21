;;; ==========================================================================
;;; pf-load.lsp  --  load the V6 suite in dependency order.
;;;
;;; APPLOAD this one file.  The loader uses *pf-root*, the support path, or
;;; this checkout's location to find the modules.
;;;
;;; THE LOAD ORDER IS THE DEPENDENCY ORDER (V5's guardrail): a file may only
;;; use files loaded ABOVE it.  Each module's README.md says what it may
;;; depend on.
;;;
;;;   shared, read only   pf-cfg -> pf-lib -> pf-mats (the pipe table)
;;;                       -> pf-carlson -> pf-files
;;;   records             pf-record (needs pf-cfg's names AT LOAD TIME)
;;;                       pf-defaults (saved label defaults: storage, look-up)
;;;                       pf-anchor -> pf-index
;;;   the only writer     pf-draw   (plus the one command wrapper, pfd:run)
;;;   commands            pf-assign, pf-struct, pf-pipe, pf-invert (the
;;;                       invert rows), pf-xing (PFXLABEL), pf-refresh,
;;;                       pf-grid (PFSETUP / PFREMOVE: the grid anchors)
;;;   the palette         pf-palette (PFPALETTE, and the Defaults dialog /
;;;                       PFDEFAULTS -- calls every command module)
;;;   workbench           pf-bench -- NOT part of the suite, deleted whole
;;;                       when V6 ships; nothing above may call into it.
;;;
;;; A reserved module is loaded as soon as its file exists.
;;; ==========================================================================

(defun pf:load ( / here source f p loaded missing)
  ;; Loading a file by full path does not add its folder to AutoCAD's support
  ;; search path.  In that case (findfile "pf-load.lsp") may return nil.
  (setq here
    (cond
      ((and (boundp '*pf-root*)
            (= (type *pf-root*) 'STR)
            (findfile (strcat *pf-root* "/pf-load.lsp")))
       *pf-root*)
      ((findfile "C:/Users/Guest01/Data/LIBRARY/LISP/PFSUITE/V6/pfsuite/pf-load.lsp")
       "C:/Users/Guest01/Data/LIBRARY/LISP/PFSUITE/V6/pfsuite")
      ((setq source (findfile "pf-load.lsp"))
       (vl-filename-directory source))))
  (if (null here)
    (prompt "\npf-load: folder not found. Set *pf-root* to the pfsuite folder and load again.")
    (progn
      ;; the suite's folder, for files a module opens itself (pf-grid's .dcl)
      (setq *pf-root* here)
      (setq loaded 0 missing nil)
      (foreach f '(("pf-cfg"     . "pf-cfg")
                   ("pf-lib"     . "pf-lib")
                   ("pf-mats"    . "pf-mats")
                   ("pf-carlson" . "pf-carlson")
                   ("pf-files"   . "pf-files")
                   ("pf-record"  . "pf-record")
                   ("pf-defaults" . "pf-defaults")
                   ("pf-anchor"  . "pf-anchor")
                   ("pf-index"   . "pf-index")
                   ("pf-draw"    . "pf-draw")
                   ("pf-assign"  . "pf-assign")
                   ("pf-struct"  . "pf-struct")
                   ("pf-pipe"    . "pf-pipe")
                   ("pf-invert"  . "pf-invert")
                   ("pf-xing"    . "pf-xing")
                   ("pf-refresh" . "pf-refresh")
                   ("pf-grid"    . "pf-grid")
                   ("pf-export"  . "pf-export")
                   ("pf-palette" . "pf-palette")
                   ("Diagnostic_Tools" . "pf-bench"))
        (setq p (strcat here "\\" (car f) "\\" (cdr f) ".lsp"))
        (cond
          ((findfile p) (load p) (setq loaded (1+ loaded)))
          (T (setq missing (cons (cdr f) missing)))))
      (prompt (strcat "\n\nPFSUITE V6: " (itoa loaded) " file(s) loaded."))
      (if missing
        (progn
          (prompt "\n  NOT FOUND:")
          (foreach f (reverse missing) (prompt (strcat "\n    " f ".lsp")))))
      (prompt "\n  Commands:  PFPALETTE  PFDEFAULTS  PFSETUP  PFREMOVE  PFASSIGN  PFSTRUCT  PFPIPE  PFXLABEL  PFREFRESH  PFEXPORT  (PFPRELOAD after a Studio save)")
      (prompt "\n  Workbench: PFMKATT  PFMKPIPEATT  PFMKPLABEL  PFSEL  PFGATE  PFSWAP  PFRECTEST  PFSYNCTEST  PFPIPETEST  PFGRIDTEST  PFLINETEST  PFSELFTEST  PFMKANCATT")))
  (princ))

(pf:load)
(princ)
