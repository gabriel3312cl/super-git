import Foundation

/// Descubre repositorios git recorriendo carpetas raíz hasta cierta profundidad.
enum RepoScanner {

    /// Carpetas que nunca vale la pena recorrer: son grandes y jamás contienen
    /// repos propios.
    static let skippedNames: Set<String> = [
        "node_modules", ".build", "build", "DerivedData", "Pods", "vendor",
        ".venv", "venv", "env", "__pycache__", "dist", ".next", "target",
        ".gradle", ".cache", "Library", "site-packages", ".tox", "coverage",
        "tmp", ".terraform"
    ]

    static func scan(roots: [URL], maxDepth: Int) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var found: [URL] = []
                var seen = Set<String>()
                for root in roots {
                    walk(root, depth: 0, maxDepth: maxDepth, found: &found, seen: &seen)
                }
                found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                continuation.resume(returning: found)
            }
        }
    }

    private static func walk(
        _ directory: URL,
        depth: Int,
        maxDepth: Int,
        found: inout [URL],
        seen: inout Set<String>
    ) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }

        // `.git` puede ser carpeta (repo normal) o archivo (worktree/submódulo).
        if fm.fileExists(atPath: directory.appendingPathComponent(".git").path) {
            let path = directory.standardizedFileURL.path
            if seen.insert(path).inserted {
                found.append(directory.standardizedFileURL)
            }
            return // no bajamos dentro de un repo
        }

        guard depth < maxDepth else { return }

        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if skippedNames.contains(entry.lastPathComponent) { continue }
            walk(entry, depth: depth + 1, maxDepth: maxDepth, found: &found, seen: &seen)
        }
    }
}
