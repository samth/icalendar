#lang racket/base
;; MIME grammar, boundaries and content-transfer decoding belong to net/mime.
(require net/mime racket/list racket/port racket/string "private/ics.rkt")
(provide read-calendar-mime calendar-part-events (struct-out ical-part))
(struct ical-part (name method calendar error) #:transparent)
(define (read-calendar-mime source #:max-bytes [limit (* 4 1024 1024)])
  (unless (exact-positive-integer? limit) (raise-argument-error 'read-calendar-mime "exact-positive-integer?" limit))
  (define bytes (cond [(bytes? source) source] [(string? source) (string->bytes/utf-8 source)]
                      [(input-port? source) (read-bytes (add1 limit) source)]
                      [else (raise-argument-error 'read-calendar-mime "(or/c bytes? string? input-port?)" source)]))
  (when (or (eof-object? bytes) (zero? (bytes-length bytes)) (> (bytes-length bytes) limit))
    (raise (exn:fail:ical "iCalendar MIME: empty input or input exceeds byte limit" (current-continuation-marks) #f)))
  (define message
    (with-handlers ([exn:fail? (lambda (_) (raise (exn:fail:ical "iCalendar MIME: malformed MIME document" (current-continuation-marks) #f)))])
      (mime-analyze bytes)))
  (define (visit message depth)
    (when (> depth 32) (raise (exn:fail:ical "iCalendar MIME: nesting exceeds limit" (current-continuation-marks) #f)))
    (define e (message-entity message))
    (define filename (disposition-filename (entity-disposition e)))
    (define calendar? (or (and (eq? (entity-type e) 'text) (eq? (entity-subtype e) 'calendar))
                          (and (string? filename) (string-suffix? (string-downcase filename) ".ics"))))
    (cond
      [calendar?
       (define name (if (and (string? filename) (non-empty-string? filename)) filename "Calendar invitation"))
       (define method (let ([p (or (assoc "method" (entity-params e)) (assoc 'method (entity-params e)))]) (if p (string-upcase (cdr p)) "")))
       (list (with-handlers ([exn:fail? (lambda (_) (ical-part name method #f "Could not parse this calendar part."))])
         (define decoded (call-with-output-bytes (entity-body e)))
         (define charset (string-downcase (format "~a" (entity-charset e))))
         (define utf8
           (if (member charset '("utf-8" "utf8" "us-ascii")) decoded
               (call-with-output-bytes (lambda (out)
                 (define in (reencode-input-port (open-input-bytes decoded) charset #f #t))
                 (copy-port in out) (close-input-port in)))))
         (ical-part name method (parse-ics utf8 #:max-bytes limit) #f)))]
      [else (append-map (lambda (part) (visit part (add1 depth))) (entity-parts e))]))
  (visit message 0))
(define (calendar-part-events part)
  (define cal (ical-part-calendar part))
  (cond [(not cal) '()]
        [else
         (define methods (component-properties cal "METHOD"))
         (define method (ical-part-method part))
         (define effective
           (if (or (pair? methods) (string=? method "")) cal
               (struct-copy ical-component cal [properties (append (ical-component-properties cal) (list (ical-property "METHOD" (hash) method)))])))
         (for/list ([event (in-list (calendar-events effective))])
           (if (and (pair? methods) (non-empty-string? method) (not (string-ci=? method (ical-event-method event))))
               (struct-copy ical-event event [warnings (append (ical-event-warnings event) '("MIME method differs from calendar METHOD; calendar METHOD used"))])
               event))]))
