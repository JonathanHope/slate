;;; slate.el --- Master TODO list.

;; Copyright (C) 2019 Jonathan Hope

;; Author: Jonathan Hope <jonathan.douglas.hope@gmail.com>
;; Version: 1.0
;; Package-Requires ()
;; Keywords: todo

;; TODO: Add ability to exclude archive directory.
;; TODO: Add priority filtering.
;; TODO: Add tag filtering.
;; TODO: Add ability to truncate tag length.

;;; Commentary:

;; slate is a major mode that gathers the TODOS from all org files in a directory.
;; Those TODOS are then displayed in a list that can be used to visit those files.

;;; Code:

(require 'cl)

;; Customization

(defgroup slate nil
  "Emacs Slate mode."
  :group 'local)

(defcustom slate-directory (expand-file-name "~/Notes/")
  "Directory containing org files to find TODOs in."
  :type 'directory
  :safe 'stringp
  :group 'slate)

(defcustom slate-rg "rg"
  "Location of ripgrep executable."
  :type 'string
  :group 'slate)

(defcustom slate-todo-limit 0
  "Number of TODOs to render. No limit if zero."
  :type 'number
  :group 'slate)

(defcustom slate-file-name-limit 40
  "Max length of file name."
  :type 'number
  :group 'slate)

(defcustom slate-ellipsis "..."
  "What to denote a truncated string with."
  :type 'string
  :group 'slate)

(defcustom slate-ellipsis-length 3
  "The actual width of the ellipsis. The character could be double width."
  :type 'number
  :group 'slate)

(defcustom slate-show-tags t
  "Whether to show tags or not."
  :type 'boolean
  :group 'slate)

;; Faces

(defgroup slate-faces nil
  "Faces used in Slate mode"
  :group 'slate
  :group 'faces)

(defface slate-header-face
  '((t :inherit font-lock-keyword-face :bold t))
  "Face for Slate header."
  :group 'slate-faces)

(defface slate-file-name-face
  '((t :inherit font-lock-function-name-face :bold t))
  "Face for Slate file name."
  :group 'slate-faces)

(defface slate-divider-face
  '((t :inherit font-lock-builtin-face :bold t))
  "Face for Slate file name line number divider."
  :group 'slate-faces)

(defface slate-line-number-face
  '((t :inherit font-lock-function-name-face :bold t))
  "Face for Slate line number."
  :group 'slate-faces)

(defface slate-todo-face
  '((t :inherit font-lock-string-face))
  "Face for Slate TODO."
  :group 'slate-faces)

(defface slate-priority-a-face
  '((t :inherit font-lock-warning-face :bold t))
  "Face for Slate priority a indicator."
  :group 'slate-faces)

(defface slate-priority-b-face
  '((t :inherit font-lock-variable-name-face :bold t))
  "Face for Slate priority b indicator."
  :group 'slate-faces)

(defface slate-priority-c-face
  '((t :inherit font-lock-type-face :bold t))
  "Face for Slate priority c indicator."
  :group 'slate-faces)

(defface slate-filter-text-face
  '((t :inherit font-lock-builtin-face))
  "Face for Slate priority c indicator."
  :group 'slate-faces)

(defface slate-tags-face
  '((t :inherit font-lock-doc-string-face))
  "Face for Slate priority c indicator."
  :group 'slate-faces)

;; Constants

(defconst slate-buffer "*Slate*"
  "Slate buffer name.")

(defconst slate-file-name-line-number-divider ":"
  "The printed divider between the file name and the line number.")

(defconst slate-tag-divider ","
  "The divider between tags.")

(defconst slate-priority-length 1
  "The length of the printed priority.")

(defconst slate-priority-spacer-length 1
  "The length of the printed spacer between the priority and the file name.")

(defconst slate-file-name-line-number-divider-length 1
  "The length of the printed divider between the file name and the line number.")

(defconst slate-line-number-todo-text-divider-length 1
  "The length of the printed divider between the line number and the todo text.")

(defconst slate-todo-text-tags-divider-length 1
  "The length of the printed divider between the todo text and the tags.")

;; Variables

(defvar slate-todos nil
  "The unfiltered TODOs gathered from the org files.")

(defvar slate-filtered-todos nil
  "The filtered TODOs that are displayed in the slate buffer.")

(defvar slate-max-file-name-length nil
  "The length of the longest file name in the slate-todos list.")

(defvar slate-window-width nil
  "The current width of the window containing the slate buffer.")

(defvar slate-current-regex-filter ""
  "The current regex filter being applied to the TODOs.")

;; Keymap definition

(defvar slate-mode-map
  (let ((i 0)
        (map (make-keymap)))

    (setq i 48)
    (while (< i 58)
      (define-key map (vector i) 'slate-filter-increment)
      (setq i (1+ i)))

    (setq i 65)
    (while (< i 91)
      (define-key map (vector i) 'slate-filter-increment)
      (setq i (1+ i)))

    (setq i 97)
    (while (< i 123)
      (define-key map (vector i) 'slate-filter-increment)
      (setq i (1+ i)))

    (define-key map (kbd "SPC") 'slate-filter-increment)
    (define-key map (kbd "DEL") 'slate-filter-decrement)
    (define-key map (kbd "RET") 'slate-open)
    map)
  "Keymap for Slate mode.")

;; Low level helpers

(defun slate-get-current-line-number ()
  "Get the line number the cursor is on currently."
  (interactive)
  (save-restriction
    (widen)
    (save-excursion
      (beginning-of-line)
      (1+ (count-lines 1 (point))))))

(defun slate-append (list value)
  "Append something to a list."
  (append list (list value)))


(defun slate-get-window-width ()
  "Return current width of window displaying `slate-buffer'."
  (- (window-text-width) 1))

(defun slate-buffer-visible-p ()
  "Return non-nil if a window is displaying `slate-buffer'."
  (and (get-buffer-window slate-buffer)
       (not (window-minibuffer-p))))

(defun slate-join-strings (strings seperator)
  "Join strings together using a seperator string."
  (mapconcat 'identity strings seperator))

(defun slate-sort-strings (strings)
  "Sort a list of strings."
  (cl-sort strings 'string-lessp))

;; Building the model

(defun slate-ripgrep-todos ()
  "Use ripgrep to find all of the TODO items in org files in a directory."
  (when default-directory
    (shell-command-to-string (concat slate-rg " --line-number --no-messages --color never --no-heading \"^[*][*]* ?TODO \" --iglob \"*.org\" "  default-directory))))

(defun slate-string-to-lines (ripgrep-output)
  "Split a string into lines."
  (when ripgrep-output
    (split-string ripgrep-output "\n")))

(defun slate-filter-empty-strings (todos)
  "Filter empty lines out of a list of lines."
  (when todos
    (seq-filter (lambda (todo)
                  (not (string= todo "")))
                todos)))

(defun slate-remove-drive-letters (todos)
  "Remove any Windows driver letters from a list of strings."
  (when todos
    (mapcar (lambda (todo)
              (replace-regexp-in-string "^[a-zA-Z]:/" "" todo))
            todos)))

(defun slate-get-file-paths (todos)
  "Get the full file paths from the todos."
  (when todos
    (mapcar (lambda (todo)
              (replace-regexp-in-string ":[0-9]+:.*" "" todo))
            todo-lines-non-empty)))

(defun slate-get-priorities (todos)
  "Get the priorities from the todos."
  (when todos
    (let ((regex "\\(\\[#[A-C]\\]\\)"))
      (mapcar (lambda (todo)
                (if (string-match-p regex todo)
                    (progn
                      (string-match "\\(\\[#[A-C]\\]\\)" todo)
                      (substring (match-string 0 todo) 2 -1))
                  " "))
              todos))))

(defun slate-tokenize (todos)
  "Tokenize a list of strings by :."
  (when todos
    (mapcar (lambda (todo)
              (split-string todo ":"))
            todos)))

(defun slate-filter-todo-text (todo-text)
  "Filter to just the todo text."
  (when todo-text
    (string-trim
     (replace-regexp-in-string "^[*][*]* ?TODO \\(\\[#[A-C]\\]\\)?" "" todo-text))))

(defun slate-calc-file-name-length (file-name line-number)
  "Get the length of the filename for a todo item."
  (if (and file-name line-number)
      (let* ((file-name-length (if (> (length file-name) slate-file-name-limit)
                                   slate-file-name-limit
                                 (length file-name)))
             (file-name-length-with-line-number (+ file-name-length
                                                   (length (number-to-string line-number))
                                                   slate-file-name-line-number-divider-length)))
        file-name-length-with-line-number)
    0))

(defun slate-build-todos (todos file-paths priorities)
  "Build the final todos list object."
  (when (and todos file-paths priorities)
    (let ((index 0)
          (processed-todos '()))
      (while (< index (length todos))
        (let* ((todo (nth index todos))
               (file-name (file-name-nondirectory (nth 0 todo)))
               (line-number (string-to-number (nth 1 todo)))
               (priority (nth index priorities))
               (todo-text (slate-filter-todo-text (nth 2 todo)))
               (file-path (nth index file-paths))
               (file-name-length (slate-calc-file-name-length file-name line-number))
               (tags (slate-sort-strings (slate-filter-empty-strings (seq-drop todo 3)))))
          (setq index (1+ index))
          (setq processed-todos (slate-append processed-todos
                                              (let ((todo-hash-table (make-hash-table :test 'equal)))
                                                (puthash "file-name" file-name todo-hash-table)
                                                (puthash "line-number" line-number todo-hash-table)
                                                (puthash "priority" priority todo-hash-table)
                                                (puthash "todo-text" todo-text todo-hash-table)
                                                (puthash "file-path" file-path todo-hash-table)
                                                (puthash "file-name-length" file-name-length todo-hash-table)
                                                (puthash "tags" tags todo-hash-table)
                                                todo-hash-table)))))
      processed-todos)))

(defun slate-sort-todos (todos)
  "Sort the todos into priority buckets."
  (when todos
    (let ((priority-a-todos '())
          (priority-b-todos '())
          (priority-c-todos '())
          (priority-none-todos '()))
      (progn
        (dolist (todo todos)
          (let ((priority (gethash "priority" todo)))
            (cond ((equal "A" priority)
                   (setq priority-a-todos (slate-append priority-a-todos todo)))
                  ((equal "B" priority)
                   (setq priority-b-todos (slate-append priority-b-todos todo)))
                  ((equal "C" priority)
                   (setq priority-c-todos (slate-append priority-c-todos todo)))
                  ((equal " " priority)
                   (setq priority-none-todos (slate-append priority-none-todos todo))))))
        (append priority-none-todos
                priority-a-todos
                priority-b-todos
                priority-c-todos)))))

(defun slate-find-todos ()
  "Find all of the TODOs in org files in a given directory."
  (let* ((rg-output (slate-ripgrep-todos))
         (todo-lines (slate-string-to-lines rg-output))
         (todo-lines-non-empty (slate-filter-empty-strings todo-lines))
         (todo-lines-non-empty-no-drive-letter (slate-remove-drive-letters todo-lines-non-empty))
         (full-file-paths (slate-get-file-paths todo-lines-non-empty))
         (priorities (slate-get-priorities todo-lines-non-empty))
         (todos-tokens (slate-tokenize todo-lines-non-empty-no-drive-letter))
         (todos (slate-build-todos todos-tokens full-file-paths priorities))
         (sorted-todos (slate-sort-todos todos)))
    (setq slate-todos sorted-todos)))

;; Filtering the model.

(defun slate-filter-todos-regex (todos)
  "Filter the text of the TODO with the current regex filer."
  (if (not (equal "" slate-current-regex-filter))
      (seq-filter (lambda (todo)
                    (let ((todo-text (gethash "todo-text" todo)))
                      (string-match-p slate-current-regex-filter todo-text)))
                  todos)
    todos))

(defun slate-limit-todos (todos)
  "Limit the number of TODOs that are being rendered."
  (when todos
    (if (< 0 slate-todo-limit)
        (seq-take todos slate-todo-limit)
      todos)))

(defun slate-filter-todos ()
  "Apply any filters to the current TODOs."
  (let* ((regex-filtered-todos (slate-filter-todos-regex slate-todos))
         (limited-todos (slate-limit-todos regex-filtered-todos)))
    (setq slate-filtered-todos limited-todos)))

;; Geometry calculations.

(defun slate-find-max-file-name-length (todos)
  "Find the length of the longest file name amongst the file names of the TODOs."
  (if todos
      (let ((file-name-lengths (mapcar (lambda (todo)
                                         (gethash "file-name-length" todo))
                                       todos)))
        (reduce #'max file-name-lengths))
    0))

(defun slate-calculate-geometry ()
  "Do any calcualtions needed to draw the UI later."
  (with-current-buffer slate-buffer
    (let ((max-file-name-length (slate-find-max-file-name-length slate-filtered-todos))
          (window-width (slate-get-window-width)))
      (setq slate-max-file-name-length max-file-name-length)
      (setq slate-window-width window-width))))

;; Binding the model to the UI

(defun slate-truncate-string (value max-length)
  "Truncate a string to a length and append an ellipsis to it."
  (if (> (length value) max-length)
      (concat (substring value 0 (- max-length slate-ellipsis-length)) slate-ellipsis)
    value))

(defun slate-draw-header ()
  "Print the header to slate buffer."
  (let ((inhibit-read-only t))
    (if (not (equal slate-current-regex-filter ""))
        (progn
          (insert (propertize "Slate: " 'face 'slate-header-face))
          (insert (propertize slate-current-regex-filter 'face 'slate-filter-text-face))
          (insert "\n\n"))
      (progn
        (insert (propertize "Slate" 'face 'slate-header-face))
        (insert "\n\n")))))

(defun slate-draw-todo (todo)
  "Print the TODOs to the slate buffer."
  (let* ((priority (gethash "priority" todo))
         (file-name (slate-truncate-string (gethash "file-name" todo) slate-file-name-limit))
         (line-number (gethash "line-number" todo))
         (file-name-length (gethash "file-name-length" todo))
         (file-name-spacer-length (if (< file-name-length slate-max-file-name-length)
                                      (- slate-max-file-name-length file-name-length)
                                    0))
         (left-section-length (+ slate-priority-length
                                 slate-priority-spacer-length
                                 file-name-length
                                 file-name-spacer-length
                                 slate-line-number-todo-text-divider-length))
         (tags (gethash "tags" todo))
         (right-section (if slate-show-tags (slate-join-strings tags ", ") ""))
         (right-section-length (length right-section))
         (todo-text-limit (- slate-window-width
                             left-section-length
                             right-section-length
                             (if slate-show-tags slate-todo-text-tags-divider-length 0)))
         (todo-text (slate-truncate-string (gethash "todo-text" todo) todo-text-limit))
         (todo-text-length (length todo-text))
         (inhibit-read-only t))
    (cond ((equal "A" priority) (insert (propertize priority 'face 'slate-priority-a-face)))
          ((equal "B" priority) (insert (propertize priority 'face 'slate-priority-b-face)))
          ((equal "C" priority) (insert (propertize priority 'face 'slate-priority-c-face)))
          ((equal " " priority) (insert " ")))
    (insert " ")
    (insert (propertize file-name 'face 'slate-file-name-face))
    (insert (propertize ":" 'face 'slate-divider-face))
    (insert (propertize (number-to-string line-number) 'face 'slate-line-number-face))
    (if (< file-name-length slate-max-file-name-length)
        (insert (make-string (- slate-max-file-name-length
                                file-name-length)
                             ? )))
    (insert " ")
    (insert (propertize todo-text 'face 'slate-todo-face))
    (if (and slate-show-tags
             (> right-section-length 0))
        (progn
          (insert " ")
          (insert (make-string (- slate-window-width
                                  left-section-length
                                  todo-text-length
                                  right-section-length
                                  slate-todo-text-tags-divider-length)
                               ? ))
          (insert (propertize right-section 'face 'slate-tags-face))))
    (insert "\n")))

(defun slate-draw ()
  (interactive)
  (with-current-buffer slate-buffer
    (let ((inhibit-read-only t))
      (erase-buffer))
    (remove-overlays)
    (slate-draw-header)
    (if (executable-find slate-rg)
        (progn
          (if (eq 0 (length slate-todos))
              (let ((inhibit-read-only t))
                (insert "Nothing slated."))
            (mapc 'slate-draw-todo slate-filtered-todos))
          (goto-char (point-min))
          (forward-line 2)
          (forward-char 0))
      (let ((inhibit-read-only t))
        (insert "Ripgrep not found.")))))

;; Externally useful functions

(defun slate-refresh ()
  "Refresh the TODO list."
  (interactive)
  (slate-find-todos)
  (slate-filter-todos)
  (slate-calculate-geometry)
  (slate-draw))

;; Events

(defun slate-window-size-changed (frame)
  "Handle the window size changing."
  (when (and (slate-buffer-visible-p))
    (slate-calculate-geometry)
    (slate-draw)))

(defun slate-open ()
  "Open the file under the cursor and go to the line number of the TODO."
  (interactive)
  (let* ((current-line-number (slate-get-current-line-number))
         (todo-index (- current-line-number 3)))
    (if (and (>= todo-index 0)
             (< todo-index (length slate-filtered-todos)))
        (let* ((todo (nth todo-index slate-filtered-todos))
               (file-path (gethash "file-path" todo))
               (line-number (gethash "line-number" todo)))
          (find-file file-path)
          (goto-line line-number)))))

(defun slate-filter-increment ()
  "Add a character to the current slate filter."
  (interactive)
  (let* ((char last-command-event)
         (char-as-string (char-to-string char)))
    (setq slate-current-regex-filter (concat slate-current-regex-filter char-as-string))
    (slate-filter-todos)
    (slate-calculate-geometry)
    (slate-draw)))

(defun slate-filter-decrement ()
  "Remove a character from the current slate filter."
  (interactive)
  (unless (equal slate-current-regex-filter "")
    (setq slate-current-regex-filter (substring slate-current-regex-filter 0 -1))
    (slate-filter-todos)
    (slate-calculate-geometry)
    (slate-draw)))

;; Mode definition

(put 'slate-mode 'mode-class 'special)

(defun slate-mode ()
  "Major mode for quickly viewing all org TODOs in a directory."
  (kill-all-local-variables)
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (if (file-directory-p slate-directory)
      (setq default-directory (expand-file-name slate-directory)))
  (when (fboundp 'visual-line-mode)
    (visual-line-mode 0))
  (use-local-map slate-mode-map)
  (setq major-mode 'slate-mode)
  (setq mode-name "Slate")
  (add-hook 'window-size-change-functions
            'slate-window-size-changed t)
  (slate-refresh))

(put 'slate-mode 'mode-class 'special)

;;;###autoload
(defun slate ()
  "Switch to *Slate* buffer and gather TODOs."
  (interactive)
  (switch-to-buffer slate-buffer)
  (if (not (eq major-mode 'slate-mode))
      (slate-mode)))

(provide 'slate)

;; slate.el ends here
