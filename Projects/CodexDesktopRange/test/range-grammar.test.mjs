import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createHighlighter } from "shiki";

const grammar = JSON.parse(
  await readFile(new URL("../range.tmLanguage.json", import.meta.url), "utf8"),
);
const darkTheme = JSON.parse(
  await readFile(new URL("../range-codability-dark.json", import.meta.url), "utf8"),
);
const lightTheme = JSON.parse(
  await readFile(new URL("../range-codability-light.json", import.meta.url), "utf8"),
);

function tokenFor(tokens, content) {
  return tokens.flat().find((token) => token.content === content);
}

test("Range grammar highlights the language surface", async () => {
  const highlighter = await createHighlighter({
    themes: [darkTheme, lightTheme],
    langs: [grammar],
  });
  const code = [
    "@main {",
    '    let message: String("hello \\(Range)")',
    "    print(value: message)",
    "}",
  ].join("\n");
  const tokens = highlighter.codeToTokensBase(code, {
    lang: "range",
    theme: "range-codability-dark",
  });
  const styled = tokens.flat().filter((token) => token.color != null);

  assert.ok(styled.some((token) => token.content === "let"));
  assert.ok(styled.some((token) => token.content === "String"));
  assert.ok(styled.some((token) => token.content.includes("hello")));
  assert.ok(styled.some((token) => token.content === "value"));
});

test("Range grammar mirrors the Zed Codability capture colors", async () => {
  const highlighter = await createHighlighter({
    themes: [darkTheme, lightTheme],
    langs: [grammar],
  });
  const code = [
    "macro many(count: Int?): @member {",
    "  let element: #environment.target.Declaration.type",
    "  if #environment.target.Application.values.count != count {",
    '    @diagnostic("negative")',
    "  }",
    "}",
  ].join("\n");

  for (const [theme, expected] of [
    ["range-codability-dark", { keyword: "#55A8FF", macro: "#B6A0FF", type: "#70D9D1", property: "#62C5BE", string: "#F5A524" }],
    ["range-codability-light", { keyword: "#0073E4", macro: "#886DE9", type: "#008C86", property: "#007974", string: "#B45309" }],
  ]) {
    const tokens = highlighter.codeToTokensBase(code, { lang: "range", theme });
    assert.equal(tokenFor(tokens, "macro")?.color, expected.keyword);
    assert.equal(tokenFor(tokens, "#environment")?.color, expected.macro);
    assert.equal(tokenFor(tokens, "Int")?.color, expected.type);
    assert.equal(tokenFor(tokens, "target")?.color, expected.property);
    assert.equal(tokenFor(tokens, '"negative"')?.color, expected.string);
  }
});
