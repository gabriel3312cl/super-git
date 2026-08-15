import Foundation

/// Operaciones de alto nivel sobre un repositorio.
enum GitService {

    // MARK: - Lectura

    static func status(at url: URL) async throws -> RepoStatus {
        let result = try await GitRunner.checked(
            ["status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"],
            in: url,
            timeout: 45
        )
        return GitStatusParser.parse(result.stdoutData)
    }

    static func lastCommitSubject(at url: URL) async -> String? {
        let result = try? await GitRunner.run(["log", "-1", "--pretty=%s"], in: url, timeout: 15)
        guard let result, result.ok else { return nil }
        let subject = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? nil : subject
    }

    // MARK: - Staging

    static func stage(_ paths: [String], at url: URL) async throws {
        guard !paths.isEmpty else { return }
        try await GitRunner.checked(["add", "-A", "--"] + paths, in: url)
    }

    static func stageAll(at url: URL) async throws {
        try await GitRunner.checked(["add", "-A"], in: url)
    }

    static func unstage(_ paths: [String], at url: URL) async throws {
        guard !paths.isEmpty else { return }
        if await hasCommits(at: url) {
            try await GitRunner.checked(["restore", "--staged", "--"] + paths, in: url)
        } else {
            // Sin HEAD todavía: sacar del índice es la única opción.
            try await GitRunner.checked(["rm", "--cached", "-r", "-q", "--"] + paths, in: url)
        }
    }

    static func unstageAll(at url: URL) async throws {
        if await hasCommits(at: url) {
            try await GitRunner.checked(["reset", "-q", "HEAD"], in: url)
        } else {
            try await GitRunner.checked(["rm", "--cached", "-r", "-q", "."], in: url)
        }
    }

    /// Descarta cambios del worktree. Los archivos sin seguimiento se borran.
    static func discard(_ changes: [FileChange], at url: URL) async throws {
        let tracked = changes.filter { !$0.isUntracked }.map(\.path)
        let untracked = changes.filter(\.isUntracked).map(\.path)

        if !tracked.isEmpty {
            try await GitRunner.checked(["checkout", "--"] + tracked, in: url)
        }
        if !untracked.isEmpty {
            try await GitRunner.checked(["clean", "-fd", "--"] + untracked, in: url)
        }
    }

    // MARK: - Commit

    static func commit(message: String, at url: URL, amend: Bool = false) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitError.failed(command: "commit", message: "El mensaje de commit está vacío.", code: 1)
        }

        // Mensaje por archivo: evita cualquier problema de quoting o multilínea.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("supergit-commit-\(UUID().uuidString).txt")
        try trimmed.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        var args = ["commit", "-F", file.path]
        if amend { args.append("--amend") }
        try await GitRunner.checked(args, in: url, timeout: 120)
    }

    // MARK: - Remoto

    static func fetch(at url: URL) async throws -> String {
        let result = try await GitRunner.checked(
            ["fetch", "--all", "--prune"], in: url, timeout: 180
        )
        return result.combined
    }

    enum PullMode {
        case fastForward, rebase, merge

        var arguments: [String] {
            switch self {
            case .fastForward: return ["pull", "--ff-only"]
            case .rebase: return ["pull", "--rebase"]
            case .merge: return ["pull", "--no-rebase"]
            }
        }
    }

    static func pull(at url: URL, mode: PullMode) async throws -> String {
        let result = try await GitRunner.checked(mode.arguments, in: url, timeout: 300)
        return result.combined
    }

    static func push(at url: URL, status: RepoStatus) async throws -> String {
        var args = ["push"]
        if !status.hasUpstream, let branch = status.branch {
            args += ["--set-upstream", "origin", branch]
        }
        let result = try await GitRunner.checked(args, in: url, timeout: 300)
        return result.combined
    }

    // MARK: - Helpers

    static func hasCommits(at url: URL) async -> Bool {
        let result = try? await GitRunner.run(["rev-parse", "--verify", "HEAD"], in: url, timeout: 15)
        return result?.ok ?? false
    }

    static func remotes(at url: URL) async -> [String] {
        let result = try? await GitRunner.run(["remote"], in: url, timeout: 15)
        guard let result, result.ok else { return [] }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
