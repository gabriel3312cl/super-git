import Foundation
import Observation

enum DetailMode: String, CaseIterable, Identifiable {
    case changes = "Cambios"
    case compare = "Comparar"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .changes: return "pencil.and.list.clipboard"
        case .compare: return "arrow.triangle.pull"
        }
    }
}

/// Un repositorio descubierto, con su estado y el borrador de commit.
@MainActor
@Observable
final class Repo: Identifiable {
    let url: URL
    let path: String
    let name: String
    /// Carpeta contenedora, para distinguir repos con el mismo nombre.
    let parentName: String

    var status: RepoStatus?
    var lastCommitSubject: String?
    var commitMessage: String = ""
    var isBusy: Bool = false
    var busyLabel: String?
    var errorMessage: String?
    var lastOperationOutput: String?

    var mode: DetailMode = .changes
    /// Se conserva por repo para no perder la base ni la selección de commits
    /// al cambiar de repositorio y volver.
    let compare = CompareState()

    nonisolated var id: String { path }

    init(url: URL) {
        let standardized = url.standardizedFileURL
        self.url = standardized
        self.path = standardized.path
        self.name = standardized.lastPathComponent
        self.parentName = standardized.deletingLastPathComponent().lastPathComponent
    }

    /// Ruta con `~` para mostrar en la UI.
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
