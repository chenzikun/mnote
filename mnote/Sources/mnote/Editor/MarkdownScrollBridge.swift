import AppKit
import SwiftUI
import WebKit

extension WKWebView {
    /// 查找用于文档滚动的 `NSScrollView`。新版 WebKit 已禁止对 `scrollView` 使用 KVC（会抛异常），改为遍历子视图。
    var mnote_enclosingScrollView: NSScrollView? {
        if let sc = enclosingScrollView, sc.documentView != nil {
            return sc
        }
        var queue: [NSView] = [self]
        var index = 0
        while index < queue.count {
            let v = queue[index]
            index += 1
            if let sc = v as? NSScrollView, sc.documentView != nil {
                return sc
            }
            queue.append(contentsOf: v.subviews)
        }
        return nil
    }
}

/// 编辑区与 WKWebView 预览之间按比例同步滚动。
final class MarkdownScrollBridge: ObservableObject {
    weak var webView: WKWebView?
    weak var editorScrollView: NSScrollView?

    private var lockingWeb = false
    private var lockingEditor = false

    func editorScrolled() {
        guard !lockingEditor, !lockingWeb, let w = webView, editorScrollView != nil else { return }
        let ratio = Self.ratio(fromNSScroll: editorScrollView!)
        lockingWeb = true
        let js = """
        (function() {
          var el = document.documentElement;
          var h = Math.max(0, el.scrollHeight - window.innerHeight);
          window.scrollTo(0, h * \(ratio));
        })();
        """
        w.evaluateJavaScript(js) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.lockingWeb = false
            }
        }
    }

    func previewScrolled() {
        guard !lockingWeb, !lockingEditor, let w = webView, let es = editorScrollView else { return }
        let ratio = Self.ratio(fromWKWebView: w)
        lockingEditor = true
        Self.applyScrollRatio(ratio, to: es)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.lockingEditor = false
        }
    }

    private static func ratio(fromNSScroll scrollView: NSScrollView) -> CGFloat {
        guard let doc = scrollView.documentView else { return 0 }
        let docH = doc.bounds.height
        let visH = scrollView.contentView.bounds.height
        let maxScroll = Swift.max(CGFloat(1), docH - visH)
        let y = scrollView.contentView.bounds.origin.y
        return Swift.min(1, Swift.max(0, y / maxScroll))
    }

    private static func ratio(fromWKWebView webView: WKWebView) -> CGFloat {
        guard let scrollView = webView.mnote_enclosingScrollView else { return 0 }
        guard let doc = scrollView.documentView else { return 0 }
        let docH = doc.bounds.height
        let visH = scrollView.contentView.bounds.height
        let maxScroll = Swift.max(CGFloat(1), docH - visH)
        let y = scrollView.contentView.bounds.origin.y
        return Swift.min(1, Swift.max(0, y / maxScroll))
    }

    private static func applyScrollRatio(_ ratio: CGFloat, to scrollView: NSScrollView) {
        guard let doc = scrollView.documentView else { return }
        let maxScroll = Swift.max(CGFloat(0), doc.bounds.height - scrollView.contentView.bounds.height)
        let y = ratio * maxScroll
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
