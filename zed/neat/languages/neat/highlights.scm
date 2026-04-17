; ── Comments ────────────────────────────────────────────────────────────────
(comment) @comment

("@" @keyword)

; When syntax is incomplete, tree-sitter can fall back to plain identifiers
; inside ERROR nodes. Keep core keywords colored by text anyway.
((identifier) @keyword
 (#match? @keyword "^(construct|enum|case|extension|macro|func|function|protocol|state|environment|binding|derived|value|var|if|else|for|in|while|switch|default|return|break|continue|background|get|set|on|builder|capture|precedencegroup|prefix|infix|postfix|operator)$"))

((identifier) @keyword
 (#match? @keyword "^(core|main)$"))

("macro" @keyword)

[
  "switch"
  "case"
  "default"
] @keyword

(break_statement) @keyword.control
(continue_statement) @keyword.control
(return_statement
  "return" @keyword.control)

(switch_statement
  "switch" @keyword)

(switch_case
  "case" @keyword)

(switch_default
  "default" @keyword)

; ── Attribute applications ───────────────────────────────────────────────────
(attribute_application
  sigil: "@" @keyword
  name: (identifier) @keyword)

; ── @main entry point ────────────────────────────────────────────────────────
(main_block
  "@" @keyword
  "main" @keyword)



(macro_declaration
  "macro" @keyword)

(macro_bindings
  "in" @keyword)

(macro_application
  sigil: "#" @type
  name: (identifier) @type)

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
    type: (_) @type))

(macro_declaration
  "->" @operator
  expansion_type: (_) @type)

(builder_declaration
  name: (type_identifier) @type.definition)

(callable_declaration
  "function" @keyword
  name: (callable_name
    (identifier) @function.method))

(callable_declaration
  "function" @keyword
  name: (callable_name
    (callable_operator_symbol) @operator))

(precedence_group_declaration
  "precedencegroup" @keyword
  name: (type_identifier) @type.definition)

(operator_declaration
  [
    "prefix"
    "infix"
    "postfix"
  ] @keyword
  "operator" @keyword
  symbol: (operator_symbol) @operator)

(operator_declaration
  precedence: (type_identifier) @type)

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
  type: (_) @type)

(protocol_declaration
  name: (type_identifier) @type.definition)

(function_declaration
  "func" @keyword
  name: (identifier) @function)

; ── Parameters & variables ───────────────────────────────────────────────────
(parameter
  name: (identifier) @variable.parameter)

(parameter
  type: (capture_type
    "capture" @keyword
    captured: (_) @type))

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
(string_literal
  "\"" @string)
(string_content) @string
(escape_sequence) @string.escape
(interpolation
  "\\(" @string.escape
  ")" @string.escape)
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
(nil_literal) @keyword
