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

    /// Todas las filas miden lo mismo: es lo que mantiene alineadas las dos
    /// columnas de la vista lado a lado, que se dibujan por separado.
    static let rowHeight: CGFloat = ceil(nsFont.boundingRectForFont.height) + 4
    static let handleWidth: CGFloat = 11

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

/// Una de las dos columnas de la vista lado a lado. Cada una tiene su propio
/// scroll horizontal, así que se puede leer una línea larga de un lado sin
/// mover el otro.
private struct SplitColumn: View {
    enum Side { case old, new }

    let rows: [DiffRow]
    let side: Side
    let width: CGFloat
    let contentWidth: CGFloat

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    halfRow(row)
                }
            }
            .frame(width: contentWidth, alignment: .leading)
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func halfRow(_ row: DiffRow) -> some View {
        if let header = row.header {
            // El encabezado del bloque se escribe en la columna izquierda; la
            // derecha lleva solo la banda de color para no repetir el texto.
            Text(side == .old ? header.text : "")
                .font(DiffStyle.font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(width: contentWidth, height: DiffStyle.rowHeight, alignment: .leading)
                .background(DiffStyle.background(for: header.kind))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(side == .old ? header.accessibilityDescription : "")
                .accessibilityHidden(side == .new)
        } else if let line = (side == .old ? row.left : row.right) {
            HStack(spacing: 0) {
                Gutter(value: side == .old ? line.oldNumber : line.newNumber)
                LineText(line: line)
            }
            .frame(width: contentWidth, height: DiffStyle.rowHeight, alignment: .leading)
            .background(DiffStyle.background(for: line.kind))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.accessibilityDescription)
        } else {
            Color.clear
                .frame(width: contentWidth, height: DiffStyle.rowHeight)
                .background(DiffStyle.emptySide)
                .accessibilityHidden(true)
        }
    }
}

/// Separador arrastrable entre las dos columnas.
private struct SplitHandle: View {
    @Binding var ratio: Double
    let totalWidth: CGFloat

    @State private var ratioAtDragStart: Double?

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1)
            .frame(width: DiffStyle.handleWidth)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                // En coordenadas globales: el separador se mueve mientras se
                // arrastra, y midiendo en su espacio local el desplazamiento se
                // restaría a sí mismo, avanzando la mitad de lo que pide el mouse.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = ratioAtDragStart ?? ratio
                        if ratioAtDragStart == nil { ratioAtDragStart = start }
                        guard totalWidth > 0 else { return }
                        ratio = clamp(start + value.translation.width / totalWidth)
                    }
                    .onEnded { _ in ratioAtDragStart = nil }
            )
            // Simultáneo, no encadenado: si no, el gesto de arrastre se queda
            // con el doble clic y el reset nunca llega a dispararse.
            .simultaneousGesture(TapGesture(count: 2).onEnded { ratio = 0.5 })
            .contextMenu {
                Button("Igualar columnas") { ratio = 0.5 }
                Button("Ampliar la versión anterior") { ratio = 0.7 }
                Button("Ampliar la versión nueva") { ratio = 0.3 }
            }
            .help("Arrastra para repartir el ancho · clic derecho para igualar las columnas")
            .accessibilityElement()
            .accessibilityLabel("Ancho de las columnas del diff")
            .accessibilityValue("\(Int((ratio * 100).rounded())) por ciento para la versión anterior")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: ratio = clamp(ratio + 0.05)
                case .decrement: ratio = clamp(ratio - 0.05)
                @unknown default: break
                }
            }
    }

    private func clamp(_ value: Double) -> Double {
        min(0.85, max(0.15, value))
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

    private var contentWidth: CGFloat {
        max(DiffStyle.unifiedWidth(characters: longestLine), availableWidth)
    }

    /// Ancho que se le da a cada columna, según dónde esté el separador.
    private var columnWidths: (left: CGFloat, right: CGFloat) {
        let usable = max(availableWidth - DiffStyle.handleWidth, 120)
        let left = (usable * state.splitRatio).rounded()
        return (left, usable - left)
    }

    private var splitContent: some View {
        let rows = DiffParser.splitRows(from: visibleLines)
        let widths = columnWidths
        let needed = DiffStyle.columnWidth(characters: longestLine)

        return HStack(spacing: 0) {
            SplitColumn(
                rows: rows, side: .old, width: widths.left,
                contentWidth: max(needed, widths.left)
            )
            SplitHandle(
                ratio: Binding(
                    get: { state.splitRatio },
                    set: { state.splitRatio = $0 }
                ),
                totalWidth: max(availableWidth - DiffStyle.handleWidth, 1)
            )
            SplitColumn(
                rows: rows, side: .new, width: widths.right,
                contentWidth: max(needed, widths.right)
            )
        }
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
            switch layout {
            case .unified:
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLines) {
                            UnifiedRow(line: $0, width: contentWidth)
                        }
                    }
                }
            case .split:
                splitContent
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
