import AppKit
import cmark_gfm
import cmark_gfm_extensions

/// 编辑区内 Markdown 语法着色（cmark 源码范围 + NSTextStorage），色相分层参考 MacDown / peg-markdown-highlight。
enum MarkdownEditorSyntaxHighlight {

    static func apply(to textView: NSTextView, baseFont: NSFont, isDarkAppearance: Bool) {
        guard let storage = textView.textStorage else { return }
        let plain = storage.string as NSString
        let fullLength = plain.length
        let full = NSRange(location: 0, length: fullLength)
        storage.beginEditing()
        resetBaseAttributes(storage: storage, range: full, baseFont: baseFont)
        guard fullLength > 0,
              let doc = parseGFMDocument(storage.string)
        else {
            storage.endEditing()
            return
        }
        let palette = Palette(isDark: isDarkAppearance)
        walk(
            node: doc,
            storage: storage,
            fullString: plain,
            fullLength: fullLength,
            baseFont: baseFont,
            palette: palette
        )
        cmark_node_free(doc)
        storage.endEditing()
    }

    private static func resetBaseAttributes(storage: NSTextStorage, range: NSRange, baseFont: NSFont) {
        storage.removeAttribute(.backgroundColor, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.setAttributes(
            [.font: baseFont, .foregroundColor: NSColor.labelColor],
            range: range
        )
    }

    private static func parseGFMDocument(_ markdown: String) -> UnsafeMutablePointer<cmark_node>? {
        cmark_gfm_core_extensions_ensure_registered()
        let parseOptions = CMARK_OPT_SMART | CMARK_OPT_GITHUB_PRE_LANG
        guard let parser = cmark_parser_new(parseOptions) else { return nil }
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
        return cmark_parser_finish(parser)
    }

    private struct Palette {
        let isDark: Bool
        var heading: NSColor { hsb(0.72, 0.75, isDark ? 0.88 : 0.42) }
        var blockQuote: NSColor { hsb(0.34, 0.35, isDark ? 0.65 : 0.45) }
        var emphasis: NSColor { hsb(0.15, 0.45, isDark ? 0.85 : 0.38) }
        var link: NSColor { hsb(0.67, 0.85, isDark ? 0.95 : 0.45) }
        var codeInlineFg: NSColor { hsb(0, 0.65, isDark ? 0.95 : 0.35) }
        var codeInlineBg: NSColor { NSColor.labelColor.withAlphaComponent(isDark ? 0.12 : 0.08) }
        var codeBlockBg: NSColor { NSColor.labelColor.withAlphaComponent(isDark ? 0.14 : 0.09) }
        var hrAndMeta: NSColor { hsb(0, 0, isDark ? 0.45 : 0.55) }
        var html: NSColor { hsb(0.08, 0.55, isDark ? 0.72 : 0.45) }

        private func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(calibratedHue: h, saturation: s, brightness: b, alpha: 1)
        }
    }

    private static func walk(
        node: UnsafeMutablePointer<cmark_node>?,
        storage: NSTextStorage,
        fullString: NSString,
        fullLength: Int,
        baseFont: NSFont,
        palette: Palette
    ) {
        guard let node else { return }
        let type = cmark_node_get_type(node)
        if let range = sourceRange(of: node, fullString: fullString, fullUTF16Length: fullLength),
           range.length > 0 {
            applyStyle(
                for: type,
                node: node,
                range: range,
                storage: storage,
                baseFont: baseFont,
                palette: palette
            )
        }
        var child = cmark_node_first_child(node)
        while let c = child {
            walk(node: c, storage: storage, fullString: fullString, fullLength: fullLength, baseFont: baseFont, palette: palette)
            child = cmark_node_next(c)
        }
    }

    private static func applyStyle(
        for type: cmark_node_type,
        node: UnsafeMutablePointer<cmark_node>,
        range: NSRange,
        storage: NSTextStorage,
        baseFont: NSFont,
        palette: Palette
    ) {
        switch type {
        case CMARK_NODE_HEADING:
            let level = max(1, min(6, Int(cmark_node_get_heading_level(node))))
            let step: CGFloat = max(0, 6 - CGFloat(level)) * 1.2
            let size = baseFont.pointSize + step
            let f = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
            storage.addAttributes([.font: f, .foregroundColor: palette.heading], range: range)
        case CMARK_NODE_BLOCK_QUOTE:
            storage.addAttribute(.foregroundColor, value: palette.blockQuote, range: range)
        case CMARK_NODE_CODE_BLOCK:
            storage.addAttributes(
                [.font: baseFont, .backgroundColor: palette.codeBlockBg],
                range: range
            )
        case CMARK_NODE_THEMATIC_BREAK:
            storage.addAttribute(.foregroundColor, value: palette.hrAndMeta, range: range)
        case CMARK_NODE_HTML_BLOCK:
            storage.addAttributes([.font: baseFont, .foregroundColor: palette.html], range: range)
        case CMARK_NODE_EMPH:
            let f = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            storage.addAttributes([.font: f, .foregroundColor: palette.emphasis], range: range)
        case CMARK_NODE_STRONG:
            let f = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            storage.addAttributes([.font: f, .foregroundColor: NSColor.labelColor], range: range)
        case CMARK_NODE_LINK, CMARK_NODE_IMAGE:
            storage.addAttributes(
                [
                    .foregroundColor: palette.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: range
            )
        case CMARK_NODE_CODE:
            let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 0.5, weight: .regular)
            storage.addAttributes(
                [
                    .font: codeFont,
                    .foregroundColor: palette.codeInlineFg,
                    .backgroundColor: palette.codeInlineBg,
                ],
                range: range
            )
        case CMARK_NODE_HTML_INLINE:
            storage.addAttributes([.font: baseFont, .foregroundColor: palette.html], range: range)
        default:
            if let s = cmark_node_get_type_string(node), let str = String(validatingUTF8: s), str == "strikethrough" {
                storage.addAttributes(
                    [
                        .foregroundColor: palette.hrAndMeta,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    ],
                    range: range
                )
            }
        }
    }

    private static func sourceRange(
        of node: UnsafeMutablePointer<cmark_node>,
        fullString: NSString,
        fullUTF16Length: Int
    ) -> NSRange? {
        let sl = Int(cmark_node_get_start_line(node))
        let el = Int(cmark_node_get_end_line(node))
        let sc = Int(cmark_node_get_start_column(node))
        let ec = Int(cmark_node_get_end_column(node))
        guard sl > 0, el > 0, sc > 0, ec > 0,
              let start = utf16Offset(line: sl, column: sc, fullString: fullString, fullUTF16Length: fullUTF16Length),
              let end = utf16Offset(line: el, column: ec, fullString: fullString, fullUTF16Length: fullUTF16Length),
              end >= start
        else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    /// cmark 行、列均为 1-based；列按与 UTF-16 对齐的字符步进（适用于常见 Markdown 源）。
    private static func utf16Offset(
        line: Int,
        column: Int,
        fullString: NSString,
        fullUTF16Length: Int
    ) -> Int? {
        guard line >= 1, column >= 1 else { return nil }
        var lineNum = 1
        var i = 0
        while i < fullUTF16Length && lineNum < line {
            if fullString.character(at: i) == 10 {
                lineNum += 1
            }
            i += 1
        }
        guard lineNum == line else { return nil }
        let lineStart = i
        let pos = lineStart + (column - 1)
        guard pos <= fullUTF16Length else { return nil }
        return pos
    }
}
