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


;; some code adapted from http://cs.gmu.edu/~white/CS363/Scheme/SchemeSamples.html (sorting)
(define map
  (lambda (f lst)
    (if (and f lst)
	(cons (f (car lst)) (map f (cdr lst)))
      nil)))





(define length
  (lambda (lst)
    (if lst
	(+ 1 (length (cdr lst)))
      0)))



(define mergelists
  (lambda (lst1 lst2 comparator)
    (if (not lst1)
	lst2
      (if (not lst2)
	  lst1
	(if (comparator (car lst1) (car lst2))
	    (cons (car lst1) (mergelists (cdr lst1) lst2 comparator))
	  (cons (car lst2) (mergelists lst1 (cdr lst2) comparator)))))))

(define mergesort
  (lambda (lst comparator)
    (let ((len (length lst)))
      (if len
	  (if (= 1 len)
	      lst
	    (if (= 2 len)
		(mergelists (list (car lst)) (cdr lst) comparator)
	      (let ((split-lst (split lst)))
		(mergelists (mergesort (car split-lst) comparator)
			    (mergesort (car (cdr split-lst)) comparator)
			    comparator))))))))


(define sublist
  (lambda (lst start stop counter)
    (if (not lst)
	lst
      (if (< counter start)
	  (sublist (cdr lst) start stop (+ counter 1))
	(if (> counter stop)
	    nil
	  (cons (car lst) (sublist (cdr lst) start stop (+ counter 1))))))))


(define split
  (lambda (lst)
    (let ((len (length lst)))
      (if (= len 0)
	  (list nil nil)
	(if (= len 1)
	    (list lst nil)
	  (list (sublist lst 1 (/ len 2) 1)
		(sublist lst (+ (/ len 2) 1/2) len 1)))))))




; input in the form ((keyin1 valin1) (keyin2 valin2) ...)
; output element is the result of (mf keyin1 valin1)
; return value of mf must be in the form (keyout1 valout1)
; output in the form ((keyout1 valout1) (keyout2 valout2) (keyout1 valout3) ...)
(define mrmap
  (lambda (mf kvps)
      (dmap mf kvps)))

; input in the form of ((key1 val1) (key2 val2) (key1 val3) ...)
(define mrreduce
  (lambda (rf key-comparator input)
    (let ((collated (collate key-comparator input)))
      (dmap rf collated))))


(define make-key-comparator
  (lambda (comp)
    (lambda (arg1 arg2)
      (let ((key1 (car arg1))
	    (key2 (car arg2)))
	(comp key1 key2)))))

(define collapse-on-keys
  (lambda (elements)
    (let ((element (car elements)))
      (let ((key (car element)))
	(collapse-on-keys-real elements key nil nil)))))

(define collapse-on-keys-real
  (lambda (elements current-key current-list output)
    (if elements
	(let ((element (car elements)))
	  (let ((key (car element))
		(val (car (cdr element))))
	    (if (dequal key current-key)
		(collapse-on-keys-real
                 (cdr elements)
                 key
                 (cons val current-list)
                 output)
	      (collapse-on-keys-real
               (cdr elements)
               key
               (list val)
               (cons (list current-key current-list) output)))))
	(if (or current-key current-list)
            (cons (list current-key current-list) output)
          output))))

; input in the form of ((key1 val1) (key2 val2) (key1 val3) ...)
; output in the form of ((key1 (val1 val3 ...)) (key2 (val2 ...)) ...)
(define collate
  (lambda (key-comparator input)
    (collapse-on-keys (mergesort input key-comparator))))


(define mapreduce
  (lambda (kvps map-function reduce-function key-comparator)
    (mrreduce reduce-function key-comparator (mrmap map-function kvps))))



;(mapreduce mapper (list (list 1 3) (list 4 56)) reducer comparator)

