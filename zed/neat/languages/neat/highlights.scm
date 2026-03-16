; ── Comments ────────────────────────────────────────────────────────────────
(comment) @comment

; ── Sigil operators ──────────────────────────────────────────────────────────
["@" "*"] @keyword

; ── Keywords ─────────────────────────────────────────────────────────────────
[
  "construct"
  "enum"
  "case"
  "extension"
  "func"
  "function"
  "protocol"
  "state"
  "environment"
  "binding"
  "derived"
  "value"
  "var"
  "builder"
] @keyword

; When syntax is incomplete, tree-sitter can fall back to plain identifiers
; inside ERROR nodes. Keep core keywords colored by text anyway.
((identifier) @keyword
 (#match? @keyword "^(construct|enum|case|extension|func|function|protocol|state|environment|binding|derived|value|var|if|else|for|in|while|switch|default|return|break|continue|on|builder)$"))

; Control flow
[
  "if"
  "else"
  "for"
  "in"
  "while"
  "switch"
  "case"
  "default"
  "return"
] @keyword.control

(break_statement) @keyword.control
(continue_statement) @keyword.control

; Projection keyword
"on" @keyword

; ── @main entry point ────────────────────────────────────────────────────────
(main_block
  "@" @keyword
  "main" @keyword)

; ── Builder sigils ───────────────────────────────────────────────────────────
(builder_declaration
  "*" @keyword
  "builder" @keyword)

(builder_hook_declaration
  "*" @keyword)

(derived_declaration
  builder: (builder_application
    "*" @keyword))

; ── Declarations ─────────────────────────────────────────────────────────────
(sigiled_declaration
  name: (type_identifier) @type.definition)

(builder_declaration
  name: (type_identifier) @type.definition)

(sigiled_declaration
  target: (type_identifier) @type)

(callable_declaration
  name: (identifier) @function.method)

(builder_hook_declaration
  hook: [
    "expression"
    "block"
    "optional"
    "either"
    "array"
  ] @function.special)

(derived_declaration
  builder: (builder_application
    name: (type_identifier) @type))

((identifier) @function.method
 (#eq? @function.method "init"))

(enum_declaration
  name: (type_identifier) @type.definition)

(extension_declaration
  type: (type_identifier) @type)

(protocol_declaration
  name: (type_identifier) @type.definition)

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
(string_content) @string
(escape_sequence) @string.escape
(interpolation
  "\\(" @string.escape
  ")" @string.escape)
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
(nil_literal) @constant.builtin
