;;; ==========================================================================
;;; pf-defaults.lsp  --  saved label defaults: drawing, utility, line.
;;; Load position 6: after pf-record.  Prefix pfv:.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; The drafter inputs on a profile copy or pipe (PFSTAPRE ... PFSLOPESUF)
;;; take their value from, first found:
;;;   the line's saved default  ->  the utility's  ->  the drawing's  ->  built-in
;;; A value typed on one block stays on that block (Jake, 2026-11-17: this
;;; replaces the 2026-10-27 push to every block of a type).
;;;
;;; STORAGE AND LOOK-UP ONLY.  It needs pf-cfg, pf-lib and pf-record, nothing
;;; else.  The Defaults dialog and PFDEFAULTS live in pf-palette, which may
;;; call every command module; pf-struct and pf-pipe call this file.
;;; ==========================================================================

(setq *pfv-dict* "PFSUITE_DEFAULTS")

;; (pfv:dict create) -> the drawing's defaults dictionary | nil
(defun pfv:dict (create / sub)
  (cond
    ((setq sub (dictsearch (namedobjdict) *pfv-dict*)) (cdr (assoc -1 sub)))
    (create
     (dictadd (namedobjdict) *pfv-dict*
              (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary")
                          (280 . 0) (281 . 1)))))))

;; Length prefixes keep distinct utility/line/type combinations distinct.
(defun pfv:key (util line kind ty tag / parts out s)
  (setq out "D" parts (list util line kind ty tag))
  (foreach s parts
    (setq s (strcase (cond (s) ("")))
          out (strcat out (itoa (strlen s)) "_" s)))
  out)

;; (pfv:raw util line kind ty tag) -> the saved value | nil (nothing saved).
;;   "" is a saved blank, not nothing.
(defun pfv:raw (util line kind ty tag / d x)
  (if (and (setq d (pfv:dict nil))
           (setq x (dictsearch d (pfv:key util line kind ty tag))))
    (cdr (assoc 1 x))))

;; (pfv:utility line) -> "STORM" for "STORM_BA" -- before the first underscore
(defun pfv:utility (line / i)
  (if (and line (setq i (vl-string-search "_" line)))
    (strcase (substr line 1 i))
    (strcase (cond (line) ("")))))

;; The first saved value wins; an empty string is itself a valid default.
(defun pfv:effective (line kind ty tag fallback / util v)
  (setq util (pfv:utility line))
  (cond
    ((and line (setq v (pfv:raw util line kind ty tag))) v)
    ((setq v (pfv:raw util "" kind ty tag)) v)
    ((setq v (pfv:raw "" "" kind ty tag)) v)
    (fallback)))

;; The same, from a given utility and line ("" = that level is skipped).
(defun pfv:effective-for (util line kind ty tag fallback / v)
  (cond
    ((and (/= line "") (setq v (pfv:raw util line kind ty tag))) v)
    ((and (/= util "") (setq v (pfv:raw util "" kind ty tag))) v)
    ((setq v (pfv:raw "" "" kind ty tag)) v)
    (fallback)))

;; A blank value is a saved blank default.  Reset removes the record.
;; Saving over an existing default REPLACES its record (pfr:xrec-put): an
;; in-place entmod was silently ignored, so a second save never took
;; (PFSELFTEST group 13, 2026-11-17).
(defun pfv:save (util line kind ty tag value)
  (pfr:xrec-put (pfv:dict T) (pfv:key util line kind ty tag)
                (list (cons 1 (cond (value) (""))))))

(defun pfv:reset (util line kind ty tag / d key old)
  (if (and (setq d (pfv:dict nil))
           (setq key (pfv:key util line kind ty tag))
           (setq old (dictsearch d key)))
    (if (dictremove d key)
      (progn (entdel (cdr (assoc -1 old))) T)
      nil)))

;; (pfv:inputs e line kind ty tags base) -> ((tag . value) ...) as e now holds
;;   them, each default written where nobody typed one.
;; On an old insert, a non-default value with no SRC record was typed before
;; the provenance system existed.  Adopt it instead of replacing it.
(defun pfv:inputs (e line kind ty tags base / out tag cur builtin wanted src result)
  (foreach tag tags
    (setq builtin (pfr:input tag base)
          wanted  (pfv:effective line kind ty tag builtin)
          cur     (pfr:get e tag)
          src     (pfr:src-entry e tag))
    (if cur
      (progn
        (if (and (null src) (/= cur "") (/= cur builtin))
          (pfr:src-put e tag *pf-src-asserted* cur))
        (setq result (pfr:refresh e tag wanted *pf-src-rule*))
        (if (eq result 'failed)
          (prompt (strcat "\n  ** default could not be applied to " tag)))
        (setq out (cons (cons tag (pfr:get e tag)) out)))
      (setq out (cons (cons tag wanted) out))))
  (reverse out))

;; Read-only fingerprint input.  Include the recorded source and current text
;; so an Edit Attributes change is noticed even when the default is unchanged.
(defun pfv:fp-inputs (e line kind ty tags base / out tag)
  (foreach tag tags
    (setq out (cons (list tag
                          (pfv:effective line kind ty tag (pfr:input tag base))
                          (pfr:get e tag)
                          (pfr:src-entry e tag)) out)))
  (reverse out))

(princ "\npf-defaults loaded.")
(princ)
