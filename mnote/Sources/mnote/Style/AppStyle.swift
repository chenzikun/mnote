import SwiftUI

/// 4 种视觉风格，与 robotos web 端 data-theme 对齐：
/// glass-dark / glass-light / neu-light / neu-dark
enum AppStyle: String, CaseIterable, Identifiable, Codable {
    case glassDark  = "glass-dark"
    case glassLight = "glass-light"
    case neuLight   = "neu-light"
    case neuDark    = "neu-dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glassDark:  return "液体玻璃 · 暗色"
        case .glassLight: return "液体玻璃 · 亮色"
        case .neuLight:   return "新拟态 · 亮色"
        case .neuDark:    return "新拟态 · 暗色"
        }
    }

    /// 是否为液态玻璃系（backdrop-filter 毛玻璃）。
    var isGlass: Bool { self == .glassDark || self == .glassLight }
    /// 是否为新拟态系（实色背景 + 浮雕阴影）。
    var isNeu:   Bool { !isGlass }
    /// 是否为深色模式。
    var isDark:  Bool { self == .glassDark || self == .neuDark }

    /// SwiftUI 首选配色方案（`preferredColorScheme`）。
    var preferredColorScheme: ColorScheme { isDark ? .dark : .light }

    // MARK: - 新拟态调色板

    /// neu-light 基础背景色 #E0E5EC
    static let neuLightBg = Color(red: 0.878, green: 0.898, blue: 0.925)
    /// neu-dark 基础背景色 #1E2028
    static let neuDarkBg  = Color(red: 0.118, green: 0.125, blue: 0.157)

    var neuBg: Color {
        isDark ? AppStyle.neuDarkBg : AppStyle.neuLightBg
    }

    // MARK: - 预览渐变（设置页卡片缩略图）

    var previewGradient: LinearGradient {
        switch self {
        case .glassDark:
            return LinearGradient(
                colors: [Color(red: 0.04, green: 0.08, blue: 0.15),
                         Color(red: 0.11, green: 0.15, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .glassLight:
            return LinearGradient(
                colors: [Color(red: 0.91, green: 0.95, blue: 1.0),
                         Color(red: 0.84, green: 0.91, blue: 1.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .neuLight:
            return LinearGradient(
                colors: [AppStyle.neuLightBg, AppStyle.neuLightBg],
                startPoint: .top, endPoint: .bottom
            )
        case .neuDark:
            return LinearGradient(
                colors: [AppStyle.neuDarkBg, AppStyle.neuDarkBg],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - 迁移（旧设置 → appStyle）

    /// 从旧版 `liquidGlassEnabled` + `appTheme` 推断最近的 AppStyle。
    static func migrate(glassEnabled: Bool, themeName: String?) -> AppStyle {
        switch (glassEnabled, themeName) {
        case (true,  "light"):  return .glassLight
        case (true,  _):        return .glassDark
        case (false, "light"):  return .neuLight
        case (false, _):        return .neuDark
        }
    }
}
