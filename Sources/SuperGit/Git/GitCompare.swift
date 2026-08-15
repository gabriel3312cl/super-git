import Foundation

/// Consultas de comparación entre ramas y commits.
enum GitCompare {

    /// Hash del árbol vacío: sirve como "padre" del primer commit de un repo.
    private static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    // MARK: - Referencias

    static func branches(at url: URL) async -> [BranchRef] {
        let result = try? await GitRunner.run(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
            in: url, timeout: 30
        )
        guard let result, result.ok else { return [] }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
            .map { BranchRef(name: $0, isRemote: $0.contains("/")) }
    }

    /// Elige una base razonable: main/master/develop, prefiriendo la del remoto
    /// y descartando la rama en la que ya estamos.
    static func suggestedBase(from branches: [BranchRef], current: String?) -> String? {
        let preferred = [
            "origin/main", "origin/master", "origin/develop",
            "main", "master", "develop"
        ]
        let names = Set(branches.map(\.name))
        for candidate in preferred where names.contains(candidate) {
            if candidate == current { continue }
            return candidate
        }
        return branches.first { $0.name != current }?.name
    }

    // MARK: - Commits

    /// Commits que tiene HEAD y la base no, del más nuevo al más viejo.
    static func commits(base: String, at url: URL) async throws -> [CommitInfo] {
        let separator = "\u{1f}"
        let result = try await GitRunner.checked(
            ["log", "-z", "--no-merges", "--date=short",
             "--format=%H\(separator)%h\(separator)%s\(separator)%an\(separator)%ad",
             "\(base)..HEAD"],
            in: url, timeout: 60
        )

        return result.stdout
            .split(separator: "\0", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.components(separatedBy: separator)
                guard fields.count >= 5 else { return nil }
                return CommitInfo(
                    sha: fields[0], shortSha: fields[1], subject: fields[2],
                    author: fields[3], date: fields[4]
                )
            }
    }

    // MARK: - Rango

    /// Traduce el rango a los argumentos que entiende `git diff`.
    static func arguments(for range: DiffRange, at url: URL) async -> [String] {
        switch range {
        case .wholeBranch(let base):
            // Tres puntos: solo lo que aportó esta rama desde que se separó.
            return ["\(base)...HEAD"]
        case .commitSpan(let oldest, let newest):
            let parent = await parentOrEmptyTree(of: oldest, at: url)
            return [parent, newest]
        case .workingTree(let base):
            // Dos puntos contra el árbol de trabajo: incluye lo commiteado en
            // la rama y también lo que sigue sin commitear.
            return [base]
        }
    }

    private static func parentOrEmptyTree(of sha: String, at url: URL) async -> String {
        let result = try? await GitRunner.run(
            ["rev-parse", "--verify", "--quiet", "\(sha)^"], in: url, timeout: 15
        )
        if let result, result.ok {
            let parent = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !parent.isEmpty { return parent }
        }
        return emptyTree   // el commit no tiene padre: es la raíz del repo
    }

    // MARK: - Archivos

    static func files(range: DiffRange, at url: URL) async throws -> [DiffFileSummary] {
        let rangeArgs = await arguments(for: range, at: url)

        let numstat = try await GitRunner.checked(
            ["diff", "--numstat", "-z"] + rangeArgs, in: url, timeout: 120
        )
        let nameStatus = try await GitRunner.checked(
            ["diff", "--name-status", "-z"] + rangeArgs, in: url, timeout: 120
        )

        let statuses = parseNameStatus(nameStatus.stdout)
        var files = parseNumstat(numstat.stdout, statuses: statuses)

        // `git diff` no ve los archivos sin seguimiento, así que se agregan
        // aparte: si no, un trabajo hecho de archivos nuevos parecería vacío.
        if case .workingTree = range {
            files += await untrackedFiles(at: url)
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func untrackedFiles(at url: URL) async -> [DiffFileSummary] {
        let result = try? await GitRunner.run(
            ["status", "--porcelain=v2", "--untracked-files=all", "-z"], in: url, timeout: 60
        )
        guard let result, result.ok else { return [] }

        return result.stdout
            .split(separator: "\0", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("? ") }
            .map { record in
                let path = String(record.dropFirst(2))
                let measured = measure(url.appendingPathComponent(path))
                return DiffFileSummary(
                    path: path, oldPath: nil, status: "?",
                    additions: measured.lines, deletions: 0, isBinary: measured.isBinary
                )
            }
    }

    /// Cuenta líneas de un archivo nuevo sin invocar a git.
    private static func measure(_ fileURL: URL) -> (lines: Int, isBinary: Bool) {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return (0, false)
        }
        if data.prefix(8000).contains(0) { return (0, true) }
        if data.count > 5_000_000 { return (0, false) }   // demasiado grande para contar

        var lines = data.reduce(0) { $1 == 0x0a ? $0 + 1 : $0 }
        if let last = data.last, last != 0x0a { lines += 1 }
        return (lines, false)
    }

    /// `A\0path\0` · `R100\0viejo\0nuevo\0`
    private static func parseNameStatus(_ output: String) -> [String: Character] {
        var result: [String: Character] = [:]
        let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)

        var index = 0
        while index < fields.count {
            let code = fields[index]
            guard let letter = code.first, !code.isEmpty else { index += 1; continue }
            index += 1
            guard index < fields.count else { break }

            if letter == "R" || letter == "C" {
                // origen y destino
                index += 1
                guard index < fields.count else { break }
                result[fields[index]] = letter
                index += 1
            } else {
                result[fields[index]] = letter
                index += 1
            }
        }
        return result
    }

    /// `add\tdel\tpath\0` · en renombres `add\tdel\t\0viejo\0nuevo\0`
    private static func parseNumstat(
        _ output: String, statuses: [String: Character]
    ) -> [DiffFileSummary] {
        var files: [DiffFileSummary] = []
        let records = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)

        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            if record.isEmpty { continue }

            let columns = record.components(separatedBy: "\t")
            guard columns.count >= 3 else { continue }

            let isBinary = columns[0] == "-" || columns[1] == "-"
            let additions = Int(columns[0]) ?? 0
            let deletions = Int(columns[1]) ?? 0

            var path = columns[2]
            var oldPath: String?

            if path.isEmpty {
                // Renombre: las dos rutas vienen como registros aparte.
                guard index + 1 < records.count else { break }
                oldPath = records[index]
                path = records[index + 1]
                index += 2
            }

            guard !path.isEmpty else { continue }
            files.append(
                DiffFileSummary(
                    path: path,
                    oldPath: oldPath,
                    status: statuses[path] ?? "M",
                    additions: additions,
                    deletions: deletions,
                    isBinary: isBinary
                )
            )
        }

        return files
    }

    // MARK: - Diff de un archivo

    static func fileDiff(
        range: DiffRange, file: DiffFileSummary, at url: URL
    ) async throws -> [DiffLine] {
        if file.isUntracked {
            // Un archivo nuevo no está en el índice: se compara contra /dev/null.
            // `--no-index` sale con código 1 cuando encuentra diferencias, que
            // es justamente el caso normal aquí.
            let result = try await GitRunner.run(
                ["diff", "--no-index", "--no-color", "--", "/dev/null", file.path],
                in: url, timeout: 60
            )
            return DiffParser.parse(result.stdout)
        }

        let rangeArgs = await arguments(for: range, at: url)
        var paths = [file.path]
        if let oldPath = file.oldPath { paths.append(oldPath) }

        let result = try await GitRunner.checked(
            ["diff", "--find-renames", "--no-color"] + rangeArgs + ["--"] + paths,
            in: url, timeout: 120
        )
        return DiffParser.parse(result.stdout)
    }
}
