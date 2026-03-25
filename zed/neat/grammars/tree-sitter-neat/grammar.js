const PREC = {
  member: 8,
  call: 7,
  modifier: 6,
  unary: 5,
  comparison: 4,
  logical: 3,
  nil_coalescing: 2,
  ternary: 1,
};

module.exports = grammar({
  name: "neat",

  extras: ($) => [/\s/, $.comment],

  word: ($) => $.identifier,

  supertypes: ($) => [$.declaration, $.expression, $.type, $.statement],

  conflicts: ($) => [
    [$.callable_declaration, $.expression],
    [$.callable_declaration],
    [$.derived_declaration],
  ],

  rules: {
    source_file: ($) => repeat($.declaration),

    declaration: ($) =>
      choice(
        $.main_block,
        $.macro_declaration,
        $.builder_declaration,
        $.sigiled_declaration,
        $.builder_hook_declaration,
        $.callable_declaration,
        $.derived_declaration,
        $.protocol_declaration,
        $.extension_declaration,
        $.enum_declaration,
        $.function_declaration,
        $.variable_declaration,
      ),

    main_block: ($) => seq("@", "main", field("body", $.block)),

    macro_declaration: ($) =>
      seq(
        "macro",
        field("name", $.identifier),
        optional(field("generics", $.generic_parameter_clause)),
        optional(field("parameters", $.callable_parameter_clause)),
        ":",
        field("target", $.macro_target),
        field("body", $.macro_body),
      ),

    macro_target: ($) =>
      seq(
        field("kind", choice("Attached", "Freestanding")),
        "<",
        field("type", $.type),
        ">",
      ),

    macro_body: ($) =>
      seq("{", field("bindings", $.macro_bindings), repeat($.statement), "}"),

    macro_bindings: ($) =>
      seq(
        field("target", $.identifier),
        ",",
        field("result", $.identifier),
        ",",
        field("diagnostics", $.identifier),
        "in",
      ),

    builder_declaration: ($) =>
      seq(
        "*",
        "builder",
        field("name", $.type_identifier),
        field("body", $.block),
      ),

    protocol_declaration: ($) =>
      seq("protocol", field("name", $.type_identifier), field("body", $.block)),

    sigiled_declaration: ($) =>
      seq(
        "construct",
        field("name", $.type_identifier),
        optional(seq("on", field("target", $.type_identifier))),
        optional(seq(":", commaSep1($.type_identifier))),
        field("body", $.block),
      ),

    callable_declaration: ($) =>
      choice(
        prec.right(
          seq(
            optional(field("receiver", $.type_identifier)),
            "function",
            field("name", $.identifier),
            field("parameters", $.callable_parameter_clause),
            optional(seq("->", field("return_type", $.type))),
            field("body", $.block),
          ),
        ),
        seq(
          optional(field("receiver", $.type_identifier)),
          "function",
          field("name", $.identifier),
          field("parameters", $.callable_parameter_clause),
          optional(seq("->", field("return_type", $.type))),
        ),
      ),

    derived_declaration: ($) =>
      choice(
        prec.right(
          seq(
            optional(field("builder", $.builder_application)),
            "derived",
            field("name", $.identifier),
            ":",
            field("type", $.type),
            field("body", $.block),
          ),
        ),
        seq(
          optional(field("builder", $.builder_application)),
          "derived",
          field("name", $.identifier),
          ":",
          field("type", $.type),
        ),
      ),

    builder_application: ($) => seq("*", field("name", $.type_identifier)),

    builder_hook_declaration: ($) =>
      seq(
        "*",
        field(
          "hook",
          choice("expression", "block", "optional", "either", "array"),
        ),
        field("parameters", $.callable_parameter_clause),
        optional(seq("->", field("return_type", $.type))),
        field("body", $.block),
      ),

    extension_declaration: ($) =>
      seq(
        "extension",
        field("type", $.type_identifier),
        field("body", $.block),
      ),

    enum_declaration: ($) =>
      seq("enum", field("name", $.type_identifier), field("body", $.enum_body)),

    enum_body: ($) =>
      seq(
        "{",
        repeat(choice($.enum_case, $.declaration, $.assignment, $.expression)),
        "}",
      ),

    enum_case: ($) => prec.right(seq("case", commaSep1($.enum_case_item))),

    enum_case_item: ($) =>
      seq(
        field("name", $.identifier),
        optional(field("arguments", $.parameter_clause)),
      ),

    function_declaration: ($) =>
      seq(
        "func",
        field("name", $.identifier),
        field("parameters", $.parameter_clause),
        optional(seq("->", field("return_type", $.type))),
        field("body", $.block),
      ),

    variable_declaration: ($) =>
      choice(
        seq(
          choice("state", "binding", "value"),
          field("name", $.identifier),
          optional(seq(":", field("type", $.type))),
          optional(seq("=", field("value", $.expression))),
        ),
        seq(
          "environment",
          optional("state"),
          field("name", $.identifier),
          optional(seq(":", field("type", $.type))),
        ),
      ),

    member_declaration: ($) =>
      prec(
        1,
        seq(
          "var",
          field("name", $.identifier),
          ":",
          field("type", $.type),
          field("body", $.block),
        ),
      ),

    parameter_clause: ($) => seq("(", optional(commaSep1($.parameter)), ")"),

    callable_parameter_clause: ($) => seq("(", commaSep1($.parameter), ")"),

    generic_parameter_clause: ($) =>
      seq("<", commaSep1(field("parameter", $.type_identifier)), ">"),

    parameter: ($) =>
      seq(
        choice(
          seq(
            field("external_name", $.identifier),
            field("name", $.identifier),
            ":",
            field("type", choice($.type, $.slot_type)),
          ),
          seq(
            field("name", $.identifier),
            ":",
            field("type", choice($.type, $.slot_type)),
          ),
          field("type", $.type),
        ),
        optional(seq("=", field("default_value", $.expression))),
      ),

    slot_type: ($) => seq("@", field("slot", $.identifier)),

    type: ($) =>
      prec.right(
        choice(
          $.variadic_type,
          $.function_type,
          $.optional_type,
          $.generic_type,
          $.type_identifier,
          $.array_type,
          $.dictionary_type,
          $.member_type,
        ),
      ),

    generic_type: ($) =>
      seq(
        field("base", choice($.type_identifier, $.member_type)),
        "<",
        commaSep1(field("argument", $.type)),
        ">",
      ),

    array_type: ($) => seq("[", field("element", $.type), "]"),

    variadic_type: ($) =>
      seq(
        field(
          "element",
          choice(
            $.function_type,
            $.generic_type,
            $.type_identifier,
            $.array_type,
            $.dictionary_type,
            $.member_type,
          ),
        ),
        "...",
      ),

    dictionary_type: ($) =>
      seq("[", field("key", $.type), ":", field("value", $.type), "]"),

    function_type: ($) =>
      seq(
        "(",
        optional(commaSep1($.type)),
        ")",
        "->",
        field("return_type", $.type),
      ),

    optional_type: ($) =>
      seq(
        field(
          "wrapped",
          choice(
            $.function_type,
            $.generic_type,
            $.type_identifier,
            $.array_type,
            $.dictionary_type,
            $.member_type,
          ),
        ),
        "?",
      ),

    member_type: ($) =>
      prec.left(
        PREC.member,
        seq(
          field("base", $.type_identifier),
          ".",
          field("member", $.type_identifier),
        ),
      ),

    // ── Statements ────────────────────────────────────────────────────────────

    statement: ($) =>
      choice(
        $.environment_provision_statement,
        $.if_statement,
        $.for_statement,
        $.while_statement,
        $.switch_statement,
        $.break_statement,
        $.continue_statement,
        $.return_statement,
      ),

    if_statement: ($) =>
      seq(
        "if",
        field("condition", $.expression),
        field("body", $.block),
        optional(seq("else", field("else", choice($.if_statement, $.block)))),
      ),

    for_statement: ($) =>
      seq(
        "for",
        field("binding", $.identifier),
        "in",
        field("collection", $.expression),
        field("body", $.block),
      ),

    while_statement: ($) =>
      seq("while", field("condition", $.expression), field("body", $.block)),

    switch_statement: ($) =>
      seq(
        "switch",
        field("subject", $.expression),
        "{",
        repeat(choice($.switch_case, $.switch_default)),
        "}",
      ),

    switch_case: ($) =>
      seq("case", field("pattern", $.expression), ":", field("body", $.block)),

    switch_default: ($) => seq("default", ":", field("body", $.block)),

    break_statement: (_) => "break",

    continue_statement: (_) => "continue",

    return_statement: ($) =>
      prec.right(seq("return", optional(field("value", $.expression)))),

    environment_provision_statement: ($) =>
      seq(
        "*",
        "environment",
        optional("state"),
        field("name", $.identifier),
        ":",
        field("type", $.type),
        "=",
        field("value", $.expression),
      ),

    // ── Block ─────────────────────────────────────────────────────────────────

    block: ($) =>
      seq(
        "{",
        repeat(
          choice(
            $.declaration,
            $.member_declaration,
            $.statement,
            $.assignment,
            $.expression,
          ),
        ),
        "}",
      ),

    assignment: ($) =>
      seq(
        field("left", $.identifier),
        field("operator", choice("=", "+=", "-=", "*=", "/=")),
        field("right", $.expression),
      ),

    // ── Expressions ───────────────────────────────────────────────────────────

    expression: ($) =>
      choice(
        $.call_expression,
        $.modifier_call,
        $.member_expression,
        $.closure_expression,
        $.binary_expression,
        $.unary_expression,
        $.ternary_expression,
        $.dictionary_literal,
        $.array_literal,
        $.string_literal,
        $.float_literal,
        $.integer_literal,
        $.boolean_literal,
        $.nil_literal,
        $.type_identifier,
        $.identifier,
      ),

    binary_expression: ($) =>
      choice(
        prec.left(
          PREC.comparison,
          seq(
            field("left", $.expression),
            field("operator", choice("==", "!=", "<", "<=", ">", ">=")),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.logical,
          seq(
            field("left", $.expression),
            field("operator", choice("&&", "||")),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.nil_coalescing,
          seq(
            field("left", $.expression),
            field("operator", token(prec(1, "??"))),
            field("right", $.expression),
          ),
        ),
      ),

    unary_expression: ($) =>
      prec(
        PREC.unary,
        seq(field("operator", "!"), field("operand", $.expression)),
      ),

    ternary_expression: ($) =>
      prec.right(
        PREC.ternary,
        seq(
          field("condition", $.expression),
          "?",
          field("then", $.expression),
          ":",
          field("else", $.expression),
        ),
      ),

    call_expression: ($) =>
      prec.left(
        PREC.call,
        choice(
          seq(
            field(
              "function",
              choice($.identifier, $.type_identifier, $.member_expression),
            ),
            field("arguments", $.argument_clause),
            optional(field("body", $.block)),
            repeat(field("modifier", $.modifier_call)),
          ),
          seq(
            field("function", choice($.type_identifier, $.member_expression)),
            field("body", $.block),
            repeat(field("modifier", $.modifier_call)),
          ),
          seq(
            field(
              "function",
              choice($.identifier, $.type_identifier, $.member_expression),
            ),
            repeat1(field("modifier", $.modifier_call)),
          ),
        ),
      ),

    modifier_call: ($) =>
      prec.left(
        PREC.modifier,
        seq(
          ".",
          field("name", $.identifier),
          optional(field("arguments", $.argument_clause)),
        ),
      ),

    member_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field("base", choice($.identifier, $.type_identifier)),
          ".",
          field("member", $.identifier),
        ),
      ),

    argument_clause: ($) => seq("(", optional(commaSep1($.argument)), ")"),

    argument: ($) =>
      seq(
        optional(seq(field("label", $.identifier), ":")),
        field("value", $.expression),
      ),

    array_literal: ($) => seq("[", optional(commaSep1($.expression)), "]"),

    dictionary_literal: ($) => seq("[", commaSep1($.dictionary_entry), "]"),

    dictionary_entry: ($) =>
      seq(field("key", $.expression), ":", field("value", $.expression)),

    closure_expression: ($) => $.block,

    string_literal: ($) =>
      seq(
        '"',
        repeat(choice($.string_content, $.escape_sequence, $.interpolation)),
        '"',
      ),

    interpolation: ($) => seq("\\(", $.expression, ")"),

    string_content: (_) => token.immediate(/[^"\\]+/),

    escape_sequence: (_) => token.immediate(seq("\\", /./)),

    integer_literal: (_) => /\d+/,

    float_literal: (_) => /\d+\.\d+/,

    boolean_literal: (_) => choice("true", "false"),

    nil_literal: (_) => "nil",

    identifier: (_) =>
      token(choice(/[a-z_][A-Za-z0-9_]*/, /`[A-Za-z_][A-Za-z0-9_]*`/)),

    type_identifier: (_) => /[A-Z][A-Za-z0-9_]*/,

    comment: (_) =>
      token(
        choice(seq("//", /.*/), seq("/*", /[^*]*\*+([^/*][^*]*\*+)*/, "/")),
      ),
  },
});

function commaSep1(rule) {
  return seq(rule, repeat(seq(",", rule)), optional(","));
}
