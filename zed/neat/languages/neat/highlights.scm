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


(break_statement) @keyword.control
(continue_statement) @keyword.control
(return_statement) @keyword.control

(if_statement) @keyword

(for_statement) @keyword
(while_statement) @keyword
(switch_statement) @keyword
(switch_case) @keyword
(switch_default) @keyword


; ── @main entry point ────────────────────────────────────────────────────────
(main_block) @keyword


; Macro-specific syntax falls back to token highlighting for now because the
; runtime grammar shipped to Zed does not expose the macro node names that the
; source grammar declares.


; Builder-specific syntax falls back to token highlighting for now because the
; runtime grammar shipped to Zed does not expose the builder node names that
; the source grammar declares.


; ── Declarations ─────────────────────────────────────────────────────────────
(sigiled_declaration) @keyword

(protocol_declaration) @keyword

((identifier) @function.method
 (#eq? @function.method "init"))

(enum_declaration) @keyword
(extension_declaration) @keyword
(function_declaration) @keyword


; ── Parameters & variables ───────────────────────────────────────────────────
(parameter
  name: (identifier) @variable.parameter)

(variable_declaration
  name: (identifier) @variable)

(derived_declaration) @keyword

(member_declaration
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
(enum_case) @keyword.control


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


