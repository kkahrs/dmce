; research references

; multicomputer lisp interpreter
; http://www.faqs.org/rfcs/rfc504.html mentions idea
; http://authors.library.caltech.edu/26864/0/93-15.ps modula 3d may have had implementation of lisp interpreter
; http://ieeexplore.ieee.org/xpl/freeabs_all.jsp?arnumber=26721 appears to discuss lisp remote execution
; http://ditec.um.es/~jmgarcia/papers/sigplan92.ps distributed pascal

; distributed lisp interpreter
; http://ieeexplore.ieee.org/xpl/freeabs_all.jsp?arnumber=500616 seems fairly close but uses an underlying architecture for distribution, not built-in
; paralation (^) seems to be for data-parallel not execution-parallel. current implementation is kind of data-parallel oriented,
; but the addition of thread primitives appears difficult in the paralation model however not in this one






; data types: atom (symbol number string) pair

; primitives:
; atom eq cons car cdr
; + - * /
; list print
; print-global-env
; make-thread wait-thread ????

; special forms:
; def let lambda and or cond quote eval apply

; local implementation
; map
; deep-copy

; NEW!
; special form: dmap

; all bindings must be remote references (even for local)

(declaim (ftype function deval))
(declaim (ftype function do-apply))




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












; ("sbcl" "localhost" "8000")
(cond
 ((= 3 (length sb-ext:*posix-argv*))
    (let ((host (read-from-string (cadr sb-ext:*posix-argv*)))
	  (port (read-from-string (caddr sb-ext:*posix-argv*))))
      (defvar *host* host)
      (defvar *port* port)
      (defvar *master-host-key* (list *host* *port*))
      ))
 ((= 5 (length sb-ext:*posix-argv*))
    (let ((host (read-from-string (cadr sb-ext:*posix-argv*)))
	  (port (read-from-string (caddr sb-ext:*posix-argv*)))
	  (master-host (car (cdddr sb-ext:*posix-argv*)))
	  (master-port (cadr (cdddr sb-ext:*posix-argv*)))
	  )
      (defvar *host* host)
      (defvar *port* port)
      (defvar *master-host-key* (list master-host master-port))
      ))
 (t
  (progn
    (defvar *host* "localhost")
    (defvar *port* 8000)
    (defvar *master-host-key* (list *host* *port*))
    )
  )
 )
(defvar *host-key* (list *host* *port*))

(load "networkio.lisp")


; threads
; server
; distributor
; connections
; n worker











; use symbol-function
(let ((primitives (list 'not '> '< '= '+ '- '* '/ 'atom 'eq 'print-global-env 'cons 'list 
					; need custom implementation
			'car 'cdr 'print
			)))
  (defun lookup-primitive(f &optional (flist primitives))
    (if (and f flist)
	(if (eql f (car flist))
	    (symbol-function f)
	  (lookup-primitive f (cdr flist)))))
  )

; contains table of <symbol, *host-key*> pairs indicating which host has physical storage for symbol
(defparameter *global-keys* (make-hash-table :test #'equal))

; contains table of <symbol, value> pairs as physical storage for global variables
(defparameter *global-values* (make-hash-table))

(defun set-global (key val) (setf (gethash key *global-keys*) val))
(defun lookup-global (key)
  (let ((host-key (gethash key *global-keys*)))
    (if (equal host-key *host-key*)
	(gethash key *global-keys*)
      ((format t "FIXME: need to look up key on ~A~%" host-key) ())
      )))

(defun print-global-env ()
  (format t "~%")
  (maphash #'(lambda (key val) (format t "key ~a val ~a~%" key val)) *global-values*)
  (finish-output)
  nil)

(defun make-frame () (list :local (make-hash-table)))
(defun put-to-frame (key val frame) (setf (gethash key (cadr frame)) val))
(defun get-from-frame (key frame) (gethash key (cadr frame)))
(defun make-remote-frame (host port id)
  (list :remote '(host port id)))
(defun make-env () (list (make-frame)))


(defun extend-env(keys values env)
  (let ((frame (make-frame)))
    (map 'list #'(lambda (key val) (put-to-frame key val frame)) keys values)
    (cons frame env))
  )



; keep REMOTE_TYPE secret

					; just need something unique to share between cluster nodes
(let ((REMOTE_TYPE "c7ad5a0a-1f43-4756-8dc8-0cb4926318ec")
      (datastore (make-hash-table))
      )
  
  (defun remotep(item)
    (and (consp item) (eql (car item) REMOTE_TYPE)))
  (defun make-remote(item)
    (let ((ref (list REMOTE_TYPE (gethostname) *port* (gensym))))
      (setf (gethash (remote-sym ref) datastore) item)
      ref
      )
    )
					; should not be used yet?
  (defun set-remote(remote item)
    (setf (gethash (remote-sym remote) datastore) item))
  
					; check hostname, call remote host or fetch local
  (defun remote-val(remote)
    (gethash (remote-sym remote) datastore))
  (defun remote-sym(remote)
    (if (remotep remote) (cadddr remote)))
  
  
  )


(defun lookup-remote(sym env) sym env ())

(defun lookup(sym env)
  (if (and env sym)
      (cond
       ((eql 'local (car (car env)))
	(multiple-value-bind
	 (val present) (gethash sym (car (cdr (car env))))
	 (if present
	     val
	   (lookup sym (cdr env))
	   ))
	)
       ((eql 'remote (car env))
	(lookup-remote sym env))
       (t (lookup-global sym)) ; should never happen -- probably indicates malformed env
       )
    (lookup-global sym)
    )
  )


(defun do-dmap (f lst env)
  (if lst
      (cons (do-apply f (car lst) env)
	    (do-dmap f (cdr lst) env))))

(defun do-progn(body env)
  (car (last (map
	      'list
	      #'(lambda (expr) (deval expr env))
	      body)
	     )))

(defun do-let (expr env)
  (let ((vars (map 'list #'car (cadr expr)))
	(values (map 'list #'(lambda (xpr) (deval (cadr xpr) env)) (cadr expr)))
	(body (cddr expr))
	)
    (let ((env (extend-env vars values env)))
      (do-progn body env)
      )
    )
  )


(defun do-def (expr env)
  (let ((sym (cadr expr))
	(val (deval (caddr expr) env)))
    (if (symbolp sym)
	(set-global sym val)
      (progn (print (list "not a symbol" sym))
	     nil)
      )
    )
  )
; expr must be a local list
(defun getargs(expr env) (map 'list #'(lambda (xpr) (deval xpr env)) expr))

(defun getop(expr)
  (car expr))

; (lambda (env) (arg1 arg2 ...) expr expr ... )
(defun get-lambda-params(func) (caddr func))
(defun get-lambda-body(func) (cdddr func))
(defun fetch-remote(func) func nil)

(defun do-apply(func args env)
  (cond
   ((remotep func)
    (do-apply (fetch-remote func) args env))
   ((lookup-primitive func)
    (apply (lookup-primitive func) args))
   ((symbolp func)
    (do-apply (lookup func env) args env))
   ((and (listp func) ; the body of a func -- should be (lambda (...) ...)
	 (eql (car func) 'lambda)) ; check that func has been devaled and has attached env
    (let ((params (get-lambda-params func))
	  (body (get-lambda-body func))
	  )
      (let ((env (extend-env params args env))
	    )
;	(car (last (map 'list #'(lambda (expr) (deval expr env)) body)))
	(do-progn body env)

    )))
   (t nil) ; default -- should throw error
   )
  )

(defun strip-quote(expr)
  (if (consp expr)
      (if (eql (car expr) 'quote)
	  (cdr expr)
	(cons (strip-quote (car expr))
	      (strip-quote (cdr expr)))
	)
    expr))

(defun devaled(op)
  (and (cadr op) (listp (car (cadr op))))
  )

(defun do-or (expr env)
  (if expr
      (let ((elt (deval (car expr) env)))
	(if elt
	    elt
	  (do-or (cdr expr) env)))))

(defun do-and(expr env)
  (if expr
      (let ((elt (deval (car expr) env)))
	(if elt
	    (if (cdr expr)
		(do-and (cdr expr) env)
	      elt)
	  nil))
    t
    )
  )

(defun do-if(expr env)
  ; predicate then else
  (let ((pred (deval (car expr) env)))
    (if pred
	(deval (cadr expr) env)
      (deval (caddr expr) env))))


(defun deval (expr env)
  (cond
   ((atom expr)
    (cond
     ((lookup-primitive expr) expr)     
     ((symbolp expr)
      (let ((val (lookup expr env)))
	(if (remotep val)
	    (remote-val val)
	  val)))
     (t expr))
   )
   ((consp expr)
    (let ((op (car expr)))
      (cond
       ((eql op 'quote)
	(cadr expr))
       ((eql op 'lambda)
	(if (devaled expr)
	    expr
	  (cons 'lambda (cons env (cdr expr)))))
       ((eql op 'or)
	(do-or (cdr expr) env)
	)
       ((eql op 'and)
	(do-and (cdr expr) env)
	)
       ((eql op 'if)
	(do-if (cdr expr) env)
	)
       ((eql op 'let)
	(do-let expr env))
       ((or (eql op 'def) (eql op 'define))
	(do-def expr env))
       ((eql op 'dmap)
	(do-dmap op (getargs expr env) env))
       ((eql op 'eval)
	(deval (deval (cadr expr) env) env))
       (t (do-apply (deval op env) (getargs (cdr expr) env) env))
       )
      ))
; should never be reached?
   (t (print "could not eval") expr))
  )

; ==========================================================================================
(defun prompt ()
  (format t "~%> ")
  (finish-output)
  )


(defun dlisp(&optional (env (make-env)))
  (prompt)
  (let ((expr (read *STANDARD-INPUT* nil '(quit))))
    (if (and (listp expr) (eql (car expr) 'quit) (not (cdr expr)))
	expr
      (progn
	(print (deval expr env))
	(dlisp env)))))


; (with-input-from-string (stream "1 2 3 4") (let ((*STANDARD-INPUT* stream)) (dlisp)))

