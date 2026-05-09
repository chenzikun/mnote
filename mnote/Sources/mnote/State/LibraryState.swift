import AppKit
import Combine
import Foundation

extension Notification.Name {
    /// 任一会话写入了共享配置（根目录、笔记本书签、外观等），其他 `LibraryState` 应重新从磁盘对齐。
    static let mnoteLibraryPersistenceDidChange = Notification.Name("mnote.LibraryPersistenceDidChange")
    /// 菜单「文件 → 新建」：打开笔记本选择/新建弹窗（与工具栏笔记本按钮一致）。
    static let mnotePresentNotebookSheet = Notification.Name("mnote.presentNotebookSheet")
    /// 展开侧栏「笔记本内查找与替换」面板并聚焦查找框（⌘⇧F）。
    static let mnoteFocusNotebookSearch = Notification.Name("mnote.focusNotebookSearch")
}

/// 当前笔记本内，某 Markdown 文件中的一处匹配（文件名或正文行）。
struct NotebookSearchHit: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    /// 1-based；为 0 表示仅文件名匹配。
    let line: Int
    let excerpt: String

    init(fileURL: URL, line: Int, excerpt: String) {
        self.fileURL = fileURL
        self.line = line
        self.excerpt = excerpt
        self.id = "\(fileURL.path)#\(line)#\(excerpt.prefix(96))"
    }
}

/// Root + 当前 notebook（workspace）；持久化安全作用域书签；约定见仓库根目录 `docs/architecture.md`。
final class LibraryState: ObservableObject {

    // MARK: - 文件系统

    @Published private(set) var rootURL: URL?
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var notebooks: [URL] = []
    @Published private(set) var workspaceTree: [WorkspaceNode] = []
    @Published private(set) var workspaceFiles: [URL] = []
    @Published var selectedDirectoryURL: URL?
    /// true → 文件树高亮文件夹；false → 高亮 Markdown 文件。
    @Published private(set) var treeSelectionIsDirectory: Bool = false

    // MARK: - 当前文件

    @Published private(set) var currentFileURL: URL?
    @Published var currentFileContent = ""
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var lastSavedAt: Date?

    // MARK: - 外观与偏好

    /// 统一外观风格：glass-dark / glass-light / neu-light / neu-dark。
    @Published var appStyle: AppStyle = .glassDark
    @Published var previewVisible = true
    /// true → 仅预览，隐藏编辑区（阅读模式）。
    @Published var readingMode = false
    /// true → 文件树中 Markdown 文件名不显示 `.md` 后缀（路径与文件系统不变）。
    @Published var hideMarkdownExtension = false
    /// 编辑器字体的 EditorFontPreset.id，"system" = SF Mono。
    @Published var editorFontName: String = "system"
    /// 编辑器字号（pt），范围 10–24。
    @Published var editorFontSize: CGFloat = 13

    /// 当前有效的编辑器 NSFont（字体未安装时自动回退到 SF Mono）。
    var resolvedEditorFont: NSFont {
        EditorFontPreset.preset(for: editorFontName).resolve(size: editorFontSize)
    }

    // MARK: - 笔记本全文搜索

    /// 与编辑区/预览的页内「查找」不同；侧栏放大镜展开，跨全部 `.md` 搜索与全局替换。
    @Published var notebookSearchQuery = ""
    @Published var notebookSearchCaseSensitive = false
    @Published private(set) var notebookSearchHits: [NotebookSearchHit] = []
    @Published private(set) var notebookSearchIsRunning = false

    // MARK: - UI 反馈

    @Published var userMessage: String?

    // MARK: - 向后兼容

    /// 由 `appStyle` 派生，供仍引用旧接口的调用方使用。
    var liquidGlassEnabled: Bool { appStyle.isGlass }

    // MARK: - 私有存储

    private let configStore: AppConfigStore
    private let observesPersistenceFromOtherInstances: Bool
    private var persistenceObserver: NSObjectProtocol?
    private var rootAccessing = false
    private var workspaceAccessing = false
    private var autoSaveWorkItem: DispatchWorkItem?
    private let autoSaveDelay: TimeInterval = 0.8
    private var notebookSearchWorkItem: DispatchWorkItem?

    // MARK: - 初始化

    init(
        configStore: AppConfigStore = AppConfigStore(),
        observesPersistenceFromOtherInstances: Bool = true
    ) {
        self.configStore = configStore
        self.observesPersistenceFromOtherInstances = observesPersistenceFromOtherInstances
        print("mnote config path: \(configStore.fileURL.path)")
        restoreAppearanceSettings()
        restoreFromDisk()
        if observesPersistenceFromOtherInstances {
            persistenceObserver = NotificationCenter.default.addObserver(
                forName: .mnoteLibraryPersistenceDidChange,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self else { return }
                if note.object as AnyObject? === self {
                    return
                }
                self.applyExternalPersistenceUpdate()
            }
        }
    }

    deinit {
        if let persistenceObserver {
            NotificationCenter.default.removeObserver(persistenceObserver)
        }
    }

    // MARK: - Root 管理

    func chooseRootViaOpenPanel(parentWindow: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择根目录"
        panel.message = "作为所有笔记本的顶层目录（可放在 iCloud Drive 等位置）"

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setRoot(url)
        }

        if let window = parentWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    func setRoot(_ url: URL) {
        stopAccessingCurrent()

        guard let bookmark = makeBookmark(for: url) else {
            userMessage = "无法保存根目录授权，请重新选择。"
            return
        }

        configStore.set(bookmark, for: .root)
        configStore.set(Optional<Data>.none, for: .workspace)

        rootURL = nil
        workspaceURL = nil
        notebooks = []

        restoreFromDisk()
        notifyPersistenceChanged()
    }

    // MARK: - 笔记本管理

    func selectWorkspace(_ url: URL) {
        guard let root = rootURL, urlIsInside(url, parent: root) else { return }
        if workspaceURL == url {
            return
        }

        flushPendingAutoSave()
        clearNotebookSearch()

        stopWorkspaceAccess()

        guard let bookmark = makeBookmark(for: url) else {
            userMessage = "无法保存当前笔记本状态，请重试。"
            return
        }

        configStore.set(bookmark, for: .workspace)
        workspaceURL = nil
        applyWorkspaceBookmark(bookmark)
        objectWillChange.send()
        notifyPersistenceChanged()
    }

    func createNotebook(named rawName: String) {
        guard let root = rootURL else {
            userMessage = "请先选择根目录。"
            return
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            userMessage = "笔记本名称不能为空。"
            return
        }
        guard isValidNotebookName(name) else {
            userMessage = "笔记本名称包含非法字符，请使用普通文件夹名称。"
            return
        }

        let newURL = root.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: newURL.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                ensureDefaultReadme(in: newURL)
                reloadNotebooks()
                selectWorkspace(newURL)
                userMessage = nil
            } else {
                userMessage = "同名文件已存在，请换一个名称。"
            }
            return
        }

        do {
            try fm.createDirectory(at: newURL, withIntermediateDirectories: false)
            ensureDefaultReadme(in: newURL)
            reloadNotebooks()
            selectWorkspace(newURL)
            userMessage = nil
        } catch {
            userMessage = "创建失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 文件操作

    func createFileInWorkspace(named rawName: String) {
        guard workspaceURL != nil else {
            userMessage = "请先选择笔记本。"
            return
        }

        let normalized = normalizeFileName(rawName)
        guard !normalized.isEmpty else {
            userMessage = "文件名不能为空。"
            return
        }
        guard isValidFileName(normalized) else {
            userMessage = "文件名包含非法字符。"
            return
        }

        let targetDirectory = selectedDirectoryURL ?? workspaceURL!
        let fileURL = targetDirectory.appendingPathComponent(normalized, isDirectory: false)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                userMessage = "同名文件夹已存在，请换个名称。"
            } else {
                selectFile(fileURL)
                userMessage = nil
            }
            return
        }

        do {
            try "# \(fileURL.deletingPathExtension().lastPathComponent)\n\n".write(to: fileURL, atomically: true, encoding: .utf8)
            reloadWorkspaceContents()
            selectFile(fileURL)
            userMessage = nil
        } catch {
            userMessage = "创建文件失败：\(error.localizedDescription)"
        }
    }

    func createFolderInWorkspace(named rawName: String) {
        guard workspaceURL != nil else {
            userMessage = "请先选择笔记本。"
            return
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            userMessage = "文件夹名称不能为空。"
            return
        }
        guard isValidFileName(name) else {
            userMessage = "文件夹名称包含非法字符。"
            return
        }

        let parent = selectedDirectoryURL ?? workspaceURL!
        let folderURL = parent.appendingPathComponent(name, isDirectory: true)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                selectedDirectoryURL = folderURL
                userMessage = nil
            } else {
                userMessage = "同名文件已存在，请换个名称。"
            }
            return
        }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            reloadWorkspaceContents()
            selectedDirectoryURL = folderURL
            userMessage = nil
        } catch {
            userMessage = "创建文件夹失败：\(error.localizedDescription)"
        }
    }

    /// 在「当前选中目录」（或笔记本根）创建自动避名的 `未命名.md` 并打开，供随后重命名。
    @discardableResult
    func createUntitledMarkdownInSelection() -> URL? {
        guard let workspace = workspaceURL else {
            userMessage = "请先选择笔记本。"
            return nil
        }
        let targetDirectory = selectedDirectoryURL ?? workspace
        guard urlIsInside(targetDirectory, parent: workspace) else {
            userMessage = "无法在该目录创建文件。"
            return nil
        }
        let fileURL = makeUniqueMarkdownURL(in: targetDirectory, baseStem: "未命名")
        do {
            try "# \(fileURL.deletingPathExtension().lastPathComponent)\n\n".write(to: fileURL, atomically: true, encoding: .utf8)
            reloadWorkspaceContents()
            selectFile(fileURL)
            userMessage = nil
            return fileURL
        } catch {
            userMessage = "创建文件失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 在「当前选中目录」（或笔记本根）创建自动避名的 `未命名文件夹` 并选中，供随后重命名。
    @discardableResult
    func createUntitledFolderInSelection() -> URL? {
        guard let workspace = workspaceURL else {
            userMessage = "请先选择笔记本。"
            return nil
        }
        let parent = selectedDirectoryURL ?? workspace
        guard urlIsInside(parent, parent: workspace) else {
            userMessage = "无法在该目录创建文件夹。"
            return nil
        }
        let folderURL = makeUniqueFolderURL(in: parent, baseName: "未命名文件夹")
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            reloadWorkspaceContents()
            selectedDirectoryURL = folderURL
            userMessage = nil
            return folderURL
        } catch {
            userMessage = "创建文件夹失败：\(error.localizedDescription)"
            return nil
        }
    }

    private func makeUniqueMarkdownURL(in directory: URL, baseStem: String) -> URL {
        let fm = FileManager.default
        let first = directory.appendingPathComponent("\(baseStem).md", isDirectory: false)
        if !fm.fileExists(atPath: first.path) {
            return first
        }
        var n = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseStem) \(n).md", isDirectory: false)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }

    private func makeUniqueFolderURL(in parent: URL, baseName: String) -> URL {
        let fm = FileManager.default
        let first = parent.appendingPathComponent(baseName, isDirectory: true)
        if !fm.fileExists(atPath: first.path) {
            return first
        }
        var n = 2
        while true {
            let candidate = parent.appendingPathComponent("\(baseName) \(n)", isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }

    func selectFile(_ fileURL: URL) {
        guard let workspace = workspaceURL, urlIsInside(fileURL, parent: workspace) else { return }
        guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return }
        guard fileURL.pathExtension.lowercased() == "md" else { return }

        flushPendingAutoSave()

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            currentFileURL = fileURL
            currentFileContent = content
            loadedFileSnapshot = content
            hasUnsavedChanges = false
            selectedDirectoryURL = fileURL.deletingLastPathComponent()
            treeSelectionIsDirectory = false
            userMessage = nil
        } catch {
            userMessage = "读取文件失败：\(error.localizedDescription)"
        }
    }

    func selectDirectory(_ directoryURL: URL) {
        guard let workspace = workspaceURL, urlIsInside(directoryURL, parent: workspace) else { return }
        guard (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
        flushPendingAutoSave()
        selectedDirectoryURL = directoryURL
        treeSelectionIsDirectory = true
    }

    func updateCurrentFileContent(_ content: String) {
        currentFileContent = content
        hasUnsavedChanges = (content != loadedFileSnapshot)
        scheduleAutoSaveIfNeeded()
    }

    func saveCurrentFile() {
        guard let fileURL = currentFileURL else { return }
        do {
            try currentFileContent.write(to: fileURL, atomically: true, encoding: .utf8)
            loadedFileSnapshot = currentFileContent
            hasUnsavedChanges = false
            lastSavedAt = Date()
            userMessage = nil
            reloadWorkspaceContents()
        } catch {
            userMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func renameWorkspaceItem(_ targetURL: URL, to rawName: String) {
        guard let workspace = workspaceURL, urlIsInside(targetURL, parent: workspace) else { return }
        flushPendingAutoSave()

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            userMessage = "新名称不能为空。"
            return
        }
        guard isValidFileName(trimmed) else {
            userMessage = "名称包含非法字符。"
            return
        }

        let isDirectory = (try? targetURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        var finalName = trimmed
        if !isDirectory {
            let oldExt = targetURL.pathExtension
            let inputExt = URL(fileURLWithPath: trimmed).pathExtension
            if !oldExt.isEmpty && inputExt.isEmpty {
                finalName += ".\(oldExt)"
            }
        }

        let parent = targetURL.deletingLastPathComponent()
        let destination = parent.appendingPathComponent(finalName, isDirectory: isDirectory)
        if destination == targetURL {
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            userMessage = "目标名称已存在，请换一个。"
            return
        }

        do {
            try FileManager.default.moveItem(at: targetURL, to: destination)
            reloadWorkspaceContents()

            if currentFileURL == targetURL {
                currentFileURL = destination
            }
            if selectedDirectoryURL == targetURL {
                selectedDirectoryURL = destination
            }
            if currentFileURL == destination {
                selectFile(destination)
            }
            userMessage = nil
        } catch {
            userMessage = "重命名失败：\(error.localizedDescription)"
        }
    }

    func deleteWorkspaceItem(_ targetURL: URL) {
        guard let workspace = workspaceURL, urlIsInside(targetURL, parent: workspace) else { return }
        flushPendingAutoSave()

        do {
            try FileManager.default.removeItem(at: targetURL)
            if currentFileURL == targetURL || currentFileURL?.path.hasPrefix(targetURL.path + "/") == true {
                currentFileURL = nil
                currentFileContent = ""
                loadedFileSnapshot = ""
                hasUnsavedChanges = false
            }
            if selectedDirectoryURL == targetURL || selectedDirectoryURL?.path.hasPrefix(targetURL.path + "/") == true {
                selectedDirectoryURL = workspace
                treeSelectionIsDirectory = true
            }
            reloadWorkspaceContents()
            userMessage = nil
        } catch {
            userMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func rootStatusText() -> String {
        guard let rootURL else {
            return "未设置 root。"
        }
        let readable = FileManager.default.isReadableFile(atPath: rootURL.path)
        let writable = FileManager.default.isWritableFile(atPath: rootURL.path)
        switch (readable, writable) {
        case (true, true):
            return "已授权（可读写）"
        case (true, false):
            return "仅可读（无法写入）"
        case (false, _):
            return "不可读（请重新选择）"
        }
    }

    // MARK: - 外观设置

    func setAppStyle(_ style: AppStyle) {
        appStyle = style
        configStore.set(style.rawValue, for: .appStyle)
        notifyPersistenceChanged()
    }

    func setPreviewVisible(_ visible: Bool) {
        previewVisible = visible
        configStore.set(visible, for: .previewVisible)
        notifyPersistenceChanged()
    }

    func setReadingMode(_ enabled: Bool) {
        readingMode = enabled
        configStore.set(enabled, for: .readingMode)
        notifyPersistenceChanged()
    }

    func setHideMarkdownExtension(_ hidden: Bool) {
        hideMarkdownExtension = hidden
        configStore.set(hidden, for: .hideMarkdownExtension)
        notifyPersistenceChanged()
    }

    func setEditorFontName(_ name: String) {
        editorFontName = name
        configStore.set(name, for: .editorFontName)
        notifyPersistenceChanged()
    }

    func setEditorFontSize(_ size: CGFloat) {
        editorFontSize = min(max(size, 10), 24)
        configStore.set(Double(editorFontSize), for: .editorFontSize)
        notifyPersistenceChanged()
    }

    // MARK: - 链接跳转

    func openLinkFromPreview(_ href: String) {
        flushPendingAutoSave()
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let url = URL(string: trimmed) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        if trimmed.hasPrefix("#") {
            return
        }

        guard let workspace = workspaceURL else { return }
        let base = currentFileURL?.deletingLastPathComponent() ?? workspace
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let parsed = URL(string: decoded)
        var target: URL
        if let parsed, parsed.isFileURL {
            target = parsed.standardizedFileURL
        } else {
            target = URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
        }
        target = target.resolvingSymlinksInPath()

        if !urlIsInside(target, parent: workspace) {
            userMessage = "链接超出当前笔记本范围，已阻止。"
            return
        }

        if (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            selectDirectory(target)
            return
        }

        if target.pathExtension.isEmpty {
            let markdownTarget = target.appendingPathExtension("md")
            if FileManager.default.fileExists(atPath: markdownTarget.path) {
                target = markdownTarget
            }
        }

        if FileManager.default.fileExists(atPath: target.path) {
            selectFile(target)
            return
        }

        if target.pathExtension.lowercased() == "md" {
            do {
                let parent = target.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try "# \(target.deletingPathExtension().lastPathComponent)\n\n".write(to: target, atomically: true, encoding: .utf8)
                reloadWorkspaceContents()
                selectFile(target)
            } catch {
                userMessage = "无法创建链接目标：\(error.localizedDescription)"
            }
            return
        }

        userMessage = "暂不支持打开该类型链接。"
    }

    // MARK: - 笔记本全文搜索操作

    /// 更新笔记本内查找关键词（防抖后扫描当前 `workspaceFiles` 下全部 `.md`）。
    func setNotebookSearchQuery(_ raw: String) {
        notebookSearchQuery = raw
        notebookSearchWorkItem?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notebookSearchHits = []
            notebookSearchIsRunning = false
            return
        }
        notebookSearchIsRunning = true
        let caseSens = notebookSearchCaseSensitive
        let work = DispatchWorkItem { [weak self] in
            self?.runNotebookSearch(query: trimmed, caseSensitive: caseSens)
        }
        notebookSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    /// 切换「区分大小写」后，若已有查找词则重新搜索。
    func setNotebookSearchCaseSensitive(_ value: Bool) {
        notebookSearchCaseSensitive = value
        let trimmed = notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setNotebookSearchQuery(notebookSearchQuery)
    }

    /// 清空侧栏笔记本查找状态（不重置「区分大小写」偏好）。
    func clearNotebookSearch() {
        notebookSearchWorkItem?.cancel()
        notebookSearchWorkItem = nil
        notebookSearchQuery = ""
        notebookSearchHits = []
        notebookSearchIsRunning = false
    }

    /// 统计当前笔记本内将发生的非重叠替换次数及涉及文件数（用于确认框）。
    func countNotebookReplaceMatches(find: String, caseSensitive: Bool) -> (occurrences: Int, files: Int) {
        let needle = find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return (0, 0) }
        let opts = Self.notebookSearchCompareOptions(caseSensitive: caseSensitive)
        let maxFileBytes = 2_000_000
        var occurrences = 0
        var files = 0
        for file in workspaceFiles {
            if let sz = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > maxFileBytes {
                continue
            }
            guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else { continue }
            let n = Self.countNonOverlapping(in: text, needle: needle, options: opts)
            if n > 0 {
                occurrences += n
                files += 1
            }
        }
        return (occurrences, files)
    }

    /// 在当前笔记本全部 `.md` 文件中执行全局替换（先保存未写入的编辑）。
    func replaceAllInNotebook(find: String, replacement: String, caseSensitive: Bool) {
        let needle = find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            userMessage = "查找内容不能为空。"
            return
        }
        flushPendingAutoSave()
        let opts = Self.notebookSearchCompareOptions(caseSensitive: caseSensitive)
        let files = workspaceFiles
        let maxFileBytes = 2_000_000
        var changed: [URL] = []
        var total = 0
        for file in files {
            if let sz = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > maxFileBytes {
                continue
            }
            guard let data = try? Data(contentsOf: file), var text = String(data: data, encoding: .utf8) else { continue }
            let n = Self.replaceAllNonOverlapping(in: &text, needle: needle, replacement: replacement, options: opts)
            guard n > 0 else { continue }
            do {
                try text.write(to: file, atomically: true, encoding: .utf8)
                changed.append(file)
                total += n
            } catch {
                userMessage = "写入失败：\(file.lastPathComponent) — \(error.localizedDescription)"
                return
            }
        }
        reloadWorkspaceContents()
        if let cur = currentFileURL, changed.contains(cur) {
            selectFile(cur)
        }
        setNotebookSearchQuery(notebookSearchQuery)
        userMessage = changed.isEmpty
            ? "没有可替换的匹配项。"
            : "已在 \(changed.count) 个文件中替换 \(total) 处。"
    }

    /// 用于结果列表副标题：相对当前笔记本根的路径。
    func notebookFileDisplayPath(_ fileURL: URL) -> String {
        guard let workspace = workspaceURL else { return fileURL.lastPathComponent }
        let wsPath = normalizedPath(workspace) + "/"
        let fp = normalizedPath(fileURL)
        if fp.hasPrefix(wsPath) {
            return String(fp.dropFirst(wsPath.count))
        }
        return fileURL.lastPathComponent
    }

    // MARK: - 私有实现

    private var loadedFileSnapshot = ""

    /// 设置窗口等其它实例写入了共享配置后，当前窗口从磁盘刷新（不广播，避免循环）。
    private func applyExternalPersistenceUpdate() {
        flushPendingAutoSave()
        configStore.reloadFromDisk()
        restoreAppearanceSettings()
    }

    private func notifyPersistenceChanged() {
        NotificationCenter.default.post(name: .mnoteLibraryPersistenceDidChange, object: self)
    }

    private func runNotebookSearch(query: String, caseSensitive: Bool) {
        notebookSearchWorkItem = nil
        guard workspaceURL != nil else {
            notebookSearchHits = []
            notebookSearchIsRunning = false
            return
        }
        let files = workspaceFiles
        let workspace = workspaceURL!
        let wsNorm = normalizedPath(workspace)
        let opts = Self.notebookSearchCompareOptions(caseSensitive: caseSensitive)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, files, wsNorm, query, opts] in
            var hits: [NotebookSearchHit] = []
            let maxTotal = 400
            let maxContentLinesPerFile = 40
            let excerptMax = 140
            let maxFileBytes = 2_000_000

            for file in files {
                guard hits.count < maxTotal else { break }
                if let sz = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > maxFileBytes {
                    continue
                }

                var contentHits = 0
                let baseName = file.deletingPathExtension().lastPathComponent
                let fullName = file.lastPathComponent
                if baseName.range(of: query, options: opts) != nil
                    || fullName.range(of: query, options: opts) != nil {
                    let fp = file.standardizedFileURL.resolvingSymlinksInPath().path
                    let rel = fp.dropFirst(min(fp.count, wsNorm.count + 1))
                    hits.append(NotebookSearchHit(fileURL: file, line: 0, excerpt: "文件名：\(rel)"))
                }

                guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else {
                    continue
                }
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (idx, sub) in lines.enumerated() {
                    guard hits.count < maxTotal, contentHits < maxContentLinesPerFile else { break }
                    let line = String(sub)
                    guard line.range(of: query, options: opts) != nil else { continue }
                    let n = idx + 1
                    var ex = line.trimmingCharacters(in: .whitespaces)
                    if ex.isEmpty { ex = "（空行）" }
                    if ex.count > excerptMax {
                        ex = String(ex.prefix(excerptMax)) + "…"
                    }
                    hits.append(NotebookSearchHit(fileURL: file, line: n, excerpt: "\(n): \(ex)"))
                    contentHits += 1
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.notebookSearchIsRunning = false
                let still = self.notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if still == query, self.notebookSearchCaseSensitive == caseSensitive {
                    self.notebookSearchHits = hits
                }
            }
        }
    }

    private static func notebookSearchCompareOptions(caseSensitive: Bool) -> String.CompareOptions {
        caseSensitive ? [] : [.caseInsensitive]
    }

    private static func countNonOverlapping(in text: String, needle: String, options: String.CompareOptions) -> Int {
        var mutable = text
        var n = 0
        while let r = mutable.range(of: needle, options: options) {
            mutable.removeSubrange(r)
            n += 1
        }
        return n
    }

    /// 非重叠字面量替换，返回替换次数。
    private static func replaceAllNonOverlapping(
        in text: inout String,
        needle: String,
        replacement: String,
        options: String.CompareOptions
    ) -> Int {
        var n = 0
        while let r = text.range(of: needle, options: options) {
            text.replaceSubrange(r, with: replacement)
            n += 1
        }
        return n
    }

    private func restoreAppearanceSettings() {
        // 读取 appStyle（优先）；否则从旧版 liquidGlassEnabled + appTheme 迁移。
        if let raw = configStore.string(for: .appStyle), let style = AppStyle(rawValue: raw) {
            appStyle = style
        } else {
            let oldGlass = configStore.bool(for: .liquidGlassEnabled, default: true)
            let oldTheme = configStore.string(for: .appTheme)
            appStyle = AppStyle.migrate(glassEnabled: oldGlass, themeName: oldTheme)
        }
        previewVisible = configStore.bool(for: .previewVisible, default: true)
        readingMode = configStore.bool(for: .readingMode, default: false)
        hideMarkdownExtension = configStore.bool(for: .hideMarkdownExtension, default: false)
        if let name = configStore.string(for: .editorFontName) {
            editorFontName = name
        }
        let storedSize = configStore.double(for: .editorFontSize, default: 13)
        editorFontSize = CGFloat(storedSize)
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func urlIsInside(_ child: URL, parent: URL) -> Bool {
        let childPath = normalizedPath(child)
        let parentPath = normalizedPath(parent)
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    private func scheduleAutoSaveIfNeeded() {
        guard hasUnsavedChanges, currentFileURL != nil else { return }
        autoSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveCurrentFile()
        }
        autoSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoSaveDelay, execute: work)
    }

    private func flushPendingAutoSave() {
        guard hasUnsavedChanges else { return }
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        saveCurrentFile()
    }

    private func makeBookmark(for url: URL) -> Data? {
        if let security = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return security
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveBookmark(data: Data, stale: inout Bool) -> URL? {
        if let secure = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return secure
        }
        stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    private func isValidNotebookName(_ name: String) -> Bool {
        if name == "." || name == ".." {
            return false
        }
        if name.contains("/") || name.contains(":") {
            return false
        }
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return false
        }
        return true
    }

    private func ensureDefaultReadme(in notebookURL: URL) {
        let readmeURL = notebookURL.appendingPathComponent("README.md", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else { return }
        let title = notebookURL.lastPathComponent
        let content = "# \(title)\n\n"
        try? content.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    private func normalizeFileName(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let ext = URL(fileURLWithPath: trimmed).pathExtension
        if ext.isEmpty {
            return trimmed + ".md"
        }
        return trimmed
    }

    private func isValidFileName(_ name: String) -> Bool {
        if name == "." || name == ".." {
            return false
        }
        if name.contains("/") || name.contains(":") {
            return false
        }
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return false
        }
        return true
    }

    private func restoreFromDisk() {
        stopAccessingCurrent()

        guard let data = configStore.data(for: .root) else { return }

        var stale = false
        guard let url = resolveBookmark(data: data, stale: &stale) else { return }

        if stale {
            // 书签失效时仍尝试继续；用户可重新选择根目录
            if let refreshed = makeBookmark(for: url) {
                configStore.set(refreshed, for: .root)
            }
        }

        rootAccessing = url.startAccessingSecurityScopedResource()
        rootURL = url
        reloadNotebooks()

        if let wsData = configStore.data(for: .workspace) {
            applyWorkspaceBookmark(wsData)
        } else {
            pickDefaultWorkspace()
        }
    }

    private func applyWorkspaceBookmark(_ data: Data) {
        var stale = false
        guard let url = resolveBookmark(data: data, stale: &stale),
            let root = rootURL,
            urlIsInside(url, parent: root)
        else {
            pickDefaultWorkspace()
            return
        }

        if stale, let refreshed = makeBookmark(for: url) {
            configStore.set(refreshed, for: .workspace)
        }

        workspaceAccessing = url.startAccessingSecurityScopedResource()
        workspaceURL = url
        reloadWorkspaceContents()
        selectRootReadmeIfAvailable()
    }

    /// 笔记本根目录下名为 `readme`、扩展名为 `md` 的文件（文件名与扩展名不区分大小写），优先 `README.md`。
    private func selectRootReadmeIfAvailable() {
        guard let workspace = workspaceURL,
            let readme = Self.rootReadmeMarkdownURL(at: workspace)
        else { return }
        selectFile(readme)
    }

    private static func rootReadmeMarkdownURL(at workspace: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: workspace,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var matches: [URL] = []
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard url.pathExtension.lowercased() == "md" else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.lowercased() == "readme" else { continue }
            matches.append(url)
        }
        guard !matches.isEmpty else { return nil }
        if let preferred = matches.first(where: { $0.lastPathComponent == "README.md" }) {
            return preferred
        }
        return matches.sorted { $0.path < $1.path }.first
    }

    private func pickDefaultWorkspace() {
        guard rootURL != nil else { return }

        if let first = notebooks.first {
            selectWorkspace(first)
            return
        }

        workspaceURL = nil
        stopWorkspaceAccess()
        configStore.set(Optional<Data>.none, for: .workspace)
    }

    private func reloadNotebooks() {
        guard let root = rootURL else {
            notebooks = []
            return
        }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            notebooks = []
            return
        }

        notebooks = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func reloadWorkspaceContents() {
        guard let workspace = workspaceURL else {
            workspaceTree = []
            workspaceFiles = []
            selectedDirectoryURL = nil
            treeSelectionIsDirectory = false
            currentFileURL = nil
            currentFileContent = ""
            loadedFileSnapshot = ""
            hasUnsavedChanges = false
            lastSavedAt = nil
            clearNotebookSearch()
            return
        }

        guard let tree = buildTree(at: workspace) else {
            workspaceTree = []
            workspaceFiles = []
            clearNotebookSearch()
            return
        }

        workspaceTree = tree
        workspaceFiles = flattenMarkdownFiles(nodes: tree)
        if !notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notebookSearchIsRunning = true
            runNotebookSearch(
                query: notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                caseSensitive: notebookSearchCaseSensitive
            )
        }

        if selectedDirectoryURL == nil || !urlIsInside(selectedDirectoryURL!, parent: workspace) {
            selectedDirectoryURL = workspace
            treeSelectionIsDirectory = true
        }

        if let currentFileURL, !workspaceFiles.contains(currentFileURL) {
            self.currentFileURL = nil
            currentFileContent = ""
            loadedFileSnapshot = ""
            hasUnsavedChanges = false
            lastSavedAt = nil
        }
    }

    private func buildTree(at directory: URL) -> [WorkspaceNode]? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        var dirURLs: [URL] = []
        var mdURLs: [URL] = []
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                dirURLs.append(url)
            } else if values?.isRegularFile == true, url.pathExtension.lowercased() == "md" {
                mdURLs.append(url)
            }
        }
        dirURLs.sort(by: byName)
        mdURLs.sort(by: byName)

        var nodes: [WorkspaceNode] = []
        for url in dirURLs {
            let children = buildTree(at: url) ?? []
            nodes.append(WorkspaceNode(id: url, url: url, name: url.lastPathComponent, kind: .directory, children: children))
        }
        for url in mdURLs {
            nodes.append(WorkspaceNode(id: url, url: url, name: url.lastPathComponent, kind: .markdownFile, children: []))
        }

        return nodes
    }

    private func flattenMarkdownFiles(nodes: [WorkspaceNode]) -> [URL] {
        var result: [URL] = []
        for node in nodes {
            switch node.kind {
            case .markdownFile:
                result.append(node.url)
            case .directory:
                result.append(contentsOf: flattenMarkdownFiles(nodes: node.children))
            }
        }
        return result
    }

    private func stopWorkspaceAccess() {
        clearNotebookSearch()
        if workspaceAccessing, let u = workspaceURL {
            u.stopAccessingSecurityScopedResource()
        }
        workspaceAccessing = false
        workspaceURL = nil
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        workspaceTree = []
        workspaceFiles = []
        selectedDirectoryURL = nil
        currentFileURL = nil
        currentFileContent = ""
        loadedFileSnapshot = ""
        hasUnsavedChanges = false
        lastSavedAt = nil
    }

    private func stopAccessingCurrent() {
        stopWorkspaceAccess()
        if rootAccessing, let u = rootURL {
            u.stopAccessingSecurityScopedResource()
        }
        rootAccessing = false
        rootURL = nil
        notebooks = []
    }
}
