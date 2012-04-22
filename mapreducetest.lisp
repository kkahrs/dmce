(set-debug 0)

(load-file "mapreduce.lisp")

;; some tests of utility functions
(= 3 (length (list 1 2 3)))
(dequal (list 1 2 3 4 5 6) (mergelists (list 1 3 5) (list 2 4 6) <))

;; common functions for map/reduce calls
(define reducer (lambda (element)
                  (let ((key (car element))
                        (vals (car (cdr element))))
                    (list key (apply + vals)))))

(define mapper (lambda (element)
                 (let ((key (car element))
                       (val (car (cdr element))))
                   (let ((sq (* val val))) (list key sq)))))

(define comparator (make-key-comparator <))

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
