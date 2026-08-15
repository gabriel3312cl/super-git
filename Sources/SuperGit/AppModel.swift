import Foundation
import Observation

@MainActor
@Observable
final class AppModel {

    var repos: [Repo] = []
    var selectedRepoID: String?
    var config: AppConfig = .load()
    var isScanning = false
    var hasScanned = false
    var searchText = ""
    var showSettings = false

    /// Se escaneó y no apareció nada: normalmente es que macOS todavía no dio
    /// permiso de acceso a la carpeta.
    var foundNothing: Bool { hasScanned && !isScanning && repos.isEmpty }

    var selectedRepo: Repo? {
        guard let selectedRepoID else { return nil }
        return repos.first { $0.id == selectedRepoID }
    }

    var visibleRepos: [Repo] {
        let hidden = Set(config.hiddenRepos)
        let base = repos.filter { !hidden.contains($0.path) }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.parentName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var dirtyRepoCount: Int {
        visibleRepos.filter { ($0.status?.totalChanges ?? 0) > 0 }.count
    }

    // MARK: - Ciclo de vida

    func bootstrap() async {
        guard repos.isEmpty else { return }
        await rescan()
    }

    func rescan() async {
        isScanning = true
        defer { isScanning = false; hasScanned = true }

        let urls = await RepoScanner.scan(roots: config.rootURLs, maxDepth: config.maxDepth)
        let existing = Dictionary(uniqueKeysWithValues: repos.map { ($0.path, $0) })

        // Reutilizamos los objetos existentes para no perder mensajes de commit
        // a medio escribir cuando se re-escanea.
        repos = urls.map { url in
            existing[url.standardizedFileURL.path] ?? Repo(url: url)
        }

        if let selectedRepoID, !repos.contains(where: { $0.id == selectedRepoID }) {
            self.selectedRepoID = nil
        }
        if selectedRepoID == nil {
            selectedRepoID = visibleRepos.first?.id
        }

        await refreshAll()
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for repo in repos where !repo.isBusy {
                group.addTask { await self.refresh(repo) }
            }
        }
    }

    func refresh(_ repo: Repo) async {
        do {
            let status = try await GitService.status(at: repo.url)
            repo.status = status
            repo.errorMessage = nil
            if status.hasCommits {
                repo.lastCommitSubject = await GitService.lastCommitSubject(at: repo.url)
            } else {
                repo.lastCommitSubject = nil
            }
        } catch {
            repo.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Operaciones

    /// Envuelve una operación: marca ocupado, captura errores y refresca.
    private func perform(
        _ repo: Repo,
        _ label: String,
        _ operation: @escaping (URL) async throws -> String?
    ) async {
        guard !repo.isBusy else { return }
        repo.isBusy = true
        repo.busyLabel = label
        repo.errorMessage = nil
        repo.lastOperationOutput = nil

        do {
            let output = try await operation(repo.url)
            if let output, !output.isEmpty {
                repo.lastOperationOutput = output
            }
        } catch {
            repo.errorMessage = "\(label): \(error.localizedDescription)"
        }

        repo.isBusy = false
        repo.busyLabel = nil
        await refresh(repo)
    }

    func stage(_ changes: [FileChange], in repo: Repo) async {
        let paths = uniquePaths(changes)
        await perform(repo, "Stage") { url in
            try await GitService.stage(paths, at: url)
            return nil
        }
    }

    func stageAll(in repo: Repo) async {
        await perform(repo, "Stage all") { url in
            try await GitService.stageAll(at: url)
            return nil
        }
    }

    func unstage(_ changes: [FileChange], in repo: Repo) async {
        let paths = uniquePaths(changes)
        await perform(repo, "Unstage") { url in
            try await GitService.unstage(paths, at: url)
            return nil
        }
    }

    func unstageAll(in repo: Repo) async {
        await perform(repo, "Unstage all") { url in
            try await GitService.unstageAll(at: url)
            return nil
        }
    }

    func discard(_ changes: [FileChange], in repo: Repo) async {
        await perform(repo, "Descartar") { url in
            try await GitService.discard(changes, at: url)
            return nil
        }
    }

    func commit(in repo: Repo, stageAllFirst: Bool = false, amend: Bool = false) async {
        let message = repo.commitMessage
        await perform(repo, "Commit") { url in
            if stageAllFirst {
                try await GitService.stageAll(at: url)
            }
            try await GitService.commit(message: message, at: url, amend: amend)
            return nil
        }
        if repo.errorMessage == nil {
            repo.commitMessage = ""
        }
    }

    func fetch(in repo: Repo) async {
        await perform(repo, "Fetch") { url in
            try await GitService.fetch(at: url)
        }
    }

    func pull(in repo: Repo, mode: GitService.PullMode) async {
        await perform(repo, "Pull") { url in
            try await GitService.pull(at: url, mode: mode)
        }
    }

    func push(in repo: Repo) async {
        guard let status = repo.status else { return }
        await perform(repo, "Push") { url in
            try await GitService.push(at: url, status: status)
        }
    }

    // MARK: - Configuración

    func hide(_ repo: Repo) {
        guard !config.hiddenRepos.contains(repo.path) else { return }
        config.hiddenRepos.append(repo.path)
        config.save()
        if selectedRepoID == repo.id {
            selectedRepoID = visibleRepos.first?.id
        }
    }

    func unhideAll() {
        config.hiddenRepos.removeAll()
        config.save()
    }

    func addRoot(_ url: URL) async {
        let path = url.standardizedFileURL.path
        guard !config.roots.contains(path) else { return }
        config.roots.append(path)
        config.save()
        await rescan()
    }

    func removeRoot(_ root: String) async {
        config.roots.removeAll { $0 == root }
        config.save()
        await rescan()
    }

    func saveConfig() {
        config.save()
    }

    func revealInFinder(_ repo: Repo) {
        NSWorkspaceBridge.reveal(repo.url)
    }

    private func uniquePaths(_ changes: [FileChange]) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for change in changes where seen.insert(change.path).inserted {
            paths.append(change.path)
            // En un rename, la ruta original también debe entrar al índice.
            if let original = change.originalPath, seen.insert(original).inserted {
                paths.append(original)
            }
        }
        return paths
    }
}
