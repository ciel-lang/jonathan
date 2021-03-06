(in-package :cl-user)
(defpackage jonathan.encode
  (:use :cl
        :jonathan.util)
  (:import-from :fast-io
                :fast-write-byte
                :make-output-buffer
                :finish-output-buffer)
  (:import-from :trivial-types
                :association-list-p)
  (:export :write-key
           :write-value
           :write-key-value
           :with-object
           :with-array
           :write-item
           :with-output
           :*octets*
           :*from*
           :*stream*
           :to-json
           :%to-json
           :%write-char
           :%write-string))
(in-package :jonathan.encode)

(defvar *octets* nil "Default value of octets used by #'to-json.")

(defvar *from* nil "Default value of from used by #'to-json.")

(defvar *stream* nil "Stream used by #'to-json.")

(declaim (inline %write-string))
(defun %write-string (string)
  "Write string to *stream*."
  (declare (type simple-string string)
           (optimize (speed 3) (safety 0) (debug 0)))
  (if *octets*
      (loop for c across string
            do (fast-write-byte (char-code c) *stream*))
      (write-string string *stream*))
  nil)

(declaim (inline %write-char))
(defun %write-char (char)
  "Write character to *stream*."
  (declare (type character char)
           (optimize (speed 3) (safety 0) (debug 0)))
  (if *octets*
      (fast-write-byte (char-code char) *stream*)
      (write-char char *stream*))
  nil)

(declaim (inline string-to-json))
(defun string-to-json (string)
  (declare (type simple-string string)
           (optimize (speed 3) (safety 0) (debug 0)))
  (macrolet ((escape (char pairs)
               (declare (type list pairs))
               (let* ((sorted (sort (copy-list pairs) #'char<= :key #'car))
                      (min-char (caar sorted))
                      (max-char (caar (last sorted))))
                 `(if (and (char<= ,char ,max-char)
                           (char>= ,char ,min-char))
                      (cond
                        ,@(mapcar #'(lambda (pair)
                                      `((char= ,char ,(car pair))
                                        (%write-string ,(cdr pair))))
                                  pairs)
                        (t (%write-char ,char)))
                      (%write-char ,char)))))
    (%write-char #\")
    (loop for char of-type character across string
          do (escape char ((#\Newline . "\\n")
                           (#\Return . "\\r")
                           (#\Tab . "\\t")
                           (#\" . "\\\"")
                           (#\\ . "\\\\"))))
    (%write-char #\")))

#+allegro
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro with-macro-p (list)
  `(and (consp ,list)
        (member (car ,list) '(with-object with-array)))))

#-allegro
(defmacro with-macro-p (list)
  `(and (consp ,list)
        (member (car ,list) '(with-object with-array))))

(defmacro write-key (key)
  "Write key part of object."
  (declare (ignore key)))

(defmacro write-value (value)
  "Write value part of object."
  (declare (ignore value)))

(defmacro write-key-value (key value)
  "Write key and value of object."
  (declare (ignore key value)))

(defmacro with-object (&body body)
  "Make writing object safe."
  (let ((first (gensym "first")))
    `(let ((,first t))
       (macrolet ((write-key (key)
                    `(progn
                       (if ,',first
                           (setq ,',first nil)
                           (%write-char #\,))
                       (string-to-json (princ-to-string ,key))))
                  (write-value (value)
                    `(progn
                       (%write-char #\:)
                       ,(if (with-macro-p value)
                            value
                            `(%to-json ,value))))
                  (write-key-value (key value)
                    `(progn
                       (write-key ,key)
                       (write-value ,value))))
         (%write-char #\{)
         ,@body
         (%write-char #\})))))

(defmacro write-item (item)
  "Write item of array."
  (declare (ignore item)))

(defmacro with-array (&body body)
  "Make writing array safe."
  (let ((first (gensym "first")))
    `(let ((,first t))
       (macrolet ((write-item (item)
                    `(progn
                       (if ,',first
                           (setq ,',first nil)
                           (%write-char #\,))
                       ,(if (with-macro-p item)
                            item
                            `(%to-json ,item)))))
         (%write-char #\[)
         ,@body
         (%write-char #\])))))

(defmacro with-output ((stream) &body body)
  "Bind *stream* to stream."
  `(let ((*stream* ,stream))
     ,@body))

(declaim (inline alist-to-json))
(defun alist-to-json (list)
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (with-object
    (loop for (key . value) in list
          do (write-key-value key value))))

(declaim (inline plist-to-json))
(defun plist-to-json (list)
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (with-object
    (loop for (key value) on list by #'cddr
          do (write-key-value key value))))

(declaim (inline list-to-json))
(defun list-to-json (list)
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (with-array
    (loop for item in list
          do (write-item item))))

(defun to-json (obj &key (octets *octets*) (from *from*))
  "Convert LISP object to JSON String."
  (declare (optimize (speed 3) (safety 0) (debug 0)))
  (let ((*stream* (if octets
                      (make-output-buffer :output :vector)
                      (make-string-output-stream)))
        (*octets* octets)
        (*from* from))
    (%to-json obj)
    (if octets
        (finish-output-buffer *stream*)
        (get-output-stream-string *stream*))))

(defgeneric %to-json (obj)
  (:documentation "Write obj as JSON string."))

(defmethod %to-json ((string string))
  (if (typep string 'simple-string)
      (string-to-json string)
      (string-to-json (coerce string 'simple-string))))

(defmethod %to-json ((number number))
  (%write-string (princ-to-string number)))

(defmethod %to-json ((float float))
  (%write-string (format nil "~f" float)))

(defmethod %to-json ((ratio ratio))
  (%write-string (princ-to-string (coerce ratio 'float))))

(defmethod %to-json ((list list))
  (cond
    ((and (eq *from* :alist)
          (association-list-p list)
          ;; check if is alist key atom.
          (atom (caar list)))
     (alist-to-json list))
    ((and (eq *from* :jsown)
          (eq (car list) :obj))
     (alist-to-json (cdr list)))
    ((and (or (eq *from* :plist)
              (null *from*))
          (my-plist-p list))
     (plist-to-json list))
    (t (list-to-json list))))

(defmethod %to-json ((vector vector))
  (with-array
    (loop for item across vector
          do (write-item item))))

(defmethod %to-json ((hash hash-table))
  (with-object
    (loop for key being the hash-key of hash
            using (hash-value value)
          do (write-key-value key value))))

(defmethod %to-json ((symbol symbol))
  (string-to-json (symbol-name symbol)))

(defmethod %to-json ((_ (eql t)))
  (%write-string "true"))

(defmethod %to-json ((_ (eql :false)))
  (%write-string "false"))

(defmethod %to-json ((_ (eql :null)))
  (%write-string "null"))

(defmethod %to-json ((_ (eql :empty)))
  (%write-string "{}"))

(defmethod %to-json ((_ (eql nil)))
  (%write-string "[]"))
