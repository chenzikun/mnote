import AppKit

/// 为笔记本目录 / 工作区内新建文件夹设置 Finder 自定义图标（`NSWorkspace.setIcon`）。
/// 位图来自 `mnote-mark.svg` 经 Quick Look 导出的 `mnote-mark-folder.png`（与 SVG 视觉一致）。
enum WorkspaceFolderIcon {

    static func apply(toFolderAt url: URL) {
        guard let image = loadRasterIcon() else { return }
        NSWorkspace.shared.setIcon(image, forFile: url.path, options: [])
    }

    private static func loadRasterIcon() -> NSImage? {
        // 打包 .app：PNG 在 Contents/Resources；swift run：在 mnote_mnote.bundle 根目录
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "mnote-mark-folder", withExtension: "png"),
            Bundle.module.url(forResource: "mnote-mark-folder", withExtension: "png"),
        ]
        for u in candidates.compactMap({ $0 }) {
            if let img = NSImage(contentsOf: u) { return img }
        }
        return nil
    }
}
