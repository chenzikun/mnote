import Foundation
import Markdown

enum SelfCheck {
    static func run() -> Int32 {
        do {
            try runScenario()
            print("self-check: ok")
            return 0
        } catch {
            print("self-check: failed - \(error.localizedDescription)")
            return 2
        }
    }

    private static func runScenario() throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appendingPathComponent("mnote-self-check-\(UUID().uuidString)", isDirectory: true)
        let rootURL = sandbox.appendingPathComponent("root", isDirectory: true)
        let configURL = sandbox.appendingPathComponent("config", isDirectory: true)

        defer { try? fm.removeItem(at: sandbox) }
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

        // 0) Markdown GFM：swift-markdown（AST）+ cmark-gfm HTML（与 swift-markdown 同源解析栈）
        do {
            let tableMD = """
            | a | b |
            |---|---|
            | 1 | 2 |
            """
            let doc = Document(parsing: tableMD)
            guard doc.children.contains(where: { $0 is Table }) else {
                throw NSError(domain: "mnote.selfcheck", code: 1012, userInfo: [NSLocalizedDescriptionKey: "swift-markdown 未解析出 Table"])
            }
            let html = MarkdownRenderer.renderHTML(markdown: tableMD, title: "t")
            guard html.contains("<table") else {
                throw NSError(domain: "mnote.selfcheck", code: 1013, userInfo: [NSLocalizedDescriptionKey: "GFM 表格未生成 <table>"])
            }
            let gluedTable = "上文一行\n| Left | Right |\n| :--- | ----: |\n| a | b |\n"
            let gluedHTML = MarkdownRenderer.renderHTML(markdown: gluedTable, title: "t")
            guard gluedHTML.contains("<table"), gluedHTML.contains("<thead") else {
                throw NSError(domain: "mnote.selfcheck", code: 1015, userInfo: [NSLocalizedDescriptionKey: "表格紧跟段落时 cmark 未生成表格/表头"])
            }
            let spacedSep = "| Left | Center | Right |\n| :- | :---: | --: |\n| 1 | 2 | 3 |\n"
            let spacedHTML = MarkdownRenderer.renderHTML(markdown: spacedSep, title: "t")
            guard spacedHTML.contains(#"align="center""#), spacedHTML.contains(#"align="right""#) else {
                throw NSError(domain: "mnote.selfcheck", code: 1016, userInfo: [NSLocalizedDescriptionKey: "表格列对齐未生成 align"])
            }
            let glued = "paragraph\n### Sub\n"
            let h = MarkdownRenderer.renderHTML(markdown: glued, title: "t")
            guard h.contains("<h3") else {
                throw NSError(domain: "mnote.selfcheck", code: 1014, userInfo: [NSLocalizedDescriptionKey: "标题未与上文断行，未解析为 h3"])
            }
        }

        // 1) 创建并选择笔记本，创建文件
        do {
            let store = AppConfigStore(baseDirectoryURL: configURL)
            let state = LibraryState(configStore: store)
            state.setRoot(rootURL)
            state.createNotebook(named: "Inbox")
            guard state.workspaceURL?.lastPathComponent == "Inbox" else {
                throw NSError(domain: "mnote.selfcheck", code: 1001, userInfo: [NSLocalizedDescriptionKey: "workspace 未自动选中 Inbox"])
            }
            let readmePath = rootURL.appendingPathComponent("Inbox/README.md").path
            guard FileManager.default.fileExists(atPath: readmePath) else {
                throw NSError(domain: "mnote.selfcheck", code: 1008, userInfo: [NSLocalizedDescriptionKey: "新建 notebook 未生成 README.md"])
            }
            state.createFileInWorkspace(named: "today")
            guard state.currentFileURL?.lastPathComponent == "today.md" else {
                throw NSError(domain: "mnote.selfcheck", code: 1004, userInfo: [NSLocalizedDescriptionKey: "文件未自动选中"])
            }
            state.updateCurrentFileContent("# today\n\nhello")
            RunLoop.main.run(until: Date().addingTimeInterval(1.1))
            guard !state.hasUnsavedChanges else {
                throw NSError(domain: "mnote.selfcheck", code: 1005, userInfo: [NSLocalizedDescriptionKey: "自动保存后仍标记未保存"])
            }
            guard state.lastSavedAt != nil else {
                throw NSError(domain: "mnote.selfcheck", code: 1009, userInfo: [NSLocalizedDescriptionKey: "未记录自动保存时间"])
            }

            state.createFolderInWorkspace(named: "docs")
            state.selectDirectory(rootURL.appendingPathComponent("Inbox/docs", isDirectory: true))
            state.createFileInWorkspace(named: "guide")
            guard let createdGuideURL = state.currentFileURL else {
                throw NSError(domain: "mnote.selfcheck", code: 1012, userInfo: [NSLocalizedDescriptionKey: "未拿到新建文件 URL"])
            }
            state.renameWorkspaceItem(createdGuideURL, to: "guide-v2")
            let renamedGuideURL = createdGuideURL.deletingLastPathComponent().appendingPathComponent("guide-v2.md")
            guard FileManager.default.fileExists(atPath: renamedGuideURL.path) else {
                throw NSError(domain: "mnote.selfcheck", code: 1010, userInfo: [NSLocalizedDescriptionKey: "重命名失败"])
            }
            state.selectFile(rootURL.appendingPathComponent("Inbox/today.md"))
            state.updateCurrentFileContent("[guide](docs/guide-v2.md)")
            state.saveCurrentFile()
            state.openLinkFromPreview("docs/guide-v2.md")
            guard state.currentFileURL?.lastPathComponent == "guide-v2.md" else {
                throw NSError(domain: "mnote.selfcheck", code: 1007, userInfo: [NSLocalizedDescriptionKey: "链接跳转失败"])
            }
            state.deleteWorkspaceItem(renamedGuideURL)
            guard !FileManager.default.fileExists(atPath: renamedGuideURL.path) else {
                throw NSError(domain: "mnote.selfcheck", code: 1011, userInfo: [NSLocalizedDescriptionKey: "删除失败"])
            }
        }

        // 2) 重启恢复 root/workspace
        do {
            let restored = LibraryState(configStore: AppConfigStore(baseDirectoryURL: configURL))
            let expectedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
            let actualRoot = restored.rootURL?.standardizedFileURL.resolvingSymlinksInPath().path
            guard actualRoot == expectedRoot else {
                throw NSError(domain: "mnote.selfcheck", code: 1002, userInfo: [NSLocalizedDescriptionKey: "root 恢复失败"])
            }
            guard restored.workspaceURL?.lastPathComponent == "Inbox" else {
                throw NSError(domain: "mnote.selfcheck", code: 1003, userInfo: [NSLocalizedDescriptionKey: "workspace 恢复失败"])
            }
            guard restored.workspaceFiles.contains(where: { $0.lastPathComponent == "today.md" }) else {
                throw NSError(domain: "mnote.selfcheck", code: 1006, userInfo: [NSLocalizedDescriptionKey: "workspace 文件列表恢复失败"])
            }
        }
    }
}
