import AppKit
import SwiftUI

struct DroneModeView: View {
    @EnvironmentObject private var appState: AppState

    private var finalizer: DroneFinalizer { appState.droneFinalizer }
    private var config: DroneFinalizeConfig { AppSettings.droneFinalizeConfig }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                folderSection

                if let error = finalizer.previewError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if finalizer.hasProject && finalizer.previewError == nil {
                    DroneStepIndicator(current: finalizer.step)
                    stepCard
                    if !finalizer.failures.isEmpty {
                        DroneNotesBox(failures: finalizer.failures)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(AppBranding.droneModeTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    finalizer.reset()
                    appState.goHome()
                } label: {
                    Label("Home", systemImage: "house")
                }
                .help("Back to the home screen")
            }

            ToolbarItem(placement: .navigation) {
                Button {
                    finalizer.goBack()
                } label: {
                    Label("Go Back", systemImage: "arrow.uturn.backward")
                }
                .help("Undo the last step and restore the changed files")
                .disabled(!finalizer.canUndo || finalizer.isRunning)
            }
        }
        .onDisappear {
            if !finalizer.isRunning {
                finalizer.reset()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppBranding.droneModeTitle)
                .font(.largeTitle.bold())
            Text("Finalize a graded project in three steps. Each step is reversible with Go Back.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderSection: some View {
        GroupBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project folder")
                        .font(.headline)
                    if let path = finalizer.projectDirectoryPath {
                        Text(path)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Pick the folder that contains your “\(config.rawDirectoryName)” and “\(config.exportDirectoryName)” subfolders.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(finalizer.hasProject ? "Change…" : "Choose Project Folder…") {
                    chooseFolder()
                }
                .disabled(finalizer.isRunning)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var stepCard: some View {
        switch finalizer.step {
        case .merge:
            DroneMergeStepView(
                pairs: finalizer.pairMetadata,
                isRunning: finalizer.isRunning,
                statusMessage: finalizer.statusMessage,
                action: { finalizer.performCurrentStep() }
            )
        case .cleanup:
            DroneCleanupStepView(
                plan: finalizer.plan,
                config: config,
                isRunning: finalizer.isRunning,
                statusMessage: finalizer.statusMessage,
                action: { finalizer.performCurrentStep() }
            )
        case .flatten:
            DroneFlattenStepView(
                plan: finalizer.plan,
                config: config,
                isRunning: finalizer.isRunning,
                statusMessage: finalizer.statusMessage,
                action: { finalizer.performCurrentStep() }
            )
        case .done:
            DroneDoneStepView(
                projectPath: finalizer.projectDirectoryPath,
                onChooseAnother: { chooseFolder() }
            )
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the drone project folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        finalizer.loadProject(projectDirectory: url, config: config)
    }
}

// MARK: - Step indicator

private struct DroneStepIndicator: View {
    let current: DroneFinalizeStep

    private let steps: [DroneFinalizeStep] = [.merge, .cleanup, .flatten]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                let state = state(for: step)
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(state == .upcoming ? Color.secondary.opacity(0.2) : Color.accentColor)
                            .frame(width: 26, height: 26)
                        if state == .done {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step.stepNumber)")
                                .font(.caption.bold())
                                .foregroundStyle(state == .upcoming ? Color.secondary : .white)
                        }
                    }
                    Text(step.shortTitle)
                        .font(.subheadline)
                        .fontWeight(state == .current ? .semibold : .regular)
                        .foregroundStyle(state == .upcoming ? Color.secondary : .primary)
                }
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: 40)
                }
            }
        }
    }

    private enum State { case done, current, upcoming }

    private func state(for step: DroneFinalizeStep) -> State {
        if current == .done { return .done }
        if step.rawValue < current.rawValue { return .done }
        if step == current { return .current }
        return .upcoming
    }
}

// MARK: - Step container

private struct DroneStepContainer<Content: View>: View {
    let step: DroneFinalizeStep
    let description: String
    let isRunning: Bool
    let statusMessage: String?
    let actionTitle: String
    let actionRole: ButtonRole?
    let actionDisabled: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label(step.title, systemImage: step.systemImage)
                    .font(.title3.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                content()

                HStack {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusMessage ?? "Working…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(actionTitle, role: actionRole, action: action)
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || actionDisabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
}

// MARK: - Merge step

private struct DroneMergeStepView: View {
    let pairs: [DronePairMetadata]
    let isRunning: Bool
    let statusMessage: String?
    let action: () -> Void

    private var description: String {
        "Copy each original's creation/modification dates and (for video) its container metadata "
            + "onto the matching compressed file. Nothing is deleted in this step."
    }

    var body: some View {
        DroneStepContainer(
            step: .merge,
            description: description,
            isRunning: isRunning,
            statusMessage: statusMessage,
            actionTitle: pairs.isEmpty ? "Continue" : "Merge",
            actionRole: nil,
            actionDisabled: false,
            action: action
        ) {
            if pairs.isEmpty {
                Text("No compressed/original pairs found to merge. You can continue to the next step.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(pairs) { pair in
                        DronePairMetadataCard(pair: pair)
                    }
                }
            }
        }
    }
}

private struct DronePairMetadataCard: View {
    let pair: DronePairMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: pair.isVideo ? "film" : "photo")
                    .foregroundStyle(.tint)
                Text(pair.finalName)
                    .font(.headline)
            }

            HStack(alignment: .top, spacing: 16) {
                MetadataColumn(title: "Original", subtitle: pair.sourceName, snapshot: pair.original)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)
                MetadataColumn(
                    title: "Compressed",
                    subtitle: pair.compressedName,
                    snapshot: pair.compressed,
                    after: pair.original
                )
            }

            Text("After merge, the highlighted values are copied from the original onto the compressed file.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
        )
    }
}

private struct MetadataColumn: View {
    let title: String
    let subtitle: String
    let snapshot: MediaMetadataSnapshot?
    /// When set (the Compressed column), date fields show how they change after merge.
    var after: MediaMetadataSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let snapshot {
                metadataRow("Size", DroneFormat.size(snapshot.fileSizeBytes))
                metadataRow(
                    "Created",
                    DroneFormat.date(snapshot.creationDate),
                    newValue: after.map { DroneFormat.date($0.creationDate) }
                )
                metadataRow(
                    "Modified",
                    DroneFormat.date(snapshot.modificationDate),
                    newValue: after.map { DroneFormat.date($0.modificationDate) }
                )
                if let dimensions = snapshot.dimensions {
                    metadataRow("Size px", dimensions)
                }
                if let duration = snapshot.duration {
                    metadataRow("Duration", duration)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataRow(_ label: String, _ value: String, newValue: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            valueText(current: value, newValue: newValue)
                .font(.caption.monospaced())
                .lineLimit(2)
        }
    }

    private func valueText(current: String, newValue: String?) -> Text {
        guard let newValue, newValue != current else {
            return Text(current)
        }
        return Text(current).strikethrough().foregroundColor(.secondary)
            + Text("  →  ").foregroundColor(.secondary)
            + Text(newValue).foregroundColor(.green)
    }
}

// MARK: - Cleanup step

private struct DroneCleanupStepView: View {
    let plan: DroneFinalizePlan?
    let config: DroneFinalizeConfig
    let isRunning: Bool
    let statusMessage: String?
    let action: () -> Void

    private var description: String {
        "Move each original to the Trash and remove the “\(config.normalizedSuffix)” suffix "
            + "from the compressed file names."
    }

    var body: some View {
        DroneStepContainer(
            step: .cleanup,
            description: description,
            isRunning: isRunning,
            statusMessage: statusMessage,
            actionTitle: DroneFinalizeStep.cleanup.actionTitle,
            actionRole: .destructive,
            actionDisabled: false,
            action: action
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DroneFileList(
                    title: "Delete original → rename compressed",
                    icon: "trash",
                    tint: .red,
                    items: (plan?.matchedPairs ?? []).map {
                        "\($0.sourceName)  →  Trash,  \($0.compressedName)  →  \($0.finalName)"
                    }
                )
                DroneFileList(
                    title: "Rename (no original)",
                    icon: "pencil",
                    tint: .orange,
                    items: (plan?.unmatchedCompressed ?? []).map { "\($0.originalName)  →  \($0.finalName)" }
                )
            }
        }
    }
}

// MARK: - Flatten step

private struct DroneFlattenStepView: View {
    let plan: DroneFinalizePlan?
    let config: DroneFinalizeConfig
    let isRunning: Bool
    let statusMessage: String?
    let action: () -> Void

    private var description: String {
        "Move the finished media into the project folder, then move the “\(config.rawDirectoryName)” and "
            + "“\(config.exportDirectoryName)” folders to the Trash, leaving a flat project folder."
    }

    var body: some View {
        DroneStepContainer(
            step: .flatten,
            description: description,
            isRunning: isRunning,
            statusMessage: statusMessage,
            actionTitle: DroneFinalizeStep.flatten.actionTitle,
            actionRole: .destructive,
            actionDisabled: false,
            action: action
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DroneFileList(
                    title: "Move up into project folder",
                    icon: "arrow.up.doc",
                    tint: .blue,
                    items: (plan?.finalMediaNames ?? []).sorted()
                )
                DroneFileList(
                    title: "Move to Trash",
                    icon: "trash",
                    tint: .red,
                    items: ["\(config.rawDirectoryName)/", "\(config.exportDirectoryName)/"]
                )
            }
        }
    }
}

// MARK: - Done step

private struct DroneDoneStepView: View {
    let projectPath: String?
    let onChooseAnother: () -> Void

    private var description: String {
        "The project folder now holds the finished media with no subfolders. "
            + "Use Go Back to undo the last step, or choose another project."
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Finished", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let projectPath {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: projectPath)])
                        }
                    }
                    Spacer()
                    Button("Choose Another Folder", action: onChooseAnother)
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
}

// MARK: - Shared pieces

private struct DroneFileList: View {
    let title: String
    let icon: String
    let tint: Color
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(title) (\(items.count))", systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                ForEach(items.prefix(60), id: \.self) { item in
                    Text(item)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if items.count > 60 {
                    Text("And \(items.count - 60) more…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DroneNotesBox: View {
    let failures: [OrganizeFailure]

    var body: some View {
        GroupBox("Notes") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(failures.prefix(50)) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        if !failure.filename.isEmpty {
                            Text(failure.filename)
                                .font(.callout)
                                .bold()
                        }
                        Text(failure.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

enum DroneFormat {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
