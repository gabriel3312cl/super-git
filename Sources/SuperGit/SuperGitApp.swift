import AppKit
import SwiftUI

/// Pequeño puente a AppKit para acciones que SwiftUI no expone.
enum NSWorkspaceBridge {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openTerminal(at url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Necesario cuando el binario corre fuera de un bundle .app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SuperGitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Super Git") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refrescar todo") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Buscar repositorios de nuevo") {
                    Task { await model.rescan() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
