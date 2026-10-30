;;; ==========================================================================
;;; pf-record.lsp  --  read and write the structure record.
;;; Load position 5: after pf-cfg, pf-lib.  pf-cfg MUST be loaded first --
;;; this file builds its XDATA key list from pf-cfg's names at load time.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; THE ONLY FILE THAT READS OR WRITES ATTRIBUTE VALUES AND STORED DATA
;;; (XDATA).  Creating, moving and erasing entities, and setting dynamic
;;; properties, is pf-draw's.
;;;
;;; The record lives in two places on ONE insert:
;;;   attributes  -- the nine tags in *pf-tags*.  Drafter-visible, editable in
;;;                  Properties, and out in data extraction.
;;;   XDATA       -- MEMB, SRC and SCHEMA.  Tool-only, invisible.
;;;
;;; The rule that matters most is in pfr:refresh: a DERIVED value is rewritten
;;; on every run, an ASSERTED one is never touched.  That is what makes
;;; re-running a pass safe.  V5 could not do this -- Label All erased the pass
;;; by handle and took anything a drafter had typed with it.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Attributes
;;; ==========================================================================

;; (pfr:attr-ent e tag) -> the ATTRIB sub-entity carrying tag | nil
;;   Case-insensitive, and an EMPTY value still returns the entity -- "unset"
;;   and "absent" are different answers and only the caller knows which
;;   matters.
(defun pfr:attr-ent (e tag / has sub sd up out)
  (setq up  (strcase tag)
        has (cdr (assoc 66 (entget e))))
  (if (and has (= has 1))
    (progn
      (setq sub (entnext e))
      (while (and sub (null out)
                  (setq sd (entget sub))
                  (/= (cdr (assoc 0 sd)) "SEQEND"))
        (if (and (= (cdr (assoc 0 sd)) "ATTRIB")
                 (= (strcase (cdr (assoc 2 sd))) up))
          (setq out sub))
        (setq sub (entnext sub)))))
  out)

;; (pfr:get e tag) -> the attribute's value | nil if the tag is not there
;;   An empty attribute reads as "" -- present but unset.  nil means the tag
;;   does not exist on this block at all, which is a different problem.
(defun pfr:get (e tag / a)
  (if (setq a (pfr:attr-ent e tag))
    (cdr (assoc 1 (entget a)))))

;; (pfr:put e tag val) -> T | nil
(defun pfr:put (e tag val / a ed)
  (if (setq a (pfr:attr-ent e tag))
    (progn
      (setq ed (entget a))
      (entmod (subst (cons 1 (if val val "")) (assoc 1 ed) ed))
      (entupd e)
      T)))

;; (pfr:att-style e tag) -> the attribute's text style | nil
(defun pfr:att-style (e tag / a)
  (if (setq a (pfr:attr-ent e tag)) (cdr (assoc 7 (entget a)))))

;; (pfr:display-name e) -> PFNAME, or "#handle" when it has none yet.
;;   What every command prints to name a structure.
(defun pfr:display-name (e / n)
  (setq n (pfr:get e *pf-tag-name*))
  (if (and n (/= n "")) n (strcat "#" (cdr (assoc 5 (entget e))))))

;; (pfr:tags-ok-p e) -> T if every tag in *pf-tags* is present
;;   Cheap guard for callers that are about to write a whole record.  The
;;   drafter inputs (*pf-tags-fmt*) are not part of the record and each has a
;;   default, so a block still missing a newer one (PFELEVPRE) passes.
(defun pfr:tags-ok-p (e / ok)
  (setq ok T)
  (foreach tag *pf-tags*
    (if (and (not (member tag *pf-tags-fmt*)) (null (pfr:attr-ent e tag))) (setq ok nil)))
  ok)


;;; ==========================================================================
;;; SECTION 2  --  XDATA
;;; ==========================================================================
;;; Stored as key/value pairs of 1000 strings under *pf-app*.
;;;
;;; CHUNKED, and not optionally: a 1000 group holds 255 bytes.  A junction's
;;; MEMB naming several lines runs past that, and AutoCAD does not error on an
;;; over-long string -- it truncates, and the record comes back as unreadable
;;; garbage on exactly the structures that matter most.  Values are split on
;;; write and rejoined on read.

(setq *pfr-chunk* 200)             ; well under the 255 limit, with headroom

(defun pfr:regapp ()
  (if (not (tblsearch "APPID" *pf-app*)) (regapp *pf-app*))
  (princ))

;; (pfr:xd-raw e) -> the list of 1000-strings under our app, in order | nil
(defun pfr:xd-raw (e / xd app)
  (setq xd (cdr (assoc -3 (entget e (list *pf-app*)))))
  (if (setq app (assoc *pf-app* xd))
    (mapcar 'cdr (vl-remove-if-not '(lambda (p) (= 1000 (car p))) (cdr app)))))

;; (pfr:xd-pairs e) -> ((key . value) ...), chunks rejoined
;;   Wire format is a flat run of strings: KEY, then one or more chunks, then
;;   the next KEY.  A key is recognised by being in *pfr-keys*; anything else
;;   is a continuation of the value before it.  That keeps the format
;;   self-describing without storing lengths.
;; Every key the wire format knows.  A string in the XDATA run that is NOT in
;; this list is a continuation chunk of the value before it -- so adding an
;; XDATA key to pf-cfg without adding it here would make it read as part of
;; the previous value, silently.
;; Every value is written through pfr:ser, so it starts with ( or " or a
;; digit -- never bare text that could be mistaken for one of these keys.
(setq *pfr-keys* (list *pf-xd-memb* *pf-xd-src* *pf-xd-schema*
                       *pf-xd-plan* *pf-xd-line* *pf-xd-pos* *pf-xd-seen*
                       *pf-xd-pipe*
                       *pf-xd-cl* *pf-xd-pro-inv* *pf-xd-pro-top* *pf-xd-tin-ex*
                       *pf-xd-tin-des* *pf-xd-mat* *pf-xd-sums* *pf-xd-stamp*
                       *pf-xd-released*))

(defun pfr:xd-pairs (e / raw out key val s)
  (setq raw (pfr:xd-raw e))
  (foreach s raw
    (if (member s *pfr-keys*)
      (progn
        (if key (setq out (cons (cons key val) out)))
        (setq key s val ""))
      (if key (setq val (strcat val s)))))
  (if key (setq out (cons (cons key val) out)))
  (reverse out))

;; (pfr:chunks s) -> s split into <= *pfr-chunk* pieces
(defun pfr:chunks (s / out n)
  (if (or (null s) (= s ""))
    (list "")
    (progn
      (while (> (strlen s) *pfr-chunk*)
        (setq out (cons (substr s 1 *pfr-chunk*) out)
              s   (substr s (1+ *pfr-chunk*))))
      (reverse (cons s out)))))

;; (pfr:xd-write e pairs) -> T
(defun pfr:xd-write (e pairs / dat ed p c)
  (pfr:regapp)
  (setq dat nil)
  (foreach p pairs
    (setq dat (cons (cons 1000 (car p)) dat))
    (foreach c (pfr:chunks (cdr p))
      (setq dat (cons (cons 1000 c) dat))))
  (setq ed (entget e))
  (entmod
    (append (vl-remove-if '(lambda (x) (= -3 (car x))) ed)
            (list (list -3 (cons *pf-app* (reverse dat))))))
  T)

;; (pfr:xd-get e key) -> string | nil
(defun pfr:xd-get (e key)
  (cdr (assoc key (pfr:xd-pairs e))))

;; (pfr:xd-put e key val) -> T    Other keys are preserved.
(defun pfr:xd-put (e key val / pairs)
  (setq pairs (pfr:xd-pairs e))
  (if (assoc key pairs)
    (setq pairs (subst (cons key val) (assoc key pairs) pairs))
    (setq pairs (append pairs (list (cons key val)))))
  (pfr:xd-write e pairs))


;;; ==========================================================================
;;; SECTION 3  --  The typed accessors
;;; ==========================================================================
;;; A station written and read back must be the same number, or membership
;;; stops matching itself.  vl-prin1-to-string does NOT give that: it prints a
;;; real to about six significant figures, so 209.299293 went out as 209.299
;;; (caught by PFRECTEST in CAD, 2026-09-15 -- wanted and got printed
;;; identically because the report truncates the same way).  So reals are
;;; written by hand at full precision, and everything else is walked.

;; (pfr:real x) -> full-precision text that reads back as a REAL, never an INT
(defun pfr:real (x / s)
  (setq s (rtos x 2 15))
  (if (not (vl-string-search "." s)) (setq s (strcat s ".0")))
  s)

;; (pfr:ser x) -> text that (read) turns back into x
;;   Handles dotted pairs, which SRC is made of: ("PFRIM" . "CL").
(defun pfr:ser (x / out)
  (cond
    ((null x)            "nil")
    ((= (type x) 'STR)   (vl-prin1-to-string x))   ; escapes quotes correctly
    ((= (type x) 'INT)   (itoa x))
    ((= (type x) 'REAL)  (pfr:real x))
    ((= (type x) 'SYM)   (vl-symbol-name x))
    ((listp x)
     (setq out "(")
     (while (and x (listp x))
       (setq out (strcat out (if (= out "(") "" " ") (pfr:ser (car x)))
             x   (cdr x)))
     (if x (setq out (strcat out " . " (pfr:ser x))))   ; dotted tail
     (strcat out ")"))
    (T (vl-prin1-to-string x))))

(defun pfr:deser (s / r)
  (if (and s (/= s ""))
    (progn
      (setq r (vl-catch-all-apply 'read (list s)))
      (if (vl-catch-all-error-p r) nil r))))

;; MEMB -- ((line station offset) ...), written once at assign time.
(defun pfr:memb-get (e)  (pfr:deser (pfr:xd-get e *pf-xd-memb*)))
(defun pfr:memb-put (e l) (pfr:xd-put e *pf-xd-memb* (pfr:ser l)))

;; SEEN -- the fingerprint of what the block was last built from (pfl:fingerprint)
(defun pfr:stamp-get (e)    (pfr:deser (pfr:xd-get e *pf-xd-seen*)))
(defun pfr:stamp-put (e fp) (pfr:xd-put e *pf-xd-seen* (pfr:ser fp)))

;; RELEASED -- left behind when PFREMOVE took its grid away.  Every suite
;; search skips it (pfr:all, pfp:all, pfp:all-leaders, pfs:copies-if).
(defun pfr:released-p (e) (and (pfr:xd-get e *pf-xd-released*) T))
(defun pfr:release (e title) (pfr:xd-put e *pf-xd-released* (pfr:ser title)))

;; Typed accessors for any key: (pfr:val-get e key) / (pfr:val-put e key x)
;;   The anchor's records (CL, PRO-INV ... STAMP) go through these.
(defun pfr:val-get (e key)   (pfr:deser (pfr:xd-get e key)))
(defun pfr:val-put (e key x) (pfr:xd-put e key (pfr:ser x)))

;; SCHEMA
(defun pfr:schema-get (e / s)
  (if (setq s (pfr:xd-get e *pf-xd-schema*)) (atoi s)))
(defun pfr:schema-put (e)  (pfr:xd-put e *pf-xd-schema* (itoa *pf-schema*)))

;; SRC -- provenance, a list keyed by TAG:  (("PFRIM" "TIN" "769.13") ...)
;;   (tag source value-the-tool-last-wrote)
;;   One list, not a key per attribute: a key per attribute cannot be extended
;;   once SCHEMA has shipped on a live drawing.
;;   The third element is what catches a hand edit.  A drafter changes a rim in
;;   Properties, never through pfr:assert -- so "is it asserted" cannot rest on
;;   the source alone.  If the attribute no longer holds what the tool wrote,
;;   a person changed it.
(defun pfr:src-all (e) (pfr:deser (pfr:xd-get e *pf-xd-src*)))

(defun pfr:src-entry (e tag) (assoc (strcase tag) (pfr:src-all e)))

(defun pfr:src-get (e tag / a)
  (if (setq a (pfr:src-entry e tag)) (cadr a)))

(defun pfr:src-put (e tag src val / all up)
  (setq up  (strcase tag)
        all (pfr:src-all e))
  (if (assoc up all)
    (setq all (subst (list up src val) (assoc up all) all))
    (setq all (append all (list (list up src val)))))
  (pfr:xd-put e *pf-xd-src* (pfr:ser all)))


;;; ==========================================================================
;;; SECTION 4  --  Derived vs asserted.  The rule that makes re-runs safe.
;;; ==========================================================================

;; (pfr:asserted-p e tag) -> T if a human set this and the tool must not touch it
(defun pfr:asserted-p (e tag)
  (= *pf-src-asserted* (pfr:src-get e tag)))

;; (pfr:refresh e tag val src) -> 'written | 'kept | 'adopted | nil
;;   The ONLY way a derived value reaches the drawing.
;;     'kept    -- already ASSERTED.  Not touched, and that is correct.
;;     'adopted -- the attribute no longer holds what the tool last wrote, so a
;;                 person edited it by hand.  Marked ASSERTED, left as typed.
;;     'written -- computed value stored, provenance stamped.
;;     nil      -- the tag is not on this block.
;;   Callers report kept/adopted as information, never as a failure: a
;;   drafter overriding a rule is the system working.
(defun pfr:refresh (e tag val src / ent cur)
  (setq ent (pfr:src-entry e tag)
        cur (pfr:get e tag))
  (cond
    ((null (pfr:attr-ent e tag)) nil)
    ((pfr:asserted-p e tag) 'kept)
    ((and ent (/= (strcase (if cur cur "")) (strcase (if (caddr ent) (caddr ent) ""))))
     (pfr:src-put e tag *pf-src-asserted* cur)
     'adopted)
    (T
      (pfr:put e tag val)
      (pfr:src-put e tag src val)
      'written)))

;; (pfr:assert e tag val) -> T    A human said so.  Sticky from here on.
(defun pfr:assert (e tag val)
  (if (pfr:put e tag val)
    (progn (pfr:src-put e tag *pf-src-asserted* val) T)))


;;; ==========================================================================
;;; SECTION 5  --  Finding structures
;;; ==========================================================================

;; The real block name (never *U47) is pfl:effname, shared, in pf-lib.

(defun pfr:digits-p (s)
  (and (> (strlen s) 0)
       (vl-every '(lambda (c) (<= 48 c 57)) (vl-string->list s))))

;; (pfr:row-for nm) -> the *pf-blocks* row this block name belongs to | nil
;;   The name must BE the root (PFSUITE_CBI) or the root plus a numeric size
;;   (PFSUITE_DBI_04) -- nothing else.  Every block in the suite is named
;;   PFSUITE_<name> (Jake, 2026-10-15), so "starts with the root" would read
;;   any PFSUITE_CBI_<anything> as a CBI.  Order in *pf-blocks* is irrelevant.
(defun pfr:row-for (nm / up root pre hit)
  (setq up (strcase nm))
  (foreach r *pf-blocks*
    (setq root (strcase (cadr r))
          pre  (strcat root *pf-size-sep*))
    (if (and (null hit)
             (or (= up root)
                 (and (> (strlen up) (strlen pre))
                      (= (substr up 1 (strlen pre)) pre)
                      (pfr:digits-p (substr up (1+ (strlen pre)))))))
      (setq hit r)))
  hit)

;; (pfr:size-of nm) -> the size suffix with the separator stripped, or ""
(defun pfr:size-of (nm / row size)
  (if (setq row (pfr:row-for nm))
    (progn
      (setq size (substr nm (+ 1 (strlen (cadr row)))))
      (if (and (> (strlen size) 0)
               (= (substr size 1 (strlen *pf-size-sep*)) *pf-size-sep*))
        (setq size (substr size (+ 1 (strlen *pf-size-sep*)))))
      size)
    ""))

;; (pfr:ours-p e) -> T if this insert is one of ours
(defun pfr:ours-p (e)
  (and (= "INSERT" (cdr (assoc 0 (entget e))))
       (pfr:row-for (pfl:effname e))
       T))

;; (pfr:view e) -> "PLAN" | "PROFILE" | nil
;;   Read off PFVIEW, never off the visibility state.  Plan and profile share
;;   a definition, so the block name cannot tell them apart -- and reading the
;;   state would cost a COM call on every structure on every run.
(defun pfr:view (e) (pfr:get e *pf-tag-view*))

;; (pfr:all view) -> list of enames.  view nil = both.  A RELEASED block (its
;;   grid removed by PFREMOVE) is not ours any more and is never returned.
(defun pfr:all (view / ss i e out)
  (if (setq ss (ssget "_X" '((0 . "INSERT"))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (if (and (pfr:ours-p e)
                 (or (null view)
                     (= (strcase view) (strcase (if (pfr:view e) (pfr:view e) ""))))
                 (not (pfr:released-p e)))
          (setq out (cons e out)))
        (setq i (1+ i)))))
  (reverse out))


;;; ---- grid-less lines ("stubs") ----------------------------------------------
;;; A line PFSETUP's scan has named but no grid shows yet.  Kept in the
;;; drawing's own dictionary in V5's exact format, so pfm:stubs (and V5) read
;;; them: key STUB_<TYPE>_<NAME>, data (1 .cl) (2 TYPE) (3 NAME) (4 INV .pro)
;;; (5 TOP .pro), "" for none.  Drawing data, not entity data -- still only
;;; written here.

;; (pfr:stub-key ty name) -> "STUB_STORM_CA" -- V5's, characters a key can't
;;   hold turned into "-"
(defun pfr:stub-key (ty name / bad i c out)
  (setq bad "\\/:*?\"<>|;,=` " out "" i 1
        name (strcat (strcase ty) "_" (strcase name)))
  (while (<= i (strlen name))
    (setq c (substr name i 1)
          out (strcat out (if (vl-string-search c bad) "-" c))
          i (1+ i)))
  (strcat *pf-stub-prefix* out))

;; (pfr:nod create) -> the suite's drawing dictionary | nil
(defun pfr:nod (create / sub)
  (cond
    ((setq sub (dictsearch (namedobjdict) *pf-nod-name*)) (cdr (assoc -1 sub)))
    (create
     (dictadd (namedobjdict) *pf-nod-name*
              (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary") (280 . 0) (281 . 1)))))))

;; (pfr:stub-get ty name) -> ((1 . cl) (2 . TYPE) (3 . NAME) (4 . inv) (5 . top)) | nil
(defun pfr:stub-get (ty name / d cur)
  (if (and (setq d (pfr:nod nil)) (setq cur (dictsearch d (pfr:stub-key ty name))))
    (cdr (member (assoc 100 cur) cur))))

;; (pfr:stub-put ty name cl inv top) -> T   create or replace
(defun pfr:stub-put (ty name cl inv top / d k cur)
  (setq d (pfr:nod T) k (pfr:stub-key ty name))
  (if (setq cur (dictsearch d k))
    (progn (dictremove d k) (entdel (cdr (assoc -1 cur)))))
  (dictadd d k (entmakex (list '(0 . "XRECORD") '(100 . "AcDbXrecord")
                               (cons 1 (cond (cl) ("")))
                               (cons 2 (strcase ty)) (cons 3 (strcase name))
                               (cons 4 (cond (inv) (""))) (cons 5 (cond (top) (""))))))
  T)

;; (pfr:stub-del ty name) -> nil
(defun pfr:stub-del (ty name / d k cur)
  (if (and (setq d (pfr:nod nil)) (setq cur (dictsearch d (setq k (pfr:stub-key ty name)))))
    (progn (dictremove d k) (entdel (cdr (assoc -1 cur)))))
  (princ))


;;; ==========================================================================
;;; SECTION 6  --  The whole record
;;; ==========================================================================

;; (pfr:read e) -> an alist pf-model can be handed with no CAD present.
;;   'ename is carried so pf-draw can write back without re-finding it; every
;;   other key is plain data.
(defun pfr:read (e / out tag nm)
  (setq nm (pfl:effname e))
  (setq out (list (cons 'ename  e)
                  (cons 'block  nm)
                  (cons 'type   (car (pfr:row-for nm)))
                  (cons 'size   (pfr:size-of nm))
                  (cons 'pt     (cdr (assoc 10 (entget e))))
                  (cons 'memb   (pfr:memb-get e))
                  (cons 'src    (pfr:src-all e))
                  (cons 'schema (pfr:schema-get e))))
  (foreach tag *pf-tags*
    (setq out (cons (cons (strcase tag) (pfr:get e tag)) out)))
  (reverse out))

;; (pfr:val rec tag) -> a tag's value out of pfr:read's output
(defun pfr:val (rec tag) (cdr (assoc (strcase tag) rec)))


;;; ==========================================================================
;;; SECTION 7  --  Where a label sits
;;; ==========================================================================
;;; Text height, position and rotation are set per copy -- never frozen in the
;;; block definition -- because they depend on the grid's plot scale.
;;;
;;; POS remembers where the tool last put each label.  A label that is not
;;; there any more was moved by a drafter, and is left where they put it.
;;; Check BEFORE changing any dynamic property: a property change rebuilds
;;; the insert and can shift attributes, which would look like a hand move.

;; (pfr:att-pt e tag) -> the label's alignment point (x y) | nil
(defun pfr:att-pt (e tag / a ed p)
  (if (setq a (pfr:attr-ent e tag))
    (progn
      (setq ed (entget a)
            p  (if (and (= 0 (cdr (assoc 72 ed))) (= 0 (cdr (assoc 74 ed))))
                 (cdr (assoc 10 ed))            ; plain left: 11 is unused
                 (cdr (assoc 11 ed))))
      (list (car p) (cadr p)))))

;; (pfr:att-place e tag pt ht rot just) -> T | nil
;;   just: 'ML middle-left, 'MR middle-right, 'MC middle-centre.
;;   ATTRIB keeps vertical justification in 74, not 73 as TEXT does.
(defun pfr:att-place (e tag pt ht rot just / a ed p3 h)
  (if (setq a (pfr:attr-ent e tag))
    (progn
      (setq ed (entget a)
            p3 (list (car pt) (cadr pt) 0.0)
            h  (cond ((eq just 'MR) 2) ((eq just 'MC) 1) (T 0)))
      (foreach g (list (cons 10 p3) (cons 11 p3) (cons 40 ht) (cons 50 rot)
                       (cons 72 h) (cons 74 2))
        (setq ed (if (assoc (car g) ed)
                   (subst g (assoc (car g) ed) ed)
                   (append ed (list g)))))
      (entmod ed)
      (entupd e)
      T)))

;; (pfr:att-move e tag pt) -> T | nil   the label's point to pt, nothing else
;;   changed (text, height, rotation, justification stay).  Puts back a row
;;   moved by hand after a property change shifted it.
(defun pfr:att-move (e tag pt / a ed now dx dy p)
  (if (and (setq a (pfr:attr-ent e tag)) (setq now (pfr:att-pt e tag)))
    (progn
      (setq ed (entget a)
            dx (- (car pt) (car now))
            dy (- (cadr pt) (cadr now)))
      (foreach k '(10 11)
        (if (setq p (cdr (assoc k ed)))
          (setq ed (subst (list k (+ (car p) dx) (+ (cadr p) dy) (caddr p)) (assoc k ed) ed))))
      (entmod ed)
      (entupd e)
      T)))

(defun pfr:pos-all (e) (pfr:deser (pfr:xd-get e *pf-xd-pos*)))

;; (pfr:default-pt e tag) -> WORLD (x y) where the block definition itself
;;   puts this attribute -- where ATTSYNC sends it back to | nil.  Read from
;;   the ATTDEF in the insert's CURRENT definition (a dynamic insert's *U),
;;   so it already includes what the stretch actions do.
(defun pfr:default-pt (e tag / up ad p ed ins sx sy rot x y)
  (setq up (strcase tag))
  (foreach sd (pfl:block-ents e T)
    (if (and (null ad) (= "ATTDEF" (cdr (assoc 0 sd))) (= (strcase (cdr (assoc 2 sd))) up))
      (setq ad sd)))
  (if ad
    (progn
      (setq p   (if (and (= 0 (cdr (assoc 72 ad))) (= 0 (cdr (assoc 74 ad))))
                  (cdr (assoc 10 ad))
                  (cdr (assoc 11 ad)))
            ed  (entget e)
            ins (cdr (assoc 10 ed))
            sx  (cond ((cdr (assoc 41 ed))) (1.0))
            sy  (cond ((cdr (assoc 42 ed))) (1.0))
            rot (cond ((cdr (assoc 50 ed))) (0.0))
            x   (* sx (car p))
            y   (* sy (cadr p)))
      (list (+ (car ins) (- (* x (cos rot)) (* y (sin rot))))
            (+ (cadr ins) (+ (* x (sin rot)) (* y (cos rot))))))))

;; (pfr:moved-p e tag ref) -> T if a DRAFTER moved this label since the tool
;;   last placed it.
;;   ref = where the thing the label belongs to is NOW -- a CBI copy's
;;   insertion point, a pipe's midpoint.  POS keeps where the label and ref
;;   were when the tool placed it.  NOT moved by a drafter when the label is:
;;     where the tool left it                  (nothing touched it)
;;     where it would be if it travelled WITH ref  (the copy was moved, or the
;;                                            block's own action carried it --
;;                                            PFLABEL rides PFRUN: CAD, 2026-10-16)
;;     where the block definition puts it      (ATTSYNC reset it -- ATTSYNC sends
;;                                            labels home but leaves the
;;                                            stretched station line)
;;   Never placed by the tool, or placed before POS kept a reference point
;;   -> nil, so it is put back.
(defun pfr:moved-p (e tag ref / now def)
  (setq now (pfr:att-pt e tag))
  (and (pfr:moved-from-p e tag now ref)
       (not (and (setq def (pfr:default-pt e tag)) (< (distance def now) 0.01)))))

;; (pfr:moved-from-p e key now ref) -> T if NOW is neither where the tool
;;   last put KEY nor where it would be had it travelled with ref.  The core
;;   of pfr:moved-p, without the ATTSYNC test -- so it also serves a point
;;   that is not an attribute: the pipe's PFLEAD grip, kept in POS under
;;   its own name.  Never stored -> nil.
(defun pfr:moved-from-p (e key now ref / pos was wref rode)
  (setq pos (cdr (assoc (strcase key) (pfr:pos-all e))))
  (if (and pos now ref (cddr pos))
    (progn
      (setq was  (list (car pos) (cadr pos))
            wref (list (caddr pos) (cadddr pos))
            rode (list (+ (car was)  (- (car ref)  (car wref)))
                       (+ (cadr was) (- (cadr ref) (cadr wref)))))
      (and (> (distance was now) 0.01)
           (> (distance rode now) 0.01)))))

;; (pfr:pos-put e tag pt ref) -> T   remember where the tool put the label,
;;   and where ref (what it belongs to) was at that moment
(defun pfr:pos-put (e tag pt ref / all up)
  (setq up  (strcase tag)
        all (vl-remove-if '(lambda (x) (= (car x) up)) (pfr:pos-all e)))
  (pfr:xd-put e *pf-xd-pos*
              (pfr:ser (append all (list (list up (car pt) (cadr pt) (car ref) (cadr ref)))))))


;;; ==========================================================================
;;; SECTION 8  --  Drafter inputs shared across blocks
;;; ==========================================================================
;;; Some attributes are drafter INPUTS that must read the same on every block
;;; of a kind: the structure's PFSTAPRE etc., the pipe's PFLENPRE etc.  Type a
;;; new value on ANY block and the next run pushes it to all of them.  Two
;;; different new values is a disagreement: reported, and the old value stays
;;; until someone settles it.  ONE copy of this logic, for every kind
;;; (Jake, 2026-10-16: the pipe's inputs are shared too).
;;;
;;; A value still at its default, never written by the tool (a freshly placed
;;; block), is NOT an edit -- otherwise every new pipe, whose inputs come in
;;; filled, would outvote a real change.

;; (pfr:sync-inputs ents tags defaults retired) -> (inputs . notes)
;;   ents     the blocks of this kind
;;   defaults ((tag . value) ...)  what an input holds before anyone types
;;   retired  ((tag . old-value) ...)  old defaults the tool once wrote; a
;;            block still holding one, never retyped, gets today's default
;;   inputs   ((tag . value) ...)  what every block now holds -- read it with
;;            pfr:input
(defun pfr:sync-inputs (ents tags defaults retired / old edits new notes out ent cur def)
  (foreach tag tags
    (setq old nil edits nil
          def (cond ((cdr (assoc tag defaults))) ("")))
    (foreach e ents
      (setq cur (pfr:get e tag)
            ent (pfr:src-entry e tag))
      (cond
        ((null cur))                                    ; tag not on this block
        (ent
         (if (null old) (setq old (caddr ent)))
         (if (/= cur (cond ((caddr ent)) ("")))
           (if (not (member cur edits)) (setq edits (cons cur edits)))))
        ((or (= cur "") (= cur def) (member (cons tag cur) retired)))  ; untouched
        ((not (member cur edits)) (setq edits (cons cur edits)))))
    (setq new
      (cond
        ((= 1 (length edits))
         (if (and old (/= (car edits) old))
           (setq notes (cons (strcat "  " tag " changed to \"" (car edits) "\" -- applied to every one")
                             notes)))
         (car edits))
        ((> (length edits) 1)
         (setq notes (cons (strcat "  ** " tag " was typed differently on different blocks: "
                                   (pfl:join (mapcar '(lambda (x) (strcat "\"" x "\"")) edits))
                                   " -- kept \"" (cond (old) (def)) "\".  Make them agree.")
                           notes))
         (cond (old) (def)))
        ;; an old default the tool wrote, never retyped -> today's default
        ((and old (member (cons tag old) retired))
         (setq notes (cons (strcat "  " tag " updated to the new default \"" def "\"") notes))
         def)
        (old old)
        (T def)))
    ;; every block holds the agreed value AND records it -- including the one
    ;; it was typed on.  Its record still named the value before the edit,
    ;; and "the last agreed value" is read off the first record found: a
    ;; stale one rolled a disagreement back two changes (PFSELFTEST,
    ;; 2026-10-27), and repeated "changed to" on every run.
    (foreach e ents
      (if (and (pfr:get e tag)
               (or (/= (pfr:get e tag) new)
                   (null (setq ent (pfr:src-entry e tag)))
                   (/= (cond ((caddr ent)) ("")) new)))
        (progn (pfr:put e tag new) (pfr:src-put e tag *pf-src-rule* new))))
    (setq out (cons (cons tag new) out)))
  (cons out (reverse notes)))

;; (pfr:input tag inputs) -> that input's value, "" when absent
(defun pfr:input (tag inputs) (cond ((cdr (assoc tag inputs))) ("")))


(princ "\npf-record loaded.")
(princ)
