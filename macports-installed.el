;;; macports-installed.el --- A porcelain for MacPorts -*- lexical-binding: t; -*-

;; Copyright (C) 2022 Aaron Madlon-Kay

;; Author: Aaron Madlon-Kay
;; Version: 0.1.0
;; URL: https://github.com/amake/.emacs.d
;; Package-Requires: ((emacs "25.1"))
;; Keywords: convenience

;; This file is not part of GNU Emacs.

;; macports-installed.el is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 3, or (at your option) any later version.
;;
;; flutter-gen.el is distributed in the hope that it will be useful, but WITHOUT ANY
;; WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
;; A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License along with
;; macports-installed.el.  If not, see http://www.gnu.org/licenses.

;;; Commentary:

;; A porcelain for MacPorts: major mode for managing installed ports

;;; Code:

(require 'macports-core)
(require 'macports-describe)
(require 'subr-x)

;;;###autoload
(defun macports-installed ()
  "List installed ports."
  (interactive)
  (pop-to-buffer "*macports-installed*")
  (macports-installed-mode))

(defvar macports-installed-columns
  [("Port" 32 t)
   ("Version" 48 t)
   ("Active" 8 t)
   ("Requested" 10 t)
   ("Leaf" 8 t)]
  "Columns to be shown in `macports-installed-mode'.")

(defvar macports-installed-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'macports-installed-describe-port)
    (define-key map (kbd "c") #'macports-installed-port-contents)
    (define-key map (kbd "e") #'macports-installed-edit-port)
    (define-key map (kbd "u") #'macports-installed-mark-uninstall)
    (define-key map (kbd "U") #'macports-installed-mark-inactive)
    (define-key map (kbd "l") #'macports-installed-mark-leaves)
    (define-key map (kbd "a") #'macports-installed-mark-toggle-activate)
    (define-key map (kbd "r") #'macports-installed-mark-toggle-requested)
    (define-key map (kbd "x") #'macports-installed-exec)
    (define-key map (kbd "DEL") #'macports-installed-backup-unmark)
    (define-key map (kbd "?") #'macports)
    map)
  "Keymap for `macports-installed-mode'.")

(defun macports-installed-describe-port ()
  "Show details about the current port."
  (interactive)
  (macports-describe-port (elt (tabulated-list-get-entry) 0)))

(defun macports-installed-port-contents ()
  "Show contents of the current port."
  (interactive)
  (macports-describe-port-contents (elt (tabulated-list-get-entry) 0)))

(defun macports-installed-edit-port ()
  "Open portfile for the current port."
  (interactive)
  (macports-edit-portfile (elt (tabulated-list-get-entry) 0)))

(defun macports-installed-mark-uninstall (&optional _num)
  "Mark a port for uninstall and move to the next line."
  (interactive "p")
  (tabulated-list-put-tag "U" t))

(defun macports-installed-mark-toggle-activate (&optional _num)
  "Mark a port for activate/deactivate and move to the next line."
  (interactive "p")
  (let ((active (macports-installed-item-active-p)))
    (cond ((and active (eq (char-after) ?D))
           (tabulated-list-put-tag " " t))
          ((and (not active) (eq (char-after) ?A))
           (tabulated-list-put-tag " " t))
          (active (tabulated-list-put-tag "D" t))
          ((not active) (tabulated-list-put-tag "A" t)))))

(defun macports-installed-item-active-p ()
  "Return non-nil if the current item is activated."
  (not (string-empty-p (elt (tabulated-list-get-entry) 2))))

(defun macports-installed-mark-inactive ()
  "Mark all inactive ports for uninstall."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (if (macports-installed-item-active-p)
          (forward-line)
        (macports-installed-mark-uninstall)))))

(defun macports-installed-item-leaf-p ()
  "Return non-nil if the current item is a leaf."
  (not (string-empty-p (elt (tabulated-list-get-entry) 4))))

(defun macports-installed-mark-leaves ()
  "Mark all leaf ports for uninstall."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (if (macports-installed-item-leaf-p)
          (macports-installed-mark-uninstall)
        (forward-line)))))

(defun macports-installed-item-requested-p ()
  "Return non-nil if the current item is requested."
  (not (string-empty-p (elt (tabulated-list-get-entry) 3))))

(defun macports-installed-mark-toggle-requested (&optional _num)
  "Mark a port as requested/unrequested and move to the next line."
  (interactive "p")
  (let ((requested (macports-installed-item-requested-p)))
    (cond ((and requested (eq (char-after) ?r))
           (tabulated-list-put-tag " " t))
          ((and (not requested) (eq (char-after) ?R))
           (tabulated-list-put-tag " " t))
          (requested (tabulated-list-put-tag "r" t))
          ((not requested) (tabulated-list-put-tag "R" t)))))

(defun macports-installed-backup-unmark ()
  "Back up one line and clear any marks on that port."
  (interactive)
  (forward-line -1)
  (tabulated-list-put-tag " "))

(defun macports-installed-exec ()
  "Perform marked actions."
  (interactive)
  (let (uninstall deactivate activate requested unrequested)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (cond ((eq (char-after) ?U)
               (push (tabulated-list-get-entry) uninstall))
              ((eq (char-after) ?D)
               (push (tabulated-list-get-entry) deactivate))
              ((eq (char-after) ?A)
               (push (tabulated-list-get-entry) activate))
              ((eq (char-after) ?R)
               (push (tabulated-list-get-entry) requested))
              ((eq (char-after) ?r)
               (push (tabulated-list-get-entry) unrequested)))
        (forward-line)))
    (if (or uninstall deactivate activate requested unrequested)
        (when (macports-installed-prompt-transaction-p uninstall deactivate activate requested unrequested)
          (let ((uninstall-cmd (when uninstall
                                 (macports-privileged-command
                                  `("-N" "uninstall" ,@(macports-installed-list-to-args uninstall)))))
                (deactivate-cmd (when deactivate
                                  (macports-privileged-command
                                   `("-N" "deactivate" ,@(macports-installed-list-to-args deactivate)))))
                (activate-cmd (when activate
                                (macports-privileged-command
                                 `("-N" "activate" ,@(macports-installed-list-to-args activate)))))
                (requested-cmd (when requested
                                 (macports-privileged-command
                                  `("-N" "setrequested" ,@(macports-installed-list-to-args requested)))))
                (unrequested-cmd (when unrequested
                                   (macports-privileged-command
                                    `("-N" "unsetrequested" ,@(macports-installed-list-to-args unrequested))))))
            (macports-core--exec
             (string-join
              (remq nil (list uninstall-cmd deactivate-cmd activate-cmd requested-cmd unrequested-cmd))
              " && ")
             (macports-core--revert-buffer-func))))
      (user-error "No ports specified"))))

(defun macports-installed-prompt-transaction-p (uninstall deactivate activate requested unrequested)
  "Prompt the user about UNINSTALL, DEACTIVATE, ACTIVATE, REQUESTED, UNREQUESTED."
  (y-or-n-p
   (concat
    (when uninstall
      (format
       "Ports to uninstall: %s.  "
       (macports-installed-list-to-prompt uninstall)))
    (when deactivate
      (format
       "Ports to deactivate: %s.  "
       (macports-installed-list-to-prompt deactivate)))
    (when activate
      (format
       "Ports to activate: %s.  "
       (macports-installed-list-to-prompt activate)))
    (when requested
      (format
       "Ports to set as requested: %s.  "
       (macports-installed-list-to-prompt requested)))
    (when unrequested
      (format
       "Ports to set as unrequested: %s.  "
       (macports-installed-list-to-prompt unrequested)))
    "Proceed? ")))

(defun macports-installed-list-to-prompt (entries)
  "Format ENTRIES for prompting."
  (format "%d (%s)"
          (length entries)
          (mapconcat
           (lambda (entry) (concat (elt entry 0) (elt entry 1)))
           entries
           " ")))

(defun macports-installed-list-to-args (entries)
  "Format ENTRIES as command arguments."
  (apply #'nconc (mapcar
                  (lambda (entry) `(,(elt entry 0) ,(elt entry 1)))
                  entries)))

(define-derived-mode macports-installed-mode tabulated-list-mode "MacPorts installed"
  "Major mode for handling a list of installed MacPorts ports."
  (setq tabulated-list-format macports-installed-columns)
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key `("Port" . nil))
  (add-hook 'tabulated-list-revert-hook #'macports-installed-refresh nil t)
  (tabulated-list-init-header))

(defun macports-installed-refresh ()
  "Refresh the list of installed ports."
  (let ((installed (macports-installed--installed-items))
        (leaves (make-hash-table :test #'equal))
        (requested (make-hash-table :test #'equal)))
    (mapc (lambda (e) (puthash e t leaves))
          (macports-installed--leaf-items))
    (mapc (lambda (e) (puthash e t requested))
          (macports-installed--requested-items))
    (setq tabulated-list-entries
          (mapcar
           (lambda (e)
             (let ((name (nth 0 e))
                   (version (nth 1 e))
                   (active (nth 2 e)))
               (list
                (concat name version)
                (vector
                 name
                 version
                 (if active "Yes" "")
                 (if (gethash name requested) "Yes" "")
                 (if (gethash name leaves) "Yes" "")))))
           installed))))

(defun macports-installed--installed-items ()
  "Return linewise output of `port installed'."
  (let ((output (string-trim (shell-command-to-string "port -q installed"))))
    (unless (string-empty-p output)
      (mapcar
       (lambda (line) (split-string (string-trim line)))
       (split-string output "\n")))))

(defun macports-installed--leaf-items ()
  "Return linewise output of `port echo leaves'."
  (let ((output (string-trim (shell-command-to-string "port -q echo leaves"))))
    (unless (string-empty-p output)
      (split-string output))))

(defun macports-installed--requested-items ()
  "Return linewise output of `port echo requested'."
  (let ((output (string-trim (shell-command-to-string "port -q echo requested"))))
    (unless (string-empty-p output)
      (split-string output))))

(provide 'macports-installed)
;;; macports-installed.el ends here
