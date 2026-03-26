; ── Comments ────────────────────────────────────────────────────────────────
(comment) @comment

; ── Sigil operators ──────────────────────────────────────────────────────────
["@" "*"] @keyword

; When syntax is incomplete, tree-sitter can fall back to plain identifiers
; inside ERROR nodes. Keep core keywords colored by text anyway.
((identifier) @keyword
 (#match? @keyword "^(construct|enum|case|extension|macro|primitive|func|function|protocol|state|environment|binding|derived|value|var|if|else|for|in|while|switch|default|return|break|continue|on|builder)$"))

(break_statement) @keyword.control
(continue_statement) @keyword.control

; ── @main entry point ────────────────────────────────────────────────────────
(main_block
  "@" @keyword
  "main" @keyword)

(macro_declaration
  "macro" @keyword)

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
  "construct" @keyword)

(sigiled_declaration
  name: (type_identifier) @type.definition)

(protocol_declaration
  "protocol" @keyword)

(macro_declaration
  name: (identifier) @function.special)

(macro_declaration
  target: (macro_target
    kind: _ @keyword
    type: (_) @type))

(builder_declaration
  name: (type_identifier) @type.definition)

(sigiled_declaration
  "on" @keyword)

(sigiled_declaration
  target: (type_identifier) @type)

(callable_declaration
  "function" @keyword
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
  "enum" @keyword
  name: (type_identifier) @type.definition)

(extension_declaration
  "extension" @keyword
  type: (type_identifier) @type)

(protocol_declaration
  name: (type_identifier) @type.definition)

(function_declaration
  "func" @keyword
  name: (identifier) @function)

; ── Parameters & variables ───────────────────────────────────────────────────
(parameter
  name: (identifier) @variable.parameter)

(variable_declaration
  [
    "state"
    "environment"
    "binding"
    "value"
  ] @keyword
  name: (identifier) @variable)

(derived_declaration
  "derived" @keyword)

(member_declaration
  "var" @keyword
  name: (identifier) @property)

; ── Call sites ───────────────────────────────────────────────────────────────
(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (type_identifier) @constructor)

(modifier_call
  name: (identifier) @function.method)

; ── Arguments & assignment ───────────────────────────────────────────────────
(argument
  label: (identifier) @property)

(assignment
  left: (identifier) @variable)

(enum_case
  "case" @keyword.control)

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
