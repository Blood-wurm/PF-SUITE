;;; ==========================================================================
;;; pf-carlson.lsp  --  every Carlson API call, wrapped.
;;; Load position 3: after pf-cfg, pf-lib.  Depends on pf-cfg only.
;;; Contract, API and rules: README.md beside this file.
;;;
;;; THE ONLY FILE THAT NAMES cf:road_api OR cf:dtm_api.  V5 scattered raw
;;; calls across two modules; one home means one place that knows the API's
;;; real shape, one place to guard, one place to stub for testing off CAD.
;;;
;;; Every wrapper returns plain data or nil.  Never an error object, never a
;;; Carlson console message.  A caller that gets nil decides what nil means.
;;;
;;; Shapes confirmed in CAD 2026-09-03 (PF6PROBE):
;;;   cl_location_at_pt  -> (station SIGNED-offset (x y))   neg LEFT, pos RIGHT
;;;   cl_sta_range       -> (start end)
;;;   load_tin / unload_tin -> 1,   tin_z -> elevation
;;; ==========================================================================

(vl-load-com)

;; (pfc:load) -> nil   The two ARXes.  Idempotent.
(defun pfc:load ( / dir)
  (setq dir (if (and (boundp 'lspdir$) (= (type lspdir$) 'STR)) lspdir$ ""))
  (vl-catch-all-apply 'scload (list (strcat dir "tri4")))
  (vl-catch-all-apply 'scload (list (strcat dir "eworks")))
  (princ))

(defun pfc:call (fn args / r)
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r) nil r))

;; (pfc:ready-p) -> T if both APIs answer at all
(defun pfc:ready-p ()
  (and (not (null (eval 'cf:road_api)))
       (not (null (eval 'cf:dtm_api)))))

;; (pfc:metric-p) -> T on a metric drawing.
;;   IS_METRIC, confirmed 2026-09-03.  NOT ACMETRIC -- that is an ActiveX enum
;;   constant that is always 1.
(defun pfc:metric-p ( / v)
  (and (boundp *pf-metric-sym*)
       (setq v (eval *pf-metric-sym*))
       (/= v 0)))


;;; ---- centerlines ---------------------------------------------------------

;; (pfc:cl-range cl) -> (start end) | nil
(defun pfc:cl-range (cl / r)
  (setq r (pfc:call 'cf:road_api (list "cl_sta_range" cl)))
  (if (and (listp r) (numberp (car r)) (numberp (cadr r))) (list (car r) (cadr r))))

;; (pfc:cl-locate cl pt) -> (station offset) | nil
;;   Offset is SIGNED.  No terminus fallback here: V5's fallback returned a
;;   plain distance, which throws the sign away.  A point the API cannot place
;;   is nil, and the caller reports it.
(defun pfc:cl-locate (cl pt / r)
  (setq r (pfc:call 'cf:road_api
                    (list "cl_location_at_pt" cl (list (car pt) (cadr pt)))))
  (if (and (listp r) (numberp (car r)) (numberp (cadr r)))
    (list (car r) (cadr r))))

;; (pfc:cl-point cl sta) -> (x y) | nil
(defun pfc:cl-point (cl sta / r)
  (setq r (pfc:call 'cf:road_api (list "cl_location_at_sta" cl sta)))
  (cond
    ((not (listp r)) nil)
    ((and (listp (car r)) (numberp (car (car r))))
     (list (car (car r)) (cadr (car r))))
    ((and (numberp (car r)) (numberp (cadr r)))
     (list (car r) (cadr r)))))


;;; ---- surface -------------------------------------------------------------

(defun pfc:tin-load (file)
  (not (null (pfc:call 'cf:dtm_api (list "load_tin" file)))))

(defun pfc:tin-unload ()
  (pfc:call 'cf:dtm_api (list "unload_tin"))
  (princ))

;; (pfc:tin-z pt) -> elevation | nil
;;   Outside the surface the API's answer is not confirmed; anything absurd is
;;   treated as "no elevation here", never passed on as a number.
(defun pfc:tin-z (pt / r)
  (setq r (pfc:call 'cf:dtm_api (list "tin_z" (list (car pt) (cadr pt)))))
  (if (and (numberp r) (> r -9999.0) (< r 99999.0)) r))


(princ "\npf-carlson loaded.")
(princ)
