import SwiftUI

/// Vista de revisión de rama: qué trae esta rama respecto de otra, commit por
/// commit o en total, con el diff de cada archivo.
struct CompareView: View {
    let repo: Repo

    private var state: CompareState { repo.compare }

    private var rangeKey: String {
        switch state.range {
        case .wholeBranch(let base):        return "b:\(base)"
        case .commitSpan(let old, let new): return "c:\(old)..\(new)"
        case .workingTree(let base):        return "w:\(base)"
        case nil:                           return "none"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if let error = state.error {
                banner(error)
            }

            HSplitView {
                sidebar
                    .frame(minWidth: 240, idealWidth: 310, maxWidth: 460)
                diffPane
                    .frame(minWidth: 420)
            }
        }
        .task {
            guard !state.hasLoaded else { return }
            await state.load(
                url: repo.url,
                currentBranch: repo.status?.branch,
                localChanges: repo.status?.totalChanges ?? 0
            )
        }
    }

    // MARK: - Controles

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                baseMenu

                Image(systemName: "arrow.left")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("comparado con")

                Label(repo.status?.branchLabel ?? "HEAD", systemImage: "arrow.triangle.branch")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 12)

                if state.isLoading {
                    ProgressView().controlSize(.small)
                }

                summary

                Picker("Vista", selection: Binding(
                    get: { state.layout },
                    set: { state.layout = $0 }
                )) {
                    ForEach(DiffLayout.allCases) { layout in
                        Label(layout.rawValue, systemImage: layout.symbol)
                            .labelStyle(.iconOnly)
                            .tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Cambiar entre diff unificado y lado a lado")

                Button {
                    Task { await state.reload(url: repo.url) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Volver a calcular la comparación")
                .disabled(state.isLoading)
            }

            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { state.includeWorkingTree },
                    set: { value in
                        Task { await state.setIncludeWorkingTree(value, url: repo.url) }
                    }
                )) {
                    Text("Incluir cambios sin commitear")
                }
                .toggleStyle(.checkbox)
                .disabled(!state.selectedCommits.isEmpty)
                .help(
                    state.selectedCommits.isEmpty
                    ? "Compara la base contra el árbol de trabajo, no contra el último commit"
                    : "Solo disponible al comparar toda la rama"
                )

                if state.includeWorkingTree {
                    Text("mostrando también lo que aún no está commiteado")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if state.selectionHasGaps {
                Label(
                    "Los commits elegidos no son consecutivos, así que el diff incluye "
                    + "también los que quedan entre el más viejo y el más nuevo.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var baseMenu: some View {
        Menu {
            if state.branches.contains(where: { !$0.isRemote }) {
                Section("Locales") {
                    ForEach(state.branches.filter { !$0.isRemote }) { branch in
                        button(for: branch)
                    }
                }
            }
            if state.branches.contains(where: { $0.isRemote }) {
                Section("Remotas") {
                    ForEach(state.branches.filter(\.isRemote)) { branch in
                        button(for: branch)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "target")
                Text(state.base ?? "Elegir base")
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Rama contra la cual comparar")
        .accessibilityLabel("Comparar contra la rama \(state.base ?? "sin elegir")")
    }

    private func button(for branch: BranchRef) -> some View {
        Button {
            Task { await state.changeBase(to: branch.name, url: repo.url) }
        } label: {
            if branch.name == state.base {
                Label(branch.name, systemImage: "checkmark")
            } else {
                Text(branch.name)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Text("\(state.files.count) archivo\(state.files.count == 1 ? "" : "s")")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            DiffCounts(additions: state.totalAdditions, deletions: state.totalDeletions)
        }
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
    }

    // MARK: - Panel izquierdo

    private var sidebar: some View {
        List {
            Section {
                wholeBranchRow
                ForEach(state.commits) { commit in
                    CommitRow(
                        commit: commit,
                        isSelected: state.selectedCommits.contains(commit.sha),
                        onToggle: { Task { await state.toggle(commit, url: repo.url) } },
                        onOnly: { Task { await state.selectOnly(commit, url: repo.url) } }
                    )
                }
                if state.commits.isEmpty && !state.isLoading {
                    Text("Esta rama no tiene commits propios respecto de la base.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Commits (\(state.commits.count))")
            }

            Section {
                ForEach(state.files) { file in
                    FileRow(file: file) {
                        state.scrollTarget = file.path
                    }
                }
                if state.files.isEmpty && !state.isLoading {
                    Text("Sin archivos modificados.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Archivos (\(state.files.count))")
            }
        }
        .listStyle(.inset)
    }

    private var wholeBranchRow: some View {
        Button {
            Task { await state.selectWholeBranch(url: repo.url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: state.selectedCommits.isEmpty
                      ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(state.selectedCommits.isEmpty ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Toda la rama").fontWeight(.medium)
                    Text(
                        state.includeWorkingTree
                        ? "Todo lo que \(repo.status?.branchLabel ?? "HEAD") trae sobre \(state.base ?? "la base"), commiteado o no"
                        : "Todo lo que \(repo.status?.branchLabel ?? "HEAD") trae sobre \(state.base ?? "la base")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state.selectedCommits.isEmpty ? [.isSelected] : [])
    }

    // MARK: - Panel derecho

    private var diffPane: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if state.files.isEmpty && !state.isLoading {
                            emptyState
                                .padding(.top, 60)
                        }
                        ForEach(state.files) { file in
                            DiffFileView(
                                file: file,
                                repoURL: repo.url,
                                state: state,
                                layout: state.layout,
                                availableWidth: max(geometry.size.width - 30, 320)
                            )
                            .id(file.path)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: state.scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    state.scrollTarget = nil
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if state.base == nil {
            ContentUnavailableView(
                "No hay otra rama para comparar",
                systemImage: "arrow.triangle.pull",
                description: Text("Este repositorio solo tiene una rama.")
            )
        } else if !state.includeWorkingTree && (repo.status?.totalChanges ?? 0) > 0 {
            ContentUnavailableView {
                Label("Nada commiteado todavía", systemImage: "tray")
            } description: {
                Text(
                    "\(repo.status?.branchLabel ?? "HEAD") no tiene commits propios sobre "
                    + "\(state.base ?? ""), pero hay \(repo.status?.totalChanges ?? 0) "
                    + "cambios sin commitear."
                )
            } actions: {
                Button("Incluir cambios sin commitear") {
                    Task { await state.setIncludeWorkingTree(true, url: repo.url) }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "Sin diferencias",
                systemImage: "equal.circle",
                description: Text(
                    "\(repo.status?.branchLabel ?? "HEAD") no aporta cambios sobre \(state.base ?? "")."
                )
            )
        }
    }
}

// MARK: - Filas

private struct CommitRow: View {
    let commit: CommitInfo
    let isSelected: Bool
    let onToggle: () -> Void
    let onOnly: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.subject)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(commit.shortSha)
                            .font(.caption.monospaced())
                        Text(commit.author)
                            .font(.caption)
                        Text(commit.date)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Ver solo este commit", action: onOnly)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(commit.subject), \(commit.shortSha), \(commit.author), \(commit.date)")
        .accessibilityHint(isSelected ? "Quitar de la comparación" : "Añadir a la comparación")
    }
}

private struct FileRow: View {
    let file: DiffFileSummary
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !file.directory.isEmpty {
                        Text(file.directory)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 4)
                if file.isUntracked {
                    Text("nuevo")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.18), in: Capsule())
                }
                DiffCounts(additions: file.additions, deletions: file.deletions)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.path)
        .accessibilityLabel(
            "\(file.path), \(file.statusDescription), \(file.additions) agregadas, \(file.deletions) eliminadas"
        )
        .accessibilityHint("Ir al diff de este archivo")
    }
}
