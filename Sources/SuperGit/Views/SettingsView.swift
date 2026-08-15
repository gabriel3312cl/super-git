import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            Text("Ajustes")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Carpetas a escanear")
                    .font(.headline)
                List {
                    ForEach(model.config.roots, id: \.self) { root in
                        HStack {
                            Image(systemName: "folder")
                            Text(root)
                            Spacer()
                            Button {
                                Task { await model.removeRoot(root) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.config.roots.count <= 1)
                        }
                    }
                }
                .frame(height: 120)
                .border(Color.secondary.opacity(0.2))

                Button("Añadir carpeta…") { chooseFolder() }
            }

            HStack {
                Text("Profundidad de búsqueda")
                Stepper(
                    value: Binding(
                        get: { model.config.maxDepth },
                        set: { model.config.maxDepth = $0; model.saveConfig() }
                    ),
                    in: 1...6
                ) {
                    Text("\(model.config.maxDepth) niveles").monospacedDigit()
                }
            }

            HStack {
                Text("Refresco automático")
                Stepper(
                    value: Binding(
                        get: { model.config.autoRefreshSeconds },
                        set: { model.config.autoRefreshSeconds = $0; model.saveConfig() }
                    ),
                    in: 5...300,
                    step: 5
                ) {
                    Text("cada \(model.config.autoRefreshSeconds) s").monospacedDigit()
                }
            }

            if !model.config.hiddenRepos.isEmpty {
                HStack {
                    Text("\(model.config.hiddenRepos.count) repositorios ocultos")
                        .foregroundStyle(.secondary)
                    Button("Mostrar todos") { model.unhideAll() }
                }
                .font(.callout)
            }

            Text("Config: ~/.config/super-git/config.json")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Escanear ahora") {
                    Task { await model.rescan() }
                }
                Button("Listo") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Añadir"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addRoot(url) }
    }
}
