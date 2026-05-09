import AppKit
import SwiftUI

/// SwiftUI 主壳：左右分栏；左侧文件树可收起。查找分两种：**当前页**（编辑 `NSTextView` / 预览 `WKWebView` 系统查找条，用法同 MacDown）与**笔记本**（侧栏放大镜展开：跨全部 `.md` 搜索与全局替换）。
struct RootShellView: View {

    // MARK: - 状态

    @EnvironmentObject private var library: LibraryState
    @Environment(\.openSettings) private var openSettings
    @StateObject private var scrollBridge = MarkdownScrollBridge()
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var newNotebookSheetPresented = false
    @State private var newNotebookName = ""
    @State private var didTryAutoPickRoot = false
    @State private var renameSheetPresented = false
    @State private var renameTargetURL: URL?
    @State private var renameDraft = ""
    @State private var deleteTargetURL: URL?
    @FocusState private var newNotebookFieldFocused: Bool
    @FocusState private var notebookSearchFieldFocused: Bool
    @State private var workspaceNotebookSearchExpanded = false
    @State private var notebookReplaceDraft = ""
    @State private var showNotebookReplaceConfirm = false
    @State private var notebookReplaceConfirmOcc = 0
    @State private var notebookReplaceConfirmFiles = 0
    /// 文件树键盘操作（回车重命名）所针对的项；由点击行更新。
    @State private var fileTreeKeyboardTarget: URL?
    @FocusState private var fileTreeListFocused: Bool

    // MARK: - 布局常量

    /// 两栏玻璃卡片：与窗口边缘的留白一致；中间各留一半间距，避免圆角/材质贴在一起。
    private enum SplitChrome {
        static let outer: CGFloat = 8
        static let midGap: CGFloat = 10
    }

    /// 与侧栏、编辑区 `liquidGlassPanel` + `clipShape` 的圆角一致。
    private enum EditorChrome {
        static let panelCorner: CGFloat = 18
    }

    // MARK: - Body

    private var mainWindowTitle: String {
        if let ws = library.workspaceURL {
            return ws.lastPathComponent
        }
        return "mnote"
    }

    var body: some View {
        ZStack {
            library.appStyle.backgroundView

            NavigationSplitView(columnVisibility: $columnVisibility) {
                workspaceColumn
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 520)
                    // neu 模式：用 neuBg 实色覆盖 NavigationSplitView 自带的 .sidebar VFX 背景
                    .background(library.appStyle.isNeu ? library.appStyle.neuBg : .clear)
                    .padding(.top, SplitChrome.outer)
                    .padding(.bottom, SplitChrome.outer)
                    .padding(.leading, SplitChrome.outer)
                    .padding(.trailing, SplitChrome.midGap / 2)
            } detail: {
                editorDetail
                    .background(library.appStyle.isNeu ? library.appStyle.neuBg : .clear)
                    .padding(.top, SplitChrome.outer)
                    .padding(.bottom, SplitChrome.outer)
                    .padding(.leading, columnVisibility == .detailOnly ? SplitChrome.outer : SplitChrome.midGap / 2)
                    .padding(.trailing, SplitChrome.outer)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.clear)
            .background(WindowChromeBridge(appStyle: library.appStyle, title: mainWindowTitle))
            .toolbar {
                mainToolbarContent
            }
            /// 保持 SwiftUI navigation 系统持续同步 window.title，防止列切换时被清空。
            .navigationTitle(mainWindowTitle)
            .withHiddenToolbarMaterial()
            .onReceive(NotificationCenter.default.publisher(for: .mnotePresentNotebookSheet)) { _ in
                beginNewNotebookSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mnoteFocusNotebookSearch)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    workspaceNotebookSearchExpanded = true
                }
                notebookSearchFieldFocused = true
            }
            .confirmationDialog(
                "在笔记本内全部替换？",
                isPresented: $showNotebookReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("取消", role: .cancel) {}
                Button("替换全部", role: .destructive) {
                    let find = library.notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    library.replaceAllInNotebook(
                        find: find,
                        replacement: notebookReplaceDraft,
                        caseSensitive: library.notebookSearchCaseSensitive
                    )
                }
            } message: {
                Text("将替换 \(notebookReplaceConfirmOcc) 处，涉及 \(notebookReplaceConfirmFiles) 个 Markdown 文件。此操作直接写入磁盘。")
            }
            .onAppear {
                syncSelectionFromLibrary()
                autoPickRootOnFirstLaunchIfNeeded()
            }
            .onChange(of: library.rootURL) { _, _ in
                syncSelectionFromLibrary()
            }
            .alert("提示", isPresented: userMessageBinding) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(library.userMessage ?? "")
            }
            .sheet(isPresented: $renameSheetPresented) {
                renameSheet
            }
            .sheet(isPresented: $newNotebookSheetPresented) {
                newNotebookSheet
            }
            .alert("确认删除", isPresented: deleteAlertBinding) {
                Button("取消", role: .cancel) {
                    deleteTargetURL = nil
                }
                Button("删除", role: .destructive) {
                    if let target = deleteTargetURL {
                        library.deleteWorkspaceItem(target)
                    }
                    deleteTargetURL = nil
                }
            } message: {
                Text(deleteTargetURL?.lastPathComponent ?? "该项目")
            }
        }
    }

    // MARK: - 笔记本弹窗

    private var newNotebookSheet: some View {
        ZStack {
            library.appStyle.backgroundView

            VStack(alignment: .leading, spacing: 14) {
                Text("笔记本")
                    .font(.title2.bold())
                    .padding(.horizontal, 4)

                Text("可直接切换到已有笔记本，或在下方创建新笔记本。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                notebookSheetExistingCard
                notebookSheetCreateCard
            }
            .padding(16)
        }
        .background(WindowChromeBridge(appStyle: library.appStyle))
        .frame(width: 620, alignment: .topLeading)
        .withHiddenToolbarMaterial()
        .onAppear {
            DispatchQueue.main.async {
                newNotebookFieldFocused = true
            }
        }
    }

    private var notebookSheetExistingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已有笔记本")
                .font(.headline)

            if library.notebooks.isEmpty {
                Text("尚无笔记本，可在下方创建第一个。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(library.notebooks, id: \.self) { url in
                            Button {
                                chooseNotebookFromSheet(url)
                            } label: {
                                HStack {
                                    Image(systemName: "book.closed")
                                    Text(url.lastPathComponent)
                                    Spacer()
                                    if url == library.workspaceURL {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: notebookSheetListHeight)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(appStyle: library.appStyle)
    }

    private var notebookSheetCreateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建笔记本")
                .font(.headline)

            TextField("笔记本名称", text: $newNotebookName)
                .textFieldStyle(.roundedBorder)
                .focused($newNotebookFieldFocused)
                .onSubmit(createNotebookFromDraft)

            HStack {
                Button("取消") {
                    newNotebookSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建", action: createNotebookFromDraft)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedNotebookName.isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(appStyle: library.appStyle)
    }

    // MARK: - 侧栏

    private var workspaceColumn: some View {
        Group {
            if let ws = library.workspaceURL {
                workspaceFilesView(ws)
            } else if library.rootURL == nil {
                ContentUnavailableView(
                    "欢迎使用 mnote",
                    systemImage: "sparkles",
                    description: Text("请先在设置中选择 root。")
                )
            } else if library.notebooks.isEmpty {
                ContentUnavailableView(
                    "还没有笔记本",
                    systemImage: "book.closed",
                    description: Text("点击工具栏中的「新建笔记本」创建。")
                )
            } else {
                ContentUnavailableView(
                    "未选择笔记本",
                    systemImage: "tray",
                    description: Text("点击工具栏中的「笔记本」按钮选择或创建。")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appPanel(appStyle: library.appStyle, cornerRadius: EditorChrome.panelCorner, panelStyle: .splitColumn)
        .clipShape(RoundedRectangle(cornerRadius: EditorChrome.panelCorner, style: .continuous))
    }

    @ViewBuilder
    private func workspaceFilesView(_: URL) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 新建文件/文件夹/搜索按钮区（右对齐，固定在侧栏顶部）
            HStack(alignment: .center, spacing: 12) {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Button {
                        beginUntitledMarkdownCreation()
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 16))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("新建 Markdown 文件（可先点树中目录指定位置）")

                    Button {
                        beginUntitledFolderCreation()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 16))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("新建文件夹（可先点树中目录指定位置）")

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if workspaceNotebookSearchExpanded {
                                workspaceNotebookSearchExpanded = false
                                library.clearNotebookSearch()
                                notebookReplaceDraft = ""
                            } else {
                                workspaceNotebookSearchExpanded = true
                            }
                        }
                    } label: {
                        Image(
                            systemName: workspaceNotebookSearchExpanded
                                ? "magnifyingglass.circle.fill"
                                : "magnifyingglass.circle"
                        )
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("笔记本内查找与替换（⌘⇧F）")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("新建与笔记本搜索")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if workspaceNotebookSearchExpanded {
                workspaceNotebookSearchPanel
            }

            let notebookQueryActive = workspaceNotebookSearchExpanded
                && !library.notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if notebookQueryActive {
                workspaceNotebookSearchResults
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.workspaceTree.isEmpty {
                ContentUnavailableView(
                    "暂无内容",
                    systemImage: "folder",
                    description: Text("使用侧栏顶部按钮在根目录新建；点选树中的文件夹可切换新建位置。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        workspaceTreeNodes(nodes: library.workspaceTree, depth: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable()
                .focused($fileTreeListFocused)
                .focusEffectDisabled()
                .onKeyPress(.return) {
                    beginRenameFromFileTreeKeyboard()
                    return .handled
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: library.currentFileURL) { _, url in
            if let url {
                fileTreeKeyboardTarget = url
            }
        }
    }

    private var workspaceNotebookSearchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("笔记本内查找与替换")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(
                    "查找",
                    text: Binding(
                        get: { library.notebookSearchQuery },
                        set: { library.setNotebookSearchQuery($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .focused($notebookSearchFieldFocused)
                if !library.notebookSearchQuery.isEmpty {
                    Button {
                        library.clearNotebookSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清除查找")
                }
            }
            TextField("替换为", text: $notebookReplaceDraft)
                .textFieldStyle(.roundedBorder)
            Toggle("区分大小写", isOn: Binding(
                get: { library.notebookSearchCaseSensitive },
                set: { library.setNotebookSearchCaseSensitive($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            HStack(spacing: 10) {
                Button("全部替换…") {
                    prepareNotebookReplaceAllConfirm()
                }
                .disabled(library.notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer(minLength: 0)
                Button("收起") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        workspaceNotebookSearchExpanded = false
                        library.clearNotebookSearch()
                        notebookReplaceDraft = ""
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(library.appStyle.isGlass ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func prepareNotebookReplaceAllConfirm() {
        let find = library.notebookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !find.isEmpty else { return }
        let stats = library.countNotebookReplaceMatches(find: find, caseSensitive: library.notebookSearchCaseSensitive)
        guard stats.occurrences > 0 else {
            library.userMessage = "当前笔记本内没有可替换的匹配项。"
            return
        }
        notebookReplaceConfirmOcc = stats.occurrences
        notebookReplaceConfirmFiles = stats.files
        showNotebookReplaceConfirm = true
    }

    private var workspaceNotebookSearchResults: some View {
        Group {
            if library.notebookSearchIsRunning && library.notebookSearchHits.isEmpty {
                ProgressView("搜索中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.notebookSearchHits.isEmpty {
                ContentUnavailableView(
                    "无结果",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("当前笔记本下没有匹配的 Markdown 内容。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(library.notebookSearchHits) { hit in
                            Button {
                                library.selectFile(hit.fileURL)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.excerpt)
                                        .font(.callout)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                    Text(library.notebookFileDisplayPath(hit.fileURL))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    /// 不使用 `List`：macOS 上 NSTableView 会画行分隔/底边，和右侧玻璃编辑区永远「对不齐」。
    @ViewBuilder
    private func workspaceTreeNodes(nodes: [WorkspaceNode], depth: Int) -> some View {
        ForEach(nodes) { node in
            if node.kind == .directory {
                if node.children.isEmpty {
                    workspaceTreeLeafRow(node: node, depth: depth)
                } else {
                    DisclosureGroup {
                        AnyView(workspaceTreeNodes(nodes: node.children, depth: depth + 1))
                    } label: {
                        workspaceTreeRowLabel(node: node, depth: depth)
                            .onTapGesture {
                                fileTreeKeyboardTarget = node.url
                                fileTreeListFocused = true
                                library.selectDirectory(node.url)
                            }
                    }
                    .contextMenu {
                        workspaceTreeContextMenu(for: node)
                    }
                }
            } else {
                workspaceTreeLeafRow(node: node, depth: depth)
            }
        }
    }

    @ViewBuilder
    private func workspaceTreeLeafRow(node: WorkspaceNode, depth: Int) -> some View {
        Button {
            fileTreeKeyboardTarget = node.url
            fileTreeListFocused = true
            if node.kind == .directory {
                library.selectDirectory(node.url)
            } else {
                library.selectFile(node.url)
            }
        } label: {
            workspaceTreeRowLabel(node: node, depth: depth)
        }
        .buttonStyle(.plain)
        .contextMenu {
            workspaceTreeContextMenu(for: node)
        }
    }

    private func workspaceTreeItemDisplayName(_ node: WorkspaceNode) -> String {
        guard node.kind == .markdownFile, library.hideMarkdownExtension else {
            return node.name
        }
        if node.url.pathExtension.lowercased() == "md" {
            return node.url.deletingPathExtension().lastPathComponent
        }
        return node.name
    }

    @ViewBuilder
    private func workspaceTreeRowLabel(node: WorkspaceNode, depth: Int) -> some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: CGFloat(depth) * 12)
            Image(systemName: node.kind == .directory ? "folder" : "doc.text")
                .foregroundStyle(
                    node.kind == .directory
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.primary)
                )
            Text(workspaceTreeItemDisplayName(node))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background {
            let showTreeHighlight: Bool = library.treeSelectionIsDirectory
                ? (node.kind == .directory && node.url == library.selectedDirectoryURL)
                : (node.kind == .markdownFile && node.url == library.currentFileURL)
            if showTreeHighlight {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        Color.accentColor.opacity(0.2)
                    )
            }
        }
    }

    @ViewBuilder
    private func workspaceTreeContextMenu(for node: WorkspaceNode) -> some View {
        Button("重命名") {
            presentRenameSheet(for: node.url)
        }
        Button("在 Finder 中显示") {
            revealInFinder(node.url)
        }
        Button("删除", role: .destructive) {
            deleteTargetURL = node.url
        }
    }

    /// 在访达中揭示并选中该项（不「打开」文件本身）。
    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func beginRenameFromFileTreeKeyboard() {
        guard let url = fileTreeKeyboardTarget ?? library.currentFileURL ?? library.selectedDirectoryURL else {
            return
        }
        presentRenameSheet(for: url)
    }

    // MARK: - 编辑区

    private var editorDetail: some View {
        Group {
            if let fileURL = library.currentFileURL {
                editorColumn(fileURL: fileURL)
            } else {
                ContentUnavailableView(
                    "编辑区",
                    systemImage: "doc.richtext",
                    description: Text("请在目录树中创建或选择 Markdown 文件；预览区支持应用内链接跳转。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appPanel(appStyle: library.appStyle, cornerRadius: EditorChrome.panelCorner, panelStyle: .splitColumn)
        .clipShape(RoundedRectangle(cornerRadius: EditorChrome.panelCorner, style: .continuous))
    }

    /// 右侧整列：上「标题 + 保存」，分割线，下「正文」。
    @ViewBuilder
    private func editorColumn(fileURL: URL) -> some View {
        VStack(spacing: 0) {
            editorChromeBar(fileURL: fileURL)
            Divider().opacity(library.appStyle.isGlass ? 0.5 : 0.2)
            editorMainBody(fileURL: fileURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func editorMainBody(fileURL: URL) -> some View {
        let r = EditorChrome.panelCorner
        if library.readingMode {
            previewPane(fileURL: fileURL)
        } else if library.previewVisible {
            HSplitView {
                editorTextOnly(bottomLeading: r, bottomTrailing: 0)
                    .frame(minWidth: 360)
                previewPane(fileURL: fileURL)
                    .frame(minWidth: 360)
            }
        } else {
            editorTextOnly(bottomLeading: r, bottomTrailing: r)
        }
    }

    @ViewBuilder
    private func editorChromeBar(fileURL: URL) -> some View {
        HStack {
            Text(fileURL.lastPathComponent)
                .font(.headline)
            Spacer()
            if library.hasUnsavedChanges {
                Text("未保存")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let lastSavedAt = library.lastSavedAt {
                Text("已保存 \(timeText(lastSavedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("保存") {
                library.saveCurrentFile()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!library.hasUnsavedChanges)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(library.appStyle.chromeBarBackground)
    }

    @ViewBuilder
    private func editorTextOnly(bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0) -> some View {
        MacMarkdownTextEditor(
            text: Binding(
                get: { library.currentFileContent },
                set: { library.updateCurrentFileContent($0) }
            ),
            scrollBridge: scrollBridge,
            editorFont: library.resolvedEditorFont,
            notebookSearchQuery: library.notebookSearchQuery,
            notebookSearchCaseSensitive: library.notebookSearchCaseSensitive,
            bottomLeadingRadius: bottomLeading,
            bottomTrailingRadius: bottomTrailing
        )
        .padding(4)
    }

    @ViewBuilder
    private func previewPane(fileURL: URL) -> some View {
        MarkdownPreviewWebView(
            html: MarkdownRenderer.renderHTML(
                markdown: library.currentFileContent,
                title: fileURL.lastPathComponent
            ),
            baseURL: fileURL.deletingLastPathComponent(),
            onOpenLink: { href in
                library.openLinkFromPreview(href)
            },
            scrollBridge: scrollBridge
        )
    }

    // MARK: - 辅助计算属性

    private var trimmedNotebookName: String {
        newNotebookName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var notebookSheetListHeight: CGFloat {
        let rowHeight: CGFloat = 34
        let padding: CGFloat = 16
        return min(CGFloat(library.notebooks.count) * rowHeight + padding, 240)
    }

    private var userMessageBinding: Binding<Bool> {
        Binding(
            get: { library.userMessage != nil },
            set: { isPresented in
                if !isPresented {
                    library.userMessage = nil
                }
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTargetURL != nil },
            set: { newValue in
                if !newValue {
                    deleteTargetURL = nil
                }
            }
        )
    }

    // MARK: - 弹窗与对话框

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重命名")
                .font(.headline)
            Text(renameTargetURL?.lastPathComponent ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("新名称", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitRename)
            HStack {
                Spacer()
                Button("取消") {
                    renameSheetPresented = false
                }
                Button("确定") {
                    submitRename()
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - 操作方法

    private func createNotebookFromDraft() {
        library.createNotebook(named: trimmedNotebookName)
        if library.userMessage == nil {
            newNotebookName = ""
            newNotebookSheetPresented = false
        }
    }

    private func chooseNotebookFromSheet(_ url: URL) {
        library.selectWorkspace(url)
        newNotebookSheetPresented = false
    }

    private func presentRenameSheet(for url: URL) {
        renameTargetURL = url
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDirectory {
            renameDraft = url.lastPathComponent
        } else {
            renameDraft = url.deletingPathExtension().lastPathComponent
        }
        renameSheetPresented = true
    }

    private func beginUntitledMarkdownCreation() {
        if let url = library.createUntitledMarkdownInSelection() {
            presentRenameSheet(for: url)
        }
    }

    private func beginUntitledFolderCreation() {
        if let url = library.createUntitledFolderInSelection() {
            presentRenameSheet(for: url)
        }
    }

    // MARK: - 工具栏

    private var mainToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                library.setReadingMode(!library.readingMode)
            } label: {
                Label(
                    library.readingMode ? "编辑模式" : "阅读模式",
                    systemImage: library.readingMode ? "doc.text" : "book.pages"
                )
            }
            .help(library.readingMode ? "显示编辑器" : "仅全宽预览")
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button {
                if !library.readingMode {
                    library.setPreviewVisible(!library.previewVisible)
                }
            } label: {
                Label(
                    library.previewVisible ? "隐藏预览" : "显示预览",
                    systemImage: library.previewVisible ? "rectangle.split.2x1" : "rectangle.split.2x1.fill"
                )
            }
            .disabled(library.readingMode)
            .help(library.readingMode ? "阅读模式下始终显示预览" : (library.previewVisible ? "隐藏预览栏" : "显示预览栏"))

            Button(action: beginNewNotebookSheet) {
                Label("新建笔记本", systemImage: "book.badge.plus")
            }
            .disabled(library.rootURL == nil)
            .help("选择或新建笔记本")

            Button {
                openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .help("打开设置")
        }
    }

    private func beginNewNotebookSheet() {
        newNotebookName = ""
        newNotebookSheetPresented = true
    }

    private func syncSelectionFromLibrary() {
        if library.workspaceURL == nil, let first = library.notebooks.first {
            library.selectWorkspace(first)
        }
    }

    private func autoPickRootOnFirstLaunchIfNeeded() {
        guard !didTryAutoPickRoot else { return }
        didTryAutoPickRoot = true
        guard library.rootURL == nil else { return }
        DispatchQueue.main.async {
            openSettings()
        }
    }

    private func submitRename() {
        guard let target = renameTargetURL else { return }
        library.renameWorkspaceItem(target, to: renameDraft)
        if library.userMessage == nil {
            renameTargetURL = nil
            renameSheetPresented = false
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

}
