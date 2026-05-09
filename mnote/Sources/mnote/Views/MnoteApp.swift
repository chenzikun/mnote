import AppKit
import SwiftUI
import Foundation

/// 每个文档窗口独立持有一份 `LibraryState`；「文件 → 新建笔记本…」与本窗口工具栏笔记本按钮一致。
private struct MainWindowRoot: View {
    @StateObject private var library = LibraryState()

    var body: some View {
        RootShellView()
            .environmentObject(library)
            .preferredColorScheme(library.appStyle.preferredColorScheme)
            .onAppear {
                applyNSAppearance(library.appStyle)
            }
            .onChange(of: library.appStyle) { _, new in
                applyNSAppearance(new)
            }
    }

    /// 与 `preferredColorScheme` 同步，使工具栏、SplitView 等 AppKit 控件随外观切换即刻生效（不依赖重启）。
    private func applyNSAppearance(_ style: AppStyle) {
        NSApp.appearance = style.isDark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
    }
}

private struct SettingsWindowRoot: View {
    @StateObject private var library = LibraryState(observesPersistenceFromOtherInstances: false)

    var body: some View {
        SettingsView()
            .environmentObject(library)
    }
}

private struct MainWindowCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建笔记本…") {
                NotificationCenter.default.post(name: .mnotePresentNotebookSheet, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
        CommandGroup(after: .sidebar) {
            Button("笔记本内查找与替换…") {
                NotificationCenter.default.post(name: .mnoteFocusNotebookSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

@main
struct MnoteApp: App {
    init() {
        if CommandLine.arguments.contains("--self-check") {
            let code = SelfCheck.run()
            exit(code)
        }
    }

    var body: some Scene {
        WindowGroup(id: "mnote.main") {
            MainWindowRoot()
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            MainWindowCommands()
            SidebarCommands()
        }

        Settings {
            SettingsWindowRoot()
        }
    }
}
