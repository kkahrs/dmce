



; quote atom eq cons car cdr cond
; lambda
; + - * /
; def let
; apply eval list
; open read
; make-thread wait-thread
; dmap deep-copy





(defun deval (expr env) env (eval expr))



(defun prompt ()
  (format t "~%> ")
  (finish-output)
  )


(defun make-env () (list ()))

(defun dlisp()
  (prompt)
  (let ((expr (read *STANDARD-INPUT* () '(quit))))
    (if (and (listp expr) (eql (car expr) 'quit) (not (cdr expr)))
	expr
      (progn
	(print (deval expr (make-env)))
	(dlisp)))))

