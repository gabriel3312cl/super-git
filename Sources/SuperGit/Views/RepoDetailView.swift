import SwiftUI

struct RepoDetailView: View {
    let repo: Repo
    @Environment(AppModel.self) private var model

    @State private var discardTargets: [FileChange] = []
    @State private var showDiscardConfirm = false

    private var status: RepoStatus { repo.status ?? RepoStatus() }

    var body: some View {
        @Bindable var repo = repo

        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    commitBox

                    if let message = repo.errorMessage {
                        banner(message, systemImage: "exclamationmark.triangle.fill", color: .orange)
                    }
                    if let output = repo.lastOperationOutput {
                        banner(output, systemImage: "checkmark.circle.fill", color: .green)
                    }

                    if !status.conflicted.isEmpty {
                        SectionHeader(title: "Conflictos", count: status.conflicted.count) {
                            EmptyView()
                        }
                        ForEach(status.conflicted) { change in
                            ChangeRow(
                                change: change,
                                primaryIcon: "checkmark",
                                primaryHelp: "Marcar como resuelto (stage)",
                                onPrimary: { Task { await model.stage([change], in: repo) } }
                            )
                        }
                    }

                    if !status.staged.isEmpty {
                        SectionHeader(title: "Staged changes", count: status.staged.count) {
                            Button("Unstage todo") {
                                Task { await model.unstageAll(in: repo) }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        ForEach(status.staged) { change in
                            ChangeRow(
                                change: change,
                                primaryIcon: "minus",
                                primaryHelp: "Quitar del stage",
                                onPrimary: { Task { await model.unstage([change], in: repo) } }
                            )
                        }
                    }

                    if !status.unstaged.isEmpty {
                        SectionHeader(title: "Cambios", count: status.unstaged.count) {
                            Button("Stage todo") {
                                Task { await model.stageAll(in: repo) }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        ForEach(status.unstaged) { change in
                            ChangeRow(
                                change: change,
                                primaryIcon: "plus",
                                primaryHelp: "Agregar al stage",
                                onPrimary: { Task { await model.stage([change], in: repo) } },
                                onDiscard: {
                                    discardTargets = [change]
                                    showDiscardConfirm = true
                                }
                            )
                        }
                    }

                    if status.isClean && repo.status != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal")
                            Text("Sin cambios pendientes")
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .top) {
            if repo.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(repo.busyLabel ?? "Trabajando…")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
            }
        }
        .toolbar { toolbarContent }
        .confirmationDialog(
            "¿Descartar cambios?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive) {
                let targets = discardTargets
                Task { await model.discard(targets, in: repo) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(discardMessage)
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(repo.name)
                        .font(.title2.bold())
                    Text(repo.displayPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(repo.path)
                }
                HStack(spacing: 8) {
                    Label(status.branchLabel, systemImage: "arrow.triangle.branch")
                    if status.hasUpstream {
                        Text("→ \(status.upstream ?? "")")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("sin upstream")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let subject = repo.lastCommitSubject {
                    Text("Último commit: \(subject)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if status.behind > 0 {
                    pill("arrow.down", "\(status.behind)", .blue, "Commits por traer")
                }
                if status.ahead > 0 {
                    pill("arrow.up", "\(status.ahead)", .purple, "Commits por subir")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pill(_ icon: String, _ text: String, _ color: Color, _ help: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).imageScale(.small)
            Text(text).monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .help(help)
    }

    // MARK: - Caja de commit

    private var commitBox: some View {
        @Bindable var repo = repo

        return VStack(alignment: .leading, spacing: 8) {
            TextField(
                "Mensaje de commit (⌘↩ para confirmar)",
                text: $repo.commitMessage,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(2...8)
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Button {
                    Task { await model.commit(in: repo) }
                } label: {
                    Label("Commit", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit)

                Menu {
                    Button("Stage todo y commit") {
                        Task { await model.commit(in: repo, stageAllFirst: true) }
                    }
                    .disabled(status.totalChanges == 0 || trimmedMessage.isEmpty)

                    Button("Amend al último commit") {
                        Task { await model.commit(in: repo, amend: true) }
                    }
                    .disabled(!status.hasCommits || trimmedMessage.isEmpty)
                } label: {
                    Text("Más")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(repo.isBusy)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await model.fetch(in: repo) }
            } label: {
                Label("Fetch", systemImage: "arrow.down.circle")
            }
            .help("git fetch --all --prune")

            Menu {
                Button("Pull (fast-forward)") {
                    Task { await model.pull(in: repo, mode: .fastForward) }
                }
                Button("Pull con rebase") {
                    Task { await model.pull(in: repo, mode: .rebase) }
                }
                Button("Pull con merge") {
                    Task { await model.pull(in: repo, mode: .merge) }
                }
            } label: {
                Label("Pull", systemImage: "arrow.down.to.line")
            } primaryAction: {
                Task { await model.pull(in: repo, mode: .fastForward) }
            }
            .help("Traer cambios del remoto")

            Button {
                Task { await model.push(in: repo) }
            } label: {
                Label(
                    status.hasUpstream ? "Push" : "Publicar branch",
                    systemImage: status.hasUpstream ? "arrow.up.to.line" : "arrow.up.circle.badge.clock"
                )
            }
            .help(status.hasUpstream ? "git push" : "git push -u origin \(status.branch ?? "")")

            Button {
                Task { await model.refresh(repo) }
            } label: {
                Label("Refrescar", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    // MARK: - Helpers

    private var trimmedMessage: String {
        repo.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCommit: Bool {
        !repo.isBusy && !trimmedMessage.isEmpty && status.canCommit
    }

    private var discardMessage: String {
        if discardTargets.count == 1, let change = discardTargets.first {
            return change.isUntracked
                ? "Se eliminará el archivo «\(change.fileName)». Esta acción no se puede deshacer."
                : "Se perderán los cambios de «\(change.fileName)». Esta acción no se puede deshacer."
        }
        return "Se perderán los cambios de \(discardTargets.count) archivos. Esta acción no se puede deshacer."
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
