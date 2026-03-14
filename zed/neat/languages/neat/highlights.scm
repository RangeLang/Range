(comment) @comment

["#" "@"] @keyword

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

(sigiled_declaration
  name: (type_identifier) @property)

(sigiled_declaration
  (type_identifier) @keyword)

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

(parameter
  name: (identifier) @parameter)

(variable_declaration
  name: (identifier) @type)

(member_declaration
  name: (identifier) @type)

(argument
  label: (identifier) @property)

(assignment
  left: (identifier) @variable)

(enum_case_item
  name: (identifier) @constructor)

(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (type_identifier) @constructor)

(member_expression
  member: (identifier) @property)

(modifier_call
  name: (identifier) @function.method)

(type_identifier) @type

(string_literal) @string
(escape_sequence) @string.escape
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
