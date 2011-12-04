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
; quote atom eq cons car cdr cond
; + - * /
; apply eval list print
; print-global-env
; make-thread wait-thread ????

; special forms:
; def let lambda and or

; local implementation
; map
; deep-copy

; NEW!
; special form: dmap

; all bindings must be remote references (even for local)

(defun gethostname () "localhost")
(defvar *port* 8000)

; keep REMOTE_TYPE secret
(funcall
 #'(lambda ()
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
       
       
       ))
 )

(defun deval (expr env)
  (cond
   ((atom expr)
    (cond
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
	(cons 'lambda (cons env (cdr expr))))
       ((eql op 'let)
	(do-let expr env))
       ((eql op 'def)
	(do-def expr env))
       ((eql op 'dmap)
	(do-dmap (getargs expr env) env))
       ((eql op 'eval) (deval (cadr expr) env))
       (t (do-apply op (getargs expr env) env))
       )
      ))
   (t expr))

  )

; expr must be a local list
(defun getargs(expr env)
  (if expr (cons (deval (car expr) env)
		 (getargs (cdr expr) env))))

(defun getop(expr)
  (car expr))
  
(defun do-apply(func args env)
  (cond
   ((remotep func)
    (do-apply (fetch-remote func) args env))
   ((primitivep func)
    (apply (lookup-primitive func) args))
   ((symbolp func)
    (do-apply (getval func env) args env))
   ((and (listp func) ; the body of a func -- should be (lambda (...) ...)
	 (eql (car func) 'lambda))
    (let ((params (get-lambda-params func))
	  (body (get-lambda-body func))
	  )
      (let ((env (extend-env params args env))
	    )
	(car (last (map #'(lambda (expr) (deval expr env)) body)))


    )))
   (t nil) ; default -- should throw error
   )
  )


(defun prompt ()
  (format t "~%> ")
  (finish-output)
  )


(defun make-env () (list ()))

(defun dlisp(&optional (env (make-env)))
  (prompt)
  (let ((expr (read *STANDARD-INPUT* () '(quit))))
    (if (and (listp expr) (eql (car expr) 'quit) (not (cdr expr)))
	expr
      (progn
	(print (deval expr env))
	(dlisp env)))))


; (with-input-from-string (stream "1 2 3 4") (let ((*STANDARD-INPUT* stream)) (dlisp)))

