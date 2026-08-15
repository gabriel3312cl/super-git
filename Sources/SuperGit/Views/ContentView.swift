import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 440)
        } detail: {
            if let repo = model.selectedRepo {
                RepoDetailView(repo: repo)
                    .id(repo.id)
            } else if model.foundNothing {
                ContentUnavailableView {
                    Label("No se encontró ningún repositorio", systemImage: "folder.badge.questionmark")
                } description: {
                    Text(
                        """
                        Se buscó en \(model.config.roots.joined(separator: ", ")).

                        Si acabas de instalar la app, puede que macOS todavía no le \
                        haya dado acceso a esa carpeta: revísalo en Ajustes del Sistema › \
                        Privacidad y seguridad › Archivos y carpetas.
                        """
                    )
                } actions: {
                    Button("Elegir otra carpeta…") { model.showSettings = true }
                    Button("Buscar de nuevo") { Task { await model.rescan() } }
                }
            } else {
                ContentUnavailableView(
                    "Ningún repositorio seleccionado",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Elige un repositorio de la lista o vuelve a escanear.")
                )
            }
        }
        .task {
            await model.bootstrap()
        }
        .task {
            // Refresco periódico en segundo plano.
            while !Task.isCancelled {
                let seconds = max(5, model.config.autoRefreshSeconds)
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                await model.refreshAll()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await model.refreshAll() }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
    }
}

/// Colores y símbolos compartidos por las vistas.
enum ChangeStyle {
    static func color(for code: Character) -> Color {
        switch code {
        case "M", "T": return .orange
        case "A": return .green
        case "?": return .green
        case "D": return .red
        case "R", "C": return .blue
        case "U": return .pink
        default: return .secondary
        }
    }

    static func icon(for change: FileChange) -> String {
        switch (change.path as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "json": return "curlybraces"
        case "md": return "doc.text"
        case "env": return "gearshape"
        case "png", "jpg", "jpeg", "svg", "gif": return "photo"
        case "sh", "zsh", "bash": return "terminal"
        case "yml", "yaml", "toml", "ini", "cfg": return "slider.horizontal.3"
        default: return "doc"
        }
    }
}
