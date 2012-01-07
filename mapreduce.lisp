;; some code adapted from http://cs.gmu.edu/~white/CS363/Scheme/SchemeSamples.html (sorting)

(define map
  (lambda (f lst)
    (if (and f lst)
	(cons (f (car lst)) (map f (cdr lst)))
      nil)))





(define length
  (lambda (lst)
    (if (lst)
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
	  (cons (car lst2) (mergelists lst1 (cdr lst2))))))))

(define mergesort
  (lambda (lst comparator)
    (let ((len (length lst)))
      (if len
	  (if (= 1 len)
	      lst
	    (if (= 2 len)
		(mergelists (list (car lst)) (cdr lst))
	      (let ((split-lst (split lst)))
		(mergelists (mergesort (car split-lst))
			    (mergesord (car (cdr split-lst)))))))))))


(define sublist
  (lambda (lst start stop counter)
    (if (not lst)
	lst
      (if (< counter start)
	  (sublist (cdr l) start stop (+ counter 1))
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
		(sublist lst (+ (/ len 2) 1) len 1)))))))


(define sort-on-keys
  (lambda (key-comparator input)
    input))


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


; input in the form of ((key1 val1) (key2 val2) (key1 val3) ...)
; output in the form of ((key1 (val1 val3 ...)) (key2 (val2 ...)) ...)
(define collate
  (lambda (key-comparator input)
    (collapse-on-keys (sort-on-keys key-comparator input))))


(define mapreduce
  (lambda (map-function kvps reduce-function key-comparator)
    (mrreduce reduce-function key-comparator (mrmap map-function kvps))))



(mapreduce mapper (list (list 1 3) (list 4 56)) reducer comparator)

