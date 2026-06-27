import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryState
    @State private var showMessage = false
    @State private var selectedPane: SettingsPane = .general

    private enum SettingsPane: Int, CaseIterable {
        case general
        case editor
        case renderer

        var title: String {
            switch self {
            case .general: return "通用"
            case .editor: return "编辑器"
            case .renderer: return "渲染器"
            }
        }
    }

    var body: some View {
        ZStack {
            library.appStyle.backgroundView

            VStack(alignment: .leading, spacing: 10) {
                Picker("板块", selection: $selectedPane) {
                    ForEach(SettingsPane.allCases, id: \.rawValue) { pane in
                        Text(pane.title).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("设置板块")

                Group {
                    switch selectedPane {
                    case .general:  generalPane
                    case .editor:   editorPane
                    case .renderer: rendererPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(14)
        }
        .background(WindowChromeBridge(appStyle: library.appStyle))
        .frame(width: 620, height: 480, alignment: .topLeading)
        .withHiddenToolbarMaterial()
        .onChange(of: library.userMessage) { _, new in
            showMessage = new != nil
        }
        .alert("提示", isPresented: $showMessage) {
            Button("知道了", role: .cancel) {
                library.userMessage = nil
            }
        } message: {
            Text(library.userMessage ?? "")
        }
    }

    // MARK: - 通用

    private var generalPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                workspaceCard
                stylePickerCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("工作区")
                .font(.headline)

            Text("根目录（root）")
                .font(.subheadline.weight(.medium))

            Text(library.rootURL?.path ?? "尚未设置")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)

            Text("权限状态：\(library.rootStatusText())")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(library.rootURL == nil ? "选择根目录" : "更换根目录") {
                    library.chooseRootViaOpenPanel(parentWindow: NSApp.keyWindow ?? NSApp.mainWindow)
                }
                .buttonStyle(.borderedProminent)

                if let root = library.rootURL {
                    Button("在访达中打开") {
                        NSWorkspace.shared.open(root)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(appStyle: library.appStyle)
    }

    // MARK: - 4 种样式卡片选择器

    private var stylePickerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("外观风格")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(AppStyle.allCases) { style in
                    AppStyleCard(style: style, isSelected: library.appStyle == style)
                        .onTapGesture { library.setAppStyle(style) }
                }
            }

        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(appStyle: library.appStyle)
    }

    // MARK: - 编辑器

    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                fontCard
                behaviorCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var fontCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("字体")
                .font(.headline)

            HStack(alignment: .center, spacing: 10) {
                Text("字体族")
                    .font(.subheadline.weight(.medium))
                    .fixedSize()

                Picker("字体族", selection: Binding(
                    get: { library.editorFontName },
                    set: { library.setEditorFontName($0) }
                )) {
                    ForEach(EditorFontPreset.available) { preset in
                        // 复杂三目表达式拆出，避免编译器类型推断超时
                        FontPickerRow(preset: preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 120, maxWidth: 220, alignment: .leading)

                Spacer(minLength: 8)

                Text("字号")
                    .font(.subheadline.weight(.medium))
                    .fixedSize()

                Stepper(
                    value: Binding(
                        get: { library.editorFontSize },
                        set: { library.setEditorFontSize($0) }
                    ),
                    in: 10...24,
                    step: 1
                ) {
                    Text("\(Int(library.editorFontSize)) pt")
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .leading)
                }
            }

            // 预览
            VStack(alignment: .leading, spacing: 6) {
                Text("预览")
                    .font(.subheadline.weight(.medium))
                Text("// Hello, World!\nfunc greet(_ name: String) -> String {\n    return \"Hello, \\(name)!\"\n}")
                    .font(Font(library.resolvedEditorFont))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(appStyle: library.appStyle)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("行为")
                .font(.headline)

            Toggle("文件树隐藏\u{201C}.md\u{201D}后缀", isOn: Binding(
                get: { library.hideMarkdownExtension },
                set: { library.setHideMarkdownExtension($0) }
            ))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(appStyle: library.appStyle)
    }

    // MARK: - 渲染器

    private var rendererPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("预览 / HTML 渲染")
                        .font(.headline)

                    Text(
                        """
                        右侧预览由 cmark-gfm（与 swift-markdown 同源）生成 HTML，并启用 GFM 扩展（表格、任务列表、删除线等）。 \
                        主题随系统浅色 / 深色自动适配基础样式；后续可在此面板增加预览字体、行距等选项。
                        """
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appPanel(appStyle: library.appStyle)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - 样式缩略卡片

private struct AppStyleCard: View {
    let style: AppStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            // 样式预览缩略图
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.previewGradient)
                    .frame(height: 48)

                // 液态玻璃样式额外显示光泽感
                if style.isGlass {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(height: 48)
                    // 模拟小面板
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(width: 48, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                        )
                } else {
                    // 新拟态样式展示浮雕效果
                    let isDark = style == .neuDark
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(style.neuBg)
                        .frame(width: 48, height: 24)
                        .shadow(
                            color: Color.black.opacity(isDark ? 0.45 : 0.13),
                            radius: 4, x: 3, y: 3
                        )
                        .shadow(
                            color: Color.white.opacity(isDark ? 0.04 : 0.82),
                            radius: 4, x: -3, y: -3
                        )
                }
            }

            Text(style.displayName)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Picker 行（拆出避免编译器类型推断超时）

private struct FontPickerRow: View {
    let preset: EditorFontPreset

    var body: some View {
        Text(preset.displayName)
            .font(preset.swiftUIFont(size: 13))
            .tag(preset.id)
    }
}
