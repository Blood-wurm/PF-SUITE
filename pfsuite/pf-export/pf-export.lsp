;;; ==========================================================================
;;; pf-export.lsp  --  PFEXPORT: write selected connected lines for Pro-Flow.
;;;
;;; DRAFT: the anchor-scoped command still needs a live CAD check.  Load it
;;; AFTER pf-load.lsp (it needs pf-cfg, pf-lib,
;;; pf-carlson, pf-record, pf-anchor and pf-pipe).  It only READS the drawing.
;;;
;;; Writes <drawing>.<selected-line>.pfnet beside the drawing, in the format of
;;; Pro-Flow's docs/pfsuite-network-exchange.md, format version 1:
;;;   - grids     every usable anchor: the sheet -> station/elevation numbers
;;;   - lines     the line each grid shows (.cl name), with its station range
;;;   - structures  every PLAN alpha block: insert point, rotation, record
;;;                 attributes, rim and its SRC, MEMB
;;;   - pipes     every PFSUITE_PIPE: both ends in SHEET coordinates, the
;;;               grid it is drawn on, size, material, wall
;;;   - materials Carlson's pipen.dta (n, name), offered to Pro-Flow as a
;;;               suggestion only
;;; Nothing is resolved here: Pro-Flow links pipe ends to structures and
;;; reports what it cannot link.  Problems found here go in "diagnostics".
;;;
;;; Name contract: every tag and block name comes from pf-cfg's variables.
;;; ==========================================================================

(vl-load-com)

(setq *pfx-format* "pfsuite-network")
(setq *pfx-version* 1)
(setq *pfx-exporter-version* 2)


;;; ---- JSON text -------------------------------------------------------------

;; (pfx:str s) -> a JSON string literal.  Backslash, quote and control
;;   characters escaped.  Text outside ASCII is written as AutoCAD gives it;
;;   Pro-Flow reads UTF-8 and falls back to Windows-1252.
(defun pfx:str (s / out c)
  (if (null s) (setq s ""))
  (setq out "\"")
  (foreach c (vl-string->list s)
    (setq out
      (strcat out
        (cond
          ((= c 34) "\\\"")
          ((= c 92) "\\\\")
          ((= c 10) "\\n")
          ((= c 13) "\\r")
          ((= c 9)  "\\t")
          ((< c 32) (strcat "\\u00" (if (< c 16) "0" "") (pfx:hex c)))
          (T (chr c))))))
  (strcat out "\""))

(defun pfx:hex (n / d)
  (setq d "0123456789abcdef")
  (strcat (if (>= n 16) (substr d (1+ (/ n 16)) 1) "")
          (substr d (1+ (rem n 16)) 1)))

;; (pfx:num x) -> a JSON number at full precision, "null" for nil.
;;   rtos honours DIMZIN, which can drop the leading zero (".5"), and JSON
;;   needs it -- so it is put back.
(defun pfx:num (x / s)
  (cond
    ((null x) "null")
    ((= (type x) 'INT) (itoa x))
    (T
     (setq s (rtos x 2 15))
     (cond
       ((= (substr s 1 1) ".")  (strcat "0" s))
       ((= (substr s 1 2) "-.") (strcat "-0" (substr s 2)))
       (T s)))))

;; (pfx:obj pairs) -> {"k": v, ...}   pairs are ("key" . "json text")
(defun pfx:obj (pairs / out)
  (setq out "{")
  (foreach p pairs
    (setq out (strcat out (if (= out "{") "" ", ") (pfx:str (car p)) ": " (cdr p))))
  (strcat out "}"))

;; (pfx:arr items) -> [a, b, ...]   items are json text
(defun pfx:arr (items / out)
  (setq out "[")
  (foreach i items
    (setq out (strcat out (if (= out "[") "" ", ") i)))
  (strcat out "]"))

;; Pretty enough: one array element per line.
(defun pfx:arr-lines (items / out)
  (if (null items)
    "[]"
    (progn
      (setq out "[\n    ")
      (setq out (strcat out (car items)))
      (foreach i (cdr items) (setq out (strcat out ",\n    " i)))
      (strcat out "\n  ]"))))


;;; ---- gathering -------------------------------------------------------------

(setq *pfx-diags* nil)

(defun pfx:diag (level code ref msg)
  (setq *pfx-diags*
    (cons (pfx:obj (list (cons "level" (pfx:str level))
                         (cons "code" (pfx:str code))
                         (cons "ref" (pfx:str ref))
                         (cons "message" (pfx:str msg))))
          *pfx-diags*)))

;; A shared plan structure's MEMB entries join its lines.  Only those recorded
;; junctions expand the selection; lines crossing on the sheet do not.
(defun pfx:member-on-lines (memb lines / hit m)
  (foreach m memb
    (if (and (car m) (/= (car m) "")
             (member (strcase (car m)) lines))
      (setq hit T)))
  hit)

(defun pfx:connected-lines (seed / memberships lines changed memb m name)
  (setq memberships (mapcar 'pfr:memb-get (pfr:all *pf-view-plan*))
        lines       (list seed)
        changed     T)
  (while changed
    (setq changed nil)
    (foreach memb memberships
      (if (pfx:member-on-lines memb lines)
        (foreach m memb
          (if (and (car m) (/= (car m) "")
                   (not (member (setq name (strcase (car m))) lines)))
            (setq lines (cons name lines)
                  changed T))))))
  (vl-sort lines '<))

(defun pfx:pick-line ( / pick e g)
  (if (setq pick (entsel "\nPFEXPORT - select a profile anchor: "))
    (progn
      (setq e (car pick))
      (cond
        ((/= (cdr (assoc 0 (entget e))) "INSERT")
         (pfl:say "PFEXPORT: select a PFSUITE profile anchor."))
        ((not (wcmatch (strcase (pfl:effname e)) (strcase *pf-anchor-blocks*)))
         (pfl:say "PFEXPORT: select a PFSUITE profile anchor."))
        ((pfg:copy-p e)
         (pfl:say "PFEXPORT: this anchor is a copy; select the original."))
        ((null (setq g (pfg:grid e)))
         (pfl:say "PFEXPORT: this anchor has no usable grid settings."))
        ((null (pfg:line-name g))
         (pfl:say "PFEXPORT: this anchor has no .cl line name."))
        (T (pfg:line-name g))))))

;; Every usable grid (pfg:usable already drops copies and unreadable anchors).
(defun pfx:grids (lines / out g a)
  (foreach a (pfg:all)
    (if (and (pfg:copy-p a)
             (setq g (pfg:grid a))
             (member (pfg:line-name g) lines))
      (pfx:diag "warning" "anchor_copy" (pfl:handle a)
                "copied anchor (shares its stamp with another); not exported")))
  (foreach g (pfg:usable)
    (if (member (pfg:line-name g) lines)
      (setq out
      (cons (pfx:obj
              (list (cons "id"     (pfx:str (pfl:handle (pfl:g 'anchor g))))
                    (cons "line"   (pfx:str (pfg:line-name g)))
                    (cons "title"  (pfx:str (pfg:title g)))
                    (cons "sta0"   (pfx:num (pfl:g 'sta0 g)))
                    (cons "datum"  (pfx:num (pfl:g 'datum g)))
                    (cons "leftx"  (pfx:num (pfl:g 'leftx g)))
                    (cons "basey"  (pfx:num (pfl:g 'basey g)))
                    (cons "vscale" (pfx:num (pfl:g 'vscale g)))))
            out))))
  (reverse out))

;; One entry per line name across the usable grids.
(defun pfx:lines (lines / seen out lname cl rng)
  (foreach g (pfg:usable)
    (setq lname (pfg:line-name g))
    (if (and (member lname lines) (not (member lname seen)))
      (progn
        (setq seen (cons lname seen)
              cl   (pfg:cl g)
              rng  (if (and cl (pfc:ready-p)) (pfc:cl-range cl)))
        (if (null cl)
          (pfx:diag "warning" "cl_missing" lname
                    (strcat "cannot find " (if (pfl:g 'cl g) (pfl:g 'cl g) "the .cl"))))
        (setq out
          (cons (pfx:obj
                  (list (cons "id" (pfx:str lname))
                        (cons "cl_file" (if cl (pfx:str cl) "null"))
                        (cons "station_range"
                              (if rng (pfx:arr (mapcar 'pfx:num rng)) "null"))))
                out)))))
  ;; Preserve a referenced line even when its grid is unusable.  Otherwise a
  ;; shared structure's MEMB would point outside lines[] and block import.
  (foreach lname lines
    (if (not (member lname seen))
      (progn
        (pfx:diag "warning" "line_no_grid" lname
                  "connected line has no usable profile grid")
        (setq out (cons (pfx:obj
                          (list (cons "id" (pfx:str lname))
                                (cons "cl_file" "null")
                                (cons "station_range" "null")))
                        out)))))
  (reverse out))

;; The rim and where it came from.  An empty PFRIM is NONE, never zero.
(defun pfx:rim (e rec / txt v src)
  (setq txt (pfr:val rec *pf-tag-rim*)
        v   (if (and txt (/= (vl-string-trim " " txt) "")) (distof txt 2))
        src (pfr:src-get e *pf-tag-rim*))
  (cond
    ((null v)
     (pfx:obj (list (cons "value" "null") (cons "source" (pfx:str *pf-src-none*)))))
    (T
     ;; A rim typed by hand has no SRC entry, or one that no longer matches.
     (if (or (null src) (pfr:asserted-p e *pf-tag-rim*))
       (setq src *pf-src-asserted*))
     (pfx:obj (list (cons "value" (pfx:num v)) (cons "source" (pfx:str src)))))))

(defun pfx:structures (lines / out rec e pt rot memb)
  (foreach e (pfr:all *pf-view-plan*)
    (setq rec  (pfr:read e)
          pt   (cdr (assoc 'pt rec))
          rot  (cond ((cdr (assoc 50 (entget e)))) (0.0))
          memb (cdr (assoc 'memb rec)))
    (if (pfx:member-on-lines memb lines)
      (setq out
      (cons
        (pfx:obj
          (list (cons "id"       (pfx:str (pfl:handle e)))
                (cons "block"    (pfx:str (cdr (assoc 'block rec))))
                (cons "type"     (pfx:str (pfr:val rec *pf-tag-type*)))
                (cons "size"     (pfx:str (pfr:val rec *pf-tag-size*)))
                (cons "name"     (pfx:str (pfr:val rec *pf-tag-name*)))
                (cons "plan"     (pfx:obj (list (cons "x" (pfx:num (car pt)))
                                                (cons "y" (pfx:num (cadr pt)))
                                                (cons "rotation_deg" (pfx:num (pfl:deg rot))))))
                (cons "rim"      (pfx:rim e rec))
                (cons "position" (pfx:str (pfr:val rec *pf-tag-pos*)))
                (cons "inlet"    (pfx:str (pfr:val rec *pf-tag-inlet*)))
                (cons "library"  (pfx:str (pfr:val rec *pf-tag-struct*)))
                (cons "lines"
                      (pfx:arr
                        (mapcar '(lambda (m)
                                   (pfx:obj (list (cons "line" (pfx:str (car m)))
                                                  (cons "station" (pfx:num (cadr m)))
                                                  (cons "offset" (pfx:num (caddr m))))))
                                memb)))
                (cons "record_schema" (pfx:num (cdr (assoc 'schema rec))))))
        out))))
  (reverse out))

(defun pfx:pipes (lines / out ends anchor grid lname size wall)
  (foreach e (pfp:all)
    (setq ends   (pfp:ends e)
          anchor (pfg:anchor-of (if ends (pfp:mid ends) (pfl:ins e)))
          grid   (if anchor (pfg:grid anchor))
          lname  (if grid (pfg:line-name grid)))
    (if (member lname lines)
      (cond
        ((null ends)
         (pfx:diag "warning" "pipe_unreadable" (pfl:handle e)
                   "cannot read the pipe's run grip; not exported"))
        (T
       (setq
             size   (pfp:size e)
             wall   (if size (pfp:wall size)))
       (if (null size)
         (pfx:diag "error" "pipe_no_size" (pfl:handle e) "PFSIZE is blank"))
       (setq out
         (cons
           (pfx:obj
             (list (cons "id"   (pfx:str (pfl:handle e)))
                   (cons "grid" (pfx:str (if anchor (pfl:handle anchor) "")))
                   (cons "upstream"
                         (pfx:obj (list (cons "sheet"
                           (pfx:obj (list (cons "x" (pfx:num (car (car ends))))
                                          (cons "y" (pfx:num (cadr (car ends))))))))))
                   (cons "downstream"
                         (pfx:obj (list (cons "sheet"
                           (pfx:obj (list (cons "x" (pfx:num (car (cadr ends))))
                                          (cons "y" (pfx:num (cadr (cadr ends))))))))))
                   (cons "size_in"  (pfx:num size))
                   (cons "material" (pfx:str (pfp:mat e)))
                   (cons "wall_in"  (pfx:num wall))))
           out))))))
  (reverse out))

;; Carlson's pipen.dta: "n, Material, typecode" per line.
(defun pfx:materials ( / d f out)
  (if (setq d (pfp:userdir))
    (foreach l (pfl:readlines (strcat d "\\" *pf-lib-pipen*))
      (setq f (pfl:split l))
      (if (and (>= (length f) 2) (numberp (distof (car f))) (> (distof (car f)) 0.0))
        (setq out
          (cons (pfx:obj (list (cons "name" (pfx:str (cadr f)))
                               (cons "n" (pfx:num (distof (car f))))
                               (cons "source" (pfx:str *pf-lib-pipen*))))
                out)))))
  (reverse out))

(defun pfx:now ( / d)
  ;; CDATE is YYYYMMDD.HHMMSS...
  (setq d (rtos (getvar "CDATE") 2 6))
  (strcat (substr d 1 4) "-" (substr d 5 2) "-" (substr d 7 2) "T"
          (substr d 10 2) ":" (substr d 12 2) ":" (substr d 14 2)))


;;; ---- the command -------------------------------------------------------------

(defun pfx:main ( / seed connected path f grids lines structs pipes mats doc)
  (setq *pfx-diags* nil)
  (cond
    ((and *pf-metric-refuse* (pfc:metric-p))
     (pfl:say "PFEXPORT: metric drawing -- refused (the exchange is in feet)."))
    ((null (setq seed (pfx:pick-line)))
     (pfl:say "PFEXPORT: no line selected; nothing written."))
    (T
     (setq connected (pfx:connected-lines seed)
           grids   (pfx:grids connected)
           lines   (pfx:lines connected)
           structs (pfx:structures connected)
           pipes   (pfx:pipes connected)
           mats    (pfx:materials)
           path    (strcat (getvar "DWGPREFIX")
                           (vl-filename-base (getvar "DWGNAME"))
                           "." seed ".pfnet"))
     (if (null pipes)
       (pfl:say "PFEXPORT: no PFSUITE pipes on these lines; nothing written.")
       (progn
     (setq doc
       (strcat
         "{\n"
         "  \"format\": " (pfx:str *pfx-format*) ",\n"
         "  \"format_version\": " (itoa *pfx-version*) ",\n"
         "  \"snapshot\": "
         (pfx:str "partial") ",\n"
         "  \"producer\": "
         (pfx:obj (list (cons "name" (pfx:str "PFSUITE"))
                        (cons "version" (pfx:str "V6"))
                        (cons "exporter" (pfx:str "pf-export"))
                        (cons "exporter_version" (itoa *pfx-exporter-version*))
                        (cons "record_schema" (itoa *pf-schema*)))) ",\n"
         "  \"exported_at\": " (pfx:str (pfx:now)) ",\n"
         "  \"drawing\": "
         (pfx:obj (list (cons "name" (pfx:str (getvar "DWGNAME")))
                        (cons "path" (pfx:str (getvar "DWGPREFIX"))))) ",\n"
         "  \"units\": {\"length\": \"ft\", \"pipe_size\": \"in\"},\n"
         "  \"coordinates\": {\"plan\": \"drawing\", \"crs\": null},\n"
         "  \"settings\": "
         (pfx:obj (list (cons "pipe_snap_ft" (pfx:num *pf-pipe-snap*))
                        (cons "membership_tol_ft" (pfx:num *pf-memb-tol*)))) ",\n"
         "  \"lines\": " (pfx:arr-lines lines) ",\n"
         "  \"grids\": " (pfx:arr-lines grids) ",\n"
         "  \"structures\": " (pfx:arr-lines structs) ",\n"
         "  \"pipes\": " (pfx:arr-lines pipes) ",\n"
         "  \"materials\": " (pfx:arr-lines mats) ",\n"
         "  \"diagnostics\": " (pfx:arr-lines (reverse *pfx-diags*)) "\n"
         "}\n"))
     (if (setq f (open path "w"))
       (progn
         (write-line doc f)
         (close f)
         (pfl:say (strcat "PFEXPORT: " (itoa (length connected)) " connected line(s), "
                          (itoa (length structs)) " structure(s), "
                          (itoa (length pipes)) " pipe(s), "
                          (itoa (length grids)) " grid(s) -> " path))
         (if *pfx-diags*
           (pfl:say (strcat "  " (itoa (length *pfx-diags*))
                            " diagnostic(s) written into the file."))))
       (pfl:say (strcat "PFEXPORT: cannot write " path)))))))
  (princ))

(defun c:PFEXPORT () (pfx:main))

(princ "\npf-export (DRAFT) loaded.  Command: PFEXPORT")
(princ)
