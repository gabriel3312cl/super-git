import Foundation
import Observation

/// Estado de la vista de comparación de un repositorio: contra qué se compara,
/// qué commits están seleccionados y los diffs ya cargados.
@MainActor
@Observable
final class CompareState {

    var branches: [BranchRef] = []
    var base: String?
    var commits: [CommitInfo] = []
    /// Vacío significa "toda la rama".
    var selectedCommits: Set<String> = []
    var files: [DiffFileSummary] = []
    var layout: DiffLayout = .split

    var isLoading = false
    var hasLoaded = false
    var error: String?

    /// Archivo al que hay que desplazar el panel derecho.
    var scrollTarget: String?

    private var diffCache: [String: [DiffLine]] = [:]

    // MARK: - Derivados

    var range: DiffRange? {
        guard let base else { return nil }
        guard !selectedCommits.isEmpty else { return .wholeBranch(base: base) }

        let selected = commits.filter { selectedCommits.contains($0.sha) }
        guard let newest = selected.first, let oldest = selected.last else {
            return .wholeBranch(base: base)
        }
        return .commitSpan(oldest: oldest.sha, newest: newest.sha)
    }

    /// Los commits elegidos no son consecutivos, así que el rango arrastra
    /// también los que quedan en medio. Conviene avisarlo.
    var selectionHasGaps: Bool {
        guard selectedCommits.count > 1 else { return false }
        let indices = commits.indices.filter { selectedCommits.contains(commits[$0].sha) }
        guard let first = indices.first, let last = indices.last else { return false }
        return (last - first + 1) != indices.count
    }

    var selectionLabel: String {
        if selectedCommits.isEmpty {
            return commits.isEmpty ? "Toda la rama" : "Toda la rama · \(commits.count) commits"
        }
        return selectedCommits.count == 1
            ? "1 commit seleccionado"
            : "\(selectedCommits.count) commits seleccionados"
    }

    var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }

    // MARK: - Carga

    func load(url: URL, currentBranch: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false; hasLoaded = true }

        branches = await GitCompare.branches(at: url)
        if base == nil || !branches.contains(where: { $0.name == base }) {
            base = GitCompare.suggestedBase(from: branches, current: currentBranch)
        }
        await reload(url: url)
    }

    /// Vuelve a pedir commits y archivos con la base y la selección actuales.
    func reload(url: URL) async {
        guard let base else {
            commits = []
            files = []
            error = "No hay ninguna otra rama contra la cual comparar."
            return
        }

        isLoading = true
        error = nil
        diffCache.removeAll()
        defer { isLoading = false }

        do {
            commits = try await GitCompare.commits(base: base, at: url)
            // Si la base cambió, la selección anterior ya no aplica.
            selectedCommits = selectedCommits.filter { sha in
                commits.contains { $0.sha == sha }
            }
            guard let range else { files = []; return }
            files = try await GitCompare.files(range: range, at: url)
        } catch {
            self.error = error.localizedDescription
            commits = []
            files = []
        }
    }

    /// Recalcula solo los archivos: se usa al cambiar la selección de commits.
    func reloadFiles(url: URL) async {
        guard let range else { files = []; return }
        isLoading = true
        error = nil
        diffCache.removeAll()
        defer { isLoading = false }

        do {
            files = try await GitCompare.files(range: range, at: url)
        } catch {
            self.error = error.localizedDescription
            files = []
        }
    }

    func changeBase(to newBase: String, url: URL) async {
        base = newBase
        selectedCommits.removeAll()
        await reload(url: url)
    }

    func toggle(_ commit: CommitInfo, url: URL) async {
        if selectedCommits.contains(commit.sha) {
            selectedCommits.remove(commit.sha)
        } else {
            selectedCommits.insert(commit.sha)
        }
        await reloadFiles(url: url)
    }

    func selectOnly(_ commit: CommitInfo, url: URL) async {
        selectedCommits = [commit.sha]
        await reloadFiles(url: url)
    }

    func selectWholeBranch(url: URL) async {
        guard !selectedCommits.isEmpty else { return }
        selectedCommits.removeAll()
        await reloadFiles(url: url)
    }

    // MARK: - Diff por archivo

    func cachedDiff(for file: DiffFileSummary) -> [DiffLine]? {
        diffCache[file.path]
    }

    func loadDiff(for file: DiffFileSummary, url: URL) async -> [DiffLine] {
        if let cached = diffCache[file.path] { return cached }
        guard let range else { return [] }
        do {
            let lines = try await GitCompare.fileDiff(range: range, file: file, at: url)
            diffCache[file.path] = lines
            return lines
        } catch {
            let message = DiffLine(
                id: 0, kind: .meta, oldNumber: nil, newNumber: nil,
                text: "No se pudo cargar el diff: \(error.localizedDescription)"
            )
            diffCache[file.path] = [message]
            return [message]
        }
    }
}
