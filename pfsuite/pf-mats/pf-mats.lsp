;;; ==========================================================================
;;; pf-mats.lsp  --  the pipe table: materials, sizes, inside / outside
;;;                  diameters.  READ ONLY.  Prefix pft:.
;;; Load position 3: after pf-cfg, pf-lib.  Depends on nothing else.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; ONE table, kept with the lisp (Jake, 2026-11-20): pf-cfg\pf-pipes.csv.
;;; Every drafter reads the same file, so two people can't get different
;;; walls or material names for the same pipe -- the problem with Carlson's
;;; per-user pipesize.dta / pipen.dta, which are no longer read.
;;; Edited by hand, in Excel or Notepad.  Layout: pf-cfg SECTION 10.
;;;
;;; Read again whenever the file changes (date and size), so an edit is
;;; picked up on the next command without reloading the suite.
;;; ==========================================================================

(if (not (boundp '*pft-cache*)) (setq *pft-cache* nil))   ; (key . table)

;; (pft:path) -> the table's full path | nil when the suite root is unknown
(defun pft:path ()
  (if (and (boundp '*pf-root*) (= (type *pf-root*) 'STR))
    (strcat *pf-root* "\\pf-cfg\\" *pf-pipe-table*)))

;; (pft:num s) -> the number in s | nil (blank or not a number)
(defun pft:num (s)
  (if (and s (/= (vl-string-trim " " s) "") (distof s 2)) (distof s 2)))

;; (pft:utils s) -> ("STORM" "SANITARY") from "Storm; Sanitary" | nil = every type
(defun pft:utils (s / out cur)
  (setq cur "")
  (foreach c (append (vl-string->list (cond (s) (""))) '(59))
    (if (or (= c 59) (= c 44))
      (progn
        (setq cur (strcase (vl-string-trim " \t" cur)))
        (if (/= cur "") (setq out (cons cur out)))
        (setq cur ""))
      (setq cur (strcat cur (chr c)))))
  (reverse out))

;; (pft:cell k cols f) -> field f's value under column k | nil when the
;;   table has no such column
(defun pft:cell (k cols f / p)
  (if (setq p (cdr (assoc k cols))) (nth p f)))

;; (pft:parse lines) -> (materials . notes)
;;   materials: ((name utils default-p n ((nominal id od) ...)) ...) in file
;;   order, sizes climbing.  id is never nil (blank = the nominal); od nil =
;;   not on record.  notes: what was wrong with the file, one line each.
;;   Pure -- PFSELFTEST hands it lines of its own.
(defun pft:parse (lines / hdr cols f nm m mats notes nom id od row i ln)
  (setq i 0)
  (foreach l lines
    (setq i (1+ i) ln (vl-string-trim " \t" l))
    (cond
      ((or (= ln "") (= (substr ln 1 1) "#")))
      ((null hdr)
       ;; the header row names the columns; their order may change
       (setq hdr  (mapcar 'strcase (pfl:csv-split ln))
             cols (mapcar '(lambda (c) (cons c (vl-position c hdr))) *pf-pipe-table-cols*))
       (foreach c cols
         (if (null (cdr c))
           (setq notes (cons (strcat "pipe table: no " (car c) " column") notes)))))
      (T
       (setq f   (pfl:csv-split ln)
             nm  (vl-string-trim " " (cond ((pft:cell "MATERIAL" cols f)) ("")))
             nom (pft:num (pft:cell "NOMINAL" cols f))
             id  (pft:num (pft:cell "ID" cols f))
             od  (pft:num (pft:cell "OD" cols f)))
       (cond
         ((= nm "") (setq notes (cons (strcat "pipe table line " (itoa i) ": no material -- skipped") notes)))
         ((or (null nom) (<= nom 0.0))
          (setq notes (cons (strcat "pipe table line " (itoa i) ": " nm " has no Nominal size -- skipped") notes)))
         (T
          (if (null id) (setq id nom))
          (if (and od (<= od id))
            (setq notes (cons (strcat "pipe table line " (itoa i) ": " nm " " (rtos nom 2 0)
                                      "\" -- OD " (rtos od 2 3) " is not bigger than ID " (rtos id 2 3)
                                      " -- OD ignored")
                              notes)
                  od nil))
          (setq row (list nom id od)
                m   (assoc (strcase nm) mats))
          (if m
            (if (assoc nom (nth 5 m))
              (setq notes (cons (strcat "pipe table line " (itoa i) ": " nm " " (rtos nom 2 0)
                                        "\" is listed twice -- the first kept")
                                notes))
              (setq mats (subst (append (reverse (cdr (reverse m))) (list (cons row (nth 5 m)))) m mats)))
            ;; first row of a material: its utilities, default and n
            (setq mats (cons (list (strcase nm) nm
                                   (pft:utils (pft:cell "UTILITIES" cols f))
                                   (and (wcmatch (strcase (cond ((pft:cell "DEFAULT" cols f)) (""))) "Y*") T)
                                   (pft:num (pft:cell "N" cols f))
                                   (list row))
                             mats))))))))
  (if (null hdr) (setq notes (cons "pipe table: empty, or no header row" notes)))
  (cons (mapcar '(lambda (m)
                   (list (nth 1 m) (nth 2 m) (nth 3 m) (nth 4 m)
                         (vl-sort (nth 5 m) '(lambda (a b) (< (car a) (car b))))))
                (reverse mats))
        (reverse notes)))

;; (pft:table) -> (materials . notes) of the file, read when it changed | nil
;;   when there is no file
(defun pft:table ( / p key)
  (if (and (setq p (pft:path)) (findfile p))
    (progn
      (setq key (list (strcase p) (vl-file-systime p) (vl-file-size p)))
      (if (not (equal key (car *pft-cache*)))
        (setq *pft-cache* (cons key (pft:parse (pfl:readlines p)))))
      (cdr *pft-cache*))))

;; (pft:mats-all) -> every material row (name utils default-p n sizes) | nil
(defun pft:mats-all () (car (pft:table)))

;; (pft:notes) -> what is wrong with the table, one line each | nil
(defun pft:notes ( / t1)
  (cond
    ((null (pft:path)) (list "pipe table: the suite folder isn't known -- load pf-load.lsp"))
    ((null (setq t1 (pft:table))) (list (strcat "pipe table: " (pft:path) " not found")))
    (T (cdr t1))))

;; (pft:mat name) -> that material's row, any case | nil
(defun pft:mat (name)
  (if name
    (vl-some '(lambda (m) (if (= (strcase (car m)) (strcase (vl-string-trim " " name))) m))
             (pft:mats-all))))

;; (pft:offered-p m util) -> T when material row m is offered for utility util
(defun pft:offered-p (m util)
  (or (null util) (= util "") (null (cadr m)) (and (member (strcase util) (cadr m)) T)))

;; (pft:materials util) -> the names offered for that utility, file order.
;;   util nil or "" -> every material.
(defun pft:materials (util)
  (mapcar 'car (vl-remove-if-not '(lambda (m) (pft:offered-p m util)) (pft:mats-all))))

;; (pft:default util) -> the material marked Default for that utility | nil.
;;   Two marked for one utility: the first in the file (pft:default-notes says so).
(defun pft:default (util)
  (car (vl-remove-if-not '(lambda (n) (caddr (pft:mat n))) (pft:materials util))))

;; (pft:default-notes) -> a line for every utility with more than one default
(defun pft:default-notes ( / us out d)
  (foreach m (pft:mats-all)
    (if (caddr m) (foreach u (cadr m) (if (not (member u us)) (setq us (cons u us))))))
  (foreach u us
    (setq d (vl-remove-if-not '(lambda (m) (and (caddr m) (member u (cadr m)))) (pft:mats-all)))
    (if (cdr d)
      (setq out (cons (strcat "pipe table: " (itoa (length d)) " materials are the Default for " u
                              " -- " (car (car d)) " is used")
                      out))))
  out)

;; (pft:sizes name) -> that material's nominal sizes, climbing.  name nil ->
;;   every size any material has.
(defun pft:sizes (name / m out)
  (if name
    (if (setq m (pft:mat name)) (mapcar 'car (nth 4 m)))
    (progn
      (foreach m (pft:mats-all)
        (foreach s (nth 4 m) (if (not (member (car s) out)) (setq out (cons (car s) out)))))
      (vl-sort out '<))))

;; (pft:dims name nominal) -> (id od) inches; od nil = wall unknown | nil
;;   when the table has no such material and size
(defun pft:dims (name nominal / m s)
  (if (and (setq m (pft:mat name)) (setq s (assoc nominal (nth 4 m))))
    (list (cadr s) (caddr s))))

;; (pft:wall name nominal) -> wall thickness, inches | nil when unknown
(defun pft:wall (name nominal / d)
  (if (and (setq d (pft:dims name nominal)) (cadr d))
    (/ (- (cadr d) (car d)) 2.0)))

;; (pft:n name) -> Manning's n | nil
(defun pft:n (name / m) (if (setq m (pft:mat name)) (nth 3 m)))


(princ "\npf-mats loaded.")
(princ)
