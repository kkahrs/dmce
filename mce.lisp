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


; data types: atom (symbol number string) cons

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

; all bindings must be remote references (even for local) ???

; using install of usocket from quicklisp http://beta.quicklisp.org/quicklisp.lisp
; installed in ~/quicklisp

; quicklisp/dists/quicklisp/software/usocket-0.5.4/backend/sbcl.lisp
; commented out :serve-events nil

(ql:quickload "usocket")
(ql:quickload "bordeaux-threads")

(declaim (ftype function deval))
(declaim (ftype function do-apply))


(defparameter *connections* (make-hash-table :test #'equal))
(defparameter *locks* (make-hash-table :test #'equal))
(defparameter *pending-requests* (make-hash-table :test #'equal))
(defparameter *local-memory* (make-hash-table))
(defparameter *global-keys* (make-hash-table :test #'equal))

;; ("sbcl" "localhost" "8000")
(cond
 ((= 3 (length sb-ext:*posix-argv*))
  (let ((host (read-from-string (cadr sb-ext:*posix-argv*)))
	(port (read-from-string (caddr sb-ext:*posix-argv*))))
    (defparameter *host* host)
    (defparameter *port* port)
    (defparameter *master-host-key* (list *host* *port*))))
 ((= 5 (length sb-ext:*posix-argv*))
  (let ((host (read-from-string (cadr sb-ext:*posix-argv*)))
	(port (read-from-string (caddr sb-ext:*posix-argv*)))
	(master-host (car (cdddr sb-ext:*posix-argv*)))
	(master-port (cadr (cdddr sb-ext:*posix-argv*))))
    (defparameter *host* host)
    (defparameter *port* port)
    (defparameter *master-host-key* (list master-host master-port))))
 (t
  (progn
    (defparameter *host* "localhost")
    (defparameter *port* 8000)
    (defparameter *master-host-key* (list *host* *port*)))))


(defparameter *host-key* (list *host* *port*))
(defparameter *sym-prefix* (with-output-to-string (stream) (format stream "~A:~A." *host* *port*)))

(defun await-response (key wait)
  (let ((condition (getf wait :condition)))
    (loop
     (bt:with-lock-held (condition)
      (if (getf wait :returned)
	  (progn
	    (setf (gethash key *pending-requests*) nil)
	    (return (getf wait :return)))
	(bt:condition-wait condition))))))

(defun blocking-request (hostspec op expr)
  (let ((key (gensym *sym-prefix*))
	(wait (list :condition (bt:make-condition-variable) :return nil :returned nil)))
    (setf (gethash key *pending-requests*) wait)
    (send-data hostspec (list :op op :key key :body expr))
    (await-response key wait)))

(defun handle-message (hostspec expr)
  (let ((op (getf expr :op))
	(key (intern (symbol-name (getf expr :key))))
	(body (getf expr :body)))

    ;; message types
    ;; response --  (:op 'response :key key :body response-expr)
    ;; job --  (:op 'run :key key :body (fn arg env-id))
    ;; lookup --  (:op 'lookup :key key :body (:sym sym :env env-id))
    ;; fetch --  (:op 'fetch :key key :body mem-key)
    (case op
	  ;; initiate local action on request from remote
	  ('job (receive-job hostspec key body))
	  ('lookup (send-response hostspec key (lookup key (getf body :sym) (getf body :env))))
	  ('fetch (send-response hostspec key (fetch body)))
	  ;; receive results of remote action
	  ('response (receive-response key body)))))

(defun receive-response(key body)
  (let ((wait (gethash key *pending-requests*)))
    (let ((condition (gethash wait :condition)))
      (bt:with-lock-held
       (condition)
       (setf (gethash wait :returned) t)
       (setf (gethash wait :return) body)
       (bt:condition-notify condition)))))

(defun receive-job (hostspec key body)
  (bt:make-thread
   #'(lambda ()
       (let ((fn (car body))
	     (arg (cadr body))
	     (env (caddr body)))
	 (send-response hostspec key (deval (list fn arg) env))))))


(defun send-data(hostspec expr)
  (let ((lock (gethash hostspec *locks*))
	(stream (gethash hostspec *streams*)))
    (bt:with-lock-held (lock)
     (format stream "~A~%" expr)
     (force-output stream))))

(defun send-job (hostspec key fn arg env)
  (send-data hostspec (list :op 'run :key key
			    :body (list fn (lazy-marshall arg) env))))

(defun launch-local-job (wait fn arg env)
  (bt:make-thread
   #'(lambda ()
       (let ((condition (getf wait :condition))
	     (val (deval (list fn arg) env)))
	 (bt:with-lock-held (condition)	  
	  (setf (getf wait :return) val)
	  (setf (getf wait :returned) t)
	  (bt:condition-notify condition))))))

(defun launch-job (hostspec fn arg env)
  (let ((wait (list (gensym *sym-prefix*) :condition (bt:make-condition-variable) :return nil :returned nil)))
    (setf (gethash (car wait) *pending-requests*) (cdr wait))
    (if (equal hostspec *host-key*)
	(launch-local-job (cdr wait) fn arg env)
      (let ((key (car wait)))
	(send-job hostspec key fn arg env)))
    wait))

(defun store-local (item)
  (if (and item (consp item))
      (let ((key (gensym *sym-prefix*)))
	(setf (gethash key *local-memory*) item)
	(list :stored *host-key* :key key))
    ;; atomic types do not need to be stored locally (maybe unless a very very long string?)
    item))


(defun lazy-marshall (item)
  (if (and item (consp item))
      (let ((ca (store-local (car item)))
	    (cd (store-local (cdr item))))
	(cons ca cd))
    item))

(defun fetch-local (key)
  (gethash key *local-memory*))

;; fetch an unnamed memory location from this instance and return ready for network transport
(defun fetch (memkey)
  (let ((val (fetch-local memkey)))
    (if (and (consp val) (eql :lambda (car val)))
	val
      (lazy-marshall val))))


(defun send-response (hostspec key expr)
  (send-data hostspec (list :op 'response :key key :body expr)))

; probably don't want to specify master-host without master-port?
(defun start-server (host port &optional (master-host host) (master-port port))
  (usocket:socket-server
   host port
   #'(lambda (stream)
       (declare (type stream stream))
       (let ((hostspec (read stream nil)))
	 (format stream "~A~%" *master-host*)
	 (setf (gethash hostspec *connections*) stream)
	 (setf (gethash hostspec *locks*) (bt:make-lock))
	 (loop
	  (let ((expr (read stream nil '(quit))))
	    (if (equal expr '(quit))
		(return))
	    (handle-message hostspec expr)))))
   nil
   :multi-threading t
   :in-new-thread t))













; threads
; server
; distributor
; connections
; n worker




; use symbol-function
(defun lookup-primitive (f &optional (flist (list 'not '> '< '= '+ '- '* '/ 'atom 'eq 'cons 'list 'print
						  'print-global-env)))
  (if (and f flist)
      (if (eql f (car flist))
	  (symbol-function f)
	(lookup-primitive f (cdr flist)))))

(defun decons (op arg)
  (if (consp arg)
      (let ((val (op arg)))
	(if (and arg val (consp val) (eq :stored (car val)))
	    (blocking-request (getf val :stored) 'fetch (getf val :key))
	  val))
    (print "car or cdr of non-cons should be error")))



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

(defun make-env (&optional (parent nil))
  (let ((id (gensym *sym-prefix*))
	(storage (make-hash-table)))
    (setf (gethash id *frames*) storage)
    ;; when a frame is returned from, if it has not had any remote calls it may be discarded safely
    (list :frame id :location *host-key* :parent parent)))

(defun put-to-env (key val env)
  (let ((id (getf env :frame))
	(hostspec (getf env :location)))
    (if (equal hostspec *host-key*)
	(let ((storage (gethash id *frames*)))
	  (setf (gethash key storage) val))
      (print "binding symbols in remote frames not supported"))))


(defun extend-env(keys values env)
  (let ((env (make-env env)))
    (map 'list #'(lambda (key val) (put-to-env key val env)) keys values)
    env))



;; keep REMOTE_TYPE secret
;; just need something unique to share between cluster nodes
;;(let ((REMOTE_TYPE "c7ad5a0a-1f43-4756-8dc8-0cb4926318ec")
;;      (datastore (make-hash-table)));
;;  (defun remotep(item)
;;    (and (consp item) (eql (car item) REMOTE_TYPE)))
;;  (defun make-remote(item)
;;    (let ((ref (list REMOTE_TYPE (gethostname) *port* (gensym))))
;;      (setf (gethash (remote-sym ref) datastore) item)
;;      ref))

  ;; should not be used yet?
;;  (defun set-remote(remote item)
;;    (setf (gethash (remote-sym remote) datastore) item))
  
  ;; check hostname, call remote host or fetch local
;;  (defun remote-val(remote)
;;    (gethash (remote-sym remote) datastore))
;;  (defun remote-sym(remote)
;;    (if (remotep remote) (cadddr remote))))


(defun lookup-remote(sym env)
  (blocking-request (getf env :location) 'lookup sym))

(defun lookup(sym env)
  (if (and env sym)
      (let ((id (getf env :frame))
	    (hostspec (getf env :location)))
	(if (equal hostspec *host-key*)
	    (let ((storage (gethash id *frames*)))
	      (multiple-value-bind
	       (val present) (gethash key storage)
	       (if present
		   val
		 (lookup sym (cdr env)))))
	  (lookup-remote sym env)))
    (lookup-global sym)))

(defun local-list (lst)
  (if (and lst (consp lst))
      (cons (car lst)
	    (local-list (decons #'cdr lst)))))
      
  


(defun do-dmap (f lst env)
  (let ((lst (local-list lst)))
    (let ((wait-list
	   (map 'list
		#'(lambda (arg)
		    (launch-job (get-next-host) f arg env)))))
      (map 'list #'(lambda (wait) (await-response (car wait) (cdr wait))) wait-list))))



(defun do-progn (body env)
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
	 (eql (car func) :lambda))
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


(defun do-or (expr env)
  (if expr
      (let ((elt (deval (car expr) env)))
	(if elt
	    elt
	  (do-or (cdr expr) env)))))

(defun do-and (expr env)
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
      (lookup expr env))
     (t expr)))
   ((consp expr)
    (let ((op (car expr)))
      (cond
       ((or (eql op 'car) (eql op 'cdr))
	(let ((arg (car (getargs (cdr expr) env))))
	  (decons (symbol-function op) arg)))
       ((eql op 'quote)
	(cadr expr))
       ((eql op :lambda) expr)
       ((eql op 'lambda)
	(cons :lambda (cons env (cdr expr))))
       ((eql op 'or)
	(do-or (cdr expr) env))
       ((eql op 'and)
	(do-and (cdr expr) env))
       ((eql op 'if)
	(do-if (cdr expr) env))
       ((eql op 'let)
	(do-let expr env))
       ((or (eql op 'def) (eql op 'define))
	(do-def expr env))
       ((eql op 'dmap)
	(do-dmap op (getargs expr env) env))
       ((eql op 'eval)
	(deval (deval (cadr expr) env) env))
       (t (do-apply (deval op env) (getargs (cdr expr) env) env)))))
; should never be reached?
   (t (print "could not eval") expr)))

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

