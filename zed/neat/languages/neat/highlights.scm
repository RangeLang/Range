; GENERATED FILE. Do not edit directly.
; Source fragments live under languages/neat/highlights/.

; ── Comments ────────────────────────────────────────────────────────────────
(comment) @comment


("@" @keyword)

; When syntax is incomplete, tree-sitter can fall back to plain identifiers
; inside ERROR nodes. Keep core keywords colored by text anyway.
((identifier) @keyword
 (#match? @keyword "^(construct|enum|case|extension|macro|func|function|protocol|state|environment|binding|derived|value|var|if|else|for|in|while|switch|default|return|break|continue|background|get|set|on|builder|capture|precedencegroup|prefix|infix|postfix|operator)$"))

((identifier) @keyword
 (#match? @keyword "^(core|main)$"))

[
  "background"
  "binding"
  "break"
  "builder"
  "capture"
  "case"
  "construct"
  "continue"
  "default"
  "derived"
  "else"
  "enum"
  "environment"
  "extension"
  "for"
  "func"
  "function"
  "get"
  "if"
  "in"
  "infix"
  "macro"
  "main"
  "on"
  "operator"
  "postfix"
  "precedencegroup"
  "prefix"
  "protocol"
  "return"
  "set"
  "state"
  "switch"
  "value"
  "var"
  "while"
] @keyword


[
  "if"
  "else"
  "for"
  "in"
  "while"
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


; ── @main entry point ────────────────────────────────────────────────────────
(main_block
  "@" @keyword
  "main" @keyword)


; Macro-specific syntax falls back to token highlighting for now because the
; runtime grammar shipped to Zed does not expose the macro node names that the
; source grammar declares.


; Builder-specific syntax falls back to token highlighting for now because the
; runtime grammar shipped to Zed does not expose the builder node names that
; the source grammar declares.


; ── Declarations ─────────────────────────────────────────────────────────────
(sigiled_declaration
  "construct" @keyword)

(sigiled_declaration
  name: (type_identifier) @type.definition)

(protocol_declaration
  "protocol" @keyword)

(callable_declaration
  "function" @keyword
  name: (callable_name
    (identifier) @function.method))

(callable_declaration
  "function" @keyword
  name: (callable_name
    (callable_operator_symbol) @operator))

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


