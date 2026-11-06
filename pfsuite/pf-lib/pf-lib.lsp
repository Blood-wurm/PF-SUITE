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
(defun pfl:effname (e / obj r)
  (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list e)))
  (if (vl-catch-all-error-p obj)
    (cdr (assoc 2 (entget e)))
    (progn
      (setq r (vl-catch-all-apply 'vla-get-effectivename (list obj)))
      (if (vl-catch-all-error-p r) (cdr (assoc 2 (entget e))) r))))

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
(defun pfl:block-ents (e all / bd ent sd out)
  (if (setq bd (tblobjname "BLOCK" (cdr (assoc 2 (entget e)))))
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
(defun pfl:geom-pts (e / out)
  (foreach sd (pfl:block-ents e nil)
    (cond
      ((= "LINE" (cdr (assoc 0 sd)))
       (setq out (cons (list (cadr (assoc 11 sd)) (caddr (assoc 11 sd)))
                       (cons (list (cadr (assoc 10 sd)) (caddr (assoc 10 sd))) out))))
      ((= "LWPOLYLINE" (cdr (assoc 0 sd)))
       (foreach g sd
         (if (= 10 (car g)) (setq out (cons (list (cadr g) (caddr g)) out)))))))
  (reverse out))

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
