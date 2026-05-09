import AppKit
import SwiftUI

/// 使用 NSTextView，便于监听滚动并与预览同步（TextEditor 无法取滚动位置）。
struct MacMarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var scrollBridge: MarkdownScrollBridge
    /// 编辑区字体（由 LibraryState.resolvedEditorFont 提供）。
    var editorFont: NSFont
    /// 与侧栏「笔记本内查找」同步：在正文中标出所有匹配（空字符串则清除高亮背景）。
    var notebookSearchQuery: String
    var notebookSearchCaseSensitive: Bool
    /// SwiftUI clipShape 对 NSViewRepresentable 无效；通过 CALayer 直接设置底部圆角。
    var bottomLeadingRadius: CGFloat = 0
    var bottomTrailingRadius: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.drawsBackground = false   // 让 SwiftUI 面板背景透出，避免与面板色不一致
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        /// 需为 `true` 才能在正文上绘制笔记本搜索高亮背景；内容仍为纯 Markdown 字符串，由绑定同步。
        textView.isRichText = true
        /// MacDown `findStyle="bar"`：内联查找条 + 增量搜索。
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = editorFont
        textView.typingAttributes = [.font: editorFont]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.string = text
        Self.applyMarkdownRendering(textView: textView, baseFont: editorFont)
        Self.applyNotebookSearchHighlight(
            textView: textView,
            query: notebookSearchQuery,
            caseSensitive: notebookSearchCaseSensitive,
            baseFont: editorFont
        )

        scroll.documentView = textView

        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.notifyScroll()
        }

        scrollBridge.editorScrollView = scroll
        context.coordinator.scrollView = scroll

        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        Self.applyLayerCorners(to: scroll, bottomLeading: bottomLeadingRadius, bottomTrailing: bottomTrailingRadius)

        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollBridge.editorScrollView = scrollView
        Self.applyLayerCorners(to: scrollView, bottomLeading: bottomLeadingRadius, bottomTrailing: bottomTrailingRadius)
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        if tv.font != editorFont {
            tv.font = editorFont
            tv.typingAttributes = [.font: editorFont]
        }
        Self.applyMarkdownRendering(textView: tv, baseFont: editorFont)
        Self.applyNotebookSearchHighlight(
            textView: tv,
            query: notebookSearchQuery,
            caseSensitive: notebookSearchCaseSensitive,
            baseFont: editorFont
        )
    }

    /// 对 NSScrollView 的 CALayer 直接设置底部圆角（NSView 层坐标系已翻转：MaxY = 底部）。
    private static func applyLayerCorners(to scroll: NSScrollView, bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        guard let layer = scroll.layer else { return }
        let radius = max(bottomLeading, bottomTrailing)
        layer.cornerRadius = radius
        var mask = CACornerMask()
        if bottomLeading  > 0 { mask.insert(.layerMinXMaxYCorner) }
        if bottomTrailing > 0 { mask.insert(.layerMaxXMaxYCorner) }
        layer.maskedCorners = mask
    }

    private static func applyMarkdownRendering(textView: NSTextView, baseFont: NSFont) {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        MarkdownEditorSyntaxHighlight.apply(to: textView, baseFont: baseFont, isDarkAppearance: dark)
    }

    /// 与 `LibraryState.notebookSearchCompareOptions` 一致：非重叠匹配，系统查找高亮色。
    private static func applyNotebookSearchHighlight(
        textView: NSTextView,
        query rawQuery: String,
        caseSensitive: Bool,
        baseFont: NSFont
    ) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: full)
        storage.addAttribute(.font, value: baseFont, range: full)

        let needle = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            storage.endEditing()
            return
        }

        let opts: NSString.CompareOptions = caseSensitive ? [] : .caseInsensitive
        let ns = storage.string as NSString
        let nLen = ns.length
        let mLen = (needle as NSString).length
        guard mLen > 0, nLen >= mLen else {
            storage.endEditing()
            return
        }

        var offset = 0
        while offset <= nLen - mLen {
            let searchRange = NSRange(location: offset, length: nLen - offset)
            let found = ns.range(of: needle, options: opts, range: searchRange)
            if found.location == NSNotFound { break }
            storage.addAttribute(.backgroundColor, value: NSColor.findHighlightColor, range: found)
            offset = found.location + found.length
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacMarkdownTextEditor
        weak var scrollView: NSScrollView?
        var boundsObserver: NSObjectProtocol?

        init(_ parent: MacMarkdownTextEditor) {
            self.parent = parent
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func notifyScroll() {
            parent.scrollBridge.editorScrolled()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
