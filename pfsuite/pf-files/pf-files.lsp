;;; ==========================================================================
;;; pf-files.lsp  --  where the file dialogs open.
;;; Load position 4: after pf-cfg.  Ported from V5's pfsettings.lsp (Section 4
;;; + browse).  Contract, API and rules: README.md beside this file.
;;;
;;; The project root is Carlson's tmpdir$, read live.  Each file type has the
;;; firm's standard subfolder (pf-cfg SECTION 8), found by looking at the root
;;; and a few folders above it.  The folder you last browsed to is remembered
;;; per type for the session.
;;;
;;; FIXED from V5 (its LOW-3): V5's setup overwrote the remembered folder with
;;; the standard one on every pick, so "remember where I was" never worked.
;;; Here only pff:browse writes it, and only with the folder actually chosen.
;;; ==========================================================================

(vl-load-com)

;; Session state.  Survives reloading this file; dies with the drawing session.
(if (not (boundp '*pff-last*))  (setq *pff-last* nil))   ; (("cl" . "C:\\...\\") ...)
(if (not (boundp '*pff-root*))  (setq *pff-root* nil))   ; fallback when no tmpdir$

;; (pff:norm d) -> d with exactly one trailing backslash
(defun pff:norm (d)
  (strcat (vl-string-right-trim "\\/" d) "\\"))

(defun pff:dir-p (d)
  (and d (/= d "") (vl-file-directory-p (vl-string-right-trim "\\/" d))))

;; (pff:root) -> the project data folder | nil
;;   Carlson's tmpdir$ first.  With no active project, whatever pff:root-set
;;   was given this session.
(defun pff:root ()
  (cond
    ((and (boundp 'tmpdir$) (= (type tmpdir$) 'STR) (pff:dir-p tmpdir$))
     (pff:norm tmpdir$))
    ((pff:dir-p *pff-root*) *pff-root*)))

(defun pff:root-set (d)
  (setq *pff-root* (if (pff:dir-p d) (pff:norm d))))

;; (pff:find-std start sub) -> start\sub, or the same one level up, ... | nil
;;   Up to *pf-dir-search-up* levels, so it works whether tmpdir$ is the
;;   project's top folder or a folder inside it.
(defun pff:find-std (start sub / base lvl cand hit)
  (setq base (vl-string-right-trim "\\/" start) lvl 0)
  (while (and (null hit) base (/= base "") (<= lvl *pf-dir-search-up*))
    (setq cand (strcat base "\\" sub))
    (if (vl-file-directory-p cand)
      (setq hit (pff:norm cand))
      (setq base (vl-filename-directory base) lvl (1+ lvl))))
  hit)

;; (pff:std-dir ft) -> the firm's folder for this file type | nil
(defun pff:std-dir (ft / root sub)
  (setq root (pff:root)
        sub  (cdr (assoc (strcase ft T) *pf-dir-std*)))
  (if (and root sub) (pff:find-std root sub)))

;; (pff:last-dir ft) -> the folder last browsed to for this type | nil
(defun pff:last-dir (ft / d)
  (setq d (cdr (assoc (strcase ft T) *pff-last*)))
  (if (pff:dir-p d) d))

;; (pff:dir ft) -> the folder a dialog for this file type should open in | nil
(defun pff:dir (ft / std last)
  (setq std  (pff:std-dir ft)
        last (pff:last-dir ft))
  (cond
    ((and *pf-dir-last-first* last) last)
    (std std)
    (last last)
    ((pff:root))))

;; (pff:remember ft path) -> nil   record the folder of a file just chosen
(defun pff:remember (ft path / k)
  (setq k (strcase ft T))
  (setq *pff-last*
        (cons (cons k (pff:norm (vl-filename-directory path)))
              (vl-remove-if '(lambda (c) (= (car c) k)) *pff-last*)))
  (princ))

;; (pff:browse title ft) -> full path | nil
;;   ft is the extension without the dot: "cl" "pro" "tin".
(defun pff:browse (title ft / f)
  (if (setq f (getfiled title (cond ((pff:dir ft)) ("")) ft 4))
    (progn (pff:remember ft f) f)))

;; (pff:find-in-std path ft) -> the same file name in the firm's folder | nil
;;   For a stored path that no longer exists -- a project copied or moved.
(defun pff:find-in-std (path ft / d)
  (if (and path (/= path "") (setq d (pff:std-dir ft)))
    (findfile (strcat d (vl-filename-base path) (vl-filename-extension path)))))


(princ "\npf-files loaded.")
(princ)
