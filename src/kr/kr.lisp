
(in-package :kr)

(defun g-local-value-fn (schema slot)
  "Similar to g-value-fn, but no inheritance."
  (g-value-body schema slot NIL T))

(defun g-value-inherit-values (schema slot is-leaf slot-structure)
  (declare (ftype (function (t &optional t) t) formula-fn))
  (let (has-parents)
    (when (a-local-only-slot slot)
      (return-from g-value-inherit-values NIL))
    (dolist (relation *inheritance-relations*)
      (dolist (parent (if (eq relation :IS-A)
			  (get-local-value schema :IS-A)
			  (get-local-value schema relation)))
	(setf has-parents T)
	(let ((entry (slot-accessor parent slot))
	      (value *no-value*)
	      bits			; parent bits
	      (intermediate-constant NIL))
	  (when entry
	    (setf value (sl-value entry))
	    (when (is-constant (sl-bits entry))
	      (setf intermediate-constant T)))
	  (if (eq value *no-value*)
	      ;; Attempt to inherit from its ancestors.
	      (multiple-value-setq (value bits)
		(g-value-inherit-values parent slot NIL nil))
	      ;; If value, just set bits.
	      (setf bits (sl-bits entry)))
	  (unless (eq value *no-value*)
	    (let ((was-formula (formula-p value)))
	      (when was-formula
		;; Inherit the formula, making a copy of it.
		(setf value (formula-fn value (a-formula-cached-value value)))
		(setf (a-formula-schema value) schema)
		(setf (a-formula-slot value) slot)
		(set-cache-is-valid value NIL))
	      (when (and is-leaf slot-structure)	; slot had constant bit
		(setf bits (logior bits (sl-bits slot-structure))))
	      (when intermediate-constant
		(setf bits (logior *constant-mask* bits)))
	      )
	    (return-from g-value-inherit-values (values value bits))))))
    (set-slot-accessor schema slot
		       (if has-parents NIL *no-value*)
		       (cond (is-leaf
			      (if slot-structure
				  (logior *inherited-mask*
					  (sl-bits slot-structure))
				  *inherited-mask*))
			     (has-parents *inherited-parent-mask*)
			     (t		; top-level, no parents
			      *is-parent-mask*))
		       (slot-dependents slot-structure))
    *no-value*))

(defun g-value-no-copy (schema slot &optional skip-local)
  (unless skip-local
    ;; Is there a local value?
    (let ((value (slot-accessor schema slot)))
      (when value
	(return-from g-value-no-copy (sl-value value)))))
  ;; Now try inherited values.
  (dolist (relation *inheritance-relations*)
    (dolist (*schema-self* (if (eq relation :IS-A)
			       (get-local-value schema :IS-A)
			       (get-local-value schema relation)))
      (unless (eq *schema-self* schema)	; avoid infinite loops!
	(let ((value (g-value-no-copy *schema-self* slot)))
	  (when value
	    (return-from g-value-no-copy value)))))))


;;; PRINTING AND DEBUGGING

(declaim (fixnum *debug-names-length* *debug-index*))
(defparameter *debug-names-length* 500)

(defvar *debug-names* (make-array *debug-names-length* :initial-element nil))

(defvar *debug-index* -1)

(defvar *intern-unnamed-schemata* T
  "This variable may be set to NIL to prevent PS from automatically creating
  any unnamed schemata it prints out.")

(defun cache-schema-name (schema name)
  "This does not cause any creation of symbols.  It simply records
the schema in an array, thus creating a semi-permanent way to refer
to a schema."
  (unless (find-if #'(lambda (x)
		       (and x (eql (schema-name x) name)))
		   *debug-names*)
    ;; A new schema.  Store it in the next position (cycle if
    ;; we reach the end of the array).
    (setf (aref *debug-names*
		(setf *debug-index*
		      (mod (incf *debug-index*) *debug-names-length*)))
	  schema)))

;;
(defun make-new-schema-name (schema name)
  "Creates symbols for all automatic schema names that happen to
be printed out."
  (let* (
	 parent
	 (symbol
	  ;; (intern (cond ((stringp name)
	  ;; 		 ;; a name-prefix schema
	  ;; 		 (format nil "~A-~D"
	  ;; 			 name (incf *schema-counter*)))
	  ;; 		((setf parent
	  ;; 		       (if (formula-p schema)
	  ;; 			   (a-formula-is-a schema)
	  ;; 			   (when (not-deleted-p schema)
	  ;; 			     (car (get-local-value schema :IS-A)))))
	  ;; 		 (let ((parent-name (when parent (schema-name parent))))
	  ;; 		   (when (or (integerp parent-name)
	  ;; 			     (stringp parent-name))
	  ;; 		     ;; Parent is unnamed yet - force a name.
	  ;; 		     (with-output-to-string
	  ;; 			 (bit-bucket)
	  ;; 		       (print-the-schema parent bit-bucket 0))
	  ;; 		     (setf parent-name (schema-name parent)))
	  ;; 		   (format nil "~A-~D" parent-name name)))
	  ;; 		(t
	  ;; 		 (format nil "~C~D"
	  ;; 			 (if (formula-p schema) #\F #\S)
	  ;; 			 name)))
	  ;; 	  debug-package)
	   ))
    ;; (set symbol schema)
    ;; (setf (schema-name schema) symbol)
    ;; (export symbol debug-package)
    ))

(defun print-the-slot (slot stream level)
  (declare (ignore level))
  (format stream "<slot ~S  value ~S, bits ~S"
	  (sl-name slot) (sl-value slot) (sl-bits slot))
  (if (full-sl-p slot)
      (format stream ",  dependents ~S>" (full-sl-dependents slot))
      (format stream ">")))

(defun print-the-schema (schema stream level)
  (declare (ignore level))
  (let ((name (schema-name schema))
	(destroyed (not (not-deleted-p schema))))
    ;; This version is for debugging.  Record the latest schemata in the
    ;; array.
    (cond ((or (integerp name) (stringp name))
	   ;; This is a nameless schema.  Print it out, and record it in the
	   ;; debugging array.
	   (when *intern-unnamed-schemata*
	     (make-new-schema-name schema name))
	   (cache-schema-name schema name)
	   ;; This gives control over whether unnamed schemata are interned.
	   (setf name (schema-name schema)))
	  ((null name)
	   ;; This was a deleted schema
	   (setf name '*DESTROYED*)))
    (when destroyed (format stream "*DESTROYED*(was "))
    (if *print-as-structure*
	(progn
	  (format stream "#k<~S" name)
	  (dolist (slot *print-structure-slots*)
	    (let ((value (g-value schema slot)))
	      (when value
		(format stream " (~S ~S)" slot value))))
	  (format stream ">")
	  (when destroyed (format stream ")")))
	(progn
	  (format stream "~S" name)
	  (when destroyed (format stream ")"))))))


(defun name-for-schema (schema)
  "Given a schema, returns its printable name as a string.  The string
CANNOT be destructively modified.
Note that this returns the pure name, without the #k<> notation."
  (let ((name (schema-name schema)))
    (when (or (integerp name) (stringp name))
      ;; This is a nameless schema.  Print it out, and record it in the
      ;; debugging array.
      ;; (when *intern-unnamed-schemata*
      ;; 	(make-new-schema-name schema name))
      (cache-schema-name schema name)
      ;; This gives control over whether unnamed schemata are interned.
      (setf name (schema-name schema)))
    (symbol-name name)))


(defun s (number)
  "This is a debugging function which returns a schema, given its internal
number.  It only works if the schema was printed out rather recently,
i.e., if it is contained in the temporary array of names."
  (setf number (format nil "~D" number))
  (find-if #'(lambda (x)
	       (and x
		    (symbolp (schema-name x))
		    (do* ((name (symbol-name (schema-name x)))
			  (i (1- (length name)) (1- i))
			  (j (1- (length number)) (1- j)))
			 ((minusp j)
			  (unless (digit-char-p (schar name i))
			    x))
		      (unless (char= (schar name i) (schar number j))
			(return nil)))))
	   *debug-names*))



;;; RELATIONS

(defun unlink-one-value (schema slot value)	    ; e.g., child :is-a parent
  "Remove the inverse link from <value> to <schema>, following the inverse
of <slot>."
  (let ((inverse (cadr (assocq slot *relations*)))) ; e.g., is-a-inv
    (when inverse
      ;; If the relation has an INVERSE slot, remove <schema> from the
      ;; inverse slot.
      (let ((entry (slot-accessor value inverse)) ; e.g., A child B
	    values)
	(when entry
	  (setf values (sl-value entry))
	  (if (eq (car values) schema)
	      ;; <schema> is first in the inverse list
	      (set-slot-accessor value inverse (delete schema values)
				 (sl-bits entry) (slot-dependents entry))
	      ;; just do a destructive operation
	      (setf (cdr values) (delete schema (cdr values)))))))))

(defun unlink-all-values (schema slot)
  "Same as above, but unlinks all schemata that are in <slot>."
  (let ((inverse (cadr (assocq slot *relations*))))
    (when inverse
      (let ((entry (if (eq slot :IS-A)
		       (slot-accessor schema :IS-A)
		       (if (eq slot :IS-A-INV)
			   (slot-accessor schema :IS-A-INV)
			   (slot-accessor schema slot)))))
	(when entry
	  (dolist (parent (sl-value entry))
	    (when (not-deleted-p parent) ; parent is not destroyed
	      ;; If the terminal has an INVERSE slot, remove <schema> from the
	      ;; inverse slot.
	      (let ((entry (if (eq inverse :is-a-inv)
			       (slot-accessor parent :is-a-inv) ; e.g., A child B
			       (slot-accessor parent inverse)))
		    values)
		(when entry
		  (setf values (sl-value entry))
		  (if (eq (car values) schema)
		      (pop (sl-value entry))
		      (setf (cdr values) (delete schema (cdr values)))))))))))))


(defun link-in-relation (schema slot values)
  "Since the <values> are being added to <slot>, see if we need to put in an
inverse link to <schema> from each of the <values>.
This happens when <slot> is a relation with an inverse."
  (let ((inverse (if (eq slot :is-a)
		     :is-a-inv
		     (cadr (assocq slot *relations*)))))
    (when inverse
      ;; <values> is a list: cycle through them all
      (dolist (value values)
	(let* ((entry (if (eq slot :is-a)
			  (slot-accessor value :is-a-inv)
			  (slot-accessor value inverse)))
	       (previous-values (when entry (sl-value entry))))
	  (if entry
	      ;; Create the back-link.  We use primitives here to avoid looping.
	      (if (or *schema-is-new*
		      (not (memberq schema previous-values)))
		  ;; Handle an important special case efficiently.
		  (if (eq (sl-value entry) *no-value*)
		      ;; There was no value after all!
		      (setf (sl-value entry) (list schema))
		      ;; There were real values.
		      (push schema (sl-value entry))))
	      ;; There was no inverse in the parent yet.
	      (set-slot-accessor value inverse (list schema) *local-mask* nil)))))))


(defun check-relation-slot (schema slot values)
  "We are setting the <slot> (a relation) to <values>.  Check that the
latter contains valid relation entries.
RETURNS: <values> (or a list of a single value, if <values> is not a list)
if success; *no-value* if failure."
  (unless (listp values)
    (format
     t "S-VALUE: relation ~s in schema ~S should be given a list of values!~%"
     slot schema)
    (if (schema-p values)
	(setf values (list values))	; go ahead, use anyway.
	(return-from check-relation-slot *no-value*)))
  (dolist (value values)
    (unless (is-schema value)
      (when-debug
       (format
	t
	"S-VALUE: value ~s for relation ~s in ~s is not a schema!  Ignored.~%"
	value slot schema))
      (return-from check-relation-slot *no-value*)))
  (do ((value values (cdr value)))
      ((null value))
    (when (memberq (car value) (cdr value))
      (format
       t
       "Trying to set relation slot ~S in schema ~S with duplicate value ~S!~%"
       slot schema (car value))
      (format t "  The slot was not set.~%")
      (return-from check-relation-slot *no-value*)))
  values)


(declaim (inline inherited-p))
(defun inherited-p (schema slot)
  "Similar to HAS-SLOT-P, but when there is a formula checks whether this is
an inherited formula."
  (let ((entry (slot-accessor schema slot)))
    (when entry
      (or (is-inherited (sl-bits entry))
	  (and (formula-p (sl-value entry))
	       (formula-p (a-formula-is-a (sl-value entry))))))))

(defun formula-push (f)
;;  (bordeaux-threads:with-lock-held  (*formula-lock*)
    (push f *formula-pool*))

;;; encode types
(defparameter *types-table* (make-hash-table :test #'equal)
  "Hash table used to look up a Lisp type and returns its code")

;; (defparameter *types-table-lock* (bordeaux-threads:make-recursive-lock)
;;   "Lock to synchonize access to *types-table*")

(defmacro with-types-table-lock-held ((table) &body body)
  `(let ((,table *types-table*))
;;     (bordeaux-threads:with-recursive-lock-held (*types-table-lock*)
     ,@body))

(declaim (fixnum *types-array-inc*))
(defparameter *types-array-inc* 255) ;; allocate in blocks of this size

(declaim (fixnum *next-type-code*))
(defparameter *next-type-code*  0)   ;; next code to allocate

(defparameter types-array NIL
  "Array used to decode a number into its corresponding Lisp type.")

(defparameter type-fns-array NIL
  "Array used to decode a number into its corresponding type-fn.")

(defparameter type-docs-array NIL
  "Array used to decode a number into its corresponding documentation string.")

(declaim (inline code-to-type code-to-type-fn code-to-type-doc check-kr-type))

(defun code-to-type (type-code)
  (svref types-array type-code))

(defun code-to-type-fn (type-code)
  (svref type-fns-array type-code))

(defun code-to-type-doc (type-code)
  (svref type-docs-array type-code))

(defun check-kr-type (value code)
  (funcall (code-to-type-fn code) value))


(declaim (inline find-lisp-predicate))
(defun find-lisp-predicate (simple-type)
  "Given simple type ('NULL, 'KEYWORD, etc...), returns the name of
the lisp predicate to test this ('NULL, 'KEYWORDP, etc....)"
  (let ((p-name (concatenate 'string (symbol-name simple-type) "P"))
	(-p-name (concatenate 'string (symbol-name simple-type) "-P")))
    (cond ((memberq simple-type '(NULL ATOM)) simple-type)
	  (T (or (find-symbol p-name 'common-lisp)
		 (find-symbol -p-name 'common-lisp)
		 (find-symbol p-name)
		 (find-symbol -p-name)
		 (error "Could not find predicate for simple-type ~S~%"
			simple-type))))))

(defun make-lambda-body (complex-type)
  (with-types-table-lock-held (types-table)
    (let (code)
      (cond ((consp complex-type)	;; complex type (a list)
	     (let ((fn   (first complex-type))
		   (args (rest  complex-type)))
	       (case fn
		 ((OR AND NOT)
		  (cons fn (mapcar #'make-lambda-body args)))
		 (MEMBER
		  `(memberq value ',args))
		 ((IS-A-P IS-A)
		  `(is-a-p value ,(second complex-type)))
		 (SATISFIES
		  `(,(second complex-type) value))
		 ((INTEGER REAL)
		  (let* ((pred (find-lisp-predicate fn))
			 (lo (first args))
			 (lo-expr (when (and lo (not (eq lo '*)))
				    (if (listp lo)
					`((< ,(car lo) value))
					`((<= ,lo value)))))
			 (hi (second args))
			 (hi-expr (when (and hi (not (eq hi '*)))
				    (if (listp hi)
					`((> ,(car hi) value))
					`((>= ,hi value))))))
		    (if (or lo-expr hi-expr)
			`(and (,pred value) ,@lo-expr ,@hi-expr)
			`(,pred value))))
		 (T  (error "Unknown complex-type specifier: ~S~%" fn)))))
	    ((setq code (gethash (symbol-name complex-type) types-table))
	     ;; is this a def-kr-type?
	     (make-lambda-body (code-to-type code)))
	    (T ;; simple-type
	     (list (find-lisp-predicate complex-type) 'value))))))

(defun type-to-fn (type)
  "Given the Lisp type, construct the lambda expr, or return the
   built-in function"
  (with-types-table-lock-held (types-table)
    (let (code)
      (cond ((consp type)			; complex type
	     (if (eq (car type) 'SATISFIES)
		 (let ((fn-name (second type)))
		   `',fn-name) ;; koz
		 `(function (lambda (value)
		    (declare #.*special-kr-optimization*)
		    ,(make-lambda-body type)))))
	    ((setq code (gethash (symbol-name type) types-table))
	     ;; is this a def-kr-type?
	     (code-to-type-fn code))
	    (T
	     `',(find-lisp-predicate type))))))

(declaim (inline copy-extend-array))
(defun copy-extend-array (oldarray oldlen newlen)
  (let ((result (make-array newlen)))
    (dotimes (i oldlen)
      (setf (svref result i) (svref oldarray i)))
    result))


(defun get-next-type-code ()
  "Return the next available type-code, and extend the type arrays
if necessary."
  (let ((curlen (length types-array)))
   (when (>= *next-type-code* curlen)
    ;; out of room, allocate more space
    (let ((newlen (+ curlen *types-array-inc*)))
     (setf types-array     (copy-extend-array types-array     curlen newlen)
           type-fns-array  (copy-extend-array type-fns-array  curlen newlen)
           type-docs-array (copy-extend-array type-docs-array curlen newlen))))
   ;; in any case, return current code, then add one to it
   (prog1
       *next-type-code*
     (incf *next-type-code*))))


(defun add-new-type (typename type-body type-fn &optional type-doc)
  "This adds a new type, if necessary
Always returns the CODE of the resulting type (whether new or not)"
  (with-types-table-lock-held (types-table)
    (let ((code (gethash (or typename type-body) types-table)))
      (if code
	  ;; redefining same name
	  (if (equal (code-to-type code) type-body)
	      ;; redefining same name, same type
	      (progn
		(format t "Ignoring redundant def-kr-type of ~S to ~S~%"
			typename type-body)
		(return-from add-new-type code))
	      ;; redefining same name, new type --> replace it!
	      (format t "def-kr-type redefining ~S from ~S to ~S~%"
		      typename (code-to-type code) type-body))
	  ;; defining a new name, establish new code
	  (progn
	    (setq code (or (gethash type-body types-table)
			   (get-next-type-code)))
	    (setf (gethash typename types-table) code)))
      (unless (gethash type-body types-table)
	(setf (gethash type-body types-table) code))
      (setf (svref types-array code)
	    (if typename
		(if (stringp typename)
		    (intern typename (find-package "KR"))
		    typename)
		type-body))
      (setf (svref type-docs-array code) (or type-doc NIL))
      (setf (svref type-fns-array  code)
	    (if (and (symbolp type-fn) ;; koz
		     (fboundp type-fn))
		(symbol-function type-fn)
		type-fn))
      code)))

(defun kr-type-error (type)
  (error "Type ~S not defined; use~% (def-kr-type ... () '~S)~%" type type))

(eval-when (:execute :compile-toplevel :load-toplevel)
  (defun encode-type (type)
    "Given a LISP type, returns its encoding."
    (with-types-table-lock-held (types-table)
      ;; if there, just return it!
      (cond ((gethash type types-table))
	    ((and (listp type) (eq (car type) 'SATISFIES))
	     ;; add new satisfies type
	     (add-new-type NIL type (type-to-fn type)))
	    ((symbolp type)
	     (or (gethash (symbol-name type) types-table)
		 (let ((predicate (find-lisp-predicate type)))
		   (when predicate
		     (add-new-type NIL type predicate)))
		 (kr-type-error type)))
	    (T (kr-type-error type))))))

(defun set-type-documentation (type string)
  "Add a human-readable description to a Lisp type."
   (setf (aref type-docs-array (encode-type type)) string))


(defun get-type-documentation (type)
  "RETURNS: the documentation string for the internal number <type>."
  (aref type-docs-array (encode-type type)))

(declaim (inline slot-is-constant))
(defun slot-is-constant (schema slot)
  (let ((entry (slot-accessor schema slot)))
    (is-constant (sl-bits entry))))


(declaim (fixnum *warning-level*))
(defparameter *warning-level* 0)

(defun g-value-formula-value (schema-self slot formula entry)
  (let ((*schema-self* schema-self))
    (if (cache-is-valid formula)
	(a-formula-cached-value formula)
	(progn
	  (unless *within-g-value*
	    ;; Bump the sweep mark only at the beginning of a chain of formula
	    ;; accesses.  Increment by 2 since lower bit is "valid" flag.
	    (incf *sweep-mark* 2))
	  (if (= (cache-mark formula) *sweep-mark*)
	      (progn
		(when *warning-on-circularity*
		  (format t "Warning - circularity detected on ~S, slot ~S~%"
			  *schema-self* slot))
		(unless *setting-formula-p*
		  (set-cache-is-valid formula T))
		(a-formula-cached-value formula)))))))

(defun copy-to-all-instances (schema a-slot value &optional (is-first T))
  "Forces the <value> to be physically copied to the <a-slot> of all
instances of the <schema>, even though local values were defined.
However, if there was a local formula, do nothing."
  (s-value schema a-slot value)
  ;; Do not create copies of formulas, but set things up for inheritance
  (when (and is-first (formula-p value))
    (setf value *no-value*))
  (dolist (inverse *inheritance-inverse-relations*)
    (let ((children (if (eq inverse :IS-A-INV) ; for efficiency
			(let ((entry (slot-accessor schema :IS-A-INV)))
			  (when entry (sl-value entry)))
			(get-local-value schema inverse))))
      (unless (eq children *no-value*)
	(dolist (child children)
	  ;; force new inheritance
	  (unless (formula-p (get-value child a-slot))
	    ;; Do not override if the user has specified a local formula!
	    (copy-to-all-instances child a-slot value NIL)))))))

(defun update-inherited-internal (child a-slot entry)
  (let ((old-value (sl-value entry)))
    (unless (eq old-value *no-value*)
      (let ((child-bits (sl-bits entry)))
	(when (is-inherited child-bits)
	  (update-inherited-values child a-slot *no-value* NIL))))))

(defun update-inherited-values (schema a-slot value is-first)
  "This function is used when a value is changed in a prototype.  It makes
sure that any child schema which inherited the previous value is updated
with the new value.
INPUTS:
  - <value>: the new (i.e., current) value for the <schema>
  - <old-bits>: the setting of the slot bits for the <schema>, before the
    current value-setting operation.
  - <is-first>: if non-nil, this is the top-level call.
"
  (let ((*schema-self* schema))
    (unless is-first
      (run-invalidate-demons schema a-slot NIL)
      (propagate-change schema a-slot))
    (dolist (inverse *inheritance-inverse-relations*)
      (let ((children (if (eq inverse :IS-A-INV) ; for efficiency
			  (let ((entry (slot-accessor schema :IS-A-INV)))
			    (when entry (sl-value entry)))
			  (get-local-value schema inverse))))
	(unless (eq children *no-value*)
	  (dolist (child children)
	    (let ((entry (slot-accessor child a-slot)))
	      (when entry
		;; If child had no value, no need to propagate down
		(setf is-first NIL)
		;; force new inheritance
		(update-inherited-internal child a-slot entry)))))))))


;;; Slot and formula change  code.


(declaim (inline mark-as-changed))
(defun mark-as-changed (schema slot)
  "Forces formulas which depend on the <slot> in the <schema> to be
invalidated.  Mostly used for internal implementation.
This function can be used when manually changing a slot (without using
s-value).  It will run the demons and propagate the invalidate wave
to all the ordinary places."
  (let ((entry (slot-accessor schema slot)))
    (run-invalidate-demons schema slot entry)
    (when (and entry (is-parent (sl-bits entry)))
      (update-inherited-values schema slot (sl-value entry) T)))
  (propagate-change schema slot))


(declaim (inline mark-as-invalid))
(defun mark-as-invalid (schema slot)
  "Invalidates the value of the formula at <position> in the <slot> of the
  <schema>.  If the value is not a formula, nothing happens."
  (let ((value (get-value schema slot)))
    (when (formula-p value)
      (set-cache-is-valid value NIL))))

(defun propagate-change (schema slot)
  "Since the <slot> of the <schema> was modified, we need to propagate the
change to all the formulas which depended on the old value."
  (let ((entry (slot-accessor schema slot)))
    ;; access the dependent formulas.
    (do-one-or-list (formula (slot-dependents entry) T)
      ;; Stop propagating if this dependent formula was already marked dirty.
      (if (and (not-deleted-p formula) (cache-is-valid formula))
	(let* ((new-schema (on-schema formula))
	       (new-slot (on-slot formula))
	       (schema-ok (schema-p new-schema))
	       (new-entry  NIL))
	  (unless (and new-schema new-slot)
	    (when *warning-on-disconnected-formula*
	      (format
	       t
	       "Warning: disconnected formula ~S in propagate-change ~S ~S~%"
	       formula schema slot))
	    (continue-out))
	  (if schema-ok
	    (progn
	      (setf new-entry (slot-accessor new-schema new-slot))
	      )
	    )
	  ;; The formula gets invalidated here.
	  (set-cache-is-valid formula nil)
	  ;; Notify all children who used to inherit the old value of the
	  ;; formula.
	  (if (and schema-ok new-entry)
	    (if (slot-dependents new-entry)
	      (propagate-change new-schema new-slot))))))))


(defun visit-inherited-values (schema a-slot function)
  "Similar to update-inherited-values, but used when the hierarchy is
modified or when an inheritable slot is destroyed.
SIDE EFFECTS:
 - the <function> is called on all children which actually inherit the
   values in the <a-slot> of the <schema>.  This is determined by a fast
   check (the list of values should be EQ to that of the parent).
Note that the <function> is called after all children have been visited..
This allows it to be a destructive function."
  (let* ((entry (slot-accessor schema a-slot))
	 (parent-entry (when entry (sl-value entry))))
    (dolist (inverse *inheritance-inverse-relations*)
      (dolist (child (if (eq inverse :IS-A-INV)
			 (get-local-value schema :IS-A-INV)
			 (get-local-value schema inverse)))
	(let* ((entry (slot-accessor child a-slot))
	       (value (when entry (sl-value entry))))
	  (when (and value
		     (is-inherited (sl-bits entry))
		     (eq value parent-entry))
	    (visit-inherited-values child a-slot function)
	    (funcall function child a-slot)))))))

(defun constant-slot-error (schema slot)
  (cerror "Set the slot anyway"
	  "Schema ~S - trying to set slot ~S, which is constant."
	  schema slot))


(declaim (inline check-not-constant))
(defun check-not-constant (schema slot entry)
  "Signals an error if the <slot> of the <schema> is not constant."
  (and (not *constants-disabled*)
       entry
       (is-constant (sl-bits entry))
       (constant-slot-error schema slot)))


(declaim (inline slot-constant-p))
(defun slot-constant-p (schema slot)
  "RETURN: T if the <slot> in the <schema> is constant, nil otherwise"
  (let ((entry (slot-accessor schema slot)))
    (when entry
      (is-constant (sl-bits entry)))))


(defun set-formula-error (schema slot formula)
  "Called to give error message on multiply-installed formulas."
  ;; Formulas can only be installed on one slot!
  (format t "(s-value ~S ~S): formula ~S is already installed on~%~
	schema ~S, slot ~S.  Ignored.~%"
	  schema slot formula (on-schema formula) (on-slot formula))
  formula)


(defun s-value-fn (schema slot value)
  (locally (declare #.*special-kr-optimization*)
    (unless (schema-p schema)
      (return-from s-value-fn (values value t)))
    (let* ((entry (slot-accessor schema slot))
	   (old-value
	    nil
	     )
	    is-depended)
      ;; give error if setting constant slot
      (check-not-constant schema slot entry)
      (let ((is-formula nil) (is-relation nil)
	    (was-formula (formula-p old-value)))
	(when (and (setf is-relation (relation-p slot))
		   (eq (setf value (check-relation-slot schema slot value)) *no-value*))
	  (return-from s-value-fn (values old-value nil)))
	(when (formula-p value)
	  (when (on-schema value)
	    ;; RGA --- added error return code.
	    (return-from s-value-fn
	      (values (set-formula-error schema slot value) T)))
	  (setf is-formula T)
	  (setf (on-schema value) schema)
	  (setf (on-slot value) slot)
	  (unless (schema-name value)
	    (incf *schema-counter*)
	    (setf (schema-name value) *schema-counter*)))
	(run-invalidate-demons schema slot entry)
	(cond
	  ((and was-formula (not is-formula))
	   (when (zerop (a-formula-number old-value))
	     (format t "*** Warning: you are setting the value of slot ~S of
 object ~S.  This slot contains a formula which was never evaluated.
 The formula is now valid, but its dependencies are not set up properly.  As
 a result, the formula will never be evaluated.
 In order for this formula to work properly, you should have used
 (g-value ~S ~S) before using S-VALUE.  If you want to fix things now,
 re-install the formula using s-value.~%"
		     slot schema schema slot))
	   ;; This is the case when we allow temporary overwriting
	   (setf (cached-value old-value) value)
	   ;; Set this to NIL, temporarily, in order to cause propagation
	   ;; to leave the value alone.  It will be validated by s-value.
	   (set-cache-is-valid old-value NIL))
	  (t
	   ;; All other cases
	   (when (and is-formula (null (cached-value value)))
	     ;; place old value in the cache only if an initial value
	     ;; was not provided for the new formula
	     ;; Set value, but keep formula invalid.
	     (setf (cached-value value)
		   (if was-formula (cached-value old-value) old-value)))
	   ;; Take care of relations.
	   (when is-relation
	     (when old-value (unlink-all-values schema slot))
	     (link-in-relation schema slot value))
	   (let ((new-bits (or the-bits *local-mask*)))
	     (if entry
		 ;; This is a special slot - just set it
		 (setf (sl-value entry) value
		       (sl-bits entry) new-bits)
		 ;; This is not a special slot.
		 (setf entry (set-slot-accessor schema
						slot value new-bits nil))))))
	;; Now propagate the change to all the children which used to
	;; inherit the previous value of this slot from the schema.
	(when (and the-bits (is-parent the-bits))
	  (let ((*setting-formula-p* T))
	    (update-inherited-values schema slot value T)))
	;; Notify all dependents that the value changed.
	(when is-depended
	  (let ((*warning-on-disconnected-formula* nil))
	    (propagate-change schema slot)))
	(when (and was-formula (not is-formula))
	  ;; We validate now, rather than earlier, because of a technicality
	  ;; in demons-and-old-values.
	  (set-cache-is-valid old-value T))
	;; Was the old value a formula?
	(when (and was-formula is-formula))
	(values value nil)))))

(defun internal-s-value (schema slot value)
  (let ((is-formula (formula-p value))
	(is-relation (relation-p slot)))
    (when is-relation
      (unless (listp value)
	(setf value (list value)))
      ;; Check for special cases in relation slots.
      (when (eq (setf value (check-relation-slot schema slot value)) *no-value*)
	(return-from internal-s-value NIL)))

    ;; If we are installing a formula, make sure that the formula
    ;; points to the schema and slot.
    (when is-formula
      (when (on-schema value)
	(return-from internal-s-value (set-formula-error schema slot value)))
      (setf (on-schema value) schema)
      (setf (on-slot value) slot))

    (set-slot-accessor schema slot value *local-mask* nil)

    ;; Take care of relations.
    (when is-relation
      (link-in-relation schema slot value))
    value))


(defun set-is-a (schema value)
  "A specialized version of internal-s-value"
  ;; Check for special cases in relation slots.
  (when (eq (setf value (check-relation-slot schema :is-a value)) *no-value*)
    (return-from set-is-a NIL))
  ;; Set slot
  (set-slot-accessor schema :IS-A value *local-mask* NIL)
  (link-in-relation schema :IS-A value)
  value)

(defun find-parent (schema slot)
  "Find a parent of <schema> from which the <slot> can be inherited."
  (dolist (relation *inheritance-relations*)
    (dolist (a-parent (if (eq relation :is-a)
			  (get-local-value schema :IS-A)
			  (get-local-value schema relation)))
      (when a-parent
	(let ((value (g-local-value a-parent slot)))
	  (if value
	      (return-from find-parent (values value a-parent))
	      (multiple-value-bind (value the-parent)
		  (find-parent a-parent slot)
		(when value
		  (return-from find-parent (values value the-parent))))))))))

(defun kr-call-initialize-method (schema slot)
  "This is similar to kr-send-function, except that it is careful NOT to
inherit the method, which is only used once.  This is to reduce unnecessary
storage in every object."
  (let ((the-function (g-value-no-copy schema slot)))
    (when the-function
      ;; Bind these in case call prototype method is used.
      (let ((*kr-send-self* schema)
	    (*kr-send-slot* slot)
	    (*kr-send-parent* NIL)
	    (*demons-disabled* T))
	(funcall the-function schema)))))


(defun kr-init-method (schema the-function)
  "Similar, but even more specialized.  It is only called by create-schema
and friends, which know whether an :initialize method was specified locally."
  (let ((*kr-send-parent* nil))
    (if the-function
      (setf *kr-send-parent* schema)
      (multiple-value-setq (the-function *kr-send-parent*)
	(find-parent schema :INITIALIZE)))
    (when the-function
      ;; Bind these in case call prototype method is used.
      (let ((*kr-send-self* schema)
	    (*kr-send-slot* :INITIALIZE)
            (*kr-send-parent* NIL)
	    #-(and) (*demons-disabled* T))
	(funcall the-function schema)))))

(defun allocate-schema-slots (schema)
  (locally (declare #.*special-kr-optimization*)
    (setf (schema-bins schema)
	  (make-hash-table :test #'eq #+sbcl :synchronized #+sbcl t)))
  schema)


(defun make-a-new-schema (name)
  "Creates a schema with the given <name>, making sure to destroy the old
one by that name if it exists.  The initial number of slots is
<needed-slots>."
  (locally (declare #.*special-kr-optimization*)
    (when (keywordp name)
      (setf name (symbol-name name)))
    (cond ((null name)
	   ;; An unnamed schema.
	   (let ((schema (make-schema)))
	     (setf *schema-counter* (1+ *schema-counter*))
	     (setf (schema-name schema) *schema-counter*)
	     (allocate-schema-slots schema)
	     schema))
	  ((stringp name)
	   ;; This clause must precede the next!
	   (let ((schema (make-schema)))
	     (allocate-schema-slots schema)
	     (setf (schema-name schema) name)
	     schema))
	  ;; Is this an existing schema?  If so, destroy the old one and its
	  ;; children.
	  ((and (boundp name)
		(symbolp name))
	   (let ((schema (symbol-value name)))
	     (setf (schema-name schema) name)
	     (set name schema)))
	  ((symbolp name)
	   (eval `(defvar ,name))
	   (let ((schema (make-schema)))
	     (allocate-schema-slots schema)
	     (setf (schema-name schema) name)
	     (set name schema)))
	  (t
	   (format t "Error in CREATE-SCHEMA - ~S is not a valid schema name.~%"
		   name)))))

(defun declare-constant (schema slot)
  "Declare slot constants AFTER instance creation time."
  (unless *constants-disabled*
    (if (eq slot T)
      ;; This means that all constants declared in :MAYBE-CONSTANT should be
      ;; made constant
      (let ((maybe (g-value-no-copy schema :MAYBE-CONSTANT)))
	(dolist (m maybe)
	  (declare-constant schema m)))
      ;; This is the normal case - only 1 slot.
      (let ((constant-list (g-value schema :CONSTANT))
	    (positive T))
	(do ((list constant-list (if (listp list) (cdr list) NIL))
	     (prev nil list)
	     c)
	    ((null list)
	     (setf constant-list (cons slot (if (listp constant-list)
					      constant-list
					      (list constant-list))))
	     (s-value schema :CONSTANT constant-list))
	  (setf c (if (listp list) (car list) list))
	  (cond ((eq c :EXCEPT)
		 (setf positive NIL))
		((eq c slot)
		 (when positive
		   (return nil))
		 ;; Slot was explicitly excepted from constant list.
		 (setf (cdr prev) (cddr prev)) ; remove from :EXCEPT
		 (when (and (null (cdr prev))
			    (eq (car prev) :EXCEPT))
		   ;; We are removing the last exception to the constant list
		   (let ((end (nthcdr (- (length constant-list) 2)
				      constant-list)))
		     (setf (cdr end) nil)))
		 (setf constant-list (cons c constant-list))
		 (s-value schema :CONSTANT constant-list)
		 (return))))))))

(defun process-constant-slots (the-schema parents constants do-types)
  "Process local-only and constant declarations."
  (locally (declare #.*special-kr-optimization*)
    ;; Install all update-slots entries, and set their is-update-slot bits
    (dolist (slot (g-value-no-copy the-schema :UPDATE-SLOTS))
      (let ((entry (slot-accessor the-schema slot)))
	(if entry
	    (setf (sl-bits entry) (set-is-update-slot (sl-bits entry)))
	    (set-slot-accessor the-schema slot *no-value*
			       (set-is-update-slot *local-mask*)
			       NIL))))
    ;; Mark the local-only slots.
    (dolist (parent parents)
      (dolist (local (g-value-no-copy parent :LOCAL-ONLY-SLOTS))
	(unless (listp local)
	  (cerror "Ignore the declaration"
		  "create-instance (object ~S, parent ~S):  :local-only-slots
declarations should consist of lists of the form (:slot T-or-NIL).  Found
the expression ~S instead."
		  the-schema parent local)
	  (return))
	;; Set the slots marked as local-only
	(let ((slot (car local)))
	  (unless (slot-accessor the-schema slot)
	    (if (second local)
		;; Copy down the parent value, once and for all.
		(let* ((entry (slot-accessor parent slot))
		       (value (if entry (sl-value entry))))
		  (unless (formula-p value)
		    ;; Prevent inheritance from ever happening
		    (internal-s-value the-schema slot (g-value parent slot))))
		;; Avoid inheritance and set the slot to NIL.
		(internal-s-value the-schema slot NIL))))))
    (when (and do-types *types-enabled*)
      ;; Copy type declarations down from the parent(s), unless overridden
      ;; locally.
      (dolist (parent parents)
	(iterate-slot-value (parent T T nil)
	  value						 ;; suppress warning
	  (let ((bits (sl-bits iterate-slot-value-entry))) ; get parent's bits
	    ;; keep only the type information
	    (setf bits (logand bits *type-mask*))
	    (unless (zerop bits)
	      (let ((the-entry (slot-accessor the-schema slot)))
		(if the-entry
		    (let ((schema-bits (sl-bits the-entry)))
		      (when (zerop (extract-type-code schema-bits))
			;; Leave type alone, if one was declared locally.
			(setf (sl-bits the-entry)
			      (logior (logand schema-bits *all-bits-mask*)
				      bits))))
		    (set-slot-accessor the-schema slot *no-value* bits NIL))))))))))

(defun merge-declarations (declaration keyword output)
  (let ((old (find keyword output :key #'second)))
    (if old
	(setf (cadr (third old)) (union (cdr declaration)
					(cadr (third old))))
	(push `(cons ,keyword ',(cdr declaration)) output)))
  output)


(eval-when (:execute :compile-toplevel :load-toplevel)
  (defun process-slots (slots)
    "This function processes all the parameters of CREATE-INSTANCE and returns
an argument list suitable for do-schema-body.  It is called at compile time.
RETURNS: a list, with elements as follows:
 - FIRST: the prototype (or list of prototypes), or NIL;
 - SECOND: the list of type declarations, in the form (type slot slot ...)
   or NIL (if there were no type declarations) or :NONE (if the declaration
   (type) was used, which explicitly turns off all types declared in the
   prototype(s).
 - REST OF THE LIST: all slot specifiers, with :IS-A removed (because that
   information is moved to the prototype list)."
    (let ((output nil)
	  (is-a nil))
      (do ((head slots (cdr head))
	   (types nil)
	   (had-types nil)		; true if there is a declaration
	   slot)
	  ((null head)
	   (if types
	       (push `(quote ,types) output)
	       (if had-types
		   (push :NONE output)
		   (push NIL output))))
	(setf slot (car head))
	(cond ((null slot)
	       ;; This is an error.
	       (cerror
		"Ignore the specification"
		"Error in CREATE-SCHEMA: NIL is not a valid slot ~
		 specifier; ignored.~%~
	         Object ~S, slot specifiers are ~S~%"
		kr::*create-schema-schema* head))
	      ((keywordp slot)
	       ;; Process declarations and the like.
	       (case slot
		 (:NAME-PREFIX
		  (pop head))
		 (:DECLARE
		  (pop head)
		  (dolist (declaration (if (listp (caar head))
					   (car head)
					   (list (car head))))
		    (case (car declaration)
		      (:TYPE
		       (setf had-types T)
		       (dolist (spec (cdr declaration))
			 (push spec types)))
		      ((:CONSTANT :IGNORED-SLOTS :LOCAL-ONLY-SLOTS
				  :MAYBE-CONSTANT :PARAMETERS :OUTPUT
				  :SORTED-SLOTS :UPDATE-SLOTS)
		       (setf output (merge-declarations declaration
							(car declaration)
							output)))
		      (t
		       (cerror
			"Ignore the declaration"
			"Unknown declaration (~S) in object creation:~%~S~%"
			(car declaration)
			declaration)))))))
	      ((listp slot)
	       ;; Process slot descriptors.
	       (if (eq (car slot) :IS-A)
		   (setf is-a (if (cddr slot)
				  `(list ,@(cdr slot))
				  (cadr slot)))
		   (if (listp (cdr slot))
		       (if  nil
			   (if (cddr slot)
			       (push `(list ,(car slot) . ,(cdr slot)) output)
			       (push `(cons ,(car slot) . ,(cdr slot)) output))
			   (if (cddr slot)
			       (push `'(,(car slot) . ,(cdr slot)) output)
			       (push `'(,(car slot) . ,(cadr slot)) output)))
		       (push (cdr slot) output))))
	      (T
	       (cerror
		"Ignore the specification"
		"A slot specification should be of the form ~
		 (:name [values]*) ;~%found ~S instead.  Object ~S, slots ~S."
		slot kr::*create-schema-schema* slots))))
      (cons is-a output))))

(defun handle-is-a (schema is-a generate-instance override)
  (if (or (eq schema is-a)
	  (memberq schema is-a))
      (format t "~A: cannot make ~S an instance of itself!  ~
    			Using NIL instead.~%"
	      (if generate-instance
		  "CREATE-INSTANCE" "CREATE-SCHEMA")
	      schema)
      ;; Make sure :override does not duplicate is-a-inv contents.
      (let ((*schema-is-new* (not override)))
	(set-is-a schema is-a))))

(defun do-schema-body (schema is-a generate-instance do-constants override
		       types &rest slot-specifiers)
  "Create-schema and friends expand into a call to this function."
  (when (equal is-a '(nil))
    (format
     t
     "*** (create-instance ~S) called with an illegal (unbound?) class name.~%"
     schema)
    (setf is-a NIL))
  (unless (listp is-a)
    (setf is-a (list is-a)))
  (when is-a
    (let ((*schema-is-new* T))
      (handle-is-a schema is-a generate-instance override)))
  (do* ((slots slot-specifiers (cdr slots))
	(slot (car slots) (car slots))
	(initialize-method NIL)
	(constants NIL)
	(had-constants NIL)
	(cancel-constants (find '(:constant) slot-specifiers :test #'equal))
	(parent (car is-a))
	(slot-counter (if is-a 1 0)))
       ((null slots)
	(unless (eq types :NONE)
	  (dolist (type types)
	    (if (cdr type)
		(let ((n (encode-type (car type))))
		  (dolist (slot (cdr type))
		    (set-slot-type schema slot n)))
		(format t "*** ERROR - empty list of slots in type declaration ~
                          for object ~S:~%  ~S~%" schema (car type)))))
	;; Process the constant declarations, and check the types.
	(when do-constants
	  (process-constant-slots
	   schema is-a
	   (if had-constants
	       (if constants
		   (if (formula-p constants)
		       (g-value-formula-value schema :CONSTANT constants NIL)
		       constants)
		   :NONE)
	       ;; There was no constant declaration.
	       NIL)
	   (not (eq types :NONE))))
	;; Merge prototype and local declarations.
	(dolist (slot slot-specifiers)
	  (when (and (listp slot)
		     (memberq (car slot)
			      '(:IGNORED-SLOTS :LOCAL-ONLY-SLOTS
				:MAYBE-CONSTANT :PARAMETERS :OUTPUT
				:SORTED-SLOTS :UPDATE-SLOTS)))
	    ))
	(when generate-instance
	  ;; We are generating code for a CREATE-INSTANCE, really.
	  (kr-init-method schema initialize-method))
	schema)
    (cond ((eq slot :NAME-PREFIX)
	   ;; Skip this and the following argument
	   (pop slots))
	  ((consp slot)
	   (let ((slot-name (car slot))
		 (slot-value (cdr slot)))
	     (case slot-name		; handle a few special slots.
	       (:INITIALIZE
		(when slot-value
		  ;; A local :INITIALIZE method was provided
		  (setf initialize-method slot-value)))
	       (:CONSTANT
		(setf constants (cdr slot))
		(setf had-constants T)))
	     ;; Check that the slot is not declared constant in the parent.
	     (when (and (not cancel-constants) (not *constants-disabled*)
			(not *redefine-ok*))
	       (when (and parent (slot-constant-p parent slot-name))
		 (cerror
		  "If continued, the value of the slot will change anyway"
		  "Slot ~S in ~S was declared constant in prototype ~S!~%"
		  slot-name schema (car is-a))))
	     (if override
		 (s-value schema slot-name slot-value)
		 (setf slot-counter
		       (internal-s-value schema slot-name slot-value)))))
	  (T
	   (format t "Incorrect slot specification: object ~S ~S~%"
		   schema slot)))))

(defun do-schema-body-alt (schema is-a generate-instance do-constants override
		       types &rest slot-specifiers)
  (unless (listp is-a)
    (setf is-a (list is-a)))
  (when is-a
    (let ((*schema-is-new* T))
      (handle-is-a schema is-a generate-instance override)))
  (do* ((slots slot-specifiers (cdr slots))
	(slot (car slots) (car slots))
	(initialize-method NIL)
	(constants NIL)
	(had-constants NIL)
	(cancel-constants (find '(:constant) slot-specifiers :test #'equal))
	(parent (car is-a))
	(slot-counter (if is-a 1 0)))
       ((null slots)
	(unless (eq types :NONE)
	  (dolist (type types)
	    (if (cdr type)
		(let ((n (encode-type (car type))))
		  (dolist (slot (cdr type))
		    (set-slot-type schema slot n)))
		(format t "*** ERROR - empty list of slots in type declaration ~
                          for object ~S:~%  ~S~%" schema (car type)))))
	;; Process the constant declarations, and check the types.
	(when do-constants
	  (process-constant-slots
	   schema is-a
	   (if had-constants
	       (if constants
		   (if (formula-p constants)
		       (g-value-formula-value schema :CONSTANT constants NIL)
		       constants)
		   :NONE)
	       ;; There was no constant declaration.
	       NIL)
	   (not (eq types :NONE))))
	;; Merge prototype and local declarations.
	(dolist (slot slot-specifiers)
	  (when (and (listp slot)
		     (memberq (car slot)
			      '(:IGNORED-SLOTS :LOCAL-ONLY-SLOTS
				:MAYBE-CONSTANT :PARAMETERS :OUTPUT
				:SORTED-SLOTS :UPDATE-SLOTS)))
	    ))
	(when generate-instance
	  ;; We are generating code for a CREATE-INSTANCE, really.
	  (kr-init-method schema initialize-method))
	schema)
    (cond ((eq slot :NAME-PREFIX)
	   ;; Skip this and the following argument
	   (pop slots))
	  ((consp slot)
	   (let ((slot-name (car slot))
		 (slot-value (cdr slot)))
	     (case slot-name		; handle a few special slots.
	       (:INITIALIZE
		(when slot-value
		  ;; A local :INITIALIZE method was provided
		  (setf initialize-method slot-value)))
	       (:CONSTANT
		(setf constants (cdr slot))
		(setf had-constants T)))
	     ;; Check that the slot is not declared constant in the parent.
	     (when (and (not cancel-constants) (not *constants-disabled*)
			(not *redefine-ok*))
	       (when (and parent (slot-constant-p parent slot-name))
		 (cerror
		  "If continued, the value of the slot will change anyway"
		  "Slot ~S in ~S was declared constant in prototype ~S!~%"
		  slot-name schema (car is-a))))
	     (if override
		 (s-value schema slot-name slot-value)
		 (setf slot-counter
		       (internal-s-value schema slot-name slot-value)))))
	  (T
	   (format t "Incorrect slot specification: object ~S ~S~%"
		   schema slot)))))

(declaim (inline get-slot-type-code))
(defun get-slot-type-code (object slot)
  (let ((entry (slot-accessor object slot)))
    (and entry
	 (get-entry-type-code entry))))


(declaim (inline g-type))
(defun g-type (object slot)
  (let ((type (get-slot-type-code object slot)))
    (and type
	 (code-to-type type))))



(defun set-slot-type (object slot type)
  (let ((entry (or (slot-accessor object slot)
		   (set-slot-accessor object slot *no-value* type NIL))))
    (setf (sl-bits entry)
	  (logior (logand (sl-bits entry) *all-bits-mask*) type))))


(defun s-type (object slot type &optional (check-p T))
  "Adds a type declaration to the given <slot>, eliminating any previous
type declarations.  If <check-p> is true, checks whether the value
already in the <slot> satisfies the new type declaration."
  (set-slot-type object slot (if type
			       (encode-type type)
			       ;; 0 means "no type declarations"
			       0))
  (when check-p
    (let* ((entry (slot-accessor object slot))
	   (value (if entry (sl-value entry))))
      (unless (or (eq value *no-value*)
		  (formula-p value))
	)))
  type)


(defun get-declarations (schema declaration)
  "RETURNS: a list of all slots in the <schema> which are declared as
<declaration>.

Example: (get-declarations A :type)"
  (let ((slots nil))
    (case declaration
      (:CONSTANT nil)
      (:TYPE nil)
      ((:IGNORED-SLOTS :SORTED-SLOTS :MAYBE-CONSTANT
		       :PARAMETERS :OUTPUT :UPDATE-SLOTS)
       (return-from get-declarations (g-value schema declaration)))
      (:LOCAL-ONLY-SLOTS
       (return-from get-declarations (g-local-value schema declaration)))
      (t
       (return-from get-declarations NIL)))
    ;; Visit all slots, construct information
    (iterate-slot-value (schema T T NIL)
      value ;; suppress warning
      (let ((bits (sl-bits iterate-slot-value-entry)))
	(case declaration
	  (:CONSTANT
	   (when (is-constant bits)
	     (push slot slots)))
	  (:TYPE
	   (let ((type (extract-type-code bits)))
	     (unless (zerop type)
	       (push (list slot (code-to-type type)) slots)))))))
    slots))


(defun get-slot-declarations (schema slot)
  (let* ((entry (slot-accessor schema slot))
	 (bits (if entry (sl-bits entry) 0))
	 (declarations nil))
    (if (is-constant bits)
      (push :CONSTANT declarations))
    (if (memberq slot (g-value schema :update-slots))
      (push :UPDATE-SLOTS declarations))
    (if (memberq slot (g-value schema :local-only-slots))
      (push :LOCAL-ONLY-SLOTS declarations))
    (if (memberq slot (g-value schema :maybe-constant))
      (push :MAYBE-CONSTANT declarations))
    (let ((type (extract-type-code bits)))
      (unless (zerop type)
	(push (list :type (code-to-type type)) declarations)))
    ;; Now process all declarations that are not stored in the slot bits.
    (dolist (s-slot '(:IGNORED-SLOTS :PARAMETERS :OUTPUT :SORTED-SLOTS))
      (let ((values (g-value schema s-slot)))
	(if (memberq slot values)
	  (push s-slot declarations))))
    declarations))


(defun T-P (value)
  (declare #.*special-kr-optimization*
	   (ignore value))
  T)

(defun no-type-error-p (value)
  (cerror "Return T"
          "KR typechecking called on value ~S with no type"
          value)
  T)
