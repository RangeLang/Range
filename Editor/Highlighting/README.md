# Range Highlighting

This directory owns editor-agnostic highlighting policy for Range.

The split is:

- `xcode-style-palette.yaml` defines the intended color taxonomy and editable
  Xcode-style palette.
- `RangeCLI` emits semantic token meaning through the language server.
- `Editor/Highlighting` defines how those semantic categories should map to editor style names.
- Editor extensions generate their local configuration from these files.
- Tree-sitter query files remain fallback syntax highlighting for files without semantic token support.

In `xcode-style-palette.yaml`, `Supported` means the current end-to-end Range
editor pipeline can emit and style that category. `ZedNative` is separate: it
tracks whether Zed already has a direct style category we can target, or whether
Range needs extra semantic token work, parser work, or adapter mapping first.

To refresh the palette from Xcode's exported default themes:

```sh
ruby Editor/Highlighting/Scripts/import-xcode-theme.rb
```

The importer updates Xcode-derived color/font fields and leaves Range-specific
support fields such as `Supported`, `ZedNative`, `Needs`, `ZedStyle`, and `Notes`
in the palette. Use `--dark`, `--light`, and `--palette` to point it at custom
theme or palette files.

To build the Zed theme from the palette:

```sh
../RangeZed/scripts/build-zed-theme.sh
```

This writes `../RangeZed/themes/range-xcode.json`. Native Zed syntax scopes are
styled directly from `ZedStyle`; Range-specific LSP aliases from
`semantic_token_rules.zed.json`, such as `macro.range` or
`type.range.declaration`, are enriched with the nearest palette style. The
generator inherits the full UI/editor/terminal styling from
`zed-one-base.json`, which is a vendored copy of Zed's default
`assets/themes/one/one.json`, and only replaces/enriches `style.syntax`.

The current Zed adapter reads `semantic_token_rules.zed.json` and copies it to:

`../RangeZed/languages/range/semantic_token_rules.json`

Keep richer distinctions, such as declaration/application and future project/core origin, in the semantic token stream rather than tree-sitter queries.

In Zed style arrays, put the generic Tree-sitter-compatible scope first and the
Range-specific scope after it. That keeps first-paint syntax highlighting aligned
with semantic highlighting, so tokens do not flash between colors when the LSP
semantic-token response arrives.
