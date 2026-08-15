import Foundation

/// Un archivo con cambios, tal como lo reporta `git status --porcelain=v2`.
struct FileChange: Identifiable, Hashable, Sendable {
    enum Section: String, Sendable {
        case staged, unstaged, conflicted
    }

    let path: String
    let originalPath: String?
    let code: Character   // M, A, D, R, C, U, ? (untracked)
    let section: Section

    var id: String { "\(section.rawValue):\(path)" }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    var statusLabel: String {
        switch code {
        case "?": return "U"
        default: return String(code)
        }
    }

    var statusDescription: String {
        switch code {
        case "M": return "Modificado"
        case "A": return "Agregado"
        case "D": return "Eliminado"
        case "R": return "Renombrado"
        case "C": return "Copiado"
        case "U": return "Conflicto"
        case "?": return "Sin seguimiento"
        case "T": return "Tipo cambiado"
        default: return "Cambiado"
        }
    }

    var isUntracked: Bool { code == "?" }
}

/// Estado completo de un repositorio en un instante dado.
struct RepoStatus: Equatable, Sendable {
    var branch: String?
    var headSha: String?
    var upstream: String?
    var ahead: Int = 0
    var behind: Int = 0
    var hasCommits: Bool = true
    var staged: [FileChange] = []
    var unstaged: [FileChange] = []
    var conflicted: [FileChange] = []

    var isDetached: Bool { branch == nil && headSha != nil }

    var branchLabel: String {
        if let branch { return branch }
        if let sha = headSha, sha.count >= 7 { return "detached @ " + String(sha.prefix(7)) }
        return "sin commits"
    }

    var totalChanges: Int { staged.count + unstaged.count + conflicted.count }
    var isClean: Bool { totalChanges == 0 }
    var hasUpstream: Bool { upstream != nil }
    var canCommit: Bool { !staged.isEmpty && conflicted.isEmpty }
}
