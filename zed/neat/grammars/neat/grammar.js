const PREC = {
  member: 8,
  call: 7,
  modifier: 6,
};

module.exports = grammar({
  name: "neat",

  extras: ($) => [/\s/, $.comment],

  word: ($) => $.identifier,

  supertypes: ($) => [$.declaration, $.expression, $.type],

  rules: {
    source_file: ($) => repeat($.declaration),

    declaration: ($) =>
      choice(
        $.annotated_declaration,
        $.protocol_declaration,
        $.extension_declaration,
        $.enum_declaration,
        $.function_declaration,
        $.variable_declaration,
      ),

    protocol_declaration: ($) =>
      seq("protocol", field("name", $.type_identifier), field("body", $.block)),

    annotated_declaration: ($) =>
      choice(
        seq(
          alias("@main", $.main_attribute),
          field("name", $.type_identifier),
          ":",
          commaSep1($.type_identifier),
          field("body", $.block),
        ),
        seq(
          field("attribute", $.attribute),
          optional(seq(":", commaSep1($.type_identifier))),
          field("body", $.block),
        ),
      ),

    attribute: ($) =>
      seq(
        "@",
        choice($.identifier, $.type_identifier),
        optional(seq("(", field("argument", $.type), ")")),
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
      seq(
        choice("let", "var"),
        field("name", $.identifier),
        optional(seq(":", field("type", $.type))),
        optional(seq("=", field("value", $.expression))),
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

    parameter: ($) =>
      seq(
        choice(
          seq(
            field("external_name", $.identifier),
            field("name", $.identifier),
            ":",
            field("type", $.type),
          ),
          seq(field("name", $.identifier), ":", field("type", $.type)),
          field("type", $.type),
        ),
        optional(seq("=", field("default_value", $.expression))),
      ),

    type: ($) =>
      choice(
        $.type_identifier,
        $.array_type,
        $.dictionary_type,
        $.optional_type,
        $.member_type,
      ),

    array_type: ($) => seq("[", field("element", $.type), "]"),

    dictionary_type: ($) =>
      seq("[", field("key", $.type), ":", field("value", $.type), "]"),

    optional_type: ($) => seq(field("wrapped", $.type_identifier), "?"),

    member_type: ($) =>
      prec.left(
        PREC.member,
        seq(
          field("base", $.type_identifier),
          ".",
          field("member", $.type_identifier),
        ),
      ),

    block: ($) =>
      seq(
        "{",
        repeat(
          choice(
            $.declaration,
            $.member_declaration,
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

    expression: ($) =>
      choice(
        $.call_expression,
        $.modifier_call,
        $.member_expression,
        $.closure_expression,
        $.dictionary_literal,
        $.array_literal,
        $.string_literal,
        $.float_literal,
        $.integer_literal,
        $.boolean_literal,
        $.type_identifier,
        $.identifier,
      ),

    call_expression: ($) =>
      prec.left(
        PREC.call,
        seq(
          field(
            "function",
            choice($.identifier, $.type_identifier, $.member_expression),
          ),
          optional(field("arguments", $.argument_clause)),
          optional(field("body", $.block)),
          repeat(field("modifier", $.modifier_call)),
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

    interpolation: ($) => seq("\\(", repeat(choice($.expression, /[^)]/)), ")"),

    string_content: (_) => token.immediate(/[^"\\]+/),

    escape_sequence: (_) => token.immediate(seq("\\", /./)),

    integer_literal: (_) => /\d+/,

    float_literal: (_) => /\d+\.\d+/,

    boolean_literal: (_) => choice("true", "false"),

    identifier: (_) => /[a-z_][A-Za-z0-9_]*/,

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
