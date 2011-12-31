; using install of usocket from quicklisp http://beta.quicklisp.org/quicklisp.lisp
; installed in ~/quicklisp

; quicklisp/dists/quicklisp/software/usocket-0.5.4/backend/sbcl.lisp
; commented out :serve-events nil

(ql:quickload "usocket")
(ql:quickload "bordeaux-threads")



(defparameter *connections* (make-hash-table :test #'equal))
(defparameter *locks* (make-hash-table :test #'equal))

(defun handle-message (expr hostspec)
  (let ((op (getf expr :op))
	(key (getf expr :key))
	(body (getf expr :body)))

    ;; message types
    ;; response --  (:op 'response :key key :body response-expr)
    ;; job --  (:op 'run :key key :body (fn arg env-id))
    ;; lookup --  (:op 'lookup :key key :body (:sym sym :env env-id))
    ;; fetch --  (:op 'fetch :key key :body mem-key)
    (case op
	  ;; initiate local action on request from remote
	  ('job (receive-job hostspec key body))
	  ('lookup (send-response hostspec key (lookup key (getf body :sym) (get-env (getf body :env)))))
	  ('fetch (send-response hostspec key (fetch body)))
	  ;; receive results of remote action
	  ('response (receive-response key body)))
    expr))

(defun receive-response(key body)
  (let ((waiting-thread (gethash key *threads*)))
    ;; pass value to slot? in waiting thread (probably need new data structure...)
    ;; wake thread
    ))

(defun receive-job (hostspec key body)
  (bt:make-thread
   #'(lambda ()
       (let ((fn (car body))
	     (arg (cadr body))
	     (env (extend-remote-env (caddr body))))
	 (send-response hostspec key (deval (list fn arg) env))))))

(defun send-data(hostspec expr)
  (let ((lock (gethash hostspec *locks*))
	(stream (gethash hostspec *streams*)))
    (bt:with-lock-held
     (lock)
     (format stream expr)
     (force-output stream))))
  
(defun send-job (hostspec key fn arg env-id)
  (send-data hostspec
	     (list :op 'run :key key
		   :body (list fn
			       (if (consp arg)
				   (lazy-marshall arg)
				 arg)
			       env-id))))


(defun lazy-marshall (item)
  (if (consp item)
      (let ((ca (store-local (car item)))
	    (cd (store-local (cdr item))))
	(cons ca cd))))

(defun store-local (item)
  (if (consp item)
      (let ((key (gensym)))
	(setf (gethash *local-memory* key) item)
	(list :stored hostspec key))
    ;; atomic types do not need to be stored locally (maybe unless a very very long string?)
    item))

(defun fetch (memkey)
  (let ((val (fetch-local memkey)))
    (if (and (consp val) (eql :lambda (car val)))
	val
      (lazy-marshall val))))

(defun fetch-local (key)
  (gethash *local-memory* key))

(defun send-response (hostspec key expr)
  (send-data hostspec (list :op 'response :key key :body expr)))

; probably don't want to specify master-host without master-port?
(defun start-server (host port &optional (master-host host) (master-port port))
  (usocket:socket-server
   host port
   #'(lambda (stream)
       (declare (type stream stream))
       (let ((hostspec (read stream nil)))
	 (print hostspec)
	 (setf (gethash hostspec *connections*) stream)
	 (setf (gethash hostspec *locks*) (bt:make-lock))
	 (let ((read-thread
		(bt:make-thread
		 #'(lambda ()
		     (loop
		      (let ((expr (read stream () '(quit))))
			(print expr)
			(if (equal expr '(quit))
			    (return))
			(handle-message hostspec expr)
			)))))
	       (write-thread
		(bt:make-thread
		 #'(lambda ()
		     (loop
		      ; wait for outgoing message
		      ; write message
		      (format stream "~A" message)
		      (force-output stream)
		      ))))
	       )


	 (loop
	  (let ((expr (read stream () '(quit))))
	    (print expr) (finish-output) (format stream "~A~%" expr) (finish-output stream)
	    (if (equal expr '(quit))
		(return))
	    ))))
   nil
   :multi-threading t
   :in-new-thread t
   )










