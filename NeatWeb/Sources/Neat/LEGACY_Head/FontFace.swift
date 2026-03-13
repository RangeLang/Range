import Foundation

/// Head primitive for declaring a font family and ensuring its assets are
/// available to the page. Supports both:
///
/// - External font stylesheets (e.g. Google Fonts), when the URL is `http`/`https`.
/// - Self-hosted WOFF2 font files, when the URL is a local path (e.g. `/fonts/...`).
///
/// Usage:
///
///     // Define font families somewhere central
///     extension FontFamily {
///         static let geist = FontFamily(
///             "Geist",
///             "https://fonts.googleapis.com/css2?family=Geist:wght@100..900&display=swap"
///         )
///
///         static let openSans = FontFamily(
///             "Open Sans",
///             "/fonts/OpenSans-Regular.woff2"
///         )
///     }
///
///     // In App.head:
///     FontFace(.geist, loading: .preload)    // external CSS + preload-as-style
///     FontFace(.openSans)                    // local @font-face only
///
///     // In components:
///     Text("Hello").font(.geist)
///     Text("World").font(.openSans)
public struct FontFace: _PrimitiveHead {
    public enum Loading {
        /// Declare the font without any explicit preload hints.
        case standard
        /// Add a preload hint:
        /// - For external fonts: `rel="preload" as="style"` for the stylesheet.
        /// - For local fonts:    `rel="preload" as="font"` for the WOFF2 file.
        case preload
    }

    public let family: FontFamily
    public let loading: Loading

    public init(_ family: FontFamily, loading: Loading = .standard) {
        self.family = family
        self.loading = loading
    }

    public func build(in context: RenderContext?) -> ElementNode {
        guard let url = family._ff_url, !url.isEmpty else {
            // No URL associated with this family; nothing to declare.
            return .fragment([])
        }

        if family._ff_isExternal {
            return buildExternal(url: url)
        } else {
            return buildLocal(url: url)
        }
    }

    // MARK: - External (stylesheet-backed) fonts

    private func buildExternal(url: String) -> ElementNode {
        let stylesheetNode = ElementNode(
            tag: "link",
            attributes: [
                "rel": "stylesheet",
                "href": url
            ]
        )

        guard loading == .preload else {
            return stylesheetNode
        }

        let preloadNode = ElementNode(
            tag: "link",
            attributes: [
                "rel": "preload",
                "as": "style",
                "href": url
            ]
        )

        return .fragment([
            preloadNode,
            stylesheetNode
        ])
    }

    // MARK: - Local (self-hosted) fonts

    private func buildLocal(url: String) -> ElementNode {
        // Minimal @font-face declaration for a single self-hosted WOFF2 file.
        // This can be extended later with weight/style ranges or unicode-range.
        let css = """
        @font-face {
            font-family: "\(family.name)";
            src: url("\(url)") format("woff2");
            font-weight: 400;
            font-style: normal;
            font-display: swap;
        }
        """

        let styleNode = ElementNode(
            tag: "style",
            children: [
                .text(css)
            ]
        )

        guard loading == .preload else {
            return styleNode
        }

        let preloadNode = ElementNode(
            tag: "link",
            attributes: [
                "rel": "preload",
                "as": "font",
                "href": url,
                "type": "font/woff2",
                "crossorigin": "anonymous"
            ]
        )

        return .fragment([
            preloadNode,
            styleNode
        ])
    }
}

// MARK: - Internal helpers

private extension FontFamily {
    /// Unified URL accessor. Today this just forwards `url`, but if the struct
    /// evolves this can be updated without touching call sites.
    var _ff_url: String? {
        return url
    }

    /// Heuristic to distinguish external (http/https) from local URLs.
    var _ff_isExternal: Bool {
        isExternal
    }
}
