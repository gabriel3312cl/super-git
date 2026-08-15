import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectedRepoID) {
            Section("Repositorios") {
                ForEach(model.visibleRepos) { repo in
                    RepoRow(repo: repo)
                        .tag(repo.id as String?)
                        .contextMenu {
                            Button("Mostrar en Finder") { model.revealInFinder(repo) }
                            Button("Abrir en Terminal") { NSWorkspaceBridge.openTerminal(at: repo.url) }
                            Divider()
                            Button("Refrescar") { Task { await model.refresh(repo) } }
                            Button("Ocultar de la lista") { model.hide(repo) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Filtrar repositorios")
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.rescan() }
                } label: {
                    Label("Escanear de nuevo", systemImage: "arrow.clockwise")
                }
                .help("Volver a buscar repositorios (⇧⌘R)")
                .disabled(model.isScanning)
            }
            ToolbarItem {
                Button {
                    model.showSettings = true
                } label: {
                    Label("Ajustes", systemImage: "gearshape")
                }
                .help("Carpetas a escanear y refresco automático")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Escaneando…")
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("\(model.visibleRepos.count) repos · \(model.dirtyRepoCount) con cambios")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct RepoRow: View {
    let repo: Repo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .foregroundStyle(repo.status?.isClean == false ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .imageScale(.small)
                    Text(repo.status?.branchLabel ?? "…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if repo.isBusy {
                ProgressView().controlSize(.small)
            } else {
                badges
            }
        }
        .padding(.vertical, 2)
        .help(repo.displayPath)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if let status = repo.status {
                if status.behind > 0 {
                    counter(systemImage: "arrow.down", value: status.behind, color: .blue)
                }
                if status.ahead > 0 {
                    counter(systemImage: "arrow.up", value: status.ahead, color: .purple)
                }
                if status.totalChanges > 0 {
                    Text("\(status.totalChanges)")
                        .font(.caption2.monospacedDigit().bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            if repo.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.small)
            }
        }
    }

    private func counter(systemImage: String, value: Int, color: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: systemImage).imageScale(.small)
            Text("\(value)").font(.caption2.monospacedDigit())
        }
        .foregroundStyle(color)
    }
}
