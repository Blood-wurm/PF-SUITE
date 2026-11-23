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

;;; ---- V6.1 drawing settings: ONE value per drawing --------------------------
;;; Kept in their own dictionary, *pf-settings-dict* (pf-cfg), never in the
;;; label defaults above: a drawing setting has no line or utility scope.
;;;   FORMAT       "1"  -- present = this drawing has V6.1 settings
;;;   PFSLOPEMIN ... one XRECORD per value, (1 . "text").  Absent = unset.
;;;   LEGACY_<key> what migration retired from PFSUITE_DEFAULTS, for the record
;;; Until FORMAT exists (a V6.0 drawing) the V6.0 DRAWING-scope SETTING record
;;; is read, then the built-in.  Line and utility SETTING records are never
;;; read for a value -- only listed, so the drafter is told they are ignored.

;; (pfv:settings-dict create) -> the settings dictionary | nil
(defun pfv:settings-dict (create / sub)
  (cond
    ((setq sub (dictsearch (namedobjdict) *pf-settings-dict*)) (cdr (assoc -1 sub)))
    (create
     (dictadd (namedobjdict) *pf-settings-dict*
              (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary")
                          (280 . 0) (281 . 1)))))))

;; (pfv:settings-raw key) -> the text stored under key | nil
(defun pfv:settings-raw (key / d x)
  (if (and (setq d (pfv:settings-dict nil))
           (setq x (dictsearch d key)))
    (cdr (assoc 1 x))))

;; (pfv:settings-format) -> the FORMAT number | nil (a V6.0 drawing).  A
;;   number above *pf-settings-format* was written by a newer PFSUITE: its
;;   known values are read, but Save refuses to write over it.
(defun pfv:settings-format ( / v)
  (if (setq v (pfv:settings-raw "FORMAT")) (atoi v)))

;; (pfv:setting-text tag) -> the drawing's value as text | nil (unset, and no
;;   built-in)
(defun pfv:setting-text (tag / fallback saved)
  (setq fallback (cdr (assoc tag *pf-drawing-settings*)))
  (if (pfv:settings-format)
    (cond ((setq saved (pfv:settings-raw tag)) saved) (fallback))
    (cond ((setq saved (pfv:raw "" "" *pf-setting-kind* "" tag)) saved)
          (fallback))))

;; (pfv:setting tag) -> the drawing's value as a number | nil (no check)
(defun pfv:setting (tag) (pft:num (pfv:setting-text tag)))

;; (pfv:setting-source tag) -> 'saved 'v60 'builtin 'unset -- where
;;   pfv:setting-text's answer came from, for the Settings tab
(defun pfv:setting-source (tag)
  (cond
    ((pfv:settings-format)
     (cond ((pfv:settings-raw tag) 'saved) ((cdr (assoc tag *pf-drawing-settings*)) 'builtin) ('unset)))
    ((pfv:raw "" "" *pf-setting-kind* "" tag) 'v60)
    ((cdr (assoc tag *pf-drawing-settings*)) 'builtin)
    ('unset)))

;; (pfv:key-parts key) -> (util line kind type tag) | nil   pfv:key read back.
;;   Each part is <length>_<text>; a key that doesn't read back exactly --
;;   not ours, or damaged -- is nil, never guessed at.
(defun pfv:key-parts (key / pos under len start parts ok)
  (if (and key (> (strlen key) 1) (= (substr key 1 1) "D"))
    (progn
      (setq pos 2 ok T)
      (repeat 5
        (if (and ok
                 (setq under (vl-string-search "_" key (1- pos)))
                 (> under (1- pos))
                 (pfr:digits-p (setq len (substr key pos (- under (1- pos))))))
          (progn
            (setq len (atoi len) start (+ under 2))
            (if (<= (+ start len -1) (strlen key))
              (setq parts (cons (if (> len 0) (substr key start len) "") parts)
                    pos   (+ start len))
              (setq ok nil)))
          (setq ok nil)))
      (if (and ok (= pos (1+ (strlen key)))) (reverse parts)))))

;; (pfv:legacy-settings) -> ((util line tag value key) ...) every V6.0
;;   SETTING record in PFSUITE_DEFAULTS, drawing scope included
(defun pfv:legacy-settings ( / d out parts rec)
  (if (setq d (pfv:dict nil))
    (foreach key (pfl:dict-keys d)
      (if (and (setq parts (pfv:key-parts key))
               (= (strcase (nth 2 parts)) (strcase *pf-setting-kind*))
               (setq rec (dictsearch d key)))
        (setq out (cons (list (car parts) (cadr parts) (nth 4 parts)
                              (cdr (assoc 1 rec)) key)
                        out)))))
  (reverse out))

;; (pfv:ignored-settings) -> the line and utility scope ones: V6.1 never uses
;;   them, and says so until Save Settings retires them
(defun pfv:ignored-settings ()
  (vl-remove-if '(lambda (r) (and (= (car r) "") (= (cadr r) ""))) (pfv:legacy-settings)))

;; (pfv:settings-remove d key) -> T | nil
(defun pfv:settings-remove (d key / rec)
  (if (and d (setq rec (dictsearch d key)))
    (if (dictremove d key) (progn (entdel (cdr (assoc -1 rec))) T))))

;; (pfv:settings-save entries) -> T | nil (a newer FORMAT -- nothing written)
;;   entries: ((tag . text) ...), checked by the caller; "" = unset.  Runs
;;   inside pfd:run, so one UNDO takes all of it back.  The migration:
;;   - every line / utility SETTING record is copied to LEGACY_<key> and
;;     removed: V6.1 never read it, and now it is gone from the Defaults store;
;;   - the V6.0 drawing-scope records are copied the FIRST time only (later
;;     they are this writer's own mirror), then set to the new values, so a
;;     drawing opened with V6.0 code shows the same three numbers.
(defun pfv:settings-save (entries / d first tag value)
  (cond
    ((and (pfv:settings-format) (> (pfv:settings-format) *pf-settings-format*)) nil)
    (T
     (setq first (null (pfv:settings-format))
           d     (pfv:settings-dict T))
     (foreach row (pfv:legacy-settings)
       (if (or first (/= (car row) "") (/= (cadr row) ""))
         (pfr:xrec-put d (strcat "LEGACY_" (nth 4 row))
                       (list (cons 1 (cond ((nth 3 row)) (""))))))
       (if (or (/= (car row) "") (/= (cadr row) ""))
         (pfv:reset (car row) (cadr row) *pf-setting-kind* "" (nth 2 row))))
     (foreach pair *pf-drawing-settings*
       (setq tag   (car pair)
             value (cdr (assoc tag entries)))
       (if (and value (/= value ""))
         (pfr:xrec-put d tag (list (cons 1 value)))
         (pfv:settings-remove d tag))
       (if (member tag *pf-legacy-setting-tags*)
         (if (and value (/= value ""))
           (pfv:save "" "" *pf-setting-kind* "" tag value)
           (pfv:reset "" "" *pf-setting-kind* "" tag))))
     (pfr:xrec-put d "FORMAT" (list (cons 1 (itoa *pf-settings-format*))))
     T)))

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
