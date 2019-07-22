;;; flymake-quickdef.el --- Quickly define a new Flymake backend  -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Karl Otness

;; Author: Karl Otness
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: languages, tools, convenience, lisp
;; URL: https://github.com/karlotness/flymake-quickdef

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package mainly defines `flymake-quickdef-backend', a macro
;; which helps remove some of the boilerplate code from defining new
;; Flymake backend functions. Consult the function's documentation for
;; full information on use. The macro defines a function which is
;; suitable for use with `flymake-diagnostic-functions' and handles
;; running the external process, creating and removing any necessary
;; files and buffers, and regex matches against diagnostic output.

;; Users defining a new check function with the macro provide Lisp
;; forms giving the command line arguments of the external process, a
;; regular expression to search its output, and Lisp forms to
;; processes the regex matches and produce arguments for
;; `flymake-make-diagnostic'.

;; See the documentation of `flymake-quickdef-backend' for more
;; information on how to use the macro.

;;; Code:

;; Flymake backend definition macro and support

(defvar-local flymake-quickdef--procs nil
  "Internal variable used by `flymake-quickdef-backend'.
Do not edit its value. This variable holds a plist used to store
handles to running processes for Flymake backends. Entries are
keyed by the symbol name of the appropriate backend function and
values are running processes.")

;;;###autoload
(defmacro flymake-quickdef-backend (name &optional docstring &rest defs)
  "Quickly define a backend for use with Flymake.
This macro produces a new function, NAME, which is suitable for
use with the variable `flymake-diagnostic-functions'. If a string
DOCSTRING is provided, it will be the documentation for the
function. The body of the function is generated based on values
provided to the macro in DEFS, described below.

Note that this macro *requires* `lexical-binding' to be enabled.

The backend generated by this function invokes an external
program on the contents of a buffer and processes its output. It
will be similar in operation to the example backend described in
the Info node `(flymake) An annotated example backend'.


Plist Symbols

The definitions provided in DEFS are a plist of values which
determine the operation of the Flymake backend. The possible
options are keyed by symbols :proc-form, :search-regexp,
:prep-diagnostic, and also :pre-let, :pre-check, and :write-type.
The first three of these are mandatory and the rest are optional.
Further details on the values for these entries are given below.


Available Variables

The macro also makes available a few variables which can be used
user-provided Lisp forms: fmqd-source and fmqd-temp-file.

The variable fmqd-source stores a reference to the buffer
containing the text being provided to the external program. This
is useful in cases where the Lisp form may need to inspect the
buffer contents.

In cases where :write-type is set to 'file, the variable
fmqd-temp-file is provided and stores a string giving the file
name of the temporary file created and provided to the external
program.


Body Definitions

The overall execution order of the Flymake backend first makes
use of (1) :write-type, (2) :pre-let, and (3) :pre-check. Next, a
process is created following (4) :proc-form. Once the process
exits, its output is searched by (5) :search-regexp and each
match is processed by (6) :prep-diagnostic. All of the
diagnostics with non-nil types are provided to Flymake.

:write-type (optional) is either 'pipe or 'file. If it is not
provided, the value is 'pipe. When :write-type is 'pipe the
external process is provided the buffer text on standard input.
When the value is 'file the buffer's contents are written to a
temporary file and this file name must be provided to the program
in :proc-form. In this case the variable fmqd-temp-file stores
the appropriate path and should be included in :proc-form. The
temporary file will be cleaned up by the macro.

:pre-let (optional) is a Lisp form suitable for use in `let*'.
The bindings are made early in the execution of the backend and
the bindings can be used in later forms. These bindings also have
access to the special variables discussed above.

:pre-check (optional) is a Lisp form which executes after the
:pre-let bindings are established, but before the external
process is launched. It can check conditions to ensure that
launching the external program is possible. If something is wrong
it should signal an error. As discussed in the Info
node `(flymake) Backend functions' and also in Info
node `(flymake) Backend exceptions' a signal thrown here will
cause the backend to be disabled.

:proc-form (mandatory) is a Lisp form which evaluates to a list
of strings, suitable for use in the :command argument to the
function `make-process'. Using the function `executable-find' may
be useful either here or in :pre-let.

:search-regexp (mandatory) is a regexp string which matches
output from the external process. `rx' can also be used here.

:prep-diagnostic (mandatory) is a Lisp form which evaluates to a
list of arguments suitable for the function
`flymake-make-diagnostic'. This form should process the matches
from :search-regexp to produce these values and will likely use
the function `flymake-diag-region' and the fmqd-source variable
described above."
  (declare (indent defun) (doc-string 2))
  (unless lexical-binding
    (error "Need lexical-binding for flymake-quickdef-backend (%s)" name))
  (let* ((def-docstring (when (stringp docstring) docstring))
         (def-plist (if (stringp docstring) defs (cons docstring defs)))
         (write-type (or (eval (plist-get def-plist :write-type)) 'pipe))
         (temp-dir-symb (make-symbol "fmqd-temp-dir"))
         (fmqd-err-symb (make-symbol "fmqd-err"))
         (cleanup-form (when (eq write-type 'file)
                         (list (list 'delete-directory temp-dir-symb t)))))
    (dolist (elem '(:proc-form :search-regexp :prep-diagnostic))
      (unless (plist-get def-plist elem)
        (error "Missing flymake backend definition `%s'" elem)))
    (unless (memq (eval (plist-get def-plist :write-type)) '(file pipe nil))
      (error "Invalid `:write-type' value `%s'" (plist-get def-plist :write-type)))
    `(defun ,name (report-fn &rest _args)
       ,def-docstring
       (let* ((fmqd-source (current-buffer))
              ;; If storing to a file, create the temporary directory
              ,@(when (eq write-type 'file)
                  `((,temp-dir-symb (make-temp-file "flymake-" t))
                    (fmqd-temp-file
                     (concat
                      (file-name-as-directory ,temp-dir-symb)
                      (file-name-nondirectory (or (buffer-file-name) (buffer-name)))))))
              ;; Next we do the :pre-let phase
              ,@(plist-get def-plist :pre-let))
         ;; With vars defined, do :pre-check
         (condition-case ,fmqd-err-symb
             (progn
               ,(plist-get def-plist :pre-check))
           (error ,@cleanup-form
                  (signal (car ,fmqd-err-symb) (cdr ,fmqd-err-symb))))
         ;; No errors so far, kill any running (obsolete) running processes
         (let ((proc (plist-get flymake-quickdef--procs ',name)))
           (when (process-live-p proc)
             (kill-process proc)))
         (save-restriction
           (widen)
           ;; If writing to a file, send the data to the temp file
           ,@(when (eq write-type 'file)
               '((write-region nil nil fmqd-temp-file nil 'silent)))
           (setq flymake-quickdef--procs
                 (plist-put flymake-quickdef--procs ',name
                            (make-process
                             :name ,(concat (symbol-name name) "-flymake")
                             :noquery t
                             :connection-type 'pipe
                             :buffer (generate-new-buffer ,(concat " *" (symbol-name name) "-flymake*"))
                             :command ,(plist-get def-plist :proc-form)
                             :sentinel
                             (lambda (proc _event)
                               ;; If the process is actually done we can continue
                               (unless (process-live-p proc)
                                 (unwind-protect
                                     (if (eq proc (plist-get (buffer-local-value 'flymake-quickdef--procs fmqd-source) ',name))
                                         ;; This is the current process
                                         ;; Widen the code buffer so we can compute line numbers, etc.
                                         (with-current-buffer fmqd-source
                                           (save-restriction
                                             (widen)
                                             ;; Scan the process output for errors
                                             (with-current-buffer (process-buffer proc)
                                               (goto-char (point-min))
                                               (save-match-data
                                                 (let ((diags nil))
                                                   (while (search-forward-regexp
                                                           ,(eval (plist-get def-plist :search-regexp))
                                                           nil t)
                                                     ;; Save match data to work around a bug in `flymake-diag-region'
                                                     ;; That function seems to alter match data and is commonly called here
                                                     (save-match-data
                                                       (save-excursion
                                                         (let ((d (apply 'flymake-make-diagnostic
                                                                         ,(plist-get def-plist :prep-diagnostic))))
                                                           ;; Skip any diagnostics with a type of nil
                                                           ;; This makes it easier to filter some out
                                                           (when (flymake-diagnostic-type d)
                                                             (push d diags))))))
                                                   (funcall report-fn (nreverse diags)))))))
                                       ;; Else case: this process is obsolete
                                       (flymake-log :warning "Canceling obsolete check %s" proc))
                                   ;; Unwind-protect cleanup forms
                                   ,@cleanup-form
                                   (kill-buffer (process-buffer proc))))))))
           ;; If piping, send data to process
           ,@(when (eq write-type 'pipe)
               `((let ((proc (plist-get flymake-quickdef--procs ',name)))
                   (process-send-region proc (point-min) (point-max))
                   (process-send-eof proc)))))))))

(provide 'flymake-quickdef)
;;; flymake-quickdef.el ends here
