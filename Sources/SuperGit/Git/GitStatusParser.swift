import Foundation

/// Parser de `git status --porcelain=v2 --branch -z`.
///
/// El formato v2 con `-z` entrega registros separados por NUL. Los registros
/// de tipo `2` (rename/copy) traen la ruta original como un campo NUL extra.
enum GitStatusParser {

    static func parse(_ data: Data) -> RepoStatus {
        var status = RepoStatus()

        let records = data
            .split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }

        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            if record.isEmpty { continue }

            if record.hasPrefix("# ") {
                parseHeader(record, into: &status)
                continue
            }

            guard let kind = record.first else { continue }
            switch kind {
            case "1":
                if let change = parseOrdinary(record) {
                    append(change, to: &status)
                }
            case "2":
                // El siguiente registro es la ruta original del rename/copy.
                let original = index < records.count ? records[index] : nil
                index += 1
                if let changes = parseRenamed(record, originalPath: original) {
                    append(changes, to: &status)
                }
            case "u":
                if let change = parseUnmerged(record) {
                    status.conflicted.append(change)
                }
            case "?":
                let path = String(record.dropFirst(2))
                if !path.isEmpty {
                    status.unstaged.append(
                        FileChange(path: path, originalPath: nil, code: "?", section: .unstaged)
                    )
                }
            default:
                continue // "!" (ignored) u otros: no nos interesan
            }
        }

        status.staged.sort { $0.path < $1.path }
        status.unstaged.sort { $0.path < $1.path }
        status.conflicted.sort { $0.path < $1.path }
        return status
    }

    // MARK: - Cabeceras

    private static func parseHeader(_ record: String, into status: inout RepoStatus) {
        let body = String(record.dropFirst(2))
        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let key = parts[0]
        let value = parts[1]

        switch key {
        case "branch.oid":
            if value == "(initial)" {
                status.hasCommits = false
            } else {
                status.headSha = value
            }
        case "branch.head":
            status.branch = value == "(detached)" ? nil : value
        case "branch.upstream":
            status.upstream = value
        case "branch.ab":
            // "+2 -1"
            for token in value.split(separator: " ") {
                guard let sign = token.first, let count = Int(token.dropFirst()) else { continue }
                if sign == "+" { status.ahead = count }
                if sign == "-" { status.behind = count }
            }
        default:
            break
        }
    }

    // MARK: - Entradas

    /// `1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>` — 8 campos fijos + ruta.
    private static func parseOrdinary(_ record: String) -> [FileChange]? {
        guard let (xy, path) = split(record, fixedFields: 8) else { return nil }
        return changes(xy: xy, path: path, originalPath: nil)
    }

    /// `2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>` — 9 campos + ruta.
    private static func parseRenamed(_ record: String, originalPath: String?) -> [FileChange]? {
        guard let (xy, path) = split(record, fixedFields: 9) else { return nil }
        return changes(xy: xy, path: path, originalPath: originalPath)
    }

    /// `u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>` — 10 campos + ruta.
    private static func parseUnmerged(_ record: String) -> FileChange? {
        guard let (_, path) = split(record, fixedFields: 10) else { return nil }
        return FileChange(path: path, originalPath: nil, code: "U", section: .conflicted)
    }

    /// Separa los primeros `fixedFields` campos (por espacio) y devuelve el
    /// XY junto con el resto de la línea como ruta (puede contener espacios).
    private static func split(_ record: String, fixedFields: Int) -> (xy: String, path: String)? {
        let fields = record.split(separator: " ", maxSplits: fixedFields, omittingEmptySubsequences: false)
        guard fields.count == fixedFields + 1 else { return nil }
        let xy = String(fields[1])
        let path = String(fields[fixedFields])
        guard xy.count == 2, !path.isEmpty else { return nil }
        return (xy, path)
    }

    /// Un archivo puede estar a la vez staged y modificado en el worktree
    /// (por ejemplo "MM"): en ese caso aparece en ambas secciones, igual que
    /// en el panel de VS Code.
    private static func changes(xy: String, path: String, originalPath: String?) -> [FileChange] {
        var result: [FileChange] = []
        let x = xy[xy.startIndex]
        let y = xy[xy.index(after: xy.startIndex)]

        if x != "." {
            result.append(
                FileChange(path: path, originalPath: originalPath, code: x, section: .staged)
            )
        }
        if y != "." {
            result.append(
                FileChange(path: path, originalPath: originalPath, code: y, section: .unstaged)
            )
        }
        return result
    }

    private static func append(_ changes: [FileChange], to status: inout RepoStatus) {
        for change in changes {
            switch change.section {
            case .staged: status.staged.append(change)
            case .unstaged: status.unstaged.append(change)
            case .conflicted: status.conflicted.append(change)
            }
        }
    }
}
