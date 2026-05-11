import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let onOpenLink: (String) -> Void
    var scrollBridge: MarkdownScrollBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenLink: onOpenLink, scrollBridge: scrollBridge)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        // 公开 API（macOS 12+）：抑制超出内容区域时的背景拉伸色
        web.underPageBackgroundColor = .clear
        // KVC 路径：抑制 WebKit 内部绘图背景；目前仍是使 WKWebView 完全透明的必要手段。
        // Apple 已封过 scrollView KVC（故 MarkdownScrollBridge 改为 BFS 遍历），
        // 此路径暂时有效；underPageBackgroundColor 作为公开备份，一旦 KVC 失效可提供部分保障。
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.attachScrollObservationIfNeeded(webView: web)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.attachScrollObservationIfNeeded(webView: nsView)
        context.coordinator.scrollBridge = scrollBridge
        scrollBridge.webView = nsView
        if context.coordinator.lastHTML != html || context.coordinator.lastBaseURL != baseURL {
            context.coordinator.lastHTML = html
            context.coordinator.lastBaseURL = baseURL
            nsView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var lastBaseURL: URL?
        let onOpenLink: (String) -> Void
        var scrollBridge: MarkdownScrollBridge
        private var scrollObserver: NSObjectProtocol?
        private var didAttachScroll = false
        /// 与 MacDown / 系统「查找…」一致：WKWebView 实现 `NSTextFinderClient`，需挂 `NSTextFinder` + `findBarContainer`（其内部 `NSScrollView`）才能稳定出现页内查找条。
        private var previewTextFinder: NSTextFinder?

        init(onOpenLink: @escaping (String) -> Void, scrollBridge: MarkdownScrollBridge) {
            self.onOpenLink = onOpenLink
            self.scrollBridge = scrollBridge
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            attachPreviewTextFinderIfNeeded(webView: webView)
        }

        private func attachPreviewTextFinderIfNeeded(webView: WKWebView) {
            guard previewTextFinder == nil else { return }
            guard let scroll = webView.mnote_enclosingScrollView else { return }
            let finder = NSTextFinder()
            finder.client = webView
            finder.findBarContainer = scroll
            previewTextFinder = finder
        }

        func attachScrollObservationIfNeeded(webView: WKWebView) {
            guard !didAttachScroll else { return }
            scrollBridge.webView = webView
            guard let sc = webView.mnote_enclosingScrollView else { return }
            sc.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: sc.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.scrollBridge.previewScrolled()
            }
            didAttachScroll = true
        }

        // async 版本（macOS 13+ / iOS 16+，项目最低 macOS 14 覆盖），
        // 替代已弃用的基于 @escaping decisionHandler 闭包的旧签名。
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                onOpenLink(url.absoluteString)
                return .cancel
            }
            return .allow
        }
    }
}
