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
