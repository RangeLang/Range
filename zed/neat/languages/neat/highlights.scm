((attribute) @keyword
  (#eq? @keyword "@main"))

(main_attribute) @keyword

(comment) @comment
(attribute) @attribute

[
  "enum"
  "case"
  "extension"
  "func"
  "let"
  "protocol"
  "var"
] @keyword

(annotated_declaration
  name: (type_identifier) @type)

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
  name: (identifier) @variable)

(member_declaration
  name: (identifier) @variable)

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
(identifier) @variable

(string_literal) @string
(escape_sequence) @string.escape
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
