;;; pfdbi.lsp -- standalone, separate from the PFSUITE work.
;;;
;;; PFDBI   pick the centerline, pick the TIN, give the profile grid,
;;;         then click the block(s) in plan.  Each one is copied into the
;;;         profile at its station, with its base point on the TIN elevation.
;;;         Enter ends the clicking.
;;;
;;; Asks for the grid every run: lower-left corner of the profile, and the
;;; station and elevation at that corner.  Horizontal 1:1; vertical uses
;;; Carlson's exaggeration (sv:sm / sv:vs) or asks.
;;; Needs Carlson loaded (cf:road_api, cf:dtm_api).  Nothing else.

(vl-load-com)

(setq *pfdbi-cl*  (if (boundp '*pfdbi-cl*)  *pfdbi-cl*  ""))
(setq *pfdbi-tin* (if (boundp '*pfdbi-tin*) *pfdbi-tin* ""))

(defun pfdbi:say (s) (prompt (strcat "\n" s)) (princ))

(defun pfdbi:station (cl pt / r)
  (setq r (vl-catch-all-apply 'cf:road_api
            (list "cl_location_at_pt" cl (list (car pt) (cadr pt)))))
  (if (and (not (vl-catch-all-error-p r)) (listp r) (numberp (car r))) (car r)))

(defun pfdbi:tin-z (pt / r)
  (setq r (vl-catch-all-apply 'cf:dtm_api (list "tin_z" (list (car pt) (cadr pt)))))
  (if (and (numberp r) (> r -9999.0) (< r 99999.0)) r))

(defun pfdbi:sta (s) (atof (vl-string-subst "" "+" s)))

(defun pfdbi:fmt-sta (sta / n r s)
  (setq n (fix (/ (+ sta 0.005) 100.0))
        r (- sta (* n 100.0))
        s (rtos r 2 2))
  (if (< r 9.995) (setq s (strcat "0" s)))
  (strcat (itoa n) "+" s))

;; -> (x0 y0 sta0 elev0 ve) | nil
(defun pfdbi:ask-grid ( / c s e ve)
  (if (and (setq c (getpoint "\nProfile LOWER-LEFT corner: "))
           (setq s (getstring "\nStation at that corner (e.g. 1+00): "))
           (/= s "")
           (setq e (getreal "\nElevation at that corner: ")))
    (progn
      (setq ve (if (and (boundp 'sv:sm) (boundp 'sv:vs)
                        (numberp (eval 'sv:sm)) (numberp (eval 'sv:vs))
                        (> (eval 'sv:vs) 0.0))
                 (/ (float (eval 'sv:sm)) (eval 'sv:vs))
                 (getreal "\nVertical exaggeration <10>: ")))
      (list (car c) (cadr c) (pfdbi:sta s) e (or ve 10.0)))))

(defun c:PFDBI ( / cl tin g en pe ip sta z pt ms go n obj dir)
  ;; the two Carlson APIs, loaded the way the suite does
  (setq dir (if (and (boundp 'lspdir$) (= (type lspdir$) 'STR)) lspdir$ ""))
  (vl-catch-all-apply 'scload (list (strcat dir "tri4")))
  (vl-catch-all-apply 'scload (list (strcat dir "eworks")))
  (cond
    ((not (and (boundp 'cf:road_api) (boundp 'cf:dtm_api)))
     (pfdbi:say "PFDBI: Carlson isn't loaded."))
    ((null (setq cl (getfiled "Pick the centerline" *pfdbi-cl* "cl" 4)))
     (pfdbi:say "PFDBI: no centerline."))
    ((null (setq tin (getfiled "Pick the TIN" *pfdbi-tin* "tin" 4)))
     (pfdbi:say "PFDBI: no TIN."))
    ((null (setq g (pfdbi:ask-grid)))
     (pfdbi:say "PFDBI: no grid."))
    ((not (vl-catch-all-apply 'cf:dtm_api (list "load_tin" tin)))
     (pfdbi:say "PFDBI: Carlson wouldn't load that TIN."))
    (T
     (setq *pfdbi-cl* cl *pfdbi-tin* tin
           ms (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object)))
           go T n 0)
     (while go
       (setq pe (entsel "\nClick the block to place on the profile: "))
       (cond
         ((null pe) (setq go nil))
         ((/= "INSERT" (cdr (assoc 0 (entget (setq en (car pe))))))
          (pfdbi:say "That isn't a block."))
         (T
          (setq obj (vlax-ename->vla-object en)
                ip  (vlax-safearray->list (vlax-variant-value (vla-get-insertionpoint obj))))
          (cond
            ((null (setq sta (pfdbi:station cl ip)))
             (pfdbi:say "Carlson can't place that block on the centerline."))
            ((null (setq z (pfdbi:tin-z ip)))
             (pfdbi:say "No TIN elevation at that block."))
            (T
             (setq pt (list (+ (car g) (- sta (caddr g)))
                            (+ (cadr g) (* (- z (cadddr g)) (nth 4 g)))
                            0.0))
             (vla-insertblock ms (vlax-3d-point pt)
                              (vla-get-effectivename obj) 1.0 1.0 1.0 0.0)
             (setq n (1+ n))
             (pfdbi:say (strcat "Placed at STA " (pfdbi:fmt-sta sta)
                                "  elev " (rtos z 2 2))))))))
     (vl-catch-all-apply 'cf:dtm_api (list "unload_tin"))
     (pfdbi:say (strcat "PFDBI: " (itoa n) " placed."))))
  (princ))

(prompt "\npfdbi loaded.  Command: PFDBI")
(princ)
