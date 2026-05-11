import AppKit
import SwiftUI

/// 同步 `NSWindow` chrome（titlebar 透明化、全尺寸内容区、无分隔线）并保持 `window.title`。
///
/// glass 和 neu 共用相同的透明 chrome 策略：`titlebarAppearsTransparent = true` +
/// `.fullSizeContentView`，差异只在窗口背景色：
/// - glass：`backgroundColor = .clear`（SwiftUI 玻璃渐变填充）
/// - neu：`backgroundColor = NSColor(neuBg)`（SwiftUI NeuBackground 同色固实填充）
///
/// **不要**在这里再挂 `NSTitlebarAccessoryViewController`：`.top` 条与 SwiftUI 工具栏叠层时
/// 在部分系统上会截获事件，导致「工具栏图标点了没反应」。
struct WindowChromeBridge: NSViewRepresentable {
    var appStyle: AppStyle
    /// 主文档窗口传入笔记本名；设置窗口等可省略。
    var title: String = ""

    func makeNSView(context: Context) -> NSView {
        ChromeTitleConfiguratorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? ChromeTitleConfiguratorView else { return }
        v.appStyle = appStyle
        v.title = title
    }
}

private final class ChromeTitleConfiguratorView: NSView {
    var appStyle: AppStyle = .glassDark {
        didSet { applyChrome() }
    }

    var title: String = "" {
        didSet { syncTitleToWindow() }
    }

    /// 仅用于跑 `NSWindow` 配置，不参与命中测试；否则会铺满 `NavigationSplitView` 背后挡住编辑区与工具栏。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChrome()
        syncTitleToWindow()
    }

    override func layout() {
        super.layout()
        syncTitleToWindow()
    }

    private func applyChrome() {
        guard let window else { return }

        // 所有样式统一使用透明 titlebar + fullSizeContentView，
        // 让 SwiftUI 背景（glass 渐变 / NeuBackground 实色）填充整个窗口含 titlebar 区域。
        window.titlebarAppearsTransparent = true
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.toolbar?.showsBaselineSeparator = false
        // titlebarSeparatorStyle 是 macOS 13+ API；最低部署目标为 macOS 14，无需 #available 保护。
        window.titlebarSeparatorStyle = .none

        if appStyle.isGlass {
            // glass：窗口完全透明，SwiftUI 玻璃渐变透出
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            // neu：窗口背景与 NeuBackground 同色，保持不透明避免桌面透出
            window.isOpaque = true
            window.backgroundColor = appStyle.isDark
                ? NSColor(red: 0.118, green: 0.125, blue: 0.157, alpha: 1.0)
                : NSColor(red: 0.878, green: 0.898, blue: 0.925, alpha: 1.0)
        }
    }

    private func syncTitleToWindow() {
        guard let window else { return }
        window.subtitle = ""
        window.titleVisibility = .visible
        if !title.isEmpty, window.title != title {
            window.title = title
        }
    }
}
