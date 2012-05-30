;; Copyright (C) 2011,2012 Ken Kahrs (ken dot kahrs at inframesh dot com)
;; 
;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions:
;; 
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;; 
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
;; LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
;; OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
;; WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


(set-debug 0)

(print
(dmap (lambda (arg) (eval arg)) 
      (quote
       ((eq 10 (+ 1 2 3 4))
	(eq 1680 (* 5 6 7 8))

	(eq -1 (- 9 10))
	(eq 3 (/ 27 9))

	(not nil)
	(not (not (eq 3 3)))

	(and 11 12 13 14)
	(not (and 2 3 nil))

	(or 1 nil)
	(or nil nil 3)

	(not (not (or 1 1)))
	(atom 3)

	(atom "foo")
	(atom (quote bar))

	(let ((x (cons 1 2))) (eq x x))
	(not (eq (cons 1 2) (cons 1 2)))

	(dequal (list 1 2) (list 1 2))


	(dequal (list (list 22 33) (list 44 55) (list 66 77))
		(dmap (lambda (x) x) (list (list 22 33) (list 44 55) (list 66 77))))

	(eq 42 (define x 42))

	(eq 111 (car (cons 111 222)))

	(eq 222 (cdr (cons 111 222)))
	(eq 900 ((lambda (x) (* x x)) 30))

	(eq 1 (if 9 1 2))
	(eq 2 (if nil 1 2))

	(eq 63 (let ((x 63)) x))
	(eq 143 (let ((x (+ 72 71))) x))

	(eq 78 (eval (list + 43 35)))
	(eq 732 (eval (list (quote eval) (list + 311 421))))

	(eq 42 x)

	(eq 240 (apply (quote +) (list 70 80 90))))))

)
