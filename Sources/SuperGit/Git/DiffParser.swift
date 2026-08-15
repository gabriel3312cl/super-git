import Foundation

/// Convierte la salida de `git diff` de un archivo en líneas numeradas.
enum DiffParser {

    static func parse(_ text: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldNumber = 0
        var newNumber = 0
        var inHunk = false
        var index = 0

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            if line.hasPrefix("@@") {
                guard let hunk = parseHunkHeader(line) else { continue }
                oldNumber = hunk.oldStart
                newNumber = hunk.newStart
                inHunk = true
                lines.append(
                    DiffLine(id: index, kind: .hunkHeader, oldNumber: nil, newNumber: nil,
                             text: hunk.heading.isEmpty ? hunk.range : "\(hunk.range)  \(hunk.heading)")
                )
                index += 1
                continue
            }

            // Cabeceras de archivo (diff --git, index, ---, +++, rename…)
            guard inHunk else {
                if line.hasPrefix("Binary files") || line.hasPrefix("GIT binary patch") {
                    lines.append(DiffLine(id: index, kind: .meta, oldNumber: nil, newNumber: nil,
                                          text: "Archivo binario: el contenido no se puede mostrar."))
                    index += 1
                }
                continue
            }

            guard let marker = line.first else {
                // Línea vacía dentro de un hunk equivale a una línea de contexto vacía.
                lines.append(DiffLine(id: index, kind: .context, oldNumber: oldNumber,
                                      newNumber: newNumber, text: ""))
                index += 1
                oldNumber += 1
                newNumber += 1
                continue
            }

            // Los tabs se expanden: el ancho de fila se calcula en caracteres
            // monoespaciados y un tab rompería la alineación de las columnas.
            let content = String(line.dropFirst()).replacingOccurrences(of: "\t", with: "    ")
            switch marker {
            case "+":
                lines.append(DiffLine(id: index, kind: .addition, oldNumber: nil,
                                      newNumber: newNumber, text: content))
                newNumber += 1
            case "-":
                lines.append(DiffLine(id: index, kind: .deletion, oldNumber: oldNumber,
                                      newNumber: nil, text: content))
                oldNumber += 1
            case " ":
                lines.append(DiffLine(id: index, kind: .context, oldNumber: oldNumber,
                                      newNumber: newNumber, text: content))
                oldNumber += 1
                newNumber += 1
            case "\\":
                // "\ No newline at end of file"
                lines.append(DiffLine(id: index, kind: .meta, oldNumber: nil, newNumber: nil,
                                      text: "Sin salto de línea al final del archivo"))
            default:
                continue
            }
            index += 1
        }

        return lines
    }

    // MARK: - Cabecera de hunk

    private struct Hunk {
        let oldStart: Int
        let newStart: Int
        let range: String
        let heading: String
    }

    /// `@@ -18,7 +18,11 @@ TRUNCATE TABLE public.project CASCADE;`
    private static func parseHunkHeader(_ line: String) -> Hunk? {
        let parts = line.components(separatedBy: "@@")
        guard parts.count >= 3 else { return nil }

        let numbers = parts[1].trimmingCharacters(in: .whitespaces)
        let heading = parts.dropFirst(2).joined(separator: "@@")
            .trimmingCharacters(in: .whitespaces)

        var oldStart = 0
        var newStart = 0
        for token in numbers.split(separator: " ") {
            guard let sign = token.first else { continue }
            let value = token.dropFirst().split(separator: ",").first.flatMap { Int($0) } ?? 0
            if sign == "-" { oldStart = value }
            if sign == "+" { newStart = value }
        }

        return Hunk(oldStart: oldStart, newStart: newStart,
                    range: "@@ \(numbers) @@", heading: heading)
    }

    // MARK: - Vista lado a lado

    /// Empareja eliminaciones con adiciones dentro de cada bloque, para que
    /// una línea modificada quede enfrentada con su versión nueva.
    static func splitRows(from lines: [DiffLine]) -> [DiffRow] {
        var rows: [DiffRow] = []
        var deletions: [DiffLine] = []
        var additions: [DiffLine] = []
        var index = 0

        func flush() {
            for offset in 0..<max(deletions.count, additions.count) {
                rows.append(
                    DiffRow(
                        id: index,
                        left: offset < deletions.count ? deletions[offset] : nil,
                        right: offset < additions.count ? additions[offset] : nil,
                        header: nil
                    )
                )
                index += 1
            }
            deletions.removeAll(keepingCapacity: true)
            additions.removeAll(keepingCapacity: true)
        }

        for line in lines {
            switch line.kind {
            case .deletion:
                deletions.append(line)
            case .addition:
                additions.append(line)
            case .context:
                flush()
                rows.append(DiffRow(id: index, left: line, right: line, header: nil))
                index += 1
            case .hunkHeader, .meta:
                flush()
                rows.append(DiffRow(id: index, left: nil, right: nil, header: line))
                index += 1
            }
        }
        flush()

        return rows
    }
}
