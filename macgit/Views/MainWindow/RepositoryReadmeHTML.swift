// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import cmark_gfm
import cmark_gfm_extensions

enum RepositoryReadmeHTML {
    /// `untrustedContentHost` is set for pull-request descriptions and comments, which other
    /// users write. Raw HTML stays (the `tagfilter` extension escapes script, style and iframe
    /// tags), but its inline styles are blocked so it cannot imitate app UI, and images load
    /// only from the provider's own hosts so third-party images cannot track viewers.
    static func render(
        _ markdown: String,
        textScale: Double = 1,
        compact: Bool = false,
        untrustedContentHost: String? = nil
    ) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
        defer { cmark_parser_free(parser) }
        for name in ["autolink", "strikethrough", "tagfilter", "tasklist", "table"] {
            if let syntax = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, syntax) }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let html = cmark_render_html(document, CMARK_OPT_UNSAFE, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        let styleNonce = UUID().uuidString
        let contentSecurityPolicy = untrustedContentHost.map { host in
            "default-src 'none'; img-src \(imageSources(forProviderHost: host)) data:; style-src 'nonce-\(styleNonce)'; base-uri 'none'; form-action 'none'"
        } ?? "default-src 'none'; img-src 'self' https: http: data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style nonce="\(styleNonce)">
        :root { color-scheme: light dark; font: \(14 * textScale)px -apple-system, BlinkMacSystemFont, sans-serif; }
        body { margin: 0; padding: \(compact ? "0" : "8px 20px 32px"); color: light-dark(#24292f, #e6edf3); overflow-wrap: anywhere; line-height: 1.65; }
        h1,h2,h3,h4 { line-height: 1.3; margin: 1.4em 0 .6em; } h1 { font-size: 2em; } h2 { font-size: 1.5em; border-bottom: 1px solid light-dark(#d8dee4,#30363d); padding-bottom: .35em; }
        body > :first-child { margin-top: 0; } a { color: light-dark(#0969da,#58a6ff); text-decoration: none; } a:hover { text-decoration: underline; }
        img { max-width: 100%; object-fit: contain; } pre { padding: 16px; overflow-x: auto; border-radius: 8px; background: light-dark(#f6f8fa,#161b22); }
        code { font: .9em ui-monospace, SFMono-Regular, monospace; background: light-dark(#eff1f3,#262c36); border-radius: 4px; padding: .15em .3em; } pre code { background: none; padding: 0; }
        blockquote { margin-left: 0; padding-left: 16px; border-left: 3px solid light-dark(#d0d7de,#30363d); color: light-dark(#57606a,#8b949e); }
        table { border-collapse: collapse; display: block; overflow-x: auto; } th,td { padding: 6px 12px; border: 1px solid light-dark(#d0d7de,#30363d); } tr:nth-child(even) { background: light-dark(#f6f8fa,#161b22); }
        hr { border: 0; border-top: 1px solid light-dark(#d0d7de,#30363d); margin: 24px 0; } input { pointer-events: none; } summary { cursor: pointer; } details { margin: .75em 0; }
        </style></head><body>\(String(cString: html))</body></html>
        """
    }

    /// GitHub serves uploaded images from githubusercontent.com (also after redirects from
    /// github.com); GitLab and self-hosted instances serve uploads from their own host.
    static func imageSources(forProviderHost host: String) -> String {
        let host = host.lowercased()
        guard !host.isEmpty else { return "" }
        var sources = ["https://\(host)", "https://*.\(host)"]
        if host == "github.com" {
            sources.append("https://*.githubusercontent.com")
        }
        return sources.joined(separator: " ")
    }
}
