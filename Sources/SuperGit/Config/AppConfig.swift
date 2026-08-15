import Foundation

/// Configuración persistida en ~/.config/super-git/config.json
struct AppConfig: Codable, Equatable {
    var roots: [String] = ["~/Documents"]
    var maxDepth: Int = 3
    var hiddenRepos: [String] = []
    var autoRefreshSeconds: Int = 20

    var rootURLs: [URL] {
        roots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/super-git/config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    func save() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
