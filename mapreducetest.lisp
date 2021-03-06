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

(load-file "mapreduce.lisp")

;; some tests of utility functions
(= 3 (length (list 1 2 3)))
(dequal (list 1 2 3 4 5 6) (mergelists (list 1 3 5) (list 2 4 6) <))

;; common functions for map/reduce calls
(define mapper
  (lambda (element)
    (let ((key (car element))
          (val (car (cdr element))))
      (let ((sq (* val val))) (list key sq)))))

(define comparator (make-key-comparator <))

(define reducer
  (lambda (element)
    (let ((key (car element))
          (vals (car (cdr element))))
      (list key (apply + vals)))))


;; testing intermediate input prepration
(define input (quote ((1 2) (2 7) (1 3) (1 4) (1 5) (2 6) (2 8) (3 1) (4 3) (3 33) (4 4))))
(define sorted-input (mergesort input comparator))
(define collapsed-input (collapse-on-keys sorted-input))

(print "input")
(print input)

;; running unit tests of map and reduce
(print "mapping")
(define mapped (mrmap mapper input))
(print mapped)

(print "collating")
(define collated (collate comparator mapped))
(print collated)

(print "reducing")
(define reduced (mrreduce reducer comparator mapped))
(print reduced)

;; final test
(print "full test")
(define mapreduceoutput
  (mapreduce input mapper reducer comparator))

(print mapreduceoutput)

;;(define step2 (mrreduce
;;               (lambda (lst)
;;                 (let ((key (car lst))
;;                       (vals (car (cdr lst))))
;;                   (apply + vals)))
;;               (make-key-comparator equal)
;;               step1))

;;(print step2)
