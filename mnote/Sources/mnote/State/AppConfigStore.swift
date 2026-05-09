import Foundation

/// 将配置持久化到 ~/.mnote/config.json
final class AppConfigStore {
    struct Config: Codable {
        var rootBookmarkBase64: String?
        var workspaceBookmarkBase64: String?
        var appTheme: String?            // 旧版字段，保留用于迁移
        var previewVisible: Bool?
        var liquidGlassEnabled: Bool?   // 旧版字段，保留用于迁移
        var readingMode: Bool?
        var hideMarkdownExtension: Bool?
        var appStyle: String?           // glass-dark/glass-light/neu-light/neu-dark
        var editorFontName: String?     // EditorFontPreset.id，"system" 表示 SF Mono
        var editorFontSize: Double?     // 单位 pt
    }

    enum Field {
        case root
        case workspace
        case appTheme
        case previewVisible
        case liquidGlassEnabled
        case readingMode
        case hideMarkdownExtension
        case appStyle
        case editorFontName
        case editorFontSize
    }

    let directoryURL: URL
    let fileURL: URL

    private var cached: Config
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseDirectoryURL: URL? = nil) {
        let resolvedBase: URL
        if let baseDirectoryURL {
            resolvedBase = baseDirectoryURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            resolvedBase = home.appendingPathComponent(".mnote", isDirectory: true)
        }

        directoryURL = resolvedBase
        fileURL = directoryURL.appendingPathComponent("config.json")
        cached = Config()

        ensureDirectoryExists()
        loadFromDisk()
    }

    func data(for field: Field) -> Data? {
        let encoded: String?
        switch field {
        case .root:
            encoded = cached.rootBookmarkBase64
        case .workspace:
            encoded = cached.workspaceBookmarkBase64
        case .appTheme, .previewVisible, .liquidGlassEnabled, .readingMode,
             .hideMarkdownExtension, .appStyle, .editorFontName, .editorFontSize:
            encoded = nil
        }
        guard let encoded else { return nil }
        return Data(base64Encoded: encoded)
    }

    func set(_ data: Data?, for field: Field) {
        let value = data?.base64EncodedString()
        switch field {
        case .root:
            cached.rootBookmarkBase64 = value
        case .workspace:
            cached.workspaceBookmarkBase64 = value
        case .appTheme, .previewVisible, .liquidGlassEnabled, .readingMode,
             .hideMarkdownExtension, .appStyle, .editorFontName, .editorFontSize:
            break
        }
        saveToDisk()
    }

    func string(for field: Field) -> String? {
        switch field {
        case .appTheme:      return cached.appTheme
        case .appStyle:      return cached.appStyle
        case .editorFontName: return cached.editorFontName
        default:             return nil
        }
    }

    func set(_ value: String?, for field: Field) {
        switch field {
        case .appTheme:       cached.appTheme = value
        case .appStyle:       cached.appStyle = value
        case .editorFontName: cached.editorFontName = value
        default:              break
        }
        saveToDisk()
    }

    func double(for field: Field, default defaultValue: Double) -> Double {
        switch field {
        case .editorFontSize: return cached.editorFontSize ?? defaultValue
        default:              return defaultValue
        }
    }

    func set(_ value: Double, for field: Field) {
        switch field {
        case .editorFontSize: cached.editorFontSize = value
        default:              break
        }
        saveToDisk()
    }

    func bool(for field: Field, default defaultValue: Bool) -> Bool {
        switch field {
        case .previewVisible:
            return cached.previewVisible ?? defaultValue
        case .liquidGlassEnabled:
            return cached.liquidGlassEnabled ?? defaultValue
        case .readingMode:
            return cached.readingMode ?? defaultValue
        case .hideMarkdownExtension:
            return cached.hideMarkdownExtension ?? defaultValue
        default:
            return defaultValue
        }
    }

    func set(_ value: Bool, for field: Field) {
        switch field {
        case .previewVisible:
            cached.previewVisible = value
        case .liquidGlassEnabled:
            cached.liquidGlassEnabled = value
        case .readingMode:
            cached.readingMode = value
        case .hideMarkdownExtension:
            cached.hideMarkdownExtension = value
        default:
            break
        }
        saveToDisk()
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func loadFromDisk() {
        guard let raw = try? Data(contentsOf: fileURL),
              let parsed = try? decoder.decode(Config.self, from: raw)
        else {
            saveToDisk()
            return
        }
        cached = parsed
    }

    /// 另一窗口或外部写入 `config.json` 后，将内存缓存与磁盘对齐（各 `LibraryState` 持有独立 `AppConfigStore` 实例）。
    func reloadFromDisk() {
        loadFromDisk()
    }

    private func saveToDisk() {
        guard let raw = try? encoder.encode(cached) else { return }
        try? raw.write(to: fileURL, options: [.atomic])
    }
}
