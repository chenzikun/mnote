import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// 预览 HTML 使用与 [swift-markdown](https://github.com/swiftlang/swift-markdown) 相同的 **cmark-gfm**（swift-cmark）渲染管线，
/// 不做手写 Markdown 解析；GFM 表格/任务列表等由库内扩展完成。
enum MarkdownRenderer {
    static func renderHTML(markdown: String, title: String) -> String {
        let escapedTitle = escapeHTML(title)
        let body = renderGFMHTMLFragment(markdown)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>\(escapedTitle)</title>
          <style>
            :root { color-scheme: light dark; }
            body { font: 15px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; padding: 20px; line-height: 1.6; background: transparent; }
            pre { background: rgba(127,127,127,0.15); padding: 10px; border-radius: 8px; overflow-x: auto; }
            code { font-family: ui-monospace, Menlo, monospace; }
            a { text-decoration: none; border-bottom: 1px dashed currentColor; }
            a:hover { border-bottom-style: solid; }
            blockquote { border-left: 3px solid rgba(127,127,127,0.5); margin: 0; padding-left: 10px; color: rgba(127,127,127,1); }
            p { margin: 0.65em 0; }
            h1, h2, h3, h4, h5, h6 { margin: 1em 0 0.45em; line-height: 1.25; font-weight: 600; }
            hr { margin: 1em 0; border: none; border-top: 1px solid rgba(127,127,127,0.35); }
            ul, ol { margin: 0.5em 0; padding-left: 1.4em; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid rgba(127,127,127,0.35); padding: 6px 8px; }
            th:not([align]), td:not([align]) { text-align: left; }
            th[align="left"], td[align="left"] { text-align: left; }
            th[align="center"], td[align="center"] { text-align: center; }
            th[align="right"], td[align="right"] { text-align: right; }
            input[type="checkbox"] { transform: translateY(1px); }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// cmark-gfm：`cmark_render_html`，扩展附着方式对齐 swift-markdown `CommonMarkConverter.parseString`。
    private static func renderGFMHTMLFragment(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        let parseOptions = CMARK_OPT_SMART | CMARK_OPT_GITHUB_PRE_LANG
        let renderOptions = CMARK_OPT_SMART | CMARK_OPT_GITHUB_PRE_LANG | CMARK_OPT_UNSAFE

        guard let parser = cmark_parser_new(parseOptions) else {
            return ""
        }
        defer { cmark_parser_free(parser) }

        for name in ["table", "strikethrough", "tasklist", "autolink", "tagfilter"] {
            guard let ext = cmark_find_syntax_extension(name) else { continue }
            cmark_parser_attach_syntax_extension(parser, ext)
        }

        let data = Data(markdown.utf8)
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return }
            cmark_parser_feed(parser, base, data.count)
        }

        guard let document = cmark_parser_finish(parser) else {
            return ""
        }
        defer { cmark_node_free(document) }

        guard let mem = cmark_get_default_mem_allocator() else {
            return ""
        }

        let extList = cmark_parser_get_syntax_extensions(parser)
        guard let htmlPtr = cmark_render_html_with_mem(document, renderOptions, extList, mem) else {
            return ""
        }
        defer { mem.pointee.free(htmlPtr) }

        return String(cString: htmlPtr)
    }
}
