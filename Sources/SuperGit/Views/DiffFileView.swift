import AppKit
import SwiftUI

/// Colores y medidas compartidas por el visor de diff.
///
/// El ancho se calcula en caracteres: con fuente monoespaciada se sabe de
/// antemano cuánto mide la línea más larga, así que las filas pueden tener
/// todas el mismo ancho y quedar perfectamente alineadas en la vista lado a
/// lado, con scroll horizontal en vez de recortar o partir palabras.
enum DiffStyle {
    static let nsFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    static let font = Font(nsFont)
    static let charWidth: CGFloat = ("0" as NSString).size(withAttributes: [.font: nsFont]).width
    static let gutterWidth: CGFloat = 38
    static let markerWidth: CGFloat = 12
    static let sidePadding: CGFloat = 18

    static let rowHeight: CGFloat = nsFont.boundingRectForFont.height + 2

    /// Ancho de una columna capaz de mostrar `characters` caracteres.
    static func columnWidth(characters: Int) -> CGFloat {
        gutterWidth + 6 + markerWidth + CGFloat(max(characters, 20)) * charWidth + sidePadding
    }

    /// La vista unificada lleva dos numeradores en vez de uno.
    static func unifiedWidth(characters: Int) -> CGFloat {
        columnWidth(characters: characters) + gutterWidth + 6
    }

    static func splitWidth(characters: Int) -> CGFloat {
        columnWidth(characters: characters) * 2 + 1
    }

    static func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition:   return Color.green.opacity(0.18)
        case .deletion:   return Color.red.opacity(0.16)
        case .hunkHeader: return Color.accentColor.opacity(0.10)
        case .meta:       return Color.secondary.opacity(0.08)
        case .context:    return .clear
        }
    }

    static func marker(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        default:        return .secondary
        }
    }

    /// Hueco en la vista lado a lado: ahí no existe línea equivalente.
    static let emptySide = Color.primary.opacity(0.04)
}

private struct Gutter: View {
    let value: Int?

    var body: some View {
        Text(value.map(String.init) ?? "")
            .font(DiffStyle.font)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(width: DiffStyle.gutterWidth, alignment: .trailing)
            .padding(.trailing, 6)
            .accessibilityHidden(true)
    }
}

private struct LineText: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.marker)
                .font(DiffStyle.font.bold())
                .foregroundStyle(DiffStyle.marker(for: line.kind))
                .frame(width: DiffStyle.markerWidth, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(DiffStyle.font)
                .textSelection(.enabled)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
    }
}

/// Fila de la vista unificada.
private struct UnifiedRow: View {
    let line: DiffLine
    let width: CGFloat

    var body: some View {
        Group {
            if line.kind == .hunkHeader || line.kind == .meta {
                Text(line.text)
                    .font(DiffStyle.font)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .frame(width: width, alignment: .leading)
            } else {
                HStack(spacing: 0) {
                    Gutter(value: line.oldNumber)
                    Gutter(value: line.newNumber)
                    LineText(line: line)
                }
                .padding(.vertical, 1)
                .frame(width: width, alignment: .leading)
            }
        }
        .background(DiffStyle.background(for: line.kind))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityDescription)
    }
}

/// Fila de la vista lado a lado.
private struct SplitRow: View {
    let row: DiffRow
    let columnWidth: CGFloat

    var body: some View {
        if let header = row.header {
            Text(header.text)
                .font(DiffStyle.font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(width: columnWidth * 2 + 1, alignment: .leading)
                .background(DiffStyle.background(for: header.kind))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(header.accessibilityDescription)
        } else {
            HStack(spacing: 0) {
                side(row.left, number: \.oldNumber)
                Divider()
                side(row.right, number: \.newNumber)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pairDescription)
        }
    }

    @ViewBuilder
    private func side(_ line: DiffLine?, number: KeyPath<DiffLine, Int?>) -> some View {
        if let line {
            HStack(spacing: 0) {
                Gutter(value: line[keyPath: number])
                LineText(line: line)
            }
            .padding(.vertical, 1)
            .frame(width: columnWidth, alignment: .leading)
            .background(DiffStyle.background(for: line.kind))
        } else {
            Color.clear
                .frame(width: columnWidth, height: DiffStyle.rowHeight)
                .background(DiffStyle.emptySide)
        }
    }

    private var pairDescription: String {
        switch (row.left, row.right) {
        case let (left?, right?) where left.id == right.id:
            return left.accessibilityDescription
        case let (left?, right?):
            return "\(left.accessibilityDescription). Reemplazada por: \(right.accessibilityDescription)"
        case let (left?, nil):
            return left.accessibilityDescription
        case let (nil, right?):
            return right.accessibilityDescription
        case (nil, nil):
            return "Línea vacía"
        }
    }
}

/// Tarjeta con el diff completo de un archivo.
struct DiffFileView: View {
    let file: DiffFileSummary
    let repoURL: URL
    let state: CompareState
    let layout: DiffLayout
    /// Ancho disponible en el panel: si el diff es más angosto, las filas se
    /// estiran igual para que el color de fondo llegue hasta el borde.
    let availableWidth: CGFloat

    @State private var lines: [DiffLine] = []
    @State private var isLoading = true
    @State private var isExpanded = true
    @State private var showsEverything = false

    /// Los archivos muy grandes se recortan: dibujar decenas de miles de filas
    /// congela la ventana sin aportar nada.
    private let lineLimit = 500

    private var visibleLines: [DiffLine] {
        (showsEverything || lines.count <= lineLimit) ? lines : Array(lines.prefix(lineLimit))
    }

    private var longestLine: Int {
        visibleLines.map(\.text.count).max() ?? 0
    }

    private var columnWidth: CGFloat {
        max(DiffStyle.columnWidth(characters: longestLine), (availableWidth - 1) / 2)
    }

    private var contentWidth: CGFloat {
        max(DiffStyle.unifiedWidth(characters: longestLine), availableWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider()
                content
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .task {
            lines = await state.loadDiff(for: file, url: repoURL)
            // Un diff enorme arranca plegado: se abre si se quiere leer.
            isExpanded = lines.count <= 1500
            isLoading = false
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    if !file.directory.isEmpty {
                        Text(file.directory + "/")
                            .foregroundStyle(.secondary)
                    }
                    Text(file.fileName).bold()
                }
                .lineLimit(1)
                .truncationMode(.head)

                if let oldPath = file.oldPath {
                    Text("← \(oldPath)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(file.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DiffCounts(additions: file.additions, deletions: file.deletions)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(file.path), \(file.statusDescription), \(file.additions) líneas agregadas, \(file.deletions) eliminadas"
        )
        .accessibilityHint(isExpanded ? "Contraer el diff" : "Expandir el diff")
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Cargando diff…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } else if file.isBinary {
            note("Archivo binario: el contenido no se puede mostrar.")
        } else if lines.isEmpty {
            note("Sin cambios de texto en este archivo.")
        } else {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    switch layout {
                    case .unified:
                        ForEach(visibleLines) {
                            UnifiedRow(line: $0, width: contentWidth)
                        }
                    case .split:
                        ForEach(DiffParser.splitRows(from: visibleLines)) {
                            SplitRow(row: $0, columnWidth: columnWidth)
                        }
                    }
                }
            }

            if lines.count > lineLimit && !showsEverything {
                Divider()
                Button {
                    showsEverything = true
                } label: {
                    Label(
                        "Mostrar las \(lines.count - lineLimit) líneas restantes",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }
}

/// Contador +N −M, con el signo escrito para no depender solo del color.
struct DiffCounts: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("+\(additions)")
                .foregroundStyle(.green)
            Text("−\(deletions)")
                .foregroundStyle(.red)
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(additions) agregadas, \(deletions) eliminadas")
    }
}
