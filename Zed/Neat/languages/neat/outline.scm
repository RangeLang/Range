(macro_declaration
  name: (identifier) @name) @item

(sigiled_declaration
  name: (type_identifier) @name) @item

(builder_declaration
  name: (type_identifier) @name) @item

(callable_declaration
  name: (callable_name
    [
      (identifier)
      (callable_operator_symbol)
    ] @name)) @item

(operator_declaration
  symbol: (operator_symbol) @name) @item

(precedence_group_declaration
  name: (type_identifier) @name) @item

(builder_hook_declaration
  hook: (_) @name) @item

(enum_declaration
  name: (type_identifier) @name) @item

(extension_declaration
  type: (_) @name) @item

(function_declaration
  name: (identifier) @name) @item

(variable_declaration
  name: (identifier) @name) @item

(enum_case_item
  name: (identifier) @name) @item
