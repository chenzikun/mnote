import SwiftUI

/// 玻璃拟态风格的浅色 / 深色开关（ pill 轨道 + 滑动拇指，太阳 / 月亮）。
struct GlassLightDarkToggle: View {
    @Binding var isDark: Bool
    var disabled: Bool = false

    private let trackW: CGFloat = 200
    private let trackH: CGFloat = 42
    // 轨道与滑块共用胶囊几何，避免边缘倒角视觉不对齐。
    private let thumbInset: CGFloat = 3.5

    private var thumbSize: CGFloat { trackH - thumbInset * 2 }
    private var thumbTravel: CGFloat { trackW - thumbSize - thumbInset * 2 }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.ultraThinMaterial)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: trackW, height: trackH)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.18),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)

            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.55), Color.orange.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.leading, 12)
                Spacer()
                Image(systemName: "moon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.trailing, 12)
            }
            .allowsHitTesting(false)

            Capsule()
                .fill(.regularMaterial)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.9),
                                    Color.white.opacity(0.2),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                .overlay {
                    Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isDark ? Color.white : Color.yellow)
                }
                .offset(x: thumbInset + (isDark ? thumbTravel : 0))
                .animation(.spring(response: 0.38, dampingFraction: 0.84), value: isDark)
        }
        .frame(width: trackW, height: trackH)
        .contentShape(Capsule())
        .onTapGesture {
            guard !disabled else { return }
            isDark.toggle()
        }
        .opacity(disabled ? 0.42 : 1)
        .allowsHitTesting(!disabled)
        .accessibilityLabel(Text(isDark ? "深色" : "浅色"))
        .accessibilityHint(Text("在浅色与深色之间切换"))
        .accessibilityAddTraits(.isButton)
    }
}
