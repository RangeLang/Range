# Range Highlighting

This directory owns editor-agnostic highlighting policy for Range.

The split is:

- `codability-palette.yaml` defines the intended color taxonomy and the
  Codability code-preview palette.
- The Range compiler host emits semantic token meaning through editor tooling.
- `Editor/Highlighting` defines how those semantic categories should map to editor style names.
- Editor extensions generate their local configuration from these files.
- Tree-sitter query files remain fallback syntax highlighting for files without semantic token support.

In `codability-palette.yaml`, `Supported` means the current end-to-end Range
editor pipeline can emit and style that category. `ZedNative` is separate: it
tracks whether Zed already has a direct style category we can target, or whether
Range needs extra semantic token work, parser work, or adapter mapping first.

The historical Xcode importer remains available for palette research:

```sh
ruby Editor/Highlighting/Scripts/import-xcode-theme.rb \
  --palette /path/to/xcode-reference-palette.yaml
```

Use `--dark`, `--light`, and `--palette` to point it at explicit research
inputs. Do not run it against `codability-palette.yaml`: the website's
Codability treatment is now the design source of truth.

To build the Zed theme from the palette:

```sh
../RangeZed/scripts/build-zed-theme.sh
```

This writes `../RangeZed/themes/range-codability.json`. Native Zed syntax scopes are
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
