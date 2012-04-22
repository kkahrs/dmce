(set-debug 0)

(load-file "mapreduce.lisp")
(= 3 (length (list 1 2 3)))

(dequal (list 1 2 3 4 5 6) (mergelists (list 1 3 5) (list 2 4 6) <))


(define input (quote ((1 2) (2 7) (1 3) (1 4) (1 5) (2 6) (2 8))))
(define sorted-input (mergesort input (make-key-comparator <)))
(define collapsed-input (collapse-on-keys sorted-input))

(print "mapping")

(define mapped (mrmap (lambda (element)
                        (let ((key (car element))
                              (val (car (cdr element))))
                          (let ((sq (* val val))) (list key sq)))) input))

(print mapped)

(print "collating")
(define collated (collate (make-key-comparator <) mapped))
(print collated)

(print "reducing")
(define reduced (mrreduce (lambda (element)
                            (let ((key (car element))
                                  (vals (car (cdr element))))
                              (list key (apply + vals))))
                          (make-key-comparator <)
                          mapped))
(print reduced)


;;(define step2 (mrreduce
;;               (lambda (lst)
;;                 (let ((key (car lst))
;;                       (vals (car (cdr lst))))
;;                   (apply + vals)))
;;               (make-key-comparator equal)
;;               step1))

;;(print step2)
