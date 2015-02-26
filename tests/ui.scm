;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013, 2014, 2015 Ludovic Courtès <ludo@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.


(define-module (test-ui)
  #:use-module (guix ui)
  #:use-module (guix profiles)
  #:use-module (guix store)
  #:use-module (guix derivations)
  #:use-module ((guix scripts build)
                #:select (%standard-build-options))
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-19)
  #:use-module (srfi srfi-64)
  #:use-module (ice-9 regex))

;; Test the (guix ui) module.

(define %paragraph
  "GNU Guile is an implementation of the Scheme programming language, with
support for many SRFIs, packaged for use in a wide variety of environments.
In addition to implementing the R5RS Scheme standard and a large subset of
R6RS, Guile includes a module system, full access to POSIX system calls,
networking support, multiple threads, dynamic linking, a foreign function call
interface, and powerful string processing.")

(define guile-1.8.8
  (manifest-entry
    (name "guile")
    (version "1.8.8")
    (item "/gnu/store/...")
    (output "out")))

(define guile-2.0.9
  (manifest-entry
    (name "guile")
    (version "2.0.9")
    (item "/gnu/store/...")
    (output "out")))

(define-syntax-rule (with-environment-variable variable value body ...)
  "Run BODY with VARIABLE set to VALUE."
  (let ((orig (getenv variable)))
    (dynamic-wind
      (lambda ()
        (setenv variable value))
      (lambda ()
        body ...)
      (lambda ()
        (if orig
            (setenv variable orig)
            (unsetenv variable))))))


(test-begin "ui")

(test-equal "parse-command-line"
  '((argument . "bar") (argument . "foo")
    (cores . 10)                                  ;takes precedence
    (substitutes? . #f) (keep-failed? . #t)
    (max-jobs . 77) (cores . 42))

  (with-environment-variable "GUIX_BUILD_OPTIONS" "-c 42 -M 77"
    (parse-command-line '("--keep-failed" "--no-substitutes"
                          "--cores=10" "foo" "bar")
                        %standard-build-options
                        (list '()))))

(test-equal "parse-command-line and --no options"
  '((argument . "foo")
    (substitutes? . #f))                          ;takes precedence

  (with-environment-variable "GUIX_BUILD_OPTIONS" "--no-substitutes"
    (parse-command-line '("foo")
                        %standard-build-options
                        (list '((substitutes? . #t))))))

(test-assert "fill-paragraph"
  (every (lambda (column)
           (every (lambda (width)
                    (every (lambda (line)
                             (<= (string-length line) width))
                           (string-split (fill-paragraph %paragraph
                                                         width column)
                                         #\newline)))
                  '(15 30 35 40 45 50 60 70 80 90 100)))
   '(0 5)))

(test-assert "fill-paragraph, consecutive newlines"
  (every (lambda (width)
           (any (lambda (line)
                  (string-prefix? "When STR" line))
                (string-split
                 (fill-paragraph (procedure-documentation fill-paragraph)
                                 width)
                 #\newline)))
         '(15 20 25 30 40 50 60)))

(test-equal "fill-paragraph, large unbreakable word"
  '("Here is a" "very-very-long-word"
    "and that's" "it.")
  (string-split
   (fill-paragraph "Here is a very-very-long-word and that's it."
                   10)
   #\newline))

(test-equal "fill-paragraph, two spaces after period"
  "First line.  Second line"
  (fill-paragraph "First line.
Second line" 24))

(test-equal "package-specification->name+version+output"
  '(("guile" #f "out")
    ("guile" "2.0.9" "out")
    ("guile" #f "debug")
    ("guile" "2.0.9" "debug")
    ("guile-cairo" "1.4.1" "out"))
  (map (lambda (spec)
         (call-with-values
             (lambda ()
               (package-specification->name+version+output spec))
           list))
       '("guile"
         "guile-2.0.9"
         "guile:debug"
         "guile-2.0.9:debug"
         "guile-cairo-1.4.1")))

(test-equal "integer"
  '(1)
  (string->generations "1"))

(test-equal "comma-separated integers"
  '(3 7 1 4 6)
  (string->generations "3,7,1,4,6"))

(test-equal "closed range"
  '(4 5 6 7 8 9 10 11 12)
  (string->generations "4..12"))

(test-equal "closed range, equal endpoints"
  '(3)
  (string->generations "3..3"))

(test-equal "indefinite end range"
  '(>= 7)
  (string->generations "7.."))

(test-equal "indefinite start range"
  '(<= 42)
  (string->generations "..42"))

(test-equal "integer, char"
  #f
  (string->generations "a"))

(test-equal "comma-separated integers, consecutive comma"
  #f
  (string->generations "1,,2"))

(test-equal "comma-separated integers, trailing comma"
  #f
  (string->generations "1,2,"))

(test-equal "comma-separated integers, chars"
  #f
  (string->generations "a,b"))

(test-equal "closed range, start > end"
  #f
  (string->generations "9..2"))

(test-equal "closed range, chars"
  #f
  (string->generations "a..b"))

(test-equal "indefinite end range, char"
  #f
  (string->generations "a.."))

(test-equal "indefinite start range, char"
  #f
  (string->generations "..a"))

(test-equal "duration, 1 day"
  (make-time time-duration 0 (* 3600 24))
  (string->duration "1d"))

(test-equal "duration, 1 week"
  (make-time time-duration 0 (* 3600 24 7))
  (string->duration "1w"))

(test-equal "duration, 1 month"
  (make-time time-duration 0 (* 3600 24 30))
  (string->duration "1m"))

(test-equal "duration, 1 week == 7 days"
  (string->duration "1w")
  (string->duration "7d"))

(test-equal "duration, 1 month == 30 days"
  (string->duration "1m")
  (string->duration "30d"))

(test-equal "duration, integer"
  #f
  (string->duration "1"))

(test-equal "duration, char"
  #f
  (string->duration "d"))

(test-equal "size->number, bytes"
  42
  (size->number "42"))

(test-equal "size->number, MiB"
  (* 42 (expt 2 20))
  (size->number "42MiB"))

(test-equal "size->number, GiB"
  (* 3 (expt 2 30))
  (size->number "3GiB"))

(test-equal "size->number, 1.2GiB"
  (inexact->exact (round (* 1.2 (expt 2 30))))
  (size->number "1.2GiB"))

(test-equal "size->number, 1T"
  (expt 2 40)
  (size->number "1T"))

(test-assert "size->number, invalid unit"
  (catch 'quit
    (lambda ()
      (size->number "9X"))
    (lambda args
      #t)))

(test-equal "show-what-to-build, zero outputs"
  ""
  (with-store store
    (let ((drv (derivation store "zero" "/bin/sh" '()
                           #:outputs '())))
      (with-error-to-string
       (lambda ()
         ;; This should print nothing.
         (show-what-to-build store (list drv)))))))

(test-assert "show-manifest-transaction"
  (let* ((m (manifest (list guile-1.8.8)))
         (t (manifest-transaction (install (list guile-2.0.9)))))
    (with-store store
      (and (string-match "guile\t1.8.8 → 2.0.9"
                         (with-fluids ((%default-port-encoding "UTF-8"))
                           (with-error-to-string
                            (lambda ()
                              (show-manifest-transaction store m t)))))
           (string-match "guile\t1.8.8 -> 2.0.9"
                         (with-fluids ((%default-port-encoding "ISO-8859-1"))
                           (with-error-to-string
                            (lambda ()
                              (show-manifest-transaction store m t)))))))))

(test-end "ui")


(exit (= (test-runner-fail-count (test-runner-current)) 0))

;;; Local Variables:
;;; eval: (put 'with-environment-variable 'scheme-indent-function 2)
;;; End:
