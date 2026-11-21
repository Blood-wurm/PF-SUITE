;;; ==========================================================================
;;; pf-lib.lsp  --  the shared engine.  READ ONLY.
;;; Load position 2: after pf-cfg.  Depends on pf-cfg only.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; Everything more than one lisp needs lives here and is CALLED, never copied
;;; (Jake, 2026-10-15) -- the same job V5's pftools-lib did.  Maths and
;;; formatting, messages, strings, file reading, real block names, reading
;;; dynamic properties and reading a block's own geometry.
;;;
;;; NOTHING HERE WRITES THE DRAWING.  Writers live in pf-draw (entities,
;;; parameters) and pf-record (attributes, stored data).
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Messages
;;; ==========================================================================

;; While *pfl-quiet* is on, what a command says is kept in *pfl-heard*
;; (newest first) instead of printed -- PFSELFTEST runs a command's work and
;; reads what it said (2026-10-30).
(if (not (boundp '*pfl-quiet*)) (setq *pfl-quiet* nil *pfl-heard* nil))

;; (pfl:say s) -> nil   one line on the command line
(defun pfl:say (s)
  (if *pfl-quiet*
    (setq *pfl-heard* (cons s *pfl-heard*))
    (prompt (strcat "\n" s)))
  (princ))


;;; ==========================================================================
;;; SECTION 2  --  Angles and faces  (pure)
;;; ==========================================================================

;; (pfl:norm a) -> a folded into (-pi, pi]
(defun pfl:norm (a)
  (while (> a pi)       (setq a (- a (* 2.0 pi))))
  (while (<= a (- pi))  (setq a (+ a (* 2.0 pi))))
  a)

(defun pfl:deg (a) (* a (/ 180.0 pi)))

;; (pfl:readable a) -> angle a, flipped if text at that angle would read
;;   upside down
(defun pfl:readable (a)
  (setq a (rem a (* 2.0 pi)))
  (if (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (if (and (> a (/ pi 2.0)) (<= a (* 1.5 pi))) (- a pi) a))

;; (pfl:face-of dir rot) -> (letter . degrees-from-nearest-corner)
;;   dir = a world direction pointing OUT of the structure through some face.
;;   rot = the block's rotation.  At zero rotation FRONT is +X.
;;     within 45 deg of front -> "F",  within 45 deg of back -> "B",  else "S".
;;   The second value is how far the direction sits from a 45-degree corner.
;;   Small means the letter is a coin toss and the caller should say so.
(defun pfl:face-of (dir rot / a ab)
  (setq a  (pfl:norm (- dir rot))
        ab (abs a))
  (cons
    (cond ((<= ab (/ pi 4.0))       "F")
          ((>= ab (* 0.75 pi))      "B")
          (T                        "S"))
    (pfl:deg (min (abs (- ab (/ pi 4.0)))
                  (abs (- ab (* 0.75 pi)))))))

;; (pfl:face-pair in-dir out-dir rot) -> ("BF" . min-margin-degrees)
;;   in-dir  = the line's travel direction ARRIVING at the structure.
;;   out-dir = the line's travel direction LEAVING it.
;;   The line ENTERS through the face that points back where it came from --
;;   the reverse of its arriving direction.  It LEAVES through the face its
;;   leaving direction points at.
(defun pfl:face-pair (in-dir out-dir rot / e x)
  (setq e (pfl:face-of (+ in-dir pi) rot)
        x (pfl:face-of out-dir rot))
  (cons (strcat (car e) (car x)) (min (cdr e) (cdr x))))


;;; ==========================================================================
;;; SECTION 3  --  Profile grid  (pure)
;;; ==========================================================================
;;; Same conversion V5 used, so a V6 profile copy lands where V5 put labels:
;;;   x = leftx + (station - sta0)            horizontal is 1:1
;;;   y = basey + (elev - datum) * vscale     vscale = hplot / vplot

;; (pfl:grid leftx basey sta0 datum vscale) -> grid alist
(defun pfl:grid (leftx basey sta0 datum vscale)
  (list (cons 'leftx leftx) (cons 'basey basey)
        (cons 'sta0 sta0)   (cons 'datum datum)
        (cons 'vscale vscale)))

(defun pfl:g (k g) (cdr (assoc k g)))

(defun pfl:sta->x (sta g)
  (+ (pfl:g 'leftx g) (- sta (pfl:g 'sta0 g))))

(defun pfl:elev->y (elev g)
  (+ (pfl:g 'basey g) (* (- elev (pfl:g 'datum g)) (pfl:g 'vscale g))))

;; The way back: a point drawn on the profile -> its station and elevation.
(defun pfl:x->sta (x g)
  (+ (pfl:g 'sta0 g) (- x (pfl:g 'leftx g))))

(defun pfl:y->elev (y g)
  (+ (pfl:g 'datum g) (/ (- y (pfl:g 'basey g)) (pfl:g 'vscale g))))


;;; ==========================================================================
;;; SECTION 4  --  Numbers and strings  (pure)
;;; ==========================================================================

;; (pfl:fix n dec) -> n with exactly dec decimals, whatever DIMZIN says
(defun pfl:fix (n dec / s p)
  (setq s (rtos n 2 dec))
  (if (and (> dec 0) (not (vl-string-search "." s))) (setq s (strcat s ".")))
  (if (> dec 0)
    (progn
      (setq p (vl-string-search "." s))
      (while (< (- (strlen s) p 1) dec) (setq s (strcat s "0")))))
  s)

;; (pfl:fmt-sta 209.3) -> "2+09.30"
(defun pfl:fmt-sta (sta / neg n r s)
  (setq neg (< sta 0.0)
        sta (abs sta)
        n   (fix (/ (+ sta 0.005) 100.0))
        r   (- sta (* n 100.0))
        s   (pfl:fix r 2))
  (if (< r 9.995) (setq s (strcat "0" s)))
  (strcat (if neg "-" "") (itoa n) "+" s))

;; (pfl:parse-sta "2+09.30") -> 209.3   also accepts plain "209.3"
(defun pfl:parse-sta (s)
  (atof (vl-string-subst "" "+" s)))

;; (pfl:number-p s) -> T if s reads as a number
(defun pfl:number-p (s)
  (and s (/= s "") (distof s 2) T))

;; (pfl:join parts) -> the non-empty parts joined with single spaces
(defun pfl:join (parts / out)
  (setq out "")
  (foreach p parts
    (if (and p (/= p ""))
      (setq out (if (= out "") p (strcat out " " p)))))
  out)

;; (pfl:join-with sep parts) -> the non-empty parts joined with sep
(defun pfl:join-with (sep parts / out)
  (setq out "")
  (foreach p parts
    (if (and p (/= p ""))
      (setq out (if (= out "") p (strcat out sep p)))))
  out)

;; (pfl:line-parts lname) -> (util . letters) from a .cl file's name, which is
;;   what MEMB files a line under: "STORM_AA" -> ("STORM" . "AA").  Split at
;;   the FIRST underscore, as V5's pf:type-of / pf:name-of do.  No underscore
;;   -> ("" . name).
(defun pfl:line-parts (lname / i)
  (if (setq i (vl-string-search "_" lname))
    (cons (substr lname 1 i) (substr lname (+ i 2)))
    (cons "" lname)))

;; (pfl:subst-all new old s) -> s with EVERY old replaced by new
(defun pfl:subst-all (new old s / i)
  (while (setq i (vl-string-search old s))
    (setq s (strcat (substr s 1 i) new (substr s (+ i 1 (strlen old))))))
  s)

(defun pfl:nospace (s) (vl-list->string (vl-remove 32 (vl-string->list s))))

;; (pfl:pad s w) -> s padded with spaces to at least w characters
(defun pfl:pad (s w) (while (< (strlen s) w) (setq s (strcat s " "))) s)

;; (pfl:fp-str x) -> x printed for a fingerprint.  Reals to 4 decimals, so
;;   float noise below 0.0001 never reads as a change.  Dotted pairs allowed.
(defun pfl:fp-str (x / out)
  (cond
    ((null x) "nil")
    ((= (type x) 'STR) x)
    ((= (type x) 'INT) (itoa x))
    ((= (type x) 'REAL) (pfl:fix x 4))
    ((listp x)
     (setq out "(")
     (while (and x (listp x))
       (setq out (strcat out (pfl:fp-str (car x)) " ")
             x   (cdr x)))
     (if x (setq out (strcat out ". " (pfl:fp-str x))))
     (strcat out ")"))
    (T (vl-princ-to-string x))))

;; (pfl:fingerprint x) -> short text that changes whenever x does
;;   Adler-32-style running sums over the printed form, plus its length.
;;   What PFREFRESH compares to decide "changed since the tool last wrote it".
(defun pfl:fingerprint (x / s a b)
  (setq s (pfl:fp-str x) a 1 b 0)
  (foreach c (vl-string->list s)
    (setq a (rem (+ a c) 65521)
          b (rem (+ b a) 65521)))
  (strcat (itoa a) "-" (itoa b) "-" (itoa (strlen s))))

;; (pfl:csv-split s) -> one CSV line's fields, as Excel writes them: a field
;;   in double quotes may hold commas, and "" inside it is one quote.  Each
;;   field trimmed of spaces and tabs.  A UTF-8 byte-order mark at the start
;;   of the line (Excel's "CSV UTF-8") is dropped.
(defun pfl:csv-split (s / cs out cur inq c nx)
  (setq cs (vl-string->list s) cur nil out nil inq nil)
  ;; the BOM: EF BB BF read as three characters, or as one when the file
  ;; was opened as UTF-8
  (cond
    ((and (>= (length cs) 3) (= (car cs) 239) (= (cadr cs) 187) (= (caddr cs) 191))
     (setq cs (cdddr cs)))
    ((and cs (= (car cs) 65279)) (setq cs (cdr cs))))
  (while cs
    (setq c (car cs) cs (cdr cs) nx (car cs))
    (cond
      ((and inq (= c 34) (= nx 34)) (setq cur (cons 34 cur) cs (cdr cs)))
      ((= c 34) (setq inq (not inq)))
      ((and (not inq) (= c 44))
       (setq out (cons (vl-string-trim " \t" (vl-list->string (reverse cur))) out) cur nil))
      (T (setq cur (cons c cur)))))
  (reverse (cons (vl-string-trim " \t" (vl-list->string (reverse cur))) out)))

;; (pfl:split s) -> "a, b, c" -> ("a" "b" "c"), each trimmed of spaces,
;;   tabs and quotes.  Comma-delimited only (Carlson's .dta files).
(defun pfl:split (s / out cur)
  (setq cur "")
  (foreach c (vl-string->list s)
    (if (= c 44)
      (setq out (cons (vl-string-trim " \t\"" cur) out) cur "")
      (setq cur (strcat cur (chr c)))))
  (reverse (cons (vl-string-trim " \t\"" cur) out)))


;;; ==========================================================================
;;; SECTION 5  --  Files
;;; ==========================================================================

;; (pfl:readlines path) -> the file's non-blank lines | nil
(defun pfl:readlines (path / f l out)
  (if (and path (setq f (open path "r")))
    (progn
      (while (setq l (read-line f))
        (if (/= "" (vl-string-trim " \t" l)) (setq out (cons l out))))
      (close f)))
  (reverse out))

;; (pfl:file-sum path) -> a checksum of a text file's contents | nil when it
;;   can't be read.  pfl:fingerprint over its lines: the same file gives the
;;   same answer, any edit a different one.  For the .cl and .pro files an
;;   anchor binds (TINs are binary and large -- not summed).
(defun pfl:file-sum (path / l)
  (if (and path (findfile path) (setq l (pfl:readlines path)))
    (pfl:fingerprint l)))

;; (pfl:pro-parts path) -> (name . role)   V5's pf:parse-pro-name.
;;   "Storm_CA_INV.pro" -> ("CA" . "INV").  role nil = no known role suffix.
(defun pfl:pro-parts (path / full n hit suf)
  (setq full (strcase (cdr (pfl:line-parts (vl-filename-base path))))
        n    (strlen full))
  (foreach r *pf-pro-roles*
    (setq suf (strcat "_" r))
    (if (and (null hit) (> n (strlen suf)) (= (substr full (- n (strlen suf) -1)) suf))
      (setq hit (cons (substr full 1 (- n (strlen suf))) r))))
  (cond (hit) ((cons full nil))))

;; (pfl:tin-design-p path) -> T when the .tin is the proposed surface (DESIGN_*)
(defun pfl:tin-design-p (path / b p)
  (setq b (strcase (vl-filename-base path)) p (strcase *pf-tin-design-prefix*))
  (and (>= (strlen b) (strlen p)) (= (substr b 1 (strlen p)) p)))

;; (pfl:type-keyword ty) -> the word a grid name uses for the utility --
;;   "FORCE MAIN" for FORCEMAIN, else the type itself
(defun pfl:type-keyword (ty / c)
  (if (setq c (assoc (strcase ty) *pf-type-keywords*)) (strcase (cdr c)) (strcase ty)))

;; (pfl:plain-text s) -> s without AutoCAD's text formatting codes: TEXT's
;;   %%U / %%O (underline, overline) and MTEXT's \L \O and braces.  A grid
;;   name drawn underlined reads "%%USANITARY LINE A" (PFSETUP Scan,
;;   2026-11-03).  %%D, %%P, %%C stand for characters and are left alone.
(defun pfl:plain-text (s)
  (foreach code '("%%U" "%%u" "%%O" "%%o" "\\L" "\\l" "\\O" "\\o" "{" "}")
    (setq s (pfl:subst-all "" code s)))
  s)

;; (pfl:sheet-type s) -> the utility a grid-name text names | nil.  The
;;   LONGEST keyword found wins (V5's pf:sheet-type).
(defun pfl:sheet-type (s / u hit n kw)
  (setq u (strcase s) n 0)
  (foreach ty *pf-types*
    (setq kw (pfl:type-keyword ty))
    (if (and (> (strlen kw) n) (vl-string-search kw u)) (setq hit ty n (strlen kw))))
  hit)

;; (pfl:sheet-name s ty) -> "DA" from "STORM LINE 'DA'" | nil.  The name is in
;;   straight quotes (a leading backtick is tolerated, as V5 did).
(defun pfl:sheet-name (s ty / u p1 p2)
  (setq u (strcase s))
  (if (vl-string-search (pfl:type-keyword ty) u)
    (progn
      (setq p1 (cond ((vl-string-search "'" u)) ((vl-string-search "`" u))))
      (if p1 (setq p2 (vl-string-search "'" u (1+ p1))))
      (if (and p1 p2 (> p2 (1+ p1)))
        (vl-string-trim " " (substr u (+ p1 2) (- p2 p1 1)))))))


;;; ==========================================================================
;;; SECTION 6  --  Reading entities
;;; ==========================================================================

(defun pfl:ins (e) (cdr (assoc 10 (entget e))))

(defun pfl:handle (e) (cdr (assoc 5 (entget e))))

;; (pfl:effname e) -> the real definition name, never the anonymous *U47.
;;   A dynamic block reports *U47 in DXF group 2 once a non-default state is
;;   set.  Every block-name comparison in V6 goes through here.
;;   FAST (2026-11-20, the palette took a minute): a name that is not
;;   anonymous IS the real name, so AutoCAD is asked only for "*" names, and
;;   each anonymous definition only once -- remembered by its BLOCK record,
;;   which is never reused for another block.  pfl:effname-forget empties the
;;   memory; pfd:run does at every command start, the palette at every
;;   rebuild.  PFSELFTEST group 20 checks this against AutoCAD's own answer.
(setq *pfl-effname-memo* nil)

(defun pfl:effname-forget () (setq *pfl-effname-memo* nil))

(defun pfl:effname-com (e / obj r)
  (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list e)))
  (if (vl-catch-all-error-p obj)
    (cdr (assoc 2 (entget e)))
    (progn
      (setq r (vl-catch-all-apply 'vla-get-effectivename (list obj)))
      (if (vl-catch-all-error-p r) (cdr (assoc 2 (entget e))) r))))

(defun pfl:effname (e / nm blk hit r)
  (setq nm (cdr (assoc 2 (entget e))))
  (cond
    ((null nm) (pfl:effname-com e))
    ((/= (substr nm 1 1) "*") nm)
    ((and (setq blk (tblobjname "BLOCK" nm))
          (setq hit (assoc blk *pfl-effname-memo*)))
     (cdr hit))
    (T
     (setq r (pfl:effname-com e))
     (if (and blk r) (setq *pfl-effname-memo* (cons (cons blk r) *pfl-effname-memo*)))
     r)))

;; (pfl:bbox obj) -> (minx miny maxx maxy) | nil
(defun pfl:bbox (obj / mn mx r)
  (setq r (vl-catch-all-apply 'vla-getboundingbox (list obj 'mn 'mx)))
  (if (vl-catch-all-error-p r)
    nil
    (progn
      (setq mn (vlax-safearray->list mn)
            mx (vlax-safearray->list mx))
      (list (car mn) (cadr mn) (car mx) (cadr mx)))))

;; (pfl:text-len s ht style) -> how long the text draws
(defun pfl:text-len (s ht style / b)
  (setq b (textbox (list (cons 1 s) (cons 40 ht) (cons 7 (if style style "Standard")))))
  (if b (- (caadr b) (caar b)) (* (strlen s) ht)))


;;; ==========================================================================
;;; SECTION 7  --  Reading dynamic block properties
;;; ==========================================================================
;;; Writing them is pf-draw's (pfd:prop-put / pfd:dynprop-put / pfd:set-state).

;; (pfl:dynprops obj) -> every dynamic property object on the insert | nil
(defun pfl:dynprops (obj / r)
  (setq r (vl-catch-all-apply
            '(lambda () (vlax-safearray->list
                          (vlax-variant-value (vla-getdynamicblockproperties obj))))))
  (if (vl-catch-all-error-p r) nil r))

;; (pfl:dynprop obj propname) -> the property object of that name | nil.
;;   Found by name, never by index.  Spaces ignored: a point parameter's
;;   properties read "PFRUN X" in some places and "PFRUNX" in others.
(defun pfl:dynprop (obj propname / nm hit want)
  (setq want (strcase (pfl:nospace propname)))
  (foreach p (pfl:dynprops obj)
    (setq nm (vl-catch-all-apply 'vla-get-propertyname (list p)))
    (if (and (null hit) (not (vl-catch-all-error-p nm))
             (= (strcase (pfl:nospace nm)) want))
      (setq hit p)))
  hit)

;; (pfl:prop-get p) -> value | nil          THE one read.
(defun pfl:prop-get (p / r)
  (setq r (vl-catch-all-apply 'vla-get-value (list p)))
  (if (vl-catch-all-error-p r) nil
    (if (= (type r) 'VARIANT) (vlax-variant-value r) r)))

(defun pfl:dynprop-get (obj propname / p)
  (if (setq p (pfl:dynprop obj propname)) (pfl:prop-get p)))

;; (pfl:allowed p) -> a property's allowed values, as strings, or nil.
;;   Two unwraps -- every element of the safearray is itself a variant
;;   (CAD, 2026-09-11).  An EMPTY allowed-values variant is still a non-nil
;;   object, so callers must test the unwrapped LIST, not the variant.
(defun pfl:allowed (p / r)
  (setq r (vl-catch-all-apply
            '(lambda () (vlax-safearray->list (vlax-variant-value (vla-get-allowedvalues p))))))
  (if (vl-catch-all-error-p r) nil
    (mapcar '(lambda (v) (if (= (type v) 'VARIANT) (vl-princ-to-string (vlax-variant-value v))
                           (vl-princ-to-string v)))
            r)))

;; (pfl:visprop obj) -> the visibility property | nil
;;   PFVIS by name first; failing that, the one property with allowed values
;;   (AutoCAD permits only ONE visibility parameter per block).
(defun pfl:visprop (obj / hit)
  (setq hit (pfl:dynprop obj *pf-vis-param*))
  (if (null hit)
    (foreach p (pfl:dynprops obj)
      (if (and (null hit) (pfl:allowed p)) (setq hit p))))
  hit)


;;; ==========================================================================
;;; SECTION 8  --  Reading a block's own geometry
;;; ==========================================================================
;;; A dynamic insert's CURRENT geometry is its *U definition, so these read
;;; the block the insert points at now.  Entities another visibility state
;;; hides carry 60 = 1 there and are left out (confirmed by PFGATE's count,
;;; CAD 2026-10-15).  Nested blocks and attributes are never counted: a line
;;; inside a nested block cannot be stretched, so it is not the block's own.

;; (pfl:block-ents e all) -> the entity lists drawn directly in the insert.
;;   all nil = showing only;  all T = hidden ones too.
(defun pfl:block-ents (e all)
  (pfl:def-ents (cdr (assoc 2 (entget e))) all))

;; (pfl:def-ents name all) -> the entity lists in block definition name.
;;   all as above.  The same walk, by name -- for a nested symbol.
(defun pfl:def-ents (name all / bd ent sd out)
  (if (and name (setq bd (tblobjname "BLOCK" name)))
    (progn
      (setq ent (entnext bd))
      (while (and ent (setq sd (entget ent)) (/= "ENDBLK" (cdr (assoc 0 sd))))
        (if (or all (/= 1 (cdr (assoc 60 sd)))) (setq out (cons sd out)))
        (setq ent (entnext ent)))))
  (reverse out))

;; (pfl:vlines e) -> ((x ybot ytop) ...) every vertical LINE or 2-point
;;   polyline showing, in BLOCK coordinates, longest first
(defun pfl:vlines (e / p1 p2 v out)
  (foreach sd (pfl:block-ents e nil)
    (setq p1 nil p2 nil)
    (cond
      ((= "LINE" (cdr (assoc 0 sd)))
       (setq p1 (cdr (assoc 10 sd)) p2 (cdr (assoc 11 sd))))
      ((and (= "LWPOLYLINE" (cdr (assoc 0 sd))) (= 2 (cdr (assoc 90 sd))))
       (setq v  (vl-remove-if-not '(lambda (g) (= 10 (car g))) sd)
             p1 (cdar v) p2 (cdadr v))))
    (if (and p1 p2 (< (abs (- (car p1) (car p2))) 1e-6))
      (setq out (cons (list (car p1) (min (cadr p1) (cadr p2)) (max (cadr p1) (cadr p2)))
                      out))))
  (vl-sort out '(lambda (a b) (> (- (caddr a) (cadr a)) (- (caddr b) (cadr b))))))

;; (pfl:vsegs e) -> ((x ybot ytop) ...) EVERY vertical segment showing, in
;;   BLOCK coordinates: LINEs and each segment of every LWPOLYLINE, a closed
;;   one's closing segment too.  A barrel drawn as one rectangle is four
;;   segments, two of them its walls.
(defun pfl:vsegs (e / pts closed out p q)
  (foreach sd (pfl:block-ents e nil)
    (setq pts nil)
    (cond
      ((= "LINE" (cdr (assoc 0 sd)))
       (setq pts (list (cdr (assoc 10 sd)) (cdr (assoc 11 sd))) closed nil))
      ((= "LWPOLYLINE" (cdr (assoc 0 sd)))
       (setq pts    (mapcar 'cdr (vl-remove-if-not '(lambda (g) (= 10 (car g))) sd))
             closed (= 1 (logand 1 (cond ((cdr (assoc 70 sd))) (0)))))))
    (if (and closed (cdr pts)) (setq pts (append pts (list (car pts)))))
    (while (cdr pts)
      (setq p (car pts) q (cadr pts) pts (cdr pts))
      (if (and (< (abs (- (car p) (car q))) 1e-6) (> (abs (- (cadr p) (cadr q))) 1e-6))
        (setq out (cons (list (car p) (min (cadr p) (cadr q)) (max (cadr p) (cadr q))) out)))))
  out)

;; (pfl:walls e r) -> (left-ybot right-ybot half-width) in WORLD Y | nil
;;   The structure's two outer walls in profile and where each one stops at
;;   the bottom -- the floor at that wall.  r: the barrel's half-width when
;;   the block says it (PFBARREL_R; 2.0 on the 48" sanitary MH), else nil and
;;   the outermost vertical segment on each side is taken.  The station line
;;   (at X 0) is never a wall.  Read off what the insert SHOWS: no parameter
;;   is nudged, so reading it never changes the drawing.
(defun pfl:walls (e r / ed sy sx y0 segs lft rgt lx rx lb rb hw)
  (setq ed   (entget e)
        sx   (cond ((cdr (assoc 41 ed))) (1.0))
        sy   (cond ((cdr (assoc 42 ed))) (1.0))
        y0   (cadr (cdr (assoc 10 ed)))
        segs (vl-remove-if '(lambda (s) (< (abs (car s)) 1e-3)) (pfl:vsegs e)))
  (if r
    (setq lft (vl-remove-if-not '(lambda (s) (< (abs (+ (car s) r)) 0.05)) segs)
          rgt (vl-remove-if-not '(lambda (s) (< (abs (- (car s) r)) 0.05)) segs)))
  ;; no wall at the stated width: the outermost on each side
  (if (null lft)
    (progn
      (foreach s segs (if (and (< (car s) 0.0) (or (null lx) (< (car s) lx))) (setq lx (car s))))
      (if lx (setq lft (vl-remove-if-not '(lambda (s) (< (abs (- (car s) lx)) 1e-3)) segs)))))
  (if (null rgt)
    (progn
      (foreach s segs (if (and (> (car s) 0.0) (or (null rx) (> (car s) rx))) (setq rx (car s))))
      (if rx (setq rgt (vl-remove-if-not '(lambda (s) (< (abs (- (car s) rx)) 1e-3)) segs)))))
  (if (and lft rgt)
    (progn
      (setq lb (apply 'min (mapcar 'cadr lft))
            rb (apply 'min (mapcar 'cadr rgt))
            hw (* sx (max (abs (car (car lft))) (abs (car (car rgt))))))
      (list (+ y0 (* sy lb)) (+ y0 (* sy rb)) hw))))

;; (pfl:leader-path tip top right sf) -> ((pt start-width end-width) ...)
;;   A leader from an arrow at tip to a label whose top row's insertion point
;;   is top.  right = the label is right of the arrow.  A level landing that
;;   stops *pf-pipe-land-gap* short of the row, a bend a landing's length
;;   further from the text, a sloped leg back to the tip; the first segment
;;   tapers from nothing to the arrow's width, which IS the arrowhead.  Sizes
;;   at 1"=20', scaled by sf.  Shared by the pipe label and the crossing label.
(defun pfl:leader-path (tip top right sf / dir land bend back)
  (setq dir  (if right -1.0 1.0)
        land (list (+ (car top) (* dir sf *pf-pipe-land-gap*)) (cadr top))
        bend (list (+ (car land) (* dir sf *pf-pipe-land-len*)) (cadr land))
        back (polar tip (angle tip bend) (* sf *pf-pipe-arrow-len*)))
  (list (list tip  0.0 (* sf *pf-pipe-arrow-wid*))
        (list back 0.0 0.0)
        (list bend 0.0 0.0)
        (list land 0.0 0.0)))

;; (pfl:station-line e) -> (ybot ytop) in WORLD Y | nil
;;   The vertical line at the block's X origin -- the station -- the longest
;;   if several.  Only when nothing is at the origin, the longest vertical
;;   line anywhere (a barrel wall is vertical too, which is why the origin
;;   comes first).
(defun pfl:station-line (e / ed sy y0 vs hit)
  (setq ed  (entget e)
        sy  (cond ((cdr (assoc 42 ed))) (1.0))
        y0  (cadr (cdr (assoc 10 ed)))
        vs  (pfl:vlines e)
        hit (cond ((car (vl-remove-if-not '(lambda (v) (< (abs (car v)) 1e-3)) vs)))
                  ((car vs))))
  (if hit (list (+ y0 (* sy (cadr hit))) (+ y0 (* sy (caddr hit))))))

;; (pfl:geom-pts e) -> ((x y) ...) every vertex of the lines and polylines
;;   showing, BLOCK coordinates, in drawing order
(defun pfl:geom-pts (e) (pfl:sd-pts (pfl:block-ents e nil)))

;; (pfl:sd-pts sds) -> ((x y) ...) every vertex of the LINEs and LWPOLYLINEs
;;   in these entity lists, in order.  Shared by the two readers above/below.
(defun pfl:sd-pts (sds / out)
  (foreach sd sds
    (cond
      ((= "LINE" (cdr (assoc 0 sd)))
       (setq out (cons (list (cadr (assoc 11 sd)) (caddr (assoc 11 sd)))
                       (cons (list (cadr (assoc 10 sd)) (caddr (assoc 10 sd))) out))))
      ((= "LWPOLYLINE" (cdr (assoc 0 sd)))
       (foreach g sd
         (if (= 10 (car g)) (setq out (cons (list (cadr g) (caddr g)) out)))))))
  (reverse out))

;; (pfl:nested-bottom e) -> WORLD Y of the lowest line / polyline vertex in
;;   the plain symbols NESTED in insert e and showing in its current state |
;;   nil when it shows none.  The headwall's profile symbol is one: its
;;   geometry reaches below the flowline, and pfl:geom-bottom (which skips
;;   nested blocks) can't see it.  Nested inserts are taken as unrotated; their
;;   own insertion point and Y scale are applied, then the outer insert's.
(defun pfl:nested-bottom (e / ed sy y0 lo ny nsy y)
  (setq ed (entget e)
        sy (cond ((cdr (assoc 42 ed))) (1.0))
        y0 (cadr (cdr (assoc 10 ed))))
  (foreach sd (pfl:block-ents e nil)
    (if (= "INSERT" (cdr (assoc 0 sd)))
      (progn
        (setq ny  (cadr (cdr (assoc 10 sd)))
              nsy (cond ((cdr (assoc 42 sd))) (1.0)))
        (foreach p (pfl:sd-pts (pfl:def-ents (cdr (assoc 2 sd)) nil))
          (setq y (+ y0 (* sy (+ ny (* nsy (cadr p))))))
          (if (or (null lo) (< y lo)) (setq lo y))))))
  lo)

;; (pfl:geom-ys e) -> the WORLD Y of each of those, same order | nil
(defun pfl:geom-ys (e / ed sy y0)
  (setq ed (entget e)
        sy (cond ((cdr (assoc 42 ed))) (1.0))
        y0 (cadr (cdr (assoc 10 ed))))
  (mapcar '(lambda (p) (+ y0 (* sy (cadr p)))) (pfl:geom-pts e)))

;; (pfl:geom-bottom e) -> the lowest of those | nil
(defun pfl:geom-bottom (e / ys)
  (if (setq ys (pfl:geom-ys e)) (apply 'min ys)))

;; (pfl:end-y e which) -> world Y | nil
;;   'top: the station line's top (what PFTOP stretches).  'bot: the lowest
;;   line in the block -- used only to check PFTOP leaves the bottom alone.
(defun pfl:end-y (e which / sl)
  (if (eq which 'top)
    (if (setq sl (pfl:station-line e)) (cadr sl))
    (pfl:geom-bottom e)))


(princ "\npf-lib loaded.")
(princ)
