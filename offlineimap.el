;;; offlineimap.el --- Run OfflineIMAP from Emacs

;; Copyright (C) 2010 Julien Danjou

;; Author: Julien Danjou <julien@danjou.info>
;; URL: http://julien.danjou.info/offlineimap-el.html

;; This file is NOT part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; M-x offlineimap

;; We need comint for `comint-truncate-buffer'
(require 'comint)

(defgroup offlineimap nil
  "Run OfflineIMAP."
  :group 'comm)

(defcustom offlineimap-buffer-name "*OfflineIMAP*"
  "Name of the buffer used to run offlineimap."
  :group 'offlineimap
  :type 'string)

(defcustom offlineimap-command "offlineimap -u Machine.MachineUI"
  "Command to run to launch OfflineIMAP."
  :group 'offlineimap
  :type 'string)

(defcustom offlineimap-buffer-maximum-size comint-buffer-maximum-size
  "The maximum size in lines for OfflineIMAP buffer."
  :group 'offlineimap
  :type 'integer)

(defcustom offlineimap-enable-mode-line-p '(eq major-mode 'gnus-group-mode)
  "Whether enable OfflineIMAP mode line status display.
This form is evaluated and its return value determines if the
OfflineIMAP status should be displayed in the mode line."
  :group 'offlineimap)

(defvar offlineimap-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'offlineimap-quit)
    (define-key map (kbd "g") 'offlineimap-resync)
    map)
  "Keymap for offlineimap-mode.")

(defface offlineimap-msg-acct-face
  '((t (:foreground "purple")))
  "Face used to highlight acct lines.")

(defface offlineimap-msg-connecting-face
  '((t (:foreground "gray")))
  "Face used to highlight connecting lines.")

(defface offlineimap-msg-syncfolders-face
  '((t (:foreground "blue")))
  "Face used to highlight syncfolders lines.")

(defface offlineimap-msg-syncingfolders-face
  '((t (:foreground "cyan")))
  "Face used to highlight syncingfolders lines.")

(defface offlineimap-msg-skippingfolder-face
  '((t (:foreground "cyan")))
  "Face used to highlight skippingfolder lines.")

(defface offlineimap-msg-loadmessagelist-face
  '((t (:foreground "green")))
  "Face used to highlight loadmessagelist lines.")

(defface offlineimap-msg-syncingmessages-face
  '((t (:foreground "blue")))
  "Face used to highlight syncingmessages lines.")

(defface offlineimap-msg-copyingmessage-face
  '((t (:foreground "orange")))
  "Face used to highlight copyingmessage lines.")

(defface offlineimap-msg-deletingmessages-face
  '((t (:foreground "red")))
  "Face used to highlight deletingmessages lines.")

(defface offlineimap-msg-deletingmessage-face
  '((t (:foreground "red")))
  "Face used to highlight deletingmessage lines.")

(defface offlineimap-msg-addingflags-face
  '((t (:foreground "yellow")))
  "Face used to highlight addingflags lines.")

(defface offlineimap-msg-deletingflags-face
  '((t (:foreground "pink")))
  "Face used to highlight deletingflags lines.")

(defface offlineimap-error-face
  '((t (:foreground "red" :weight bold)))
  "Face used to highlight status when offlineimap is stopped.")

(defvar offlineimap-mode-line-string nil
  "Variable showed in mode line to display OfflineIMAP status.")

(put 'offlineimap-mode-line-string 'risky-local-variable t) ; allow properties

(defun offlineimap-make-buffer ()
  "Get the offlineimap buffer."
  (let ((buffer (get-buffer-create offlineimap-buffer-name)))
    (with-current-buffer buffer
      (offlineimap-mode))
    buffer))

(defun offlineimap-propertize-face (msg-type action text)
  "Propertize TEXT with correct face according to MSG-TYPE and ACTION."
  (let* ((face-sym (intern (concat "offlineimap-" msg-type "-" action "-face"))))
    (if (facep face-sym)
        (propertize text 'face face-sym)
      text)))

(defun offlineimap-update-mode-line (process)
  "Update mode line information about OfflineIMAP PROCESS."
  (setq offlineimap-mode-line-string
        (concat " [OfflineIMAP: "
                (let ((status (process-status process)))
                  (if (eq status 'run)
                      (let ((msg-type (process-get process :last-msg-type))
                            (action (process-get process :last-action)))
                        (offlineimap-propertize-face msg-type action action))
                    (propertize (symbol-name status) 'face 'offlineimap-error-face)))
                "]"))
  (force-mode-line-update))

(defun offlineimap-process-filter (process msg)
  "Filter PROCESS output MSG."
  (let* ((msg-data (split-string msg ":"))
         (msg-type (nth 0 msg-data))
         (action (nth 1 msg-data))
         (thread-name (nth 2 msg-data))
         (buffer (process-buffer process)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert (offlineimap-propertize-face
                   msg-type
                   action
                   (concat thread-name "::" action "\n")))
        (set-marker (process-mark process) (point))
        (let ((comint-buffer-maximum-size offlineimap-buffer-maximum-size))
          (comint-truncate-buffer))))
    (process-put process :last-msg-type msg-type)
    (process-put process :last-action action))
  (offlineimap-update-mode-line process))

(defun offlineimap-process-sentinel (process state)
  "Monitor STATE change of PROCESS."
  (offlineimap-update-mode-line process))

(defun offlineimap-mode-line ()
  "Return a string to display in mode line."
  (when (eval offlineimap-enable-mode-line-p)
    offlineimap-mode-line-string))

;;;###autoload
(defun offlineimap ()
  "Start OfflineIMAP."
  (interactive)
  (let* ((buffer (offlineimap-make-buffer)))
    (unless (get-buffer-process buffer)
      (let ((process (start-process-shell-command
                      "offlineimap"
                      buffer
                      offlineimap-command)))
        (set-process-filter process 'offlineimap-process-filter)
        (set-process-sentinel process 'offlineimap-process-sentinel))))
  (add-to-list 'global-mode-string '(:eval (offlineimap-mode-line)) t))

(defun offlineimap-quit ()
  "Quit OfflineIMAP."
  (interactive)
  (kill-buffer (current-buffer)))

(defun offlineimap-resync ()
  "Send a USR1 signal to OfflineIMAP to force accounts synchronization."
  (interactive)
  (signal-process (get-buffer-process (get-buffer offlineimap-buffer-name)) 'SIGUSR1))

(define-derived-mode offlineimap-mode fundamental-mode "OfflineIMAP"
  "A major mode for OfflineIMAP interaction."
  :group 'comm)

(provide 'offlineimap)
