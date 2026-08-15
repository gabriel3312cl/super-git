import Foundation

/// Una referencia que se puede usar como base de comparación.
struct BranchRef: Identifiable, Hashable, Sendable {
    let name: String        // "main" o "origin/main"
    let isRemote: Bool
    var id: String { name }
}

struct CommitInfo: Identifiable, Hashable, Sendable {
    let sha: String
    let shortSha: String
    let subject: String
    let author: String
    let date: String
    var id: String { sha }
}

/// Resumen de un archivo dentro de una comparación.
struct DiffFileSummary: Identifiable, Hashable, Sendable {
    let path: String
    let oldPath: String?
    let status: Character   // M A D R C T
    let additions: Int
    let deletions: Int
    let isBinary: Bool

    var id: String { path }

    var fileName: String { (path as NSString).lastPathComponent }

    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    var statusDescription: String {
        switch status {
        case "A": return "Agregado"
        case "D": return "Eliminado"
        case "R": return "Renombrado"
        case "C": return "Copiado"
        case "T": return "Tipo cambiado"
        case "?": return "Sin seguimiento"
        default:  return "Modificado"
        }
    }

    var isUntracked: Bool { status == "?" }
}

enum DiffLineKind: Sendable {
    case context, addition, deletion, hunkHeader, meta
}

struct DiffLine: Identifiable, Sendable {
    let id: Int
    let kind: DiffLineKind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String

    /// Prefijo textual del diff. Se muestra siempre, para no depender solo
    /// del color al distinguir agregado de eliminado.
    var marker: String {
        switch kind {
        case .addition:   return "+"
        case .deletion:   return "−"
        case .context:    return " "
        case .hunkHeader: return "@"
        case .meta:       return " "
        }
    }

    var accessibilityDescription: String {
        switch kind {
        case .addition:   return "Línea agregada \(newNumber.map(String.init) ?? ""): \(text)"
        case .deletion:   return "Línea eliminada \(oldNumber.map(String.init) ?? ""): \(text)"
        case .context:    return "Línea \(newNumber.map(String.init) ?? ""): \(text)"
        case .hunkHeader: return "Sección \(text)"
        case .meta:       return text
        }
    }
}

/// Fila de la vista lado a lado: la versión vieja a la izquierda y la nueva
/// a la derecha, emparejadas dentro de cada bloque de cambios.
struct DiffRow: Identifiable, Sendable {
    let id: Int
    let left: DiffLine?
    let right: DiffLine?
    let header: DiffLine?

    var isHeader: Bool { header != nil }
}

enum DiffLayout: String, CaseIterable, Identifiable, Sendable {
    case split = "Lado a lado"
    case unified = "Unificada"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .split:   return "rectangle.split.2x1"
        case .unified: return "list.bullet.rectangle"
        }
    }
}

/// Qué se está comparando.
enum DiffRange: Equatable, Sendable {
    /// Todo lo que la rama actual tiene y la base no (`base...HEAD`).
    case wholeBranch(base: String)
    /// Un tramo de commits, del más viejo al más nuevo.
    case commitSpan(oldest: String, newest: String)
    /// Desde la base hasta el árbol de trabajo: incluye lo que hay commiteado
    /// en la rama y además lo que todavía no se ha commiteado.
    case workingTree(base: String)
}
