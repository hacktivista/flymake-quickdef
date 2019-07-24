# Flymake-Quickdef
Quickly define a new [Flymake][flymake] backend

This package mainly defines `flymake-quickdef-backend`, a macro which
helps remove some of the boilerplate code from defining new Flymake
backend functions. The macro defines a function that is suitable to
register with Flymake and is similar in implementation to the
[example][example] in the Flymake manual.

New backend functions using the macro provide, minimally:

1. A Lisp form producing command line arguments for a program
2. A regular expression to search the process output
3. A Lisp form to convert the regex matches into Flymake diagnostics

The process of spawning the process and maintaining temporary files
and buffers is generated by the macro. The macro definitions work
similarly to [Flycheck's macro][fly-checker]. This makes it easier to
define Flymake diagnostics using external linters and other programs.

## Usage
Below is an example Flymake backend produced using the macro. It uses
[Bandit][bandit] to check Python source code and shows an example of
using a tool which requires a temporary file. The macro handles
creating the temporary file to reflect the (possibly unsaved) state of
the buffer, running the external process, and cleaning up.

```elisp
(flymake-quickdef-backend flymake-check-bandit
  :pre-let ((bandit-exec (executable-find "bandit")))
  :pre-check (unless bandit-exec (error "Cannot find bandit executable"))
  :write-type 'file
  :proc-form (list bandit-exec "--format" "custom" "--msg-template" "diag:{line} {severity} {test_id}: {msg}" fmqd-temp-file)
  :search-regexp "^diag:\\([[:digit:]]+\\) \\(HIGH\\|LOW\\|MEDIUM\\|UNDEFINED\\) \\([[:alpha:]][[:digit:]]+\\): \\(.*\\)$"
  :prep-diagnostic
  (let* ((lnum (string-to-number (match-string 1)))
         (severity (match-string 2))
         (code (match-string 3))
         (text (match-string 4))
         (pos (flymake-diag-region fmqd-source lnum))
         (beg (car pos))
         (end (cdr pos))
         (type (cond
                ((string= severity "HIGH") :error)
                ((string= severity "MEDIUM") :warning)
                (t :note)))
         (msg (format "%s (%s)" text code)))
    (list fmqd-source beg end type msg)))
```

Once the backend is defined, just arrange for it to be added to
`flymake-diagnostic-functions`, for example in a mode hook.

## License
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

Please see [LICENSE.txt](LICENSE.txt) for a copy of the license.

[flymake]: https://www.gnu.org/software/emacs/manual/html_node/flymake/index.html
[example]: https://www.gnu.org/software/emacs/manual/html_node/flymake/An-annotated-example-backend.html
[fly-checker]: https://www.flycheck.org/en/latest/developer/developing.html#writing-the-checker
[bandit]: https://github.com/PyCQA/bandit
