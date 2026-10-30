;;; ==========================================================================
;;; pf6probe.lsp  --  V6 Phase 0.  One CAD session, no design decisions.
;;;
;;; Throwaway instrument, in the spirit of Diagnostic_Tools/pfsys.lsp.  Not
;;; part of V6; nothing here survives into pf6-*.  APPLOAD it in a drawing
;;; that has an active Carlson project and a line already set up.
;;;
;;; READ-ONLY on the drawing: getvar / entget / atoms-family only.  No setvar,
;;; no command, no entmake, no entmod.  Two exceptions, both declared:
;;;   - it APPENDS a report to PF6PROBE.txt beside the drawing;
;;;   - PF6TIN loads a TIN into the Carlson session and unloads it again.
;;;
;;; Four commands, all appending to the one report:
;;;   PF6PROBE  no input.  Bindings, unit state, symbol hunt, command
;;;             surface, library folders.
;;;   PF6SIGN   pick a .cl and two points -- is cl_location_at_pt's offset
;;;             SIGNED?  Prints our own cross-product answer beside it.
;;;   PF6BLK    pick a plan structure block -- can it hold the §1.1 record?
;;;   PF6TIN    pick a TIN, query it, unload -- do the dtm wrappers work at
;;;             all?  V5 has never once called them.
;;;
;;; When they are done, paste PF6PROBE.txt back.
;;; ==========================================================================

(vl-load-com)

;;; ==========================================================================
;;; SECTION 1  --  Report plumbing
;;; ==========================================================================

(if (not (boundp '*p6-lines*)) (setq *p6-lines* nil))

;; (p6:dashes n) -> a rule n characters wide
(defun p6:dashes (n / s)
  (setq s "")
  (while (> n 0) (setq s (strcat s "-") n (1- n)))
  s)

;; (p6:pad s w) -> s padded with spaces to at least w
(defun p6:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; (p6:clip s n) -> s truncated to n characters with an ellipsis
(defun p6:clip (s n)
  (if (> (strlen s) n) (strcat (substr s 1 n) " ...") s))

;; (p6:say s) -> nil    One report line: to the command line AND the buffer.
(defun p6:say (s)
  (setq *p6-lines* (cons s *p6-lines*))
  (prompt (strcat "\n" s))
  (princ))

(defun p6:hr (title)
  (p6:say "")
  (p6:say (strcat "--- " title " " (p6:dashes (max 3 (- 66 (strlen title)))))))

;; (p6:fmt v) -> a printable, bounded string for any value.
;;   A long list prints as its length, not its contents -- a Carlson table
;;   bound to a probed symbol would otherwise fill the report.
(defun p6:fmt (v / s itm)
  (cond
    ((null v) "nil")
    ((= (type v) 'STR)  (strcat "\"" v "\""))
    ((= (type v) 'INT)  (itoa v))
    ((= (type v) 'REAL) (rtos v 2 6))
    ((= (type v) 'SYM)  (vl-symbol-name v))
    ((member (type v) '(SUBR USUBR EXSUBR EXRXSUBR)) "<function>")
    ((listp v)
     (if (> (length v) 12)
       (strcat "<list of " (itoa (length v)) ">")
       (progn
         (setq s "")
         (foreach itm v
           (setq s (strcat s (if (= s "") "" " ") (p6:fmt itm))))
         (strcat "(" s ")"))))
    (T (strcat "<" (vl-princ-to-string (type v)) ">"))))

;; (p6:val nm) -> the value of the symbol named nm, formatted, or NOT BOUND.
;;   Reading a symbol is side-effect free, which is what keeps this read-only.
(defun p6:val (nm / sym)
  (setq sym (read nm))
  (if (boundp sym)
    (p6:clip (p6:fmt (eval sym)) 110)
    "-- NOT BOUND"))

(defun p6:report (nm w)
  (p6:say (strcat "  " (p6:pad nm w) (p6:val nm))))

;; (p6:flush) -> nil    Append the buffer to the report file, then clear it.
(defun p6:flush ( / f p d s)
  (setq d (getvar "DWGPREFIX"))
  (setq p (strcat (if d d "") "PF6PROBE.txt"))
  (setq f (vl-catch-all-apply 'open (list p "a")))
  (if (or (vl-catch-all-error-p f) (null f))
    (prompt (strcat "\n\n  COULD NOT WRITE " p
                    "\n  -- copy the text above out of the command history instead."))
    (progn
      (foreach s (reverse *p6-lines*) (write-line s f))
      (close f)
      (prompt (strcat "\n\n  Report appended to: " p))))
  (setq *p6-lines* nil)
  (princ))

;; (p6:stamp) -> which drawing, when
(defun p6:stamp ()
  (strcat (getvar "DWGNAME") "   CDATE " (rtos (getvar "CDATE") 2 6)))

;; (p6:load-apis) -> nil   Same two catch-wrapped scloads V5 uses.  Idempotent.
;;   Caught even when scload itself is unbound, which is the answer "Carlson
;;   is not loaded in this session" rather than a crash.
(defun p6:load-apis ( / dir)
  (setq dir (if (and (boundp 'lspdir$) (= (type lspdir$) 'STR)) lspdir$ ""))
  (vl-catch-all-apply 'scload (list (strcat dir "tri4")))
  (vl-catch-all-apply 'scload (list (strcat dir "eworks")))
  (princ))

;; (p6:api fn args) -> value | error string.  Every Carlson call goes through
;;   here so a missing ARX reads as a finding instead of ending the run.
(defun p6:api (fn args / r)
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r)
    (strcat "FAILED: " (vl-catch-all-error-message r))
    r))


;;; ==========================================================================
;;; SECTION 2  --  A.  What Carlson has bound
;;; ==========================================================================
;;; The documented ones only.  Anything NOT BOUND here is itself the finding;
;;; section C goes looking for what we could not name.

;; (p6:probe-fn nm args) -> nil
;;   boundp is NOT the test for an ARX-defined external: cf:road_api can be
;;   callable while boundp answers nil.  So call it once, deliberately with a
;;   bad argument, and report the message.  "no function definition" means the
;;   ARX is not loaded; anything else means it is, and answered.
(defun p6:probe-fn (nm args / sym)
  (setq sym (read nm))
  (p6:say (strcat "  " (p6:pad nm 14)
                  "boundp " (if (boundp sym) "T  " "nil")
                  "   call -> "
                  (p6:clip (p6:fmt (p6:api sym args)) 80))))

(defun p6:sec-bindings ( / nm)
  (p6:hr "A  Carlson bindings")
  (foreach nm '("lspdir$" "tmpdir$" "usrdir$" "psname" "crdfile"
                "sv:sm" "sv:vs" "sv:ts" "sv:ps")
    (p6:report nm 12))
  (p6:say "")
  (p6:say "  The API entry points:")
  (p6:probe-fn "cf:road_api" '("cl_sta_range" ""))
  (p6:probe-fn "cf:dtm_api"  '("tin_z" (0.0 0.0)))
  (p6:probe-fn "scload"      '("")))


;;; ==========================================================================
;;; SECTION 3  --  B.  AutoCAD's own unit state
;;; ==========================================================================
;;; The metric guard's fallback.  If Carlson's own flag never turns up in
;;; section C, MEASUREMENT/INSUNITS is what V6 refuses on.

(defun p6:sec-units ( / v nm)
  (p6:hr "B  AutoCAD unit state (the fallback metric answer)")
  (foreach nm '("MEASUREMENT" "MEASUREINIT" "INSUNITS" "LUNITS"
                "AUNITS" "LUPREC" "DIMLUNIT" "DIMALT")
    (setq v (vl-catch-all-apply 'getvar (list nm)))
    (p6:say (strcat "  " (p6:pad nm 14)
                    (if (vl-catch-all-error-p v) "-- no such variable"
                      (p6:fmt v)))))
  (p6:say "")
  (p6:say "  MEASUREMENT 0 = imperial, 1 = metric.  INSUNITS 1 = inches,")
  (p6:say "  2 = feet, 4 = mm, 6 = m."))


;;; ==========================================================================
;;; SECTION 4  --  C.  The symbol hunt
;;; ==========================================================================
;;; OPEN-ISSUES.md has the metric guard blocked on a name: the reference says
;;; "is metric", which has a space in it and so is not a symbol.  Stop guessing
;;; the name and enumerate the symbol table instead.

(setq *p6-hunt*
  '(("metric / units"   ("*METRIC*" "*ENGLISH*" "*IMPERIAL*" "*UNITS*"))
    ("Carlson API"      ("CF:*"))
    ("Carlson SC layer" ("SC:*" "SC_*"))
    ("structure/inlet"  ("*STRUCT*" "*INLET*" "*MANHOLE*" "*CTCHBSN*"))
    ("libraries/paths"  ("*LIBRAR*" "PSNAME*" "*SUPPORT*" "*DIR$"))))

;; (p6:hunt pats cap) -> matching symbol names, at most cap of them
(defun p6:hunt (pats cap / out n nm hit p)
  (setq out nil n 0)
  (foreach nm (atoms-family 1)
    (if (< n cap)
      (progn
        (setq hit nil)
        (foreach p pats (if (wcmatch nm p) (setq hit T)))
        (if hit (setq out (cons nm out) n (1+ n))))))
  (vl-sort out '<))

(defun p6:sec-hunt ( / hits row nm)
  (p6:hr "C  Symbol hunt -- what is actually in the symbol table")
  (p6:say "  Every match, with its value.  A name here is a name we can wire to;")
  (p6:say "  an empty group means the thing does not exist under that spelling.")
  (foreach row *p6-hunt*
    (p6:say "")
    (p6:say (strcat "  [" (car row) "]"))
    (setq hits (p6:hunt (cadr row) 120))
    (if (null hits)
      (p6:say "    (nothing)")
      (foreach nm hits
        (p6:say (strcat "    " (p6:pad nm 30) (p6:val nm)))))))


;;; ==========================================================================
;;; SECTION 5  --  D.  The command surface
;;; ==========================================================================
;;; The V5 palette's Tools group has three items; two are wired to PFTools'
;;; own PFPROINV/PFPROTOP and the third is unmapped and refuses by name
;;; (pfpalette.lsp:2059, :2315).  This lists what a third item could BE.

(defun p6:sec-commands ( / hits nm)
  (p6:hr "D  Command surface -- C: functions worth knowing about")
  (setq hits (p6:hunt '("C:*PROFIL*" "C:*PRO*" "C:*SEWER*" "C:*STRUC*"
                        "C:*INLET*" "C:*PIPE*" "C:*TIN*" "C:*SURF*")
                      200))
  (if (null hits)
    (p6:say "  (nothing -- is Carlson loaded?)")
    (foreach nm hits (p6:say (strcat "    " nm)))))


;;; ==========================================================================
;;; SECTION 6  --  E.  The library folders
;;; ==========================================================================
;;; §3 wants PFSTRUCT/PFINLET read from Carlson's real libraries instead of
;;; *pfsew-type-map*'s four hardcoded names.  Do not guess the library file's
;;; extension -- tally what is in the folders and read the answer off.

(defun p6:dir-tally (nm / sym d fs tal e ext hit)
  (setq sym (read nm))
  (p6:say "")
  (if (and (boundp sym) (= (type (eval sym)) 'STR) (/= (eval sym) ""))
    (progn
      (setq d (eval sym))
      (p6:say (strcat "  " nm " = " d))
      (setq fs (vl-catch-all-apply 'vl-directory-files (list d "*.*" 1)))
      (if (vl-catch-all-error-p fs) (setq fs nil))
      (if (null fs)
        (p6:say "    (no files, or the folder could not be read)")
        (progn
          (setq tal nil)
          (foreach e fs
            (setq ext (vl-filename-extension e))
            (setq ext (if ext (strcase ext) "(none)"))
            (if (setq hit (assoc ext tal))
              (setq tal (subst (cons ext (1+ (cdr hit))) hit tal))
              (setq tal (cons (cons ext 1) tal))))
          ;; TOTAL order, no ties: vl-sort DROPS elements its predicate calls
          ;; equal, and equal extension counts are the common case here.
          (p6:say (strcat "    " (itoa (length fs)) " files, by extension:"))
          (foreach hit (vl-sort tal '(lambda (a b)
                                       (if (= (cdr a) (cdr b))
                                         (< (car a) (car b))
                                         (> (cdr a) (cdr b)))))
            (p6:say (strcat "      " (p6:pad (car hit) 10) (itoa (cdr hit))))))))
    (p6:say (strcat "  " nm " -- NOT BOUND"))))

(defun p6:sec-folders ( / nm)
  (p6:hr "E  Library folders -- what is in them")
  (foreach nm '("psname" "usrdir$" "tmpdir$" "lspdir$")
    (p6:dir-tally nm)))


;;; ==========================================================================
;;; SECTION 7  --  PF6PROBE  (no input)
;;; ==========================================================================

(defun c:PF6PROBE ( / )
  (p6:load-apis)
  (p6:say "")
  (p6:say "==========================================================================")
  (p6:say (strcat "PF6PROBE   " (p6:stamp)))
  (p6:say "==========================================================================")
  (p6:sec-bindings)
  (p6:sec-units)
  (p6:sec-hunt)
  (p6:sec-commands)
  (p6:sec-folders)
  (p6:say "")
  (p6:say "  Still to run, each appending to this same file:")
  (p6:say "    PF6SIGN   a .cl and two picks   -- is the offset signed?")
  (p6:say "    PF6BLK    pick a plan structure -- can it hold the record?")
  (p6:say "    PF6TIN    pick a TIN            -- do the dtm wrappers work?")
  (p6:flush))


;;; ==========================================================================
;;; SECTION 8  --  PF6SIGN.  Is cl_location_at_pt's offset signed?
;;; ==========================================================================
;;; PLAN §2's ONGRADE rule is CL elevation plus cross-slope x offset, which
;;; needs a SIDE, not a distance.  The probe prints the API's number beside
;;; our own cross-product answer, so the two can be compared directly rather
;;; than inferred from one pick.

;; (p6:side cl sta pt) -> which side of station-increasing the point is on
(defun p6:side (cl sta pt / a b ax ay vx vy wx wy cr)
  (setq a (p6:api 'cf:road_api (list "cl_location_at_sta" cl sta))
        b (p6:api 'cf:road_api (list "cl_location_at_sta" cl (+ sta 1.0))))
  (if (or (= (type a) 'STR) (= (type b) 'STR) (not (listp a)) (not (listp b)))
    "unknown (cl_location_at_sta did not answer)"
    (progn
      ;; the call answers (point ...) -- unwrap only if it really is nested
      (if (listp (car a)) (setq a (car a)))
      (if (listp (car b)) (setq b (car b)))
      (setq ax (car a) ay (cadr a))
      (setq vx (- (car b) ax) vy (- (cadr b) ay)
            wx (- (car pt) ax) wy (- (cadr pt) ay))
      (setq cr (- (* vx wy) (* vy wx)))
      (cond ((> cr 1e-9)  "LEFT of station-increasing")
            ((< cr -1e-9) "RIGHT of station-increasing")
            (T            "on the centreline")))))

(defun p6:probe-pt (cl pt lbl / pt2 res)
  (setq pt2 (list (car pt) (cadr pt)))
  (p6:say "")
  (p6:say (strcat "  " lbl "  " (p6:fmt pt2)))
  (setq res (p6:api 'cf:road_api (list "cl_location_at_pt" cl pt2)))
  (if (= (type res) 'STR)
    (p6:say (strcat "    cl_location_at_pt " res))
    (progn
      (p6:say (strcat "    raw return    " (p6:fmt res)))
      (if (and (listp res) (numberp (car res)))
        (progn
          (p6:say (strcat "    station       " (p6:fmt (car res))))
          (p6:say (strcat "    offset        " (p6:fmt (cadr res))))
          (p6:say (strcat "    side (ours)   " (p6:side cl (car res) pt2))))))))

(defun c:PF6SIGN ( / cl p1 p2 seed)
  (p6:load-apis)
  (p6:hr "F  cl_location_at_pt -- is the offset SIGNED?")
  (setq seed (if (and (boundp 'tmpdir$) (= (type tmpdir$) 'STR)) tmpdir$ ""))
  (setq cl (getfiled "Pick the line's .cl" seed "cl" 4))
  (if (null cl)
    (p6:say "  cancelled -- no .cl picked.")
    (progn
      (p6:say (strcat "  .cl = " cl))
      (p6:say (strcat "  cl_sta_range  "
                      (p6:fmt (p6:api 'cf:road_api (list "cl_sta_range" cl)))))
      (setq p1 (getpoint "\nPick a point clearly on ONE side of the centreline: "))
      (if p1 (setq p2 (getpoint "\nNow one clearly on the OTHER side: ")))
      (if (and p1 p2)
        (progn
          (p6:probe-pt cl p1 "point 1")
          (p6:probe-pt cl p2 "point 2")
          (p6:say "")
          (p6:say "  HOW TO READ IT: opposite signs on the two offsets means the API")
          (p6:say "  is signed and PLAN §2's ONGRADE rule can use it as written.")
          (p6:say "  Both positive means it returns magnitude only and V6 derives the")
          (p6:say "  side itself -- which it has to do at a terminus regardless, since")
          (p6:say "  pf:cl-locate-safe's fallback returns a distance (pftools-lib:56-73).")
          (p6:say "  Check the two 'side (ours)' lines disagree; if they agree, one of")
          (p6:say "  the picks was not across the line."))
        (p6:say "  cancelled -- needed two points."))))
  (p6:flush))


;;; ==========================================================================
;;; SECTION 9  --  PF6BLK.  Can the plan block hold the record?
;;; ==========================================================================
;;; PLAN §7 Q6 is the one open question that can invalidate §1.1 outright, and
;;; Q1's hazard is here too: a dynamic block reports an anonymous name in DXF
;;; group 2 once a non-default state is set, so every name-based lookup needs
;;; EffectiveName.  Both are answered by one pick.

(defun p6:xdata-apps (e / ed x out app)
  (setq ed (entget e '("*")))
  (setq x (cdr (assoc -3 ed)))
  (if (null x)
    "(none)"
    (progn
      (setq out "")
      (foreach app x
        (setq out (strcat out (if (= out "") "" ", ") (car app))))
      out)))

(defun p6:attrs (e / sub sd n tag val flg out)
  (setq sub (entnext e) n 0)
  (while (and sub
              (setq sd (entget sub))
              (/= (cdr (assoc 0 sd)) "SEQEND"))
    (if (= (cdr (assoc 0 sd)) "ATTRIB")
      (progn
        (setq tag (cdr (assoc 2 sd))
              val (cdr (assoc 1 sd))
              flg (cdr (assoc 70 sd))
              n   (1+ n))
        (setq out "")
        (if (and flg (= 1 (logand flg 1))) (setq out (strcat out " INVISIBLE")))
        (if (and flg (= 2 (logand flg 2))) (setq out (strcat out " CONSTANT")))
        (p6:say (strcat "    " (p6:pad (if tag tag "?") 14)
                        (p6:pad (strcat "\"" (if val val "") "\"") 24)
                        out))))
    (setq sub (entnext sub)))
  n)

(defun c:PF6BLK ( / e ed obj nm en dyn has n)
  (p6:hr "G  A plan structure block -- can it carry the record?")
  (setq e (car (entsel "\nPick a plan structure block: ")))
  (if (null e)
    (p6:say "  cancelled -- nothing picked.")
    (progn
      (setq ed (entget e))
      (p6:say (strcat "  entity type   " (cdr (assoc 0 ed))))
      (if (/= (cdr (assoc 0 ed)) "INSERT")
        (p6:say "  NOT AN INSERT -- pick the block, not a label or a line.")
        (progn
          (setq nm  (cdr (assoc 2 ed))
                has (cdr (assoc 66 ed))
                obj (vl-catch-all-apply 'vlax-ename->vla-object (list e)))
          (setq en  (if (vl-catch-all-error-p obj) "?"
                      (p6:api 'vlax-get-property (list obj 'EffectiveName)))
                dyn (if (vl-catch-all-error-p obj) "?"
                      (p6:api 'vlax-get-property (list obj 'IsDynamicBlock))))
          (p6:say (strcat "  DXF name (2)  " (p6:fmt nm)))
          (p6:say (strcat "  EffectiveName " (p6:fmt en)))
          (p6:say (strcat "  IsDynamic     " (p6:fmt dyn)))
          (p6:say (strcat "  layer         " (p6:fmt (cdr (assoc 8 ed)))))
          (p6:say (strcat "  insertion pt  " (p6:fmt (cdr (assoc 10 ed)))))
          (p6:say (strcat "  XDATA apps    " (p6:xdata-apps e)))
          (p6:say "")
          (if (and has (= has 1))
            (progn
              (p6:say "  attributes:")
              (setq n (p6:attrs e))
              (p6:say (strcat "    -- " (itoa n) " attribute(s)")))
            (p6:say "  NO ATTRIBUTES (group 66 absent) -- §1.1's record cannot live"))
          (p6:say "")
          (if (and (= (type nm) 'STR) (= (type en) 'STR) (/= nm en))
            (p6:say "  Q1 HAZARD CONFIRMED: DXF name and EffectiveName differ.")
            (p6:say "  Q1: DXF name and EffectiveName agree on THIS insert."))
          (p6:say "  Q6: an attribute list above with tags we can add to is the yes.")
          (p6:say "      A constant or empty list, or a Carlson-owned definition that")
          (p6:say "      gets re-inserted, is the no -- and §1.1 needs a companion block.")))))
  (p6:flush))


;;; ==========================================================================
;;; SECTION 10  --  PF6TIN.  Do the dtm wrappers work at all?
;;; ==========================================================================
;;; pftools-lib.lsp:45-47 has sat on the dead-code gate since V5 shipped --
;;; wrapped, documented, never once called.  PLAN Phase 4 rests entirely on
;;; them.  This is the only probe that touches Carlson session state, and it
;;; unloads what it loaded.

(defun c:PF6TIN ( / tin p r seed)
  (p6:load-apis)
  (p6:hr "H  cf:dtm_api -- never called in V5, Phase 4 depends on it")
  (setq seed (if (and (boundp 'tmpdir$) (= (type tmpdir$) 'STR)) tmpdir$ ""))
  (setq tin (getfiled "Pick the surface TIN" seed "tin" 4))
  (if (null tin)
    (p6:say "  cancelled -- no TIN picked.")
    (progn
      (p6:say (strcat "  tin = " tin))
      (setq r (p6:api 'cf:dtm_api (list "load_tin" tin)))
      (p6:say (strcat "  load_tin      " (p6:fmt r)))
      (setq p (getpoint "\nPick a point inside the surface: "))
      (if p
        (progn
          (setq r (p6:api 'cf:dtm_api
                          (list "tin_z" (list (car p) (cadr p)))))
          (p6:say (strcat "  pick          " (p6:fmt (list (car p) (cadr p)))))
          (p6:say (strcat "  tin_z         " (p6:fmt r)))
          (p6:say "  Compare that against the surface's own elevation there."))
        (p6:say "  no point picked -- tin_z not exercised."))
      (setq r (p6:api 'cf:dtm_api (list "unload_tin")))
      (p6:say (strcat "  unload_tin    " (p6:fmt r)))))
  (p6:flush))


(prompt "\npf6probe loaded.  Run PF6PROBE first (no input), then PF6SIGN,")
(prompt "\nPF6BLK and PF6TIN.  All four append to PF6PROBE.txt beside the drawing.")
(princ)
