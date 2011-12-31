

(define map
  (lambda (f lst)
    (if (and f lst)
	(cons (f (car lst)) (map f (cdr lst)))
      nil)))


; input in the form ((keyin1 valin1) (keyin2 valin2) ...)
; output element is the result of (f keyin1 valin 1)
; return value of f must be in the form (keyout1 valout1)
; output in the form ((keyout1 valout1) (keyout2 valout2) (keyout1 valout3) ...)
(define mrmap
  (lambda (fm kvps)
      (dmap fm kvps))))

; input in the form of ((key1 val1) (key2 val2) (key1 val3) ...)
(define mrreduce
  (lambda (fr key-comparator input)
    (let ((collated (collate key-comparator input)))
      (dmap fr collated))))


; input in the form of ((key1 val1) (key2 val2) (key1 val3) ...)
; output in the form of ((key1 (val1 val3 ...)) (key2 (val2 ...)))
(define collate
  (lambda (key-comparator input)
    (collapse-on-keys (sort-on-keys key-comparator input))))
