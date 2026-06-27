import AppKit
import SwiftUI

/// 编辑器等宽字体预设；仅列出程序员常用字体，运行时自动过滤系统中未安装的项。
struct EditorFontPreset: Identifiable, Equatable {
    /// 字体的 PostScript 名，或固定值 `"system"` 表示使用系统默认等宽字体（SF Mono）。
    let id: String
    let displayName: String

    // MARK: - 预设列表

    static let all: [EditorFontPreset] = [
        EditorFontPreset(id: "system",                displayName: "SF Mono"),
        EditorFontPreset(id: "Menlo-Regular",         displayName: "Menlo"),
        EditorFontPreset(id: "Monaco",                displayName: "Monaco"),
        EditorFontPreset(id: "JetBrainsMono-Regular", displayName: "JetBrains Mono"),
        EditorFontPreset(id: "FiraCode-Regular",      displayName: "Fira Code"),
        EditorFontPreset(id: "CascadiaCode-Regular",  displayName: "Cascadia Code"),
        EditorFontPreset(id: "SourceCodePro-Regular", displayName: "Source Code Pro"),
        EditorFontPreset(id: "Hack-Regular",          displayName: "Hack"),
        EditorFontPreset(id: "Inconsolata-Regular",   displayName: "Inconsolata"),
        EditorFontPreset(id: "CourierNewPSMT",        displayName: "Courier New"),
    ]

    /// 当前系统中已安装的预设（system 始终包含）。
    static let available: [EditorFontPreset] = all.filter { $0.isAvailable }

    // MARK: - 解析

    var isAvailable: Bool {
        id == "system" || NSFont(name: id, size: 13) != nil
    }

    /// 用指定字号实例化对应的 NSFont；字体未安装时回退到 SF Mono。
    func resolve(size: CGFloat) -> NSFont {
        if id == "system" {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: id, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// 从持久化的 id 字符串还原预设；未找到时返回系统默认。
    static func preset(for id: String) -> EditorFontPreset {
        all.first { $0.id == id } ?? all[0]
    }

    /// SwiftUI Font，安全处理系统动态字体。
    /// macOS 26+ 起 `monospacedSystemFont` 返回 `.AppleSystemUIFontMonospaced-Regular`（动态字体），
    /// `Font(NSFont:)` 桥接不支持动态字体会导致渲染失败；system preset 改用 `.system(design:.monospaced)`。
    func swiftUIFont(size: CGFloat) -> Font {
        if id == "system" {
            return .system(size: size, design: .monospaced)
        }
        if let nsFont = NSFont(name: id, size: size) {
            return Font(nsFont)
        }
        return .system(size: size, design: .monospaced)
    }
}
