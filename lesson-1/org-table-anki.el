;;; org-table-anki.el --- Export Org tables for Anki -*- lexical-binding: t; -*-

;; Load this file, then run M-x gothic-anki-export-file from a table or supply
;; the source table and output file names.

(require 'cl-lib)
(require 'org-table)
(require 'subr-x)

(defun gothic-anki--source-file (source)
  "Return SOURCE's file name, or nil for a non-file buffer."
  (if (bufferp source)
      (buffer-file-name source)
    (expand-file-name source)))

(defun gothic-anki--interactive-source ()
  "Use the table at point, or prompt for an Org table file."
  (if (org-at-table-p)
      (current-buffer)
    (let* ((current-file (buffer-file-name))
           (directory (and current-file (file-name-directory current-file))))
      (expand-file-name
       (read-file-name "Org table file: " directory current-file t
                       (and current-file
                            (file-name-nondirectory current-file)))
       directory))))

;;;###autoload
(defun gothic-anki-export-file (source target)
  "Export the Org table in SOURCE to TARGET as TSV for Anki.
SOURCE may be a file name or a buffer with point in an Org table.
Interactively, use the table at point, or prompt for a source file.
The first table row supplies Anki column names.  The next row
must be a horizontal rule and then after that at least one
non-empty row is required.  Ask before replacing TARGET when called
interactively.  Return the output path."
  (interactive
   (let* (;; `table-source' can be either a filename or a buffer.
          (table-source (gothic-anki--interactive-source))
          ;; The input with the extension replaced with `.tsv' is a good
          ;; starting suggestion
          (suggested (concat
                      (file-name-sans-extension
                       (or (gothic-anki--source-file table-source)
                           (expand-file-name (buffer-name table-source))))
                      ".tsv"))
          (directory (file-name-directory suggested)))
     (list table-source
           (expand-file-name
            (read-file-name "TSV output file: " directory suggested nil
                            (file-name-nondirectory suggested))
            directory))))
  (let* ((source-file (gothic-anki--source-file source))
         (source-label (or source-file (buffer-name source)))
         (target (expand-file-name target))
         (table (if (bufferp source)
                    (with-current-buffer source
                      (unless (org-at-table-p)
                        (error "Point is not in an Org table: %s" source-label))
                      (save-excursion (org-table-to-lisp)))
                  (with-temp-buffer
                    (insert-file-contents source-file)
                    (goto-char (point-min))
                    (org-table-to-lisp))))
         (rows (cl-remove 'hline table))
         (header (car rows))
         (data (cdr rows))
         (width (length header)))
    (unless (eq (cadr table) 'hline)
      (error "%s needs a horizontal rule in the second row" source-label))
    (when (and source-file
               (or (equal source-file target)
                   (and (file-exists-p target)
                        (file-equal-p source-file target))))
      (error "Source and output must be different files: %s" source-label))
    (unless (and (>= width 2) data)
      (error "%s needs a header and at least one data row" source-label))
    (when (cl-some #'string-empty-p header)
      (error "%s has an empty column name" source-label))
    (cl-loop for row in data
             for number from 1
             do (unless (= (length row) width)
                  (error "%s data row %d has %d columns; expected %d"
                         source-label number (length row) width))
             do (when (or (string-empty-p (nth 0 row))
                          (string-empty-p (nth 1 row)))
                  (error "%s data row %d has an empty required field"
                         source-label number))
             do (when (cl-some (lambda (cell)
                                 (string-match-p "[\t\n\r]" cell)) row)
                  (error "%s data row %d contains a tab or newline"
                         source-label number)))
    (when (and (called-interactively-p 'any)
               (file-exists-p target)
               (not (y-or-n-p (format "Overwrite %s? " target))))
      (user-error "Export canceled"))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file target
        (insert "#separator:tab\n#columns:"
                (orgtbl-to-tsv (list header) nil) "\n"
                (orgtbl-to-tsv data nil) "\n")))
    (when (called-interactively-p 'interactive)
      (message "Wrote %s (%d✕%d)" target width (length data)))
    target))

(provide 'org-table-anki)
;;; org-table-anki.el ends here
