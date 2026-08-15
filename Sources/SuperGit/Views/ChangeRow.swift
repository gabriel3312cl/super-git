import SwiftUI

/// Fila de archivo con acciones que aparecen al pasar el mouse,
/// igual que el panel de control de código fuente de VS Code.
struct ChangeRow: View {
    let change: FileChange
    let primaryIcon: String
    let primaryHelp: String
    let onPrimary: () -> Void
    var onDiscard: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ChangeStyle.icon(for: change))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(change.fileName)
                .lineLimit(1)
                .truncationMode(.middle)

            if !change.directory.isEmpty {
                Text(change.directory)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            if isHovering {
                if let onDiscard {
                    iconButton("arrow.uturn.backward", help: "Descartar cambios", action: onDiscard)
                }
                iconButton(primaryIcon, help: primaryHelp, action: onPrimary)
            }

            Text(change.statusLabel)
                .font(.caption.bold().monospaced())
                .foregroundStyle(ChangeStyle.color(for: change.code))
                .frame(width: 14)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help("\(change.statusDescription) · \(change.path)")
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).imageScale(.small)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Cabecera de sección con contador y acción masiva.
struct SectionHeader<Trailing: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.18), in: Capsule())
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}
