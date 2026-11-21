;;; ==========================================================================
;;; pf-cfg.lsp  --  V6 constants and rule tables.
;;; Load position 1.  Depends on nothing.
;;;
;;; THE NAME CONTRACT.  Everything below that names a block, a visibility
;;; state, an attribute tag or a dynamic property is text that also gets typed
;;; into the Block Editor.  Nothing checks the two agree -- there is no
;;; compiler and no load-order gate that spans that boundary -- so a rename on
;;; either side fails silently on a live job.  Two rules:
;;;
;;;   1. No other file contains these strings as literals.  Ever.
;;;   2. Once a drawing exists carrying these blocks, the names stop being
;;;      editable.  Changing one is a *pf-schema* bump, not a tidy-up.
;;;
;;; V5 is never loaded alongside this (Jake, 2026-09-08), so the pf- prefix is
;;; free.  Checked against V5's 53 *pf-* globals anyway: no name here collides.
;;;
;;; NEVER NEST A DYNAMIC BLOCK INSIDE A PF-* BLOCK.  AutoCAD strips a nested
;;; block's dynamic behaviour, gives the parent no way to reach in and set it,
;;; and -- the one that would actually hurt -- resets a nested block's state
;;; to default whenever the parent is redefined, which is what a library
;;; update IS.  Nested attributes never surface on the parent either.
;;;
;;; Nesting PLAIN geometry is fine and expected -- a curb shape reused across
;;; several states should be one block, drawn once.  It just has to stay dumb:
;;; no states, no parameters, no attributes.  Every state, every parameter and
;;; all nine tags live on the PFSUITE_* definition itself.
;;;
;;; Items marked HOLE are unanswered.  They are named so the gate can report
;;; them, not so they can be guessed at.
;;;
;;; Pipe materials and sizes (inside and outside diameters) live in ONE table
;;; kept with the lisp, pf-cfg\pf-pipes.csv (Jake, 2026-11-20) -- SECTION 10.
;;; Carlson's pipesize.dta / pipen.dta are no longer read.
;;; ==========================================================================

(setq *pf-schema* 1)               ; record version.  Bump on ANY name change.


;;; ==========================================================================
;;; SECTION 1  --  Block definitions
;;; ==========================================================================
;;; Usually one definition per TYPE, sizes inside it (2026-09-22): PFSUITE_CBI carries
;;; a PFSIZE_LU lookup that drives every size-dependent dimension, and the
;;; PFSIZE attribute is a field on that lookup.  Variants within a type are
;;; visibility states -- PLAN plus the nine-state face matrix on a CBI.
;;; HDWL is the fixed-size exception: PFSUITE_HDWL_12, _15, etc. have PLAN
;;; and PROFILE states and no PFSIZE_LU lookup.  The sanitary draft is a
;;; manually sized exception: its cone width/height grips are independent of
;;; the nominal PFSIZE attribute.
;;; (The first design, 2026-09-11, was one definition per type PER SIZE,
;;; PFSUITE_CBI_04 .. _12, after the company's CBI_MH_04 convention.  It was
;;; replaced; a sized name is still READ, see below.)
;;;
;;; Every suite block is PFSUITE_<NAME> (Jake, 2026-10-15).  pfr:row-for
;;; matches a name EXACTLY, or as the root plus a numeric size
;;; (PFSUITE_DBI_04) -- never by prefix, which would read any
;;; PFSUITE_CBI_<anything> as a CBI.
;;;
;;; The SIZES ARE NOT LISTED HERE.  They live in each block's own lookup
;;; table; this file is the authority on what things are CALLED.
;;;
;;; Row: (key nameroot statelist)

(setq *pf-blocks*
  '((CBI        "PFSUITE_CBI"        *pf-states-face*)
    (CBI-BOX    "PFSUITE_CBI_BOX"    *pf-states-one*)
    (DBI        "PFSUITE_DBI"        *pf-states-one*)
    (SMH        "PFSUITE_SMH"        *pf-states-cone*)
    (DMH        "PFSUITE_DMH"        *pf-states-one*)
    (MH         "PFSUITE_MH"         *pf-states-one*)
    (HDWL       "PFSUITE_HDWL"       *pf-states-one*)))

;; How a size is spelled in a block name, and therefore in PFSIZE.  The
;; company writes two digits, zero-padded, with gaps (04 05 06 07 08 10 12) --
;; so a size is TEXT, never a number.  "04" and "4" are different blocks, and
;; (itoa 4) would not find either.
(setq *pf-size-sep*   "_")
(setq *pf-size-width* 2)           ; zero-padded to this many digits
;; A box size in a name: PFSUITE_HDWL_24x36 (Jake, 2026-11-12: headwalls are
;; one block PER SIZE, box sizes included).  Matched in any case.
(setq *pf-size-by*    "x")

;; The dynamic Visibility parameter's NAME, as typed in the Block Editor.
;; NOT frozen -- pf-record DISCOVERS it, by walking the block definition's
;; extension dictionary for the BLOCKVISIBILITYPARAMETER entity and reading
;; the name off group code 301.  So a rename in the Block Editor cannot break
;; the tool.  This constant is only what the gate EXPECTS to find, so a
;; surprise gets reported instead of silently absorbed.
(setq *pf-vis-param* "PFVIS")

;; The state every PLAN insert sits in.  Plan inserts are never restated.
(setq *pf-state-plan* "PLAN")

;; Profile states for a block that carries the face matrix.  The value of the
;; PFFACE attribute IS the state name -- 1:1, no mapping table between the
;; record and the drawing.
;;   first letter  = face the .cl ENTERS through (its LOWER-station side --
;;                   downstream, where the flow LEAVES)
;;   second letter = face the .cl LEAVES through (its higher-station side)
;;   B back / F front / S side
;; Flow always leaves an inlet through its BACK (Jake, 2026-11-20), so in
;; practice the first letter is B: BB, BF or BS.  The order is unchanged --
;; "the inlets have been fine so far".
(setq *pf-states-face*
  '("BB" "BF" "BS"
    "FB" "FF" "FS"
    "SB" "SF" "SS"))

;; Profile state for a block with no matrix.
(setq *pf-states-one* '("PROFILE"))

;; Profile states for the sanitary MH: one per cone (Jake, 2026-11-19).  The
;; 48" barrel is drawn once and shown in all three; each state shows its own
;; cone.  The copy's PFSIZE IS the state name -- typed on the plan block,
;; copied by PFSTRUCT, followed by PFREFRESH -- the way PFFACE is a CBI's
;; state.  Matched in any case, spaces ignored (pfs:cone-state).
(setq *pf-states-cone* '("48x24" "48x30" "48x36"))


;;; ==========================================================================
;;; SECTION 2  --  Attribute tags
;;; ==========================================================================
;;; Drafter-visible, drafter-editable.  The test: if a human should ever see
;;; or type it, it is an attribute; if only the tool cares, it is XDATA.
;;; The SAME tag set goes on every definition, including the ones where a tag
;;; is inert -- a uniform record is worth more than a saved attribute.

(setq *pf-tag-name*   "PFNAME")    ; the structure's name.  Stored, not ranked.
(setq *pf-tag-type*   "PFTYPE")    ; CBI / DBI / SMH / DMH / MH / HDWL
(setq *pf-tag-size*   "PFSIZE")    ; nominal size, as it should print
(setq *pf-tag-pos*    "PFPOS")     ; position tag -- drives elevation (§4)
(setq *pf-tag-rim*    "PFRIM")     ; reference elevation; HDWL = flowline at basepoint
(setq *pf-tag-struct* "PFSTRUCT")  ; Carlson structure-library entry
(setq *pf-tag-inlet*  "PFINLET")   ; Carlson inlet-library entry, "" = no flow
(setq *pf-tag-view*   "PFVIEW")    ; PLAN | PROFILE -- see below
(setq *pf-tag-face*   "PFFACE")    ; the two-letter designation

;; PFNAME is the structure's DESIGNATION -- "AA-1".  The profile label is the
;; construction row, PFCON, which reads "CONST. CURB BOX INLET AA-1": PFCONPRE
;; + PFNAME + PFCONSUF, all drafter inputs.  No size (Jake, 2026-10-15).  No
;; wording from a table -- "that's what we have prefix and suffix attributes
;; for" (Jake, 2026-10-27); the type's wording is PFCONPRE's DEFAULT.
;; There is no separate label tag; PFCON is it, and it is what must match on
;; every block sharing a PFNAME.

;; Invert slots.  A structure has a varying number of pipes, and attributes are
;; fixed slots -- so there are *pf-inv-max* of them and unused ones sit blank.
;; Blank draws nothing, which is why the varying count needs no visibility
;; states at all.  Each slot is positioned by its own XY parameter, set by the
;; tool from the .pro -- see SECTION 2b.
(setq *pf-inv-max* 5)

(setq *pf-tags-inv*
  (list "PFINV1" "PFINV2" "PFINV3" "PFINV4" "PFINV5"))

;; The label stack at the grid top, as V5 builds it (pf:build-label-rows):
;;   one STATION row per line the structure is on, then the construction row,
;;   then an optional second text row, then the elevation row.
;; A plain CBI is three rows; a junction on three lines is six.  Fixed slots,
;; blank ones draw nothing -- same reason the invert slots are fixed.
;; The tool composes the text; these hold the finished strings.
(setq *pf-sta-max* 3)                 ; station rows -- a junction on 3 lines

(setq *pf-tags-row*
  (list "PFSTA1" "PFSTA2" "PFSTA3"    ; station rows
        "PFCON"                       ; CONST. 4' DRAINAGE MH AA-1
        "PFTEXT2"                     ; W/ CURB INLET CASTING  (type-dependent)
        "PFELEV"))                    ; G.L. 769.13

;; DRAFTER INPUTS.  V5 kept these in a settings dialog; here they are
;; attributes on each profile copy, filled from SAVED DEFAULTS kept in the
;; drawing -- line, then utility, then drawing, then the type's built-in
;; default below (pf-defaults; the palette's Defaults button, PFDEFAULTS).
;; The drawing carries its own wording; there is no settings file to lose.
;; A value typed on one copy stays on that copy (Jake, 2026-11-17: this
;; replaces the 2026-10-27 push to every block of a type).
(setq *pf-tag-sta-pre*  "PFSTAPRE")   ; before the station      "STA."
(setq *pf-tag-sta-suf*  "PFSTASUF")   ; after it, [line] allowed
(setq *pf-tag-con-pre*  "PFCONPRE")   ; starts the construction row  "CONST. CURB BOX INLET"
(setq *pf-tag-con-suf*  "PFCONSUF")   ; end of the construction row
(setq *pf-tag-elev-pre* "PFELEVPRE")  ; starts the elevation row  "G.L.".  Blank = no row
(setq *pf-tag-elev-suf* "PFELEVSUF")  ; end of the elevation row

(setq *pf-tags-fmt*
  (list *pf-tag-sta-pre* *pf-tag-sta-suf*
        *pf-tag-con-pre* *pf-tag-con-suf* *pf-tag-elev-pre* *pf-tag-elev-suf*))

;; WHICH TAGS ARE TEXT ON THE SHEET.  Everything else is invisible -- the
;; record and the drafter inputs read in Properties and come out in data
;; extraction, but must never print.  PFMKATT builds from this.
(setq *pf-tags-visible* (append *pf-tags-row* *pf-tags-inv*))

;; Draft-time layout only.  The tool sets every visible attribute's position,
;; rotation and height per copy from the anchor's scale, so these values decide
;; nothing at run time -- they exist so the block is legible while you build it.
;; V5's convention (pfd:draw-label-stack, confirmed 2026-09-18), NOT a Y-stack:
;; every row is rotated 90 deg reading up, one shared baseline, columns not
;; rows.  PFSTA1 sits LEFT of the station line at *pf-draw-row-offset*; every
;; row after it sits RIGHT, spaced out by *pf-draw-row-gap* each.
(setq *pf-draw-row-offset* 1.0)    ; x text height, station line -> PFSTA1
(setq *pf-draw-row-gap*    1.5)    ; x text height, between the rest of the rows

;; Consistency scopes (from the per-type push; nothing reads these since the
;; saved defaults replaced it, 2026-11-17 -- kept so no name is lost):
;;   drawing-wide -- every structure in the drawing must agree
;;   per-name     -- every block sharing a PFNAME must agree
(setq *pf-tags-drawing-wide* *pf-tags-fmt*)
(setq *pf-tags-per-name*     (list "PFCON"))

(setq *pf-tags*
  (append
    (list *pf-tag-name* *pf-tag-type* *pf-tag-size* *pf-tag-pos*
          *pf-tag-rim*  *pf-tag-struct* *pf-tag-inlet*
          *pf-tag-view* *pf-tag-face*)
    *pf-tags-inv*
    *pf-tags-row*
    *pf-tags-fmt*))


;;; ---- SECTION 2b  --  Dynamic parameters the tool sets ---------------------
;;; Parameters, unlike visibility, are NOT limited to one per block.  That is
;;; what keeps a varying invert count from multiplying the nine face states:
;;; the count stops being a discrete choice and becomes positions and a depth
;;; that the tool writes.
;;;
;;; These names are typed in the Block Editor and matched here, so they are
;;; frozen exactly like the attribute tags.
;;;
;;; BARREL DEPTH is SET BY THE DRAFTER with the PFDEPTH grip, never by the tool
;;; (Jake, 2026-10-15).  PFSTRUCT leaves it alone; PFGATE only checks the grip
;;; moves the barrel.  OPEN: a junction is one structure drawn on two or three
;;; profiles, each copy its own insert -- so its depth is set once per copy and
;;; can differ between sheets.  Fine for the CBI + PIPE first version.
;;; The invert TICKS are per copy: each profile copy shows only its own
;;; line's inverts.
(setq *pf-param-depth* "PFDEPTH")     ; vertical linear parameter -- drafter's
;; SMH floor: PFDEPTH sets the whole floor, PFFLOORDWN one end of it -- the
;; drafter's drop (0.1 is the standard).  A linear grip, straight down the
;; wall, carried along by PFDEPTH.  The tool never sets or reads it; PFGATE
;; only checks it (Jake, 2026-11-19).
(setq *pf-param-floor* "PFFLOORDWN")

;; The station line up to the grid top, with the label rows on its top end.
;; V5 puts a structure's callout at the GRID TOP, not beside the structure --
;; so the block spans from the rim up to the grid top in one entity rather
;; than a second label block that could be orphaned.  The tool sets this from
;; the same top-of-grid probe V5 uses (Q3: the probe stays).
(setq *pf-param-top* "PFTOP")

;; Which catalog size is inserted on lookup blocks.  A Lookup parameter, not a Distance --
;; drives PFOD_R/PFID_R/PFSLAB off the size table (pf-cfg carries no copy of
;; that table; it lives only in the block's own Lookup Table, same reason
;; sizes-per-type live in the block folder, not here -- see SECTION 1).
;; On lookup blocks PFSIZE the ATTRIBUTE is field-linked to this parameter;
;; PFSTRUCT copies the lookup value.  Fixed-size HDWL uses its block name,
;; and the SMH copies the plan PFSIZE attribute instead -- its cone size,
;; which also picks its profile state (*pf-states-cone*).
(setq *pf-param-size* "PFSIZE_LU")

;; The profile barrel's half-width, station line to barrel edge.  A column in
;; PFSIZE_LU's table, so the lookup sets it -- the tool never writes it.  Named
;; here so PFGATE can check it is in the block (2026-10-15).
(setq *pf-param-barrel* "PFBARREL_R")

;; NO per-invert parameters.  V5 hangs every invert column from ONE baseline --
;; the lowest invert at the structure, less 4 x text height -- and only the
;; pipe symbols sit at true elevations.  The barrel bottom IS that lowest
;; invert, so the whole fan rides down with the barrel: the five invert
;; attributes go in the PFDEPTH stretch selection and need no parameters of
;; their own.  The tool fills the text and blanks the unused slots.
(setq *pf-inv-drop-factor* 4.0)       ; x text height, fan baseline below bottom
(setq *pf-inv-gap-factor*  2.0)       ; x text height, column centre to centre

;; With no pipes at a structure, a hand-typed invert row hangs this far below
;; the rim (the barrel itself is the drafter's -- see PFDEPTH above).
(setq *pf-depth-min* 1.0)             ; feet

;; PFVIEW exists because plan and profile inserts share a definition, so a
;; selection filter cannot tell them apart by block name.  The visibility
;; state could tell them apart, but reading a state costs COM on every read
;; -- which is the whole point of putting the designation in an attribute.
(setq *pf-view-plan* "PLAN")
(setq *pf-view-pro*  "PROFILE")

;; How PFFACE is worked out.  At zero rotation a CBI's FRONT faces +X (Jake,
;; 2026-09-15), so BACK is -X and the SIDES are +/-Y.  The line's direction
;; is sampled *pf-face-probe* feet before and after the structure -- far
;; enough to see the pipe, not the structure's own footprint -- and each
;; direction is turned into a face against the block's rotation:
;;   within 45 deg of front  -> F,   within 45 deg of back -> B,   else S.
;; ENTERS = the face toward where the line comes FROM (station-increasing).
;; A direction within *pf-face-warn* degrees of a 45-degree corner is a
;; coin toss, and says so rather than picking silently.
(setq *pf-face-probe* 5.0)         ; feet either side of the structure
(setq *pf-face-warn*  5.0)         ; degrees from a corner that gets a warning

;; ONE FACE PER LINE (Jake, 2026-11-20).  Each line the structure is on gets
;; its own face, kept in its MEMB entry: (line station offset face).  The
;; profile copy on that line shows that line's face.  The plan block's
;; PFFACE attribute keeps the through-line's face (the line that runs on both
;; sides of it), or the only line's.  A PFFACE typed by hand on the plan block
;; wins on every copy.
;; Only the UPSTREAM side is read: the flow always leaves through the back,
;; *pf-face-out*.  A downstream side that reads anything else is reported --
;; the inlet is turned wrong in plan -- and that line's face is not written.
;; At the top of a line (nothing upstream) the line is taken as running
;; straight through: the face opposite the back, *pf-face-opposite*.
(setq *pf-face-out* "B")
(setq *pf-face-opposite* '(("B" . "F") ("F" . "B") ("S" . "S")))
(setq *pf-face-none* "")           ; no matrix on this block type


;;; ==========================================================================
;;; SECTION 3  --  XDATA
;;; ==========================================================================
;;; Tool-only, invisible.  regapp'd once by pf-record.

(setq *pf-app* "PFTOOLS")

(setq *pf-xd-memb*   "MEMB")       ; ((line station offset) ...) at assign time
(setq *pf-xd-src*    "SRC")        ; provenance, per derived tag -- see below
(setq *pf-xd-schema* "SCHEMA")     ; *pf-schema* as written

;; PROFILE inserts only -- the identity link back to the plan.  A profile
;; insert is a projection: it is found again by these two, never by position,
;; so a re-run MOVES the existing copy instead of stacking a second one.
(setq *pf-xd-plan*   "PLAN")       ; the plan insert's handle
(setq *pf-xd-line*   "LINE")       ; which line's profile this copy is on

;; Where the tool last put a label: ((tag x y) ...).  If the label is not
;; there any more, a drafter moved it -- and it is left where they put it.
;; UNLESS it sits exactly where the block definition puts it: that is ATTSYNC
;; resetting it, not a drafter, and it is put back (Jake, 2026-10-16).
(setq *pf-xd-pos*    "POS")

;; A short fingerprint of everything a block was last built from, written
;; whenever the tool writes the block.  PFREFRESH recomputes it: the same
;; answer means nothing changed and the block is left completely alone.
(setq *pf-xd-seen*   "SEEN")

;; On a pipe label's leader: the handle of the pipe it belongs to.
(setq *pf-xd-pipe*   "PIPE")

;; Crossings (PFXLABEL, 2026-11-20).  On a PFSUITE_XING block: what it marks,
;; (target-line target-station source-line source-station).  On everything
;; the tool draws for it (dimension, wall ticks and note, leader): the
;; crossing block's handle, so PFREFRESH redraws it with its block and erases
;; it when the block is gone.
(setq *pf-xd-xing*   "XING")

;; ON A GRID ANCHOR (Jake, 2026-10-30: V6's own records, not V5's ledger).
;; Written by PFSETUP (pf-grid); read by pfg:grid before V5's ledger.  The .cl
;; is ALSO the CL attribute, so it shows in Properties -- the two must agree.
(setq *pf-xd-cl*      "CL")          ; the .cl path
(setq *pf-xd-pro-inv* "PRO-INV")     ; _INV .pro path
(setq *pf-xd-pro-top* "PRO-TOP")     ; _TOP .pro path
(setq *pf-xd-tin-ex*  "TIN-EXIST")   ; existing-ground .tin
(setq *pf-xd-tin-des* "TIN-DESIGN")  ; DESIGN_* .tin
(setq *pf-xd-mat*     "MATERIAL")    ; the line's pipe material
(setq *pf-xd-sums*    "SUMS")        ; ((role . checksum) ...) of the .cl and .pros
(setq *pf-xd-stamp*   "STAMP")       ; the anchor's OWN handle when made -- a copy
                                     ; carries the original's, which is how it is caught

;; RELEASED: on a profile copy, pipe or leader left behind when PFREMOVE took
;; its grid's anchor away (Jake, 2026-10-30).  Every suite search skips it --
;; it is a plain drawing object from then on.  Value: the removed grid's title.
(setq *pf-xd-released* "RELEASED")

;; Part of every profile-copy and pipe fingerprint.  BUMP IT when a fix
;; changes how labels are built or placed: every copy and pipe then reads as
;; changed, and the next PFREFRESH redoes each one once.
;;   2 -- 2026-10-16: PFLABEL was wrongly read as moved by hand after the
;;        pipe was stretched (it rides PFRUN), and left at its old angle.
;;   3 -- 2026-10-22: the pipe label's leader (PFLEAD and friends).
;;   4 -- 2026-10-22: the leader is drawn by the tool, not held in the block.
;;   5 -- 2026-10-27: CBI rows built from the attributes only (no type
;;        wording); a label dragged inside the pipe goes back to the centre.
;;   6 -- 2026-11-20: a face per line, invert rows, pipe sizes from the
;;        table (PFID / PFOD).
(setq *pf-fp-ver*    6)

;; Provenance is an ALIST keyed by tag, not a scalar.  PFRIM was the first
;; derived attribute and PFFACE is the second; a key per attribute does not
;; scale and cannot be added after SCHEMA has shipped.
;;   (("PFRIM" . "CL") ("PFFACE" . "RULE"))
(setq *pf-src-cl*       "CL")         ; road centerline profile
(setq *pf-src-tin*      "TIN")        ; surface TIN
(setq *pf-src-rule*     "RULE")       ; computed from a rule table
(setq *pf-src-asserted* "ASSERTED")   ; a human said so.  NEVER overwritten.
(setq *pf-src-none*     "NONE")       ; not on record.  Not zero, not a pass.

(setq *pf-sources*
  (list *pf-src-cl* *pf-src-tin* *pf-src-rule*
        *pf-src-asserted* *pf-src-none*))


;;; ==========================================================================
;;; SECTION 4  --  Elevation derivation
;;; ==========================================================================
;;; Keyed by an EXPLICIT tag.  Not by substring-matching a block name, which
;;; is what gave V5's *pf-rule-table* its load-bearing ordering hazard
;;; ("compounds before singles, SMH/DMH before MH").  Order is not significant
;;; in this table and must never become significant.
;;;
;;; PFPOS says WHERE THE STRUCTURE SITS.  Nothing else.  Three values.
;;;
;;; Four values came out of an earlier draft of this table, all for the same
;;; reason -- they were not positions:
;;;   CREST  -- inlets do not go on crests, they catch nothing there.  A
;;;             manhole that happens to sit on one reads fine as ONGRADE.
;;;   GRATE  -- being a grate is not a place.  A grate inlet still sits either
;;;             in the road or out of it; the depression comes off PFTYPE.
;;;   HDWL   -- headwall is a type, and it sits out of the road, so its
;;;             position is SURFACE.  Its PFRIM is the FLOWLINE at the block
;;;             basepoint, entered by the drafter; it is not a TIN surface
;;;             elevation and is not drawn as an elevation row.
;;;   FIELD  -- a hand-typed rim is already ASSERTED in the provenance, which
;;;             skips the rule.  Storing it here too is how two records drift.
;;;
;;; Row: (PFPOS-value source note)

(setq *pf-pos-rules*
  (list
    (list "ONGRADE" *pf-src-cl*
          "road profile_z at station, less cross-slope x distance out")
    (list "SAG"     *pf-src-cl*
          "as ONGRADE, snapped to the vertical low point; WARNS if the structure is not at one")
    (list "SURFACE" *pf-src-tin*
          "tin_z at the structure's plan point -- not in the road")))

;; ONGRADE / SAG is not only a rim rule.  It is a hydraulic distinction, and
;; Carlson's own inlet library is split on it -- Combo-Grade / Combo-Sag,
;; Curb-Grade / Curb-Sag, Grate-Grade / Grate-Sag (inlet.dta, read 2026-09-03).
;; So PFPOS names half of the PFINLET entry and the inlet family names the
;; other half: PFINLET is DERIVED, not picked off a list.
;; HOLE: what decides the family -- PFTYPE alone, or something else?

;; Offset sign, confirmed in CAD 2026-09-03 (PF6PROBE section F):
;; cl_location_at_pt returns a SIGNED offset -- negative LEFT of
;; station-increasing, positive RIGHT.  V5 threw this away with
;; (abs (cadr res)); the ONGRADE rule needs it.
(setq *pf-offset-signed* T)

;;; ---- Facts that hang off PFTYPE, not off PFPOS ---------------------------
;;; These used to be PFPOS values.  They are properties of WHAT a structure is,
;;; so they are keyed by type and the position rule stays clean.

;; Types whose PFRIM is stored but NOT drawn as an elevation row by default.
;; For HDWL it is the flowline at the block basepoint, entered by the drafter.
(setq *pf-types-nolabel* '("HDWL"))

;; Types whose rim is the position rule's answer LESS a grate depression.
(setq *pf-types-grate* '())        ; HOLE: which types? CBI? DBI?

(setq *pf-grate-drop* 0.0)         ; HOLE: the depression, in feet.
                                   ; HOLE: one number, or per type?

;;; ---- Cross-slope ---------------------------------------------------------
;;; The fall from the road crown out to the gutter line.  ONGRADE and SAG both
;;; need it, and both need a ROAD centerline to measure the distance out --
;;; the offset stored in MEMB is from the STORM line, which is ~0 for a
;;; structure sitting on it.
;;;
;;; Default: the NEAREST road centerline, resolved once at assign time and
;;; stored, drafter can override.  Same derived-with-provenance shape as
;;; everything else.
;;;
;;; HOLE: how is a ROAD .cl told apart from a utility one?  This one matters.
;;; The project Alignments folder holds Storm_*, Sanitary_* and Water_* too,
;;; and a curb inlet sits ON its own storm line -- so plain "nearest" finds
;;; the pipe alignment first and reads a road elevation off it, silently.
;;;
;;; HOLE: superelevated curves.  On one, cross-slope is not a constant and a
;;; single number here is wrong.  Are these crowned straight sections?
(setq *pf-cross-slope* 0.02)


;;; ==========================================================================
;;; SECTION 5  --  Units
;;; ==========================================================================
;;; V5 shipped english-only and silently wrong on a metric drawing, blocked
;;; for its whole life on the flag's real name.  Confirmed in CAD 2026-09-03:
;;; it is IS_METRIC.  ACMETRIC / ACENGLISH nearby are ActiveX enum constants,
;;; NOT state -- wiring to those reads metric as permanently true.

(setq *pf-metric-sym* 'IS_METRIC)
(setq *pf-metric-refuse* T)        ; refuse, do not attempt, on a metric drawing


;;; ==========================================================================
;;; SECTION 6  --  Carlson library files
;;; ==========================================================================
;;; Plain comma-delimited text under usrdir$.  Confirmed 2026-09-03: every one
;;; of the four names V5 hardcodes in *pfsew-type-map* is literally a row in
;;; these.  No API call is needed to enumerate them.

(setq *pf-lib-struct*   "swrStruct.dta")     ; PFSTRUCT candidates
(setq *pf-lib-struct-m* "mswrStruct.dta")    ; the metric twin
(setq *pf-lib-inlet*    "inlet.dta")         ; PFINLET candidates

;; psname is per-user AppData, NOT a shared path -- a block put there resolves
;; for one user on one machine.  The firm standards path (setdir$) is the
;; shared one, and is where PFSUITE_* definitions belong.
(setq *pf-blocks-home-sym* 'setdir$)


;;; ==========================================================================
;;; SECTION 7  --  Grid anchors
;;; ==========================================================================
;;; Every profile grid has an anchor block at its lower-left corner.  V5's
;;; PFSETUP made PF-ANCHORs; V6's PFSETUP (pf-grid, 2026-10-30) makes
;;; PFSUITE_ANCHORs and keeps their records as pf-record XDATA (SECTION 3).
;;; Both kinds are read.  The attribute names are V5's (pftools-cfg.lsp),
;;; copied exactly -- do not "tidy" them.

;; Block names an anchor may be inserted as.  PFSUITE_ANCHOR is the suite's
;; own name (Jake, 2026-10-15) -- same attributes and records, renamed.
;; PF-ANCHOR / PF-GRIDANCHOR are V5's, kept so drawings V5 set up still read.
(setq *pf-anchor-blocks* "PFSUITE_ANCHOR,PF-ANCHOR,PF-GRIDANCHOR")

;; Attributes on the anchor.  WIDTH / HEIGHT are the grid size measured from
;; the anchor; an anchor with no HEIGHT is the old kind, sized by its scales.
(setq *pf-anc-line*   "LINE")      ; "CA"
(setq *pf-anc-util*   "UTIL")      ; "STORM"
(setq *pf-anc-sta0*   "STA0")      ; station at the grid's left edge
(setq *pf-anc-datum*  "DATUM")     ; elevation at the grid's bottom edge
(setq *pf-anc-hplot*  "HPLOT")     ; horizontal plot scale, 1" = 20'
(setq *pf-anc-vplot*  "VPLOT")     ; vertical plot scale,   1" = 2'
(setq *pf-anc-width*  "WIDTH")
(setq *pf-anc-height* "HEIGHT")

;; PFSUITE_ANCHOR only (Jake, 2026-10-15): the profile's .cl, WRITTEN BY THE
;; TOOL when it creates the anchor -- never typed.  An attribute so it can be
;; seen in Properties and travels with the block.  If the stored path is gone
;; (project moved), the project's Alignments folder is searched for the same
;; name.  Read FIRST; V5's anchors have no such tag and fall back to their
;; ledger's META record.
(setq *pf-anc-cl*     "CL")

;; Every tag a NEW anchor carries: all of V5's plus CL (Jake, 2026-10-30).
;; PFSETUP checks the block definition has them before writing one.
(setq *pf-anc-tags*
  (list *pf-anc-line* *pf-anc-util* *pf-anc-sta0* *pf-anc-datum* *pf-anc-hplot*
        *pf-anc-vplot* *pf-anc-width* *pf-anc-height* *pf-anc-cl*))

;; New anchors: the block inserted, its layer (created no-plot, V5's colour,
;; only if missing -- an existing layer is never repainted), and the icon's
;; size.  The icon reads right at 1"=50', so the insert is scaled by
;; HPLOT / *pf-anc-icon-hplot*, the same in X, Y and Z.  V5's rule.
(setq *pf-anc-block*       "PFSUITE_ANCHOR")
(setq *pf-anc-layer*       "PF-ANCHOR")
(setq *pf-anc-layer-color* 152)
(setq *pf-anc-icon-hplot*  50.0)

;; The anchor check (V5's corner check): a grid LINE must pass within
;; *pf-anc-probe-tol* of the anchor's corner (else the grid moved without it),
;; and the grid top at the right edge must sit within *pf-anc-top-tol* of the
;; recorded top (else the grid was stretched or redrawn).  Carlson's layers.
(setq *pf-anc-grid-layers* "PF-GRID-MJR,PF-GRID-MNR,PF-HBOX")
(setq *pf-anc-probe-tol*   0.05)
(setq *pf-anc-top-tol*     0.5)

;; PFSETUP's scan: grid names are text on this layer, "STORM LINE 'DA'"
;; (V5's AUTO).  The utility is found by its KEYWORD in that text -- a
;; FORCEMAIN line reads "FORCE MAIN".
(setq *pf-name-layer* "PF-NAME")
(setq *pf-types*      '("STORM" "SANITARY" "WATER" "FORCEMAIN" "GAS" "ELECTRIC"))
(setq *pf-type-keywords* '(("FORCEMAIN" . "FORCE MAIN")))

;; File-name conventions (V5's): Storm_CA.cl, Storm_CA_INV.pro / _TOP.pro,
;; DESIGN_*.tin is the proposed surface, anything else the existing one.
(setq *pf-pro-roles*         '("INV" "TOP"))
(setq *pf-tin-design-prefix* "DESIGN_")

;; V5's anchors keep their records in a dictionary on the insert (READ ONLY --
;; the fallback when an anchor has no V6 records).
;; PFXLEDGER is the older name, read when PFLEDGER is not there.
(setq *pf-anc-dict*        "PFLEDGER")
(setq *pf-anc-dict-legacy* "PFXLEDGER")

;; META: (1 . the line's .cl path) (302 . the anchor's own handle when made)
;; A copied anchor carries the ORIGINAL's handle in 302, so a mismatch means
;; "this is a copy" and it is never used.
(setq *pf-anc-meta*  "META")
;; FILES: (1 . INV .pro) (2 . TOP .pro) (3 . existing TIN) (4 . design TIN)
;;        (5 . pipe material)
(setq *pf-anc-files* "FILES")

;; Text height on a profile = *pf-text-base* x (HPLOT / *pf-ref-hplot*).
;; 1.60 at 1"=20', 4.00 at 1"=50'.  Same as V5.
(setq *pf-text-base* 1.60)
(setq *pf-ref-hplot* 20.0)


;;; ==========================================================================
;;; SECTION 8  --  Project folders
;;; ==========================================================================
;;; Where the file dialogs open.  Ported from V5's pfsettings.
;;; The project root is Carlson's tmpdir$ -- the active project's data folder --
;;; read live, never stored in the drawing.  Each file type has the firm's
;;; standard subfolder, looked for at the root and up to *pf-dir-search-up*
;;; parent folders above it, because tmpdir$ is not always the project's top.

(setq *pf-dir-std*
  '(("cl"  . "02_ProjectData\\Alignments")
    ("pro" . "05_Drawings\\DrawingData\\CivilSurvey")
    ("tin" . "02_ProjectData\\Surfaces")))

(setq *pf-dir-search-up* 3)

;; Which wins when both exist: the folder last browsed to this session (T),
;; or the firm's standard folder (nil, what V5 meant to do).  Either way the
;; other is the fallback, then the project root.
(setq *pf-dir-last-first* nil)


;;; ==========================================================================
;;; SECTION 9  --  First version: CBI + PIPE  (2026-10-13)
;;; ==========================================================================

;; Membership, V5's rule: a plan structure is on a line when it is within
;; this many feet of the .cl and inside its station range.  Tight on purpose.
(setq *pf-memb-tol* 0.15)

;;; ---- The line tree (V5's, ported 2026-10-22) -------------------------------
;; V5 keeps its grid-less lines ("stubs", STUB_<TYPE>_<NAME>) in the drawing's
;; own dictionary under this name.  Read only until PFSETUP comes over.
(setq *pf-nod-name*    "PFTOOLS")
(setq *pf-stub-prefix* "STUB_")

;; A structure further than *pf-memb-tol* from a line but within this many
;; feet of it is NAMED in the run as "near, not on it" -- nothing is dropped
;; without a printed reason (V5's planned fix for its dropped structures).
(setq *pf-near-tol* 1.0)

;; Two plan structures closer than this are one drawn on top of another.
;; They would get the same number, so the run names them.
(setq *pf-stack-tol* 0.5)

;; Blocks that are NOT ours but still take a number on a line (Jake,
;; 2026-10-27: headwalls count; V5 numbers them).  The tree counts them and
;; never names, places, refreshes or erases them.  A name matches as the root
;; alone or root + "_" + anything starting with a digit (HDWL_24, HDWL_24x36).
;; Keep legacy HDWL_* count-only until those inserts are replaced in drawings.
(setq *pf-count-only* '("HDWL"))

;; Station slack at a line's ends, and between two structures when numbering.
(setq *pf-range-eps* 0.01)

;; A .cl's arcs are filled in with a point every this many feet.  A .cl the
;; reader refuses is walked through Carlson at the same step instead.
(setq *pf-cl-step* 2.0)

;; The reading is checked against Carlson: its first point must land within
;; this many feet of where Carlson puts that station.
(setq *pf-cl-check-tol* 0.2)

;; A WALKED line cuts its corners by up to half a step, so a structure this
;; close to one is asked about through Carlson instead of trusted to the walk.
(setq *pf-corridor-walk* (+ *pf-cl-check-tol* (/ *pf-cl-step* 2.0)))

;;; ---- Label wording --------------------------------------------------------
;;; DEFAULTS ONLY, per block type (Jake, 2026-10-27).  The labels are built
;;; from the attributes alone; these are what a type's PFCONPRE / PFELEVPRE
;;; hold before anyone types one.  Keyed by the *pf-blocks* key.  Wording from
;;; V5's *pf-rule-table*, single-type rows.  For a headwall PFELEVPRE is the
;;; invert prefix on PFINV1; its flowline does not get a top label row.
(setq *pf-type-fmt*
  '(("CBI"     ("PFCONPRE" . "CONST. CURB BOX INLET") ("PFELEVPRE" . "G.L."))
    ("CBI-BOX" ("PFCONPRE" . "CONST. CURB BOX INLET") ("PFELEVPRE" . "G.L."))
    ("DBI"     ("PFCONPRE" . "CONST. DROP BOX INLET") ("PFELEVPRE" . "T.G."))
    ("SMH"     ("PFCONPRE" . "CONST. SANITARY MH")    ("PFELEVPRE" . "T.R."))
    ("DMH"     ("PFCONPRE" . "CONST. DRAINAGE MH")    ("PFELEVPRE" . "T.R."))
    ("MH"      ("PFCONPRE" . "CONST. MANHOLE")        ("PFELEVPRE" . "T.R."))
    ("HDWL"    ("PFCONPRE" . "CONST. HDWL")           ("PFELEVPRE" . "INV."))))

;; What the drafter inputs hold before anyone has typed one -- every type;
;; *pf-type-fmt* overrides per type.
;; In the station suffix, from the .cl file's name (Storm_AA.cl):
;;   [util] -> the part before the FIRST underscore, STORM  (V5's pf:type-of)
;;   [line] -> everything after it, AA                     (V5's pf:name-of)
;; giving "STA. 2+02.08 STORM LINE 'AA'" (Jake, 2026-10-15: no brackets;
;; "STA." with the stop, per his label standard sheet 2026-10-16).
;; The construction row is PFCONPRE + PFNAME + PFCONSUF -- "CONST. CURB BOX
;; INLET AA-1", no size (Jake, 2026-10-15); PFCONSUF is blank by default.
;;
;; A SHARED structure gets one station row per line: the grid's OWN line
;; first, then the others A-Z, " =" on every row but the last --
;;     STA. 4+09.69 STORM LINE 'BA' =
;;     STA. 3+00.00 STORM LINE 'BC'
;;     CONST. CURB BOX INLET BA-5/BC-1
(setq *pf-fmt-defaults*
  (list (cons *pf-tag-sta-pre*  "STA.")
        (cons *pf-tag-sta-suf*  "[util] LINE '[line]'")
        (cons *pf-tag-con-pre*  "CONST.")
        (cons *pf-tag-con-suf*  "")
        (cons *pf-tag-elev-pre* "")
        (cons *pf-tag-elev-suf* "")))

;; Old defaults the tool wrote before a default changed.  A structure still
;; holding one of these, never retyped by hand, gets today's default on the
;; next run.  A value someone TYPED is never replaced.  "CONST." was every
;; type's PFCONPRE before the wording moved into it (2026-10-27).
(setq *pf-fmt-retired*
  (list (cons *pf-tag-sta-suf* "([line])")
        (cons *pf-tag-sta-pre* "STA")
        (cons *pf-tag-con-pre* "CONST.")))

(setq *pf-elev-placeholder* "XXX.XX")   ; rim not filled in yet

;; Invert rows: I.O. 765.43 (15")   -- V5's wording.
(setq *pf-inv-out* "I.O.")              ; pipe LEAVES the structure
(setq *pf-inv-in*  "I.I.")              ; pipe ARRIVES

;;; ---- Invert rows (port step 4, Jake 2026-11-20) ---------------------------
;;; Written by PFREFRESH on each profile copy, in PFINV1..5:
;;;   a pipe attached     its own end's elevation, "I.O. 745.10 (15")"
;;;   no pipe on a side   the structure's BOTTOM on that side (the PFDEPTH
;;;                       grip; on the sanitary MH the left side is the
;;;                       PFFLOORDWN corner), no size -- only where the line
;;;                       carries on past the structure that way
;;; A pipe belongs to the structure when its end sits at the structure's
;;; wall -- within *pf-inv-wall-tol* of it sideways -- anywhere from the
;;; bottom up to the rim.  Downstream is LEFT: an end on the left wall is the
;;; outlet (I.O.), on the right wall the inlet (I.I.).  A pipe end BELOW the
;;; bottom is reported; above it is a drop and is fine.
;;; At a junction, another line's pipes (read on that line's own grid) go in
;;; the middle columns; its outlet takes the I.O. column if this line has
;;; none (V5's pfinvert).
(setq *pf-smh-barrel-r*  2.0)           ; ft -- the sanitary MH's fixed 48" barrel, half
(setq *pf-inv-wall-tol*  1.0)           ; ft sideways past the wall
(setq *pf-inv-rim-tol*   0.5)           ; ft above the rim, still attached
(setq *pf-inv-below-tol* 0.005)         ; ft below the bottom before it is reported
;; The most downstream structure's invert column is pushed right, measured
;; flat on the sheet (no scale): STORM from its downstream invert end,
;; SANITARY from the grid's left edge.  V5's *pfi-first-shift*.
(setq *pf-inv-first-shift* '(("SANITARY" GRID 2.0) ("STORM" INVERT 2.5)))
(setq *pf-inv-first-shift-default* '(GRID 2.0))

;;; ---- Plan label (Jake 2026-11-20) -----------------------------------------
;;; The structure's name on the PLAN block: a visible attribute (PFMKPLABEL
;;; adds it, once per block definition).  Only the plan block is filled in --
;;; on a profile copy it stays blank and draws nothing, so no visibility
;;; state is needed.  PFASSIGN writes it (a name typed over it is kept), sets its
;;; height from the PFPLANHT setting, and puts a dragged label back where it
;;; was dragged after an ATTSYNC.  Not in *pf-tags*: a block without it yet
;;; is still assigned, and named in the run.
(setq *pf-tag-plan-label* "PFPLABEL")
;; Its grip to swing it around the structure (Jake, 2026-11-20): a Rotation
;; parameter based on the block's insertion point, with a Rotate action on
;; PFPLABEL.  The drafter's -- the tool never sets it.  PFMKPLABEL adds both.
(setq *pf-param-plan-rot* "PFPLROT")

;;; ---- Settings (Jake 2026-11-20) --------------------------------------------
;;; Saved like the label defaults (pf-defaults: line, utility, drawing, then
;;; these built-ins), kind "SETTING".  Numbers kept as text.
(setq *pf-setting-kind* "SETTING")
(setq *pf-settings*
  '(("PFPLANHT"  . "2.4")    ; plan label text height
    ("PFCLRMIN"  . "18")     ; minimum crossing clearance, inches
    ("PFCLRWARN" . "6")))    ; dimension drawn when within this many inches of it

;;; ---- Top of grid ----------------------------------------------------------
;;; V5's probe: the highest line on this layer straight above the structure.
;;; Grids have stepped tops, so it is read per station.  The search stops this
;;; far (x plot scale / 20) above the anchor's top so it never reads the next
;;; grid up the sheet.
(setq *pf-top-layer*  "PF-GRID-MJR")
(setq *pf-top-margin* 25.0)

;; No grid top found at a station (Jake, 2026-10-16): say so, but still place
;; the labels this many TEXT HEIGHTS above the structure (16' at 1"=20',
;; 40' at 1"=50').  V5 skipped the structure instead.  Tune here.  A grid
;; drawn by pf-grid later will give a better way to find the top.
(setq *pf-top-default* 10.0)

;;; ---- The pipe block -------------------------------------------------------
;;; Built 2026-10-02 (memory: pfpipe-design).  Base point = UPSTREAM invert.
(setq *pf-pipe-block* "PFSUITE_PIPE")    ; was PFPIPE until 2026-10-15
(setq *pf-pipe-label* "PFLABEL")       ; the label the tool writes
(setq *pf-pipe-size*  "PFSIZE")        ; 15"     -- drafter may edit
(setq *pf-pipe-mat*   "PFMAT")         ; RCP III -- drafter may edit
(setq *pf-pipe-label2* "PFLABEL2")     ; the label's second row (2026-10-16)

;; The pipe label, TWO rows (Jake's sample, 2026-10-16) -- two rows because
;; they may need moving or stacking on a short pipe:
;;   row 1  PFLENPRE length PFLENSUF size          CONST. 45 L.F. ~ 15"
;;   row 2  material PFSLOPEPRE slope PFSLOPESUF   ADS N-12 HDPE @ 5.5%
;; The four inputs are hidden + preset, filled from the saved defaults like
;; the structure's PFSTAPRE etc.; a value typed on one pipe stays on it.
(setq *pf-pipe-len-pre*   "PFLENPRE")
(setq *pf-pipe-len-suf*   "PFLENSUF")
(setq *pf-pipe-slope-pre* "PFSLOPEPRE")
(setq *pf-pipe-slope-suf* "PFSLOPESUF")
(setq *pf-pipe-fmt-defaults*
  (list (cons *pf-pipe-len-pre*   "CONST.")
        (cons *pf-pipe-len-suf*   "L.F. ~")
        (cons *pf-pipe-slope-pre* "@")
        (cons *pf-pipe-slope-suf* "%")))
(setq *pf-pipe-tags-fmt* (mapcar 'car *pf-pipe-fmt-defaults*))

;; Rounding, per the sample: length in whole feet, slope to 0.1%.
(setq *pf-pipe-len-dec*   0)
(setq *pf-pipe-slope-dec* 1)

;; The two rows straddle the pipe centre, this many TEXT HEIGHTS apart centre
;; to centre -- V5's pipe label (3.20 x sf over 1.60 x sf text = 2.0).
(setq *pf-pipe-row-gap* 2.0)

;; Inside and outside diameter, inches, HIDDEN (Jake, 2026-11-20).  Filled
;; from the pipe table (SECTION 10) when the pipe is placed and whenever its
;; size or material changes; a value typed over is kept.  What crossings and
;; inverts read -- the block is the source of truth.  Blank OD = wall unknown.
(setq *pf-pipe-id*    "PFID")
(setq *pf-pipe-od*    "PFOD")

;; Every tag the pipe block carries -- what PFGATE checks it against.
(setq *pf-pipe-tags*
  (append (list *pf-pipe-label* *pf-pipe-label2* *pf-pipe-size* *pf-pipe-mat*
                *pf-pipe-id* *pf-pipe-od*)
          *pf-pipe-tags-fmt*))
(setq *pf-pipe-dia*   "PFDIA")         ; inside diameter, drawn (exaggerated)
(setq *pf-pipe-wt*    "PFWT")          ; wall, top
(setq *pf-pipe-wb*    "PFWB")          ; wall, bottom
(setq *pf-pipe-run-x* "PFRUN X")       ; downstream end, from the base point
(setq *pf-pipe-run-y* "PFRUN Y")
(setq *pf-pipe-vis*   "PFVIS")
(setq *pf-pipe-state-plain* "WALL OFF")   ; as named in the block (2026-10-15)
(setq *pf-pipe-state-walls* "WALL ON")

;; The label's grip (point parameter, in the block).  It carries both rows.
(setq *pf-pipe-lead*  "PFLEAD")

;; The label's leader is DRAWN BY THE TOOL, not held in the block (Jake,
;; 2026-10-22, after the in-block leader fought its own actions).
;;   Label inside the pipe  -> rotated to the pipe, no leader.
;;   Label dragged outside  -> level, on a leader: arrow on the pipe's top
;;   (label above) or bottom (label below) at its midpoint, a sloped leg to
;;   a bend, then a level landing that stops short of the top row.
;; One polyline per pipe; its first segment tapers from nothing to the
;; arrow's width, which IS the arrowhead.  It carries the pipe's handle
;; (XDATA PIPE), so PFREFRESH redraws it with its pipe and erases it when the
;; pipe is gone.  It goes on the pipe's layer.
;; Sizes in drawing units AT 1"=20', scaled by HPLOT/20 like the text.
(setq *pf-pipe-land-gap*  1.0)   ; landing end to the top row's insertion point
(setq *pf-pipe-land-len*  1.0)   ; the landing, bend to landing end (proposed,
                                 ; no standard given -- change it here)
(setq *pf-pipe-arrow-len* 2.5)   ; 1/8" plotted -- DIST on a company leader
(setq *pf-pipe-arrow-wid* (/ 2.5 3.0))   ; AutoCAD's closed-filled shape:
                                         ; a third as wide as it is long

;; A pipe end belongs to the structure whose profile copy is within this many
;; feet (horizontally) of it.  Pipes end at the wall, not the centre, so this
;; has to be wider than half the biggest structure.
(setq *pf-pipe-snap* 8.0)



;;; ==========================================================================
;;; SECTION 10  --  The pipe table (Jake, 2026-11-20)
;;; ==========================================================================
;;; ONE table of materials and sizes, kept WITH THE LISP so every drafter
;;; reads the same one: pf-cfg\pf-pipes.csv.  Edit it in Excel or Notepad.
;;; One row per material and size:
;;;   Material   exactly what prints on the pipe label's row 2 (PFMAT)
;;;   Utilities  which line types PFPIPE offers it for, ";" between them
;;;              (STORM;SANITARY).  Blank = every type
;;;   Default    Y = PFPIPE's first choice for those utilities.  One per utility
;;;   n          Manning's n (exports later).  May be blank
;;;   Nominal    the size picked and printed, inches (15)
;;;   ID / OD    inside / outside diameter, inches.  Blank ID = the nominal.
;;;              Blank OD = wall unknown: a crossing on it is UNKNOWN, never a pass
;;; A material's Utilities, Default and n are read from its first row.
;;; Lines starting with # are notes.  Read by pf-mats.
(setq *pf-pipe-table* "pf-pipes.csv")
(setq *pf-pipe-table-cols* '("MATERIAL" "UTILITIES" "DEFAULT" "N" "NOMINAL" "ID" "OD"))


;;; ==========================================================================
;;; SECTION 11  --  Crossings: PFXLABEL (Jake, 2026-11-20)
;;; ==========================================================================
;;; On the line picked in the palette (drawing-wide may come later): every
;;; place another line's .cl crosses it.  The crossing pipe comes from that
;;; line's own PFSUITE_PIPE blocks -- no pipe block there, nothing is drawn.
;;; One PFSUITE_XING block per crossing, inserted at the crossing pipe's
;;; INVERT:
;;;   ellipse       the INSIDE of the pipe, drawn 1 ft wide x 10 tall; PFDIA
;;;                 (linear) scales it from the insertion point
;;;   two ticks     short level lines at the OUTSIDE diameter, moved by
;;;                 PFODTOP / PFODBOT (linear, straight up / down from the
;;;                 insertion point)
;;;   station line  stretched by PFTOP (to the grid top) and PFBOT (below the
;;;                 grid); PFSTA1 rides PFBOT -- V5's vertical station text
;;;   label         PFLABEL / PFLABEL2 on PFLEAD (point); left of the ellipse
;;;                 by default, PFFLIP (flip) puts it right; dragged away, it
;;;                 goes on a leader the tool draws
;;; Everything in the block on layer 0, colour ByBlock: the tool turns the
;;; insert RED when the clearance is short (or unknown).
;;; Clearance is outside to outside.  Within PFCLRWARN of PFCLRMIN (or under
;;; it) the tool also draws a dimension from the outside of THIS line's pipe
;;; wall, PFCLRMIN long, toward the crossing pipe, reading `18" MIN.`, and a
;;; tick + note at that wall: `2.5" WT. (18" RCP)`.
(setq *pf-xing-block* "PFSUITE_XING")
(setq *pf-xing-dia*   "PFDIA")
(setq *pf-xing-odtop* "PFODTOP")
(setq *pf-xing-odbot* "PFODBOT")
(setq *pf-xing-top*   "PFTOP")
(setq *pf-xing-bot*   "PFBOT")
(setq *pf-xing-lead*  "PFLEAD")
(setq *pf-xing-flip*  "PFFLIP")
;; attributes
(setq *pf-xing-label*  "PFLABEL")     ; PROP. WATER MAIN 'A'
(setq *pf-xing-label2* "PFLABEL2")    ; 16" C900 DR 14 PVC
(setq *pf-xing-sta*    "PFSTA1")      ; 4+10.00 PROP. WATER CROSSING (vertical)
(setq *pf-xing-type*   "PFTYPE")      ; XING
(setq *pf-xing-size*   "PFSIZE")      ; the crossing pipe's, 16"
(setq *pf-xing-mat*    "PFMAT")
(setq *pf-xing-inv*    "PFINV")       ; its invert at this station
(setq *pf-xing-clr*    "PFCLR")       ; the clearance measured, inches | UNKNOWN
(setq *pf-xing-tags*
  (list *pf-xing-label* *pf-xing-label2* *pf-xing-sta* *pf-xing-type*
        *pf-xing-size* *pf-xing-mat* *pf-xing-inv* *pf-xing-clr*))
(setq *pf-xing-typename* "XING")
;; Short utility names, for lists -- the palette's crossing rows read
;; "Crossing SAN. A  STA 1+00.00" (Jake, 2026-11-20).  A type with no row
;; shows in full.
(setq *pf-util-abbrev*
  '(("SANITARY" . "SAN.") ("STORM" . "STM.") ("WATER" . "WTR.")
    ("FORCEMAIN" . "F.M.") ("GAS" . "GAS") ("ELECTRIC" . "ELEC.")))
;; V5's wording (pftools-cfg *pfx-label-templates* / *pfx-cross-templates*),
;; by the CROSSING line's utility.  [name] = its line letters.  A type with no
;; row: "PROP. <TYPE> LINE '[name]'" / "PROP. <TYPE> CROSSING".
(setq *pf-xing-line-words*
  '(("WATER"     . "PROP. WATER MAIN '[name]'")
    ("SANITARY"  . "PROP. SANITARY LINE '[name]'")
    ("STORM"     . "PROP. STORM LINE '[name]'")
    ("FORCEMAIN" . "PROP. FORCE MAIN '[name]'")
    ("GAS"       . "PROP. GAS LINE '[name]'")
    ("ELECTRIC"  . "PROP. ELECTRIC LINE '[name]'")))
(setq *pf-xing-sta-words*
  '(("WATER"     . "PROP. WATER CROSSING")
    ("SANITARY"  . "PROP. SANITARY CROSSING")
    ("STORM"     . "PROP. STORM CROSSING")
    ("FORCEMAIN" . "PROP. FORCE MAIN CROSSING")
    ("GAS"       . "PROP. GAS CROSSING")
    ("ELECTRIC"  . "PROP. ELECTRIC CROSSING")))
;; Sizes in drawing units AT 1"=20', scaled with the text (HPLOT / 20).
(setq *pf-xing-line-ext*  30.0)   ; station line below the grid's bottom (V5)
(setq *pf-xing-label-dx*  3.2)    ; label from the station line (V5's *pfx-text-dx*)
(setq *pf-xing-arrow-off* 1.0)    ; leader tip this far off the ellipse (Jake)
(setq *pf-xing-tick-len*  2.0)    ; the wall ticks the tool draws
;; Finding them: a crossing within this many feet of either line's end is a
;; tie-in, not a crossing; one within *pf-xing-struct-tol* of a plan
;; structure is a junction (V5's *pfx-terminus-tol* / *pfx-struct-tol*).
(setq *pf-xing-end-tol*    2.0)
(setq *pf-xing-struct-tol* 5.0)
;; An existing crossing block is the same crossing when its source line
;; matches and its target station is within this many feet.
(setq *pf-xing-match-tol*  5.0)


(princ "\npf-cfg loaded.")
(princ)
