"use client";

import { Highlight, themes, type Language } from "prism-react-renderer";
import { registerRangePrism } from "../lib/prism-range";

const prism = registerRangePrism();

export function CodeBlock({
  source,
  syntax,
  label,
}: {
  source: string;
  syntax: string;
  label: string;
}) {
  const language = syntax as Language;

  return (
    <section className="codeBlock" aria-label={label}>
      <header>{label}</header>
      <Highlight prism={prism} theme={themes.github} code={source.trimEnd()} language={language}>
        {({ className, style, tokens, getLineProps, getTokenProps }) => (
          <div className="codeBlockBody">
            <pre className={className} style={{ ...style, background: "transparent" }}>
              <code>
                {tokens.map((line, lineIndex) => {
                  const { key: _lineKey, ...lineProps } = getLineProps({
                    line,
                    key: lineIndex,
                  });
                  return (
                    <span {...lineProps} key={lineIndex}>
                      {line.map((token, tokenIndex) => {
                        const { key: _tokenKey, ...tokenProps } = getTokenProps({
                          token,
                          key: tokenIndex,
                        });
                        return <span {...tokenProps} key={tokenIndex} />;
                      })}
                      {"\n"}
                    </span>
                  );
                })}
              </code>
            </pre>
          </div>
        )}
      </Highlight>
    </section>
  );
}
