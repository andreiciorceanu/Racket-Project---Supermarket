#lang racket
(require racket/match)
(require racket/trace)
(require "queue.rkt")

(provide (all-defined-out))

(define ITEMS 5)


; TODO
; Aveți libertatea să vă structurați programul cum doriți (dar cu restricțiile
; de mai jos), astfel încât funcția serve să funcționeze conform specificației.
; 
; Restricții (impuse de checker):
; - trebuie să existe în continuare funcția (empty-counter index)
; - cozile de la case trebuie implementate folosind noul TDA queue

(define-struct counter (index tt status et queue) #:transparent)
;status =0 casa inchisa
;status=1 casa deschisa
(define (empty-counter index)
  (make-counter index 0 1 0 (make-queue empty-stream '() 0 0)))
  


(define (update f counters index)
  (cond
    [(null? counters) '()]
    [(= index (counter-index (car counters))) (cons (f (car counters)) (cdr counters))]
    [else (cons (car counters) (update f (cdr counters) index))]))

(define tt+
  (lambda (minutes)
    (lambda (C1)
      (match C1
    [(counter index tt status et queue) (counter index (+ tt minutes) status et queue)]))))

(define et+
   (lambda (minutes)
    (lambda (C2)
      (match C2
        [(counter index tt status et queue) (counter index tt status (+ et minutes) queue)]))))


(define (add-to-counter name items)     
  (λ (C)
        (if (and (null? (queue-right (counter-queue C))) (stream-empty? (queue-left (counter-queue C))))
         (struct-copy counter C
                                [tt (+ (counter-tt C) items)]
                                [et (+ (counter-et C) items)]
                                [queue (enqueue (cons name items) (counter-queue C))]) 
        (struct-copy counter C
                                [tt (+ (counter-tt C) items)]
                                [queue (enqueue (cons name items) (counter-queue C))]))
        ))

(define (sort-helper f counters acc)
   (cond
      [(null? counters)  (cons (counter-index acc) (f acc))]
      [(< (f (car counters)) (f acc))
            (sort-helper f (cdr counters) (car counters))]
      [(= (f (car counters)) (f acc))
       (if (< (counter-index (car counters)) (counter-index acc))
       (sort-helper f (cdr counters) (car counters))
      (sort-helper f (cdr counters) acc))]
      [else (> (f (car counters)) (f acc))
            (sort-helper f (cdr counters) acc)]))
  
(define (min-tt counters) 
  (sort-helper counter-tt (closed-counters counters '()) (car (closed-counters counters '()))))
(define (min-et counters)
  (sort-helper counter-tt (closed-counters counters '()) (car (closed-counters counters '()))))

(define (closed-counters counters acc)
  (if (null? counters) acc
      (if (= 0 (counter-status (car counters))) (closed-counters (cdr counters) acc)
          (closed-counters (cdr counters) (cons  (car counters) acc)))))


(define (remove-first-from-counter C)  
   (if (stream-empty?  (queue-left (dequeue (counter-queue C))))
      (struct-copy counter C [tt 0]
               [et 0]
               [queue (dequeue (counter-queue C))])
  (struct-copy counter C [tt  (+ (sum-tt (queue-left (dequeue (counter-queue C))) 0) (sum-tt (queue-right (dequeue (counter-queue C))) 0))]
               [et (cdr (top (dequeue (counter-queue C))))]
               [queue (dequeue (counter-queue C))])))


    (define (sum-tt queue sum)
      (if (null? queue) sum
          (sum-tt (cdr queue) (+ sum (cdr (car queue))))))


(define (pass-time-through-counter minutes)
  (λ (C)
    (if (and (stream-empty? (queue-left (counter-queue C))) (null? (queue-right (counter-queue C))) (> minutes (counter-tt C)))
        (struct-copy counter C [tt 0]
                     [et 0])
        (struct-copy counter C [tt (- (counter-tt C) minutes)]
                     [et (- (counter-et C) minutes)]))))
; TODO
; Implementați funcția care simulează fluxul clienților pe la case.
; ATENȚIE: Față de etapa 3, apare un nou tip de cerere, așadar
; requests conține 5 tipuri de cereri (cele moștenite din etapa 3 plus una nouă):
;   - (<name> <n-items>) - persoana <name> trebuie așezată la coadă la o casă              (ca înainte)
;   - (delay <index> <minutes>) - casa <index> este întârziată cu <minutes> minute         (ca înainte)
;   - (ensure <average>) - cât timp tt-ul mediu al caselor este mai mare decât
;                          <average>, se adaugă case fără restricții (case slow)           (ca înainte)
;   - <x> - trec <x> minute de la ultima cerere, iar starea caselor se actualizează
;           corespunzător (cu efect asupra câmpurilor tt, et, queue)                       (ca înainte)
;   - (close <index>) - casa index este închisă                                            (   NOU!   )
; Sistemul trebuie să proceseze cele 5 tipuri de cereri în ordine, astfel:
; - persoanele vor fi distribuite la casele DESCHISE cu tt minim; nu se va întâmpla
;   niciodată ca o persoană să nu poată fi distribuită la nicio casă                       (mică modificare)
; - când o casă suferă o întârziere, tt-ul și et-ul ei cresc (chiar dacă nu are clienți);
;   nu aplicați vreun tratament special caselor închise                                    (ca înainte)
; - tt-ul mediu (ttmed) se calculează pentru toate casele DESCHISE, 
;   iar la nevoie veți adăuga case slow una câte una, până când ttmed <= <average>         (mică modificare)
; - când timpul prin sistem avansează cu <x> minute, tt-ul, et-ul și queue-ul tuturor 
;   caselor se actualizează pentru a reflecta trecerea timpului; dacă unul sau mai mulți 
;   clienți termină de stat la coadă, ieșirile lor sunt contorizate în ordine cronologică. (ca înainte)
; - când o casă se închide, ea nu mai primește clienți noi; clienții care erau deja acolo
;   avansează normal, până la ieșirea din supermarket                                    
; Rezultatul funcției serve va fi o pereche cu punct între:
; - lista sortată cronologic a clienților care au părăsit supermarketul:
;   - fiecare element din listă va avea forma (index_casă . nume)
;   - dacă mai mulți clienți ies simultan, sortați-i crescător după indexul casei
; - lista cozilor (de la case DESCHISE sau ÎNCHISE) care încă au clienți:
;   - fiecare element va avea forma (index_casă . coadă) (coada este de tip queue)
;   - lista este sortată după indexul casei
(define (serve requests fast-counters slow-counters)
  (serve-helper requests fast-counters slow-counters '()))

  (define (serve-helper requests fast-counters slow-counters clienti)
  (if (null? requests)
      (cons clienti (return-func (append fast-counters slow-counters) '()))
      
      (match (car requests)

       
        [(list 'ensure average) 
         (serve-helper (cdr requests) fast-counters (func fast-counters slow-counters average) clienti)]
        
        [(list 'close index) (serve-helper (cdr requests) (update status+ fast-counters index) (update status+ slow-counters index) clienti)]
        
         [(list name n-items)
          (if (>= ITEMS n-items)
               (serve-helper (cdr requests) (update (add-to-counter name n-items) fast-counters (car (min-tt (append fast-counters slow-counters))))
                (update (add-to-counter name n-items) slow-counters (car (min-tt (append fast-counters slow-counters)))) clienti)
            (serve-helper (cdr requests) fast-counters (update (add-to-counter name n-items) slow-counters (car (min-tt slow-counters))) clienti))]
        
        [(list 'delay index minutes) (serve-helper (cdr requests) (update (et+ minutes) (update (tt+ minutes) fast-counters index) index)
                                              (update (et+ minutes) (update (tt+ minutes) slow-counters index) index) clienti)])))
        

       
        
        
;returneaza casele care mai au ceva in coada
(define (return-func counters acc)
  (if (null? counters) acc
      (if (queue-empty? (counter-queue (car counters))) (return-func (cdr counters) acc)
          (return-func (cdr counters) (append acc (list (cons (counter-index (car counters)) (counter-queue (car counters)))))))))
          
 ;returneaza lista de clienti care ies         
(define (counters-clients counters acc minutes)
       (if (null? (func-filters counters)) (cons acc (pass-time-all-counters counters '() minutes))
           (if (> (car (min-et counters)) minutes) (cons acc (pass-time-all-counters counters '() minutes))
               (counters-clients (exit counters (car (min-et counters)) '())
                                 (cons acc (func-et counters (min-et counters) '())) minutes)))) 

;func care intoarcele casele dupa ce am scos oamenii
(define (exit counters et0 acc)
  (if (null? counters) acc
  (if (= et0 (counter-et (car counters))) (exit (cdr counters) et0 (cons acc (remove-first-from-counter (car counters))))
      (exit counters et0 acc))))

              
;func care trece et pe la fiecare casa
(define (func-et counters et0 acc)
  (if (null? counters) acc
      (if (= et0 (counter-et (car counters))) (func-et (cdr counters) et0 (cons acc (car counters)))
         (func-et (cdr counters) et0 acc))))

;trece timp pe la toate casele
(define (pass-time-all-counters L acc minutes)
  (if (null? L) (reverse acc)
      (pass-time-all-counters (cdr L) (cons acc (pass-time-through-counter  minutes)) minutes)))

;inchide casa
(define status+
         (lambda (C)
           (match C
               [(counter index tt status et queue) (counter index tt (- status 1) et queue)])))
;calc suma-average
(define (func counters1 counters2 average)
    (if (<= (/ (suma-tt (append counters1 counters2) 0) (length (append counters1 counters2))) average) counters2
        (func counters1 (append counters2 (list (make-counter (+ (counter-index (last counters2)) 1) 0 1 0 (make-queue empty-stream '() 0 0)))) average)))

;calc suma tt-urilor pentru toate casele
(define (suma-tt counters sum)
    (if (null? counters) sum
        (if (= 1 (counter-status (car counters)))
        (suma-tt (cdr counters) (+ sum (counter-tt (car counters))))
        (suma-tt (cdr counters) sum))))
;coada nevida
(define (func-filters counters)
    (filter
     (lambda (x)
      (not (and (null? (queue-left (counter-queue x))) (null? (queue-right (counter-queue x)))))) counters))

  
(define C1 (empty-counter 1))
(define C2 (empty-counter 2))
(define C3 (empty-counter 3))
(define C4 (empty-counter 4))