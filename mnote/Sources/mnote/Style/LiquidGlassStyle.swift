import SwiftUI

// MARK: - 内部数据结构

struct LiquidGlassOrb {
    let fill: Color
    let opacity: CGFloat
    let side: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let blur: CGFloat
}

// MARK: - 液态玻璃固定配色（不开放用户选择，每种 glass 风格一套）

private enum GlassPalette {

    // glass-dark：近黑基底 + 蓝紫光球
    static let darkGradient: [Color] = [
        Color(red: 0.04, green: 0.04, blue: 0.10),
        Color(red: 0.06, green: 0.05, blue: 0.13),
        Color(red: 0.05, green: 0.04, blue: 0.11),
    ]
    static let darkOrbs: [LiquidGlassOrb] = [
        LiquidGlassOrb(fill: Color(red: 0.55, green: 0.40, blue: 1.00), opacity: 0.28, side: 480, offsetX: -240, offsetY: -180, blur: 80),
        LiquidGlassOrb(fill: Color(red: 0.30, green: 0.55, blue: 1.00), opacity: 0.22, side: 440, offsetX:  260, offsetY: -120, blur: 90),
        LiquidGlassOrb(fill: Color(red: 0.70, green: 0.40, blue: 1.00), opacity: 0.18, side: 380, offsetX:  120, offsetY:  220, blur: 70),
    ]

    // glass-light：近白基底 + 极淡同色光球（dark 透明度 × 0.30，blur × 1.4）
    static let lightGradient: [Color] = [
        Color(red: 0.96, green: 0.96, blue: 1.00),
        Color(red: 0.98, green: 0.97, blue: 1.00),
        Color(red: 0.95, green: 0.95, blue: 0.99),
    ]
    static let lightOrbs: [LiquidGlassOrb] = darkOrbs.map {
        LiquidGlassOrb(fill: $0.fill, opacity: $0.opacity * 0.30, side: $0.side,
                       offsetX: $0.offsetX, offsetY: $0.offsetY, blur: $0.blur * 1.4)
    }
}

// MARK: - 液态玻璃背景（glass-dark / glass-light）

struct LiquidGlassBackground: View {
    var appStyle: AppStyle   // 仅 glassDark / glassLight 有意义

    var body: some View {
        let isDark   = appStyle.isDark
        let gradient = isDark ? GlassPalette.darkGradient  : GlassPalette.lightGradient
        let orbs     = isDark ? GlassPalette.darkOrbs      : GlassPalette.lightOrbs
        ZStack {
            LinearGradient(colors: gradient,
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ForEach(0..<orbs.count, id: \.self) { i in
                let orb = orbs[i]
                Circle()
                    .fill(orb.fill.opacity(orb.opacity))
                    .frame(width: orb.side, height: orb.side)
                    .blur(radius: orb.blur)
                    .offset(x: orb.offsetX, y: orb.offsetY)
            }
        }
    }
}

// MARK: - 新拟态背景（neu-light / neu-dark）

/// 纯色背景，与面板的浮雕阴影共同构成新拟态外观。
struct NeuBackground: View {
    var isDark: Bool

    var body: some View {
        (isDark ? AppStyle.neuDarkBg : AppStyle.neuLightBg)
            .ignoresSafeArea()
    }
}

// MARK: - AppStyle 视图层扩展（style 决策集中于此，layout 层无需 switch）

extension AppStyle {

    /// 随 appStyle 自动切换的背景视图，layout 层直接调用，无需 switch。
    @ViewBuilder
    var backgroundView: some View {
        switch self {
        case .glassDark, .glassLight:
            LiquidGlassBackground(appStyle: self).ignoresSafeArea()
        case .neuLight:
            NeuBackground(isDark: false).ignoresSafeArea()
        case .neuDark:
            NeuBackground(isDark: true).ignoresSafeArea()
        }
    }

    /// 编辑区文件名栏（editorChromeBar）背景样式。
    var chromeBarBackground: AnyShapeStyle {
        switch self {
        case .glassDark, .glassLight: return AnyShapeStyle(.thinMaterial)
        case .neuLight:               return AnyShapeStyle(AppStyle.neuLightBg)
        case .neuDark:                return AnyShapeStyle(AppStyle.neuDarkBg)
        }
    }
}

// MARK: - 统一面板样式

/// `splitColumn`：分栏内并列使用，去掉外扩阴影，避免与邻栏视觉重叠。
enum LiquidGlassPanelStyle {
    case card
    case splitColumn
}

/// 4 种 AppStyle 对应的面板渲染：
/// - glassDark / glassLight：材质 + 渐变描边 + 投影
/// - neuLight / neuDark：实色背景 + 双向浮雕阴影（card）/ 纯实色（splitColumn）
struct AppPanelModifier: ViewModifier {
    var appStyle: AppStyle
    var cornerRadius: CGFloat = 16
    var panelStyle: LiquidGlassPanelStyle = .card

    func body(content: Content) -> some View {
        switch appStyle {
        case .glassDark:
            if panelStyle == .splitColumn {
                content
                    .background(
                        Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.78),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            } else {
                content
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.90), Color.white.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            }

        case .glassLight:
            if panelStyle == .splitColumn {
                content
                    .background(
                        Color.white.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.60), lineWidth: 1)
                    )
            } else {
                content
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.90), Color.white.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            }

        case .neuLight:
            if panelStyle == .splitColumn {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppStyle.neuLightBg)
                    )
            } else {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppStyle.neuLightBg)
                            .shadow(color: Color.black.opacity(0.13), radius: 7, x: 6, y: 6)
                            .shadow(color: Color.white.opacity(0.82), radius: 7, x: -6, y: -6)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }

        case .neuDark:
            if panelStyle == .splitColumn {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppStyle.neuDarkBg)
                    )
            } else {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppStyle.neuDarkBg)
                            .shadow(color: Color.black.opacity(0.45), radius: 6, x: 5, y: 5)
                            .shadow(color: Color.white.opacity(0.04), radius: 6, x: -5, y: -5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }
}

extension View {
    /// 统一面板修饰符，支持全部 4 种 AppStyle。
    func appPanel(
        appStyle: AppStyle,
        cornerRadius: CGFloat = 16,
        panelStyle: LiquidGlassPanelStyle = .card
    ) -> some View {
        modifier(AppPanelModifier(appStyle: appStyle, cornerRadius: cornerRadius, panelStyle: panelStyle))
    }

    /// 隐藏工具栏材质，让 SwiftUI 自定义背景（glass / neu）统一填充工具栏区域。
    /// glass 和 neu 均需调用；由 WindowChromeBridge + NeuBackground / LiquidGlassBackground 负责实际填色。
    @ViewBuilder
    func withHiddenToolbarMaterial() -> some View {
        if #available(macOS 15.0, *) {
            self
                .toolbarBackground(.hidden, for: .windowToolbar)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self.toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}
