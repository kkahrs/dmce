;; research references

;; multicomputer lisp interpreter
;; http://www.faqs.org/rfcs/rfc504.html mentions idea
;; http://authors.library.caltech.edu/26864/0/93-15.ps modula 3d may have had implementation of lisp interpreter
;; http://ieeexplore.ieee.org/xpl/freeabs_all.jsp?arnumber=26721 appears to discuss lisp remote execution
;; http://ditec.um.es/~jmgarcia/papers/sigplan92.ps distributed pascal

;; distributed lisp interpreter
;; http://ieeexplore.ieee.org/xpl/freeabs_all.jsp?arnumber=500616 seems fairly close but uses an underlying architecture for distribution, not built-in
;; paralation (^) seems to be for data-parallel not execution-parallel. current implementation is kind of data-parallel oriented,
;; but the addition of thread primitives appears difficult in the paralation model however not in this one


;; data types: atom (symbol number string) cons

;; primitives:
;; atom eq cons car cdr
;; + - * /
;; list print
;; print-global-env
;; make-thread wait-thread ????

;; special forms:
;; def let lambda and or cond quote eval apply

;; local implementation
;; map
;; deep-copy

;; NEW!
;; special form: dmap

;; all bindings must be remote references (even for local) ???

;; using install of usocket from quicklisp http://beta.quicklisp.org/quicklisp.lisp
;; installed in ~/quicklisp

;; quicklisp/dists/quicklisp/software/usocket-0.5.4/backend/sbcl.lisp
;; commented out :serve-events nil

(ql:quickload "usocket")
(ql:quickload "bordeaux-threads")


;; macro from http://paste.lisp.org/display/62851
(defmacro with-open-client-socket ((socket address port) &body body)
  (let ((raw-socket (gensym)))
    `(let ((,raw-socket (usocket:socket-connect ,address ,port)))
       (unwind-protect (let ((,socket (usocket:socket-stream ,raw-socket)))
                         ,@body)
         (when ,raw-socket (usocket:socket-close ,raw-socket))))))



(declaim (ftype function deval))
(declaim (ftype function blocking-request))
(declaim (ftype function handle-message))
(declaim (ftype function do-apply))

(defparameter *debug* 9)
(defparameter *connections-lock* (bt:make-lock))
(defparameter *connections* (make-hash-table :test #'equal))
(defparameter *locks* (make-hash-table :test #'equal))
(defparameter *pending-requests* (make-hash-table :test #'equal))
(defparameter *local-memory* (make-hash-table :test #'equal))
(defparameter *frames* (make-hash-table :test #'equal))
;; contains table of <symbol, value> pairs as physical storage for global variables
(defparameter *global-values-lock* (bt:make-lock))
(defparameter *global-values* (make-hash-table))


;; ("sbcl" "localhost" "8000")
(let* ((argc (length sb-ext:*posix-argv*))
       (argv sb-ext:*posix-argv*)
       (host (if (< 2 argc) (nth 1 argv) "localhost"))
       (port (if (< 2 argc) (read-from-string (nth 2 argv)) 8000))
       (master-host (if (< 4 argc) (nth 3 argv) "localhost"))
       (master-port (if (< 4 argc) (read-from-string (nth 4 argv)) 8000)))
  (defparameter *host* host)
  (defparameter *port* port)
  (defparameter *master-host-key* (list :host master-host :port master-port))
  (defparameter *host-key* (list :host host :port port))
  (defparameter *sym-prefix* (format nil "~A:~A." host port)))



(defun gen-key-string ()
  (symbol-name (gensym *sym-prefix*)))


(defun store-local (item)
  (if (and item (consp item) (not (eq :stored (car item))))
      (let ((key (gen-key-string)))
	(setf (gethash key *local-memory*) item)
	(list :stored *host-key* :key key))
    ;; atomic types do not need to be stored locally (maybe unless a very very long string?)
    item))




(defun lazy-marshall (item)
  (if (and item (consp item) (not (equal :lambda (car item))))
      (let ((ca (store-local (car item)))
	    (cd (store-local (cdr item))))
	(cons ca cd))
    item))



(defun fetch-local (key)
  (gethash key *local-memory*))

;; fetch an unnamed memory location from this instance and return ready for network transport
(defun fetch (memkey)
  (let ((val (fetch-local memkey)))
    (if (and (consp val) (equal :lambda (car val)))
	val
      (lazy-marshall val))))

(defun lookup-global (sym)
  (if (equal *host-key* *master-host-key*)
      (gethash sym *global-values*)
    (blocking-request *master-host-key* "lookup" (list :sym sym :env nil))))


(defun lookup-remote (sym env)
  (blocking-request (getf env :location) "lookup" (list :sym sym :env env)))

(defun lookup (sym env)
  (if (eq sym :stored)
      (format t "error -- tried to look up instead of fetching~%")
    (if (and env sym)
	(let ((id (getf env :frame))
	      (hostspec (getf env :location)))
	  (if (equal hostspec *host-key*)
	      (let ((storage (gethash id *frames*)))
		(multiple-value-bind
		 (val present) (gethash sym storage)
		 (if present
		     val
		   (lookup sym (getf env :parent)))))
	    (lookup-remote sym env)))
      (lookup-global sym))))


(defun send-data (hostspec expr)
  (if (not (equal hostspec *host-key*))
      (let ((lock (gethash hostspec *locks*))
	    (stream (gethash hostspec *connections*)))
	(if (and lock stream)
	    (bt:with-lock-held
	     (lock)
	     (format stream "~S~%" expr)
	     (force-output stream))
	  (format t "could not send data to ~S~%" hostspec)))))


(defun send-response (hostspec key expr)
  (send-data hostspec (list :op "response" :key key :body (lazy-marshall expr))))


(defun receive-job (hostspec key body)
  (force-output)
  (bt:make-thread
   #'(lambda ()
       (let ((fn (car body))
	     (arg (cadr body))
	     (env (caddr body)))
	 (let ((val (do-apply fn (list arg) env)))
	   (if (< 2 *debug*) (format t "deval (job from ~S) returned ~S~%" hostspec val))
	   (force-output)
	   (send-response hostspec key val))))))


(defun receive-response(key body)
  (let ((wait (gethash key *pending-requests*)))
    (if (< 1 *debug*) (format t "got response for request ~S~%" (list key body)))
    (if (not wait) (print "failed to lookup wait obj for key"))
    (let ((condition (getf wait :condition))
	  (lock (getf wait :lock)))
      (if lock
	  (bt:with-lock-held
	   (lock)
	   (setf (getf wait :returned) t)
	   (setf (getf wait :return) body)
	   (bt:condition-notify condition))
	(print "lock is nil")))))


(defun stream-reader (stream hostspec)
  (bt:with-lock-held
   (*connections-lock*)
   (setf (gethash hostspec *connections*) stream)
   (setf (gethash hostspec *locks*) (bt:make-lock)))
  (loop
   (let ((expr (read stream nil '(quit))))
     (if (equal expr '(quit))
	 (quit)
       (handle-message hostspec expr)))))




(defun peer-connect (hostspec)
  (bt:make-thread
   #'(lambda ()
       (let ((self-connect (equal hostspec *host-key*)))
	 (if self-connect
	     (print "connection to self attempted")
	   (let ((new-connection
		  (bt:with-lock-held
		   (*connections-lock*)
		   (if (not (gethash hostspec *connections*))
		       (setf (gethash hostspec *connections*) t)))))
	     (if new-connection
		 (let ((host (getf hostspec :host))
		       (port (getf hostspec :port)))
		   (if (< 1 *debug*) (format t "connecting to ~S~%" hostspec))
		   (force-output)
		   (with-open-client-socket
		    (stream host port)
		    (format stream "~S~%" *host-key*)
		    (force-output stream)
		    (stream-reader stream hostspec)))
	       (if (< 3 *debug*) (format t "already connected to ~S : ~S~%" hostspec new-connection)))))))))


(defun refresh-hostlist (hosts)
  "nothing currently handles case of disconnecting host"
  (map 'list #'peer-connect hosts))


(defun handle-message (hostspec expr)
  (let ((op (getf expr :op))
	(key (getf expr :key))
	(body (getf expr :body)))
    (if (< 2 *debug*) (format t "~%op ~S key ~S body ~S~%" op key body))
    ;; message types
    ;; response -- (:op "response" :key key :body response-expr)
    ;; job -- (:op "run" :key key :body (fn arg env-id)) ;; env-id probably will never be used -- fn will have env, arg already devaled
    ;; lookup -- (:op "lookup" :key key :body (:sym sym :env env-id))
    ;; fetch -- (:op "fetch" :key key :body mem-key)
    ;; hosts -- (:op "hosts" :key nil :body (list of hostspecs for all known hosts))
    (cond
     ;; initiate local action on request from remote
     ((equal op "run") (receive-job hostspec key body))
     ((equal op "lookup")
      (send-response
       hostspec key
       (lookup (intern (symbol-name (getf body :sym)))
	       (getf body :env))))
     ((equal op "fetch") (send-response hostspec key (fetch body)))
     ;; receive results of remote action
     ((equal op "response") (receive-response key body))
     ((equal op "hosts") (refresh-hostlist body))
     (t (print "invalid op")))))



(if (not (equal *master-host-key* *host-key*))
    (peer-connect *master-host-key*))

(defun await-response (wait)
  (let ((condition (getf wait :condition))
	(lock (getf wait :lock)))
    (loop
     (bt:with-lock-held
      (lock)
      (if (getf wait :returned)
	  (progn
	    (remhash (getf wait :key) *pending-requests*)
	    (return (getf wait :return)))
	(bt:condition-wait condition lock))))))

(defun create-wait-obj ()
  (list :key (gen-key-string)
	:condition (bt:make-condition-variable)
	:lock (bt:make-lock)
	:return nil
	:returned nil))


(defun blocking-request (hostspec op expr)
  (if (equal hostspec *host-key*)
      ;; run lookup or fetch
      (cond ((equal op "fetch")
	     (fetch-local expr))
	    ((equal op "run")
	     (print "not supported"))
	    (t (print "not supported")))
    (let ((wait (create-wait-obj)))
      (let ((key (getf wait :key)))
	(setf (gethash key *pending-requests*) wait)
	(send-data hostspec (list :op op :key key :body expr))
	(await-response wait)))))


(defun send-job (hostspec key fn arg env)
  (send-data hostspec (list :op "run" :key key
			    :body (list fn (lazy-marshall arg) env))))

(defun launch-local-job (wait fn arg env)
  (bt:make-thread
   #'(lambda ()
       (let ((val (do-apply fn (list arg) env)))
	 (if (< 4 *debug*) (format t "job returned ~S~%" val))
	 (bt:with-lock-held
	  ((getf wait :lock))	  
	  (setf (getf wait :return) val)
	  (setf (getf wait :returned) t)
	  (bt:condition-notify (getf wait :condition)))))))

(defun launch-job (hostspec fn arg env)
  (if (< 2 *debug*) (format t "launching job ~S~%" (list :hostspec hostspec :fn fn :arg arg :env env)))
  (force-output)
  (let ((wait (create-wait-obj)))
    (setf (gethash (getf wait :key) *pending-requests*) wait)
    (if (equal hostspec *host-key*)
	(launch-local-job wait fn arg env)
      (send-job hostspec (getf wait :key) fn arg env))
    wait))


(defun get-hostlist ()
  (bt:with-lock-held
   (*connections-lock*)
   (cons *host-key*
	 (let ((remote-list nil))
	   (maphash #'(lambda (key val) val (setf remote-list (cons key remote-list))) *connections*)
	   remote-list))))


(defun start-server (host port)
  (usocket:socket-server
   host port
   #'(lambda (stream)
       (declare (type stream stream))
       (let ((hostspec (read stream nil)))
	 (if (< 3 *debug*) (format t "got connection from ~S~%" hostspec))
	 (force-output)
	 (let ((hostlist-command (list :op "hosts" :key nil :body (cons hostspec (get-hostlist)))))
	   (format stream "~S~%" hostlist-command)
	   (force-output stream))
	 (stream-reader stream hostspec)))
   nil
   :multi-threading t
   :in-new-thread t))


(defun get-hostkey () *host-key*)
(defun set-debug (d) (setf *debug* d))



(defun decons (op arg)
  (if (consp arg)
      (let ((val (funcall op arg)))
	(if (and arg val (consp val) (eq :stored (car val)))
	    (blocking-request (getf val :stored) "fetch" (getf val :key))
	  val))
    (format t "op ~S of non-cons <~S> should be error~%" op arg)))



(defun deep-copy (expr)
  (if (or (atom expr) (not expr))
      expr
    (if (eq (car expr) :stored)
	;; FIXME: duplicate code
	(blocking-request (getf expr :stored) "fetch" (getf expr :key))
      (let ((ca (decons #'car expr))
	    (cd (decons #'cdr expr)))
	(cons (deep-copy ca)
	      (deep-copy cd))))))



(defun dequal (a b)
  (equal (deep-copy a) (deep-copy b)))



;; FIXME: only works on master
(defun print-global-env ()
  (format t "~%")
  (maphash #'(lambda (key val) (format t "key ~a val ~a~%" key val)) *global-values*)
  (finish-output)
  nil)

(defun make-env (&optional (parent nil))
  (let ((id (gen-key-string))
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


(defun set-global (key val)
  (if (equal *host-key* *master-host-key*)
      (bt:with-lock-held
       (*global-values-lock*)
       (setf (gethash key *global-values*) val))
    (blocking-request *master-host-key* "run"
		      (list (list :lambda (make-env) (list 'x) (list 'define key val))
			    1
			    nil))))


(defun local-list (lst)
  (if (and lst (consp lst))
      (cons (car lst)
	    (local-list (decons #'cdr lst)))))

(let ((counter 0))
  (defun get-next-host ()
    (let* ((hosts (get-hostlist))
	   (index (mod counter (length hosts))))
      (incf counter)
      (nth index hosts))))

(defun do-dmap (f lst env)
    (if (< 5 *debug*) (print lst))
  (let ((lst (local-list lst)))
    (if (< 5 *debug*) (print lst))
    (let ((wait-list
	   (map 'list
		#'(lambda (arg)
		    (launch-job (get-next-host) f arg env))
		lst)))
      (map 'list #'(lambda (wait) (await-response wait)) wait-list))))




(defun do-progn (body env)
  (car (last (map 'list
		  #'(lambda (expr) (let ((val (deval expr env)))
				     (if (< 6 *debug*) (format t "progn expr ~S returns ~S~%" expr val))
				     val))
		  body))))

(defun do-let (expr env)
  (let ((vars (map 'list #'car (cadr expr)))
	(values (map 'list #'(lambda (xpr) (deval (cadr xpr) env)) (cadr expr)))
	(body (cddr expr)))
    (let ((env (extend-env vars values env)))
      (do-progn body env))))


(defun do-def (expr env)
  (let ((sym (cadr expr))
	(val (deval (caddr expr) env)))
    (if (symbolp sym)
	(set-global sym val)
      (progn (print (list "not a symbol" sym))
	     nil))))


;; expr must be a local list
(defun getargs (expr env) (map 'list #'(lambda (xpr) (deval xpr env)) expr))

(defun getop (expr)
  (car expr))

;; (lambda env (arg1 [...]) expr [...])
(defun get-lambda-params (func) (caddr func))
(defun get-lambda-env (func) (cadr func))
(defun get-lambda-body (func) (cdddr func))
(defun fetch-remote (func) func nil)


(defun lookup-primitive (f &optional
			   (flist (list 'not '> '< '= '+ '- '* '/
					'atom 'eq 'cons 'list 'print
					'print-global-env 'get-hostlist 'get-hostkey 'deep-copy 'dequal 'set-debug)))
  (if (and f flist)
      (if (eql f (car flist))
	  (symbol-function f)
	(lookup-primitive f (cdr flist)))))


(defun do-apply (func args env)
  (cond
   ((lookup-primitive func)
    (apply (lookup-primitive func) args))
   ((symbolp func)
    (cond
     ((eq func 'eval)
      (deval (car args) env))
     ((or (eql func 'car) (eql func 'cdr))
      (decons (symbol-function func) (car args)))
     (t (do-apply (lookup func env) args env))))
   
   ((and (listp func) ; the body of a func -- should be (lambda (...) ...)
	 (eql (car func) :lambda))
    (let ((params (get-lambda-params func))
	  (body (get-lambda-body func)))
      (let ((env (extend-env params args (get-lambda-env func))))
	(do-progn body env))))
   ;; default -- should throw error
   (t (format t "could not apply func ~S to args ~S~%" func args) nil)))

(defun strip-quote (expr)
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
  (if (< 8 *debug*) (format t "calling deval with ~S in ~S~%" expr env))
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
	(let ((args (getargs (cdr expr) env)))
	  (if (< 6 *debug*) (format t "dmap args ~S~%" args))
	  (do-dmap (car args) (cadr args)  env)))
       ((eql op 'eval)
	(deval (deval (cadr expr) env) env))
       (t (do-apply (deval op env) (getargs (cdr expr) env) env)))))
					; should never be reached?
   (t (print "could not eval") expr)))

;; ==========================================================================================
(defun prompt ()
  (format t "~%> ")
  (finish-output))
(defun local-print (expr)
  (print (deep-copy expr))
  (force-output))

(defun dlisp(&optional (env (make-env)))
  (start-server *host* *port*)
  (loop
   (prompt)
   (let ((expr (read *STANDARD-INPUT* nil '(quit))))
     (if (and (listp expr) (eql (car expr) 'quit) (not (cdr expr)))
	 (return expr)
       (local-print (deval expr env))))))


(dlisp)
