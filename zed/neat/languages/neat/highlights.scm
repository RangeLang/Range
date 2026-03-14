; ── Comments ────────────────────────────────────────────────────────────────
(comment) @comment

; ── Sigil operators ──────────────────────────────────────────────────────────
["#" "@"] @keyword

; ── Keywords ─────────────────────────────────────────────────────────────────
[
  "enum"
  "case"
  "extension"
  "func"
  "let"
  "protocol"
  "state"
  "binding"
  "value"
  "var"
] @keyword

; Control flow
[
  "for"
  "in"
  "while"
  "if"
  "else"
  "switch"
  "default"
  "break"
  "continue"
  "return"
] @keyword.control

; Projection keyword
"on" @keyword

; ── @main entry point (special bold treatment) ───────────────────────────────
((callable_declaration
  name: (identifier) @keyword.special)
 (#eq? @keyword.special "main"))

; ── Declarations ─────────────────────────────────────────────────────────────
(sigiled_declaration
  name: (type_identifier) @type.definition)

(sigiled_declaration
  target: (type_identifier) @type)

(callable_declaration
  name: (identifier) @function.method)

(enum_declaration
  name: (type_identifier) @type)

(extension_declaration
  type: (type_identifier) @type)

(protocol_declaration
  name: (type_identifier) @type)

(function_declaration
  name: (identifier) @function)

; ── Parameters & variables ───────────────────────────────────────────────────
(parameter
  name: (identifier) @variable.parameter)

(variable_declaration
  name: (identifier) @variable)

(member_declaration
  name: (identifier) @property)

; ── Call sites ───────────────────────────────────────────────────────────────
(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (type_identifier) @constructor)

(modifier_call
  name: (identifier) @function.method)

; ── Member access ────────────────────────────────────────────────────────────
(member_expression
  member: (identifier) @property)

; ── Arguments & assignment ───────────────────────────────────────────────────
(argument
  label: (identifier) @property)

(assignment
  left: (identifier) @variable)

; ── Enum cases ───────────────────────────────────────────────────────────────
(enum_case_item
  name: (identifier) @constructor)

; ── Types ────────────────────────────────────────────────────────────────────
(type_identifier) @type

; ── Literals ─────────────────────────────────────────────────────────────────
(string_literal) @string
(escape_sequence) @string.escape
(interpolation) @embedded
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
(nil_literal) @constant.builtin
