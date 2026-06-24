import AppKit
import SwiftUI

// MARK: - Finalize step indicator

struct DroneStepIndicator: View {
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
        .frame(maxWidth: .infinity, alignment: .center)
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

struct DroneStepContainer<Content: View>: View {
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
        GlassCard {
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
                        .pillActionButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                        .help("\(actionTitle) (↩)")
                        .disabled(isRunning || actionDisabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Merge step

struct DroneMergeStepView: View {
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
                    DroneMergeLegend()
                }
            }
        }
    }
}

private struct DroneMergeLegend: View {
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: 7, height: 7)
                Text("Values that will be updated")
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.green.opacity(0.9))
                Text("Copied from original")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary.opacity(0.85))
    }
}

private struct DronePairMetadataCard: View {
    let pair: DronePairMetadata

    private var sizeReductionLabel: String? {
        guard let originalBytes = pair.original?.fileSizeBytes,
              let compressedBytes = pair.compressed?.fileSizeBytes,
              originalBytes > 0,
              compressedBytes < originalBytes else { return nil }
        let percent = Int((Double(originalBytes - compressedBytes) / Double(originalBytes) * 100).rounded())
        guard percent > 0 else { return nil }
        return "-\(percent)% size"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: pair.isVideo ? "film" : "photo")
                    .foregroundStyle(.secondary.opacity(0.8))
                Text(pair.finalName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let sizeReductionLabel {
                    Text(sizeReductionLabel)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.green.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.14)))
                }
            }

            if let original = pair.original, let compressed = pair.compressed {
                DroneMetadataCompareTable(original: original, compressed: compressed)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct DroneMetadataCompareTable: View {
    let original: MediaMetadataSnapshot
    let compressed: MediaMetadataSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("Property")
                    .frame(width: 88, alignment: .leading)
                Text("Original")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: 28)
                Text("After merge")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.7))
            .textCase(.uppercase)

            Divider().opacity(0.35)

            VStack(spacing: 7) {
                compareRow(
                    "Size",
                    original: DroneFormat.size(original.fileSizeBytes),
                    after: DroneFormat.size(compressed.fileSizeBytes)
                )
                compareRow(
                    "Created",
                    original: DroneFormat.date(original.creationDate),
                    after: DroneFormat.date(compressed.creationDate),
                    copiedFromOriginal: DroneFormat.date(original.creationDate)
                )
                compareRow(
                    "Modified",
                    original: DroneFormat.date(original.modificationDate),
                    after: DroneFormat.date(compressed.modificationDate),
                    copiedFromOriginal: DroneFormat.date(original.modificationDate)
                )
                if original.dimensions != nil || compressed.dimensions != nil {
                    compareRow(
                        "Resolution",
                        original: original.dimensions ?? "—",
                        after: compressed.dimensions ?? "—"
                    )
                }
                if original.duration != nil || compressed.duration != nil {
                    compareRow(
                        "Duration",
                        original: original.duration ?? "—",
                        after: compressed.duration ?? "—"
                    )
                }
            }
        }
    }

    private func compareRow(
        _ property: String,
        original: String,
        after: String,
        copiedFromOriginal: String? = nil
    ) -> some View {
        let willUpdate = copiedFromOriginal.map { after != $0 } ?? false

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(property)
                .font(.callout)
                .foregroundStyle(.secondary.opacity(0.85))
                .frame(width: 88, alignment: .leading)

            Text(original)
                .font(.body.monospaced())
                .foregroundStyle(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Group {
                if willUpdate {
                    Image(systemName: "arrow.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.green.opacity(0.9))
                }
            }
            .frame(width: 28)

            afterMergeValue(current: after, newValue: willUpdate ? copiedFromOriginal : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func afterMergeValue(current: String, newValue: String?) -> some View {
        Group {
            if let newValue {
                (Text(current).strikethrough().foregroundColor(.secondary.opacity(0.65))
                    + Text("  ")
                    + Text(newValue).foregroundColor(.green.opacity(0.92)))
                    .font(.body.monospaced())
            } else {
                Text(current)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary.opacity(0.85))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
}

// MARK: - Cleanup step

struct DroneCleanupStepView: View {
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
            DroneCleanupChangesView(
                matchedPairs: plan?.matchedPairs ?? [],
                unmatched: plan?.unmatchedCompressed ?? []
            )
        }
    }
}

private struct DroneCleanupChangesView: View {
    let matchedPairs: [DroneMatchedPair]
    let unmatched: [DroneRenameOnly]

    private var renameCount: Int { matchedPairs.count + unmatched.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !matchedPairs.isEmpty || !unmatched.isEmpty {
                DroneCleanupSummaryBadges(
                    trashCount: matchedPairs.count,
                    renameCount: renameCount
                )

                VStack(spacing: 10) {
                    ForEach(matchedPairs, id: \.compressedName) { pair in
                        DroneCleanupMatchedPairCard(pair: pair)
                    }
                    ForEach(unmatched, id: \.originalName) { item in
                        DroneCleanupRenameOnlyCard(item: item)
                    }
                }

                DroneCleanupLegend()
            }
        }
    }
}

private enum DroneCleanupStyle {
    static let delete = Color.red
    static let rename = Color.teal
}

private struct DroneCleanupSummaryBadges: View {
    let trashCount: Int
    let renameCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if trashCount > 0 {
                summaryBadge(icon: "trash", label: fileCountLabel(trashCount, noun: "Trash"), tint: DroneCleanupStyle.delete)
            }
            if renameCount > 0 {
                summaryBadge(icon: "doc", label: fileCountLabel(renameCount, noun: "rename"), tint: DroneCleanupStyle.rename)
            }
        }
    }

    private func fileCountLabel(_ count: Int, noun: String) -> String {
        "\(count) file\(count == 1 ? "" : "s") to \(noun)"
    }

    private func summaryBadge(icon: String, label: String, tint: Color) -> some View {
        Label(label, systemImage: icon)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private struct DroneCleanupLegend: View {
    var body: some View {
        HStack(spacing: 20) {
            legendItem(color: DroneCleanupStyle.delete, text: "File will be moved to Trash")
            legendItem(color: DroneCleanupStyle.rename, text: "File will be renamed (suffix removed)")
        }
        .font(.callout)
        .foregroundStyle(.secondary.opacity(0.85))
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 7, height: 7)
            Text(text)
        }
    }
}

private struct DroneCleanupMatchedPairCard: View {
    let pair: DroneMatchedPair

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary.opacity(0.8))
                Text(pair.finalName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            DroneCleanupActionRow(
                kind: .delete,
                from: pair.sourceName,
                to: "Trash"
            )
            DroneCleanupActionRow(
                kind: .rename,
                from: pair.compressedName,
                to: pair.finalName
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct DroneCleanupRenameOnlyCard: View {
    let item: DroneRenameOnly

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary.opacity(0.8))
                Text(item.finalName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            DroneCleanupActionRow(
                kind: .rename,
                from: item.originalName,
                to: item.finalName
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct DroneCleanupActionRow: View {
    enum Kind {
        case delete
        case rename

        var badge: String {
            switch self {
            case .delete: return "DELETE"
            case .rename: return "RENAME"
            }
        }

        var tint: Color {
            switch self {
            case .delete: return DroneCleanupStyle.delete
            case .rename: return DroneCleanupStyle.rename
            }
        }
    }

    let kind: Kind
    let from: String
    let to: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(kind.badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(kind.tint.opacity(0.95))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(kind.tint.opacity(0.14))
                )

            actionText
                .font(.body.monospaced())
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionText: Text {
        Text(from)
            .foregroundColor(.secondary.opacity(0.85))
        + Text("  →  ")
            .foregroundColor(.secondary.opacity(0.55))
        + Text(to)
            .foregroundColor(kind.tint.opacity(0.92))
    }
}

// MARK: - Flatten step

struct DroneFlattenStepView: View {
    let plan: DroneFinalizePlan?
    let config: DroneFinalizeConfig
    let isRunning: Bool
    let statusMessage: String?
    let action: () -> Void

    private var description: String {
        if config.preserveOrientationOnFlatten {
            let orientation = "keeping “\(config.verticalDirectoryName)/” and “\(config.horizontalDirectoryName)/” when used"
            let exportRemoval = "then remove “\(config.exportDirectoryName)/”."
            let rawNote = config.keepRawAfterFinalize
                ? " The “\(config.rawDirectoryName)/” folder is kept."
                : " The “\(config.rawDirectoryName)/” folder is moved to the Trash."
            return "Move finished media into the project folder (\(orientation)), \(exportRemoval)\(rawNote)"
        }
        let rawNote = config.keepRawAfterFinalize
            ? " The “\(config.rawDirectoryName)/” folder is kept."
            : " The “\(config.rawDirectoryName)/” folder is also moved to the Trash."
        return "Move the finished media into the project folder, then move the “\(config.exportDirectoryName)/” folder to the Trash.\(rawNote)"
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
            DroneFlattenChangesView(
                mediaNames: plan?.finalMediaNames.sorted() ?? [],
                config: config
            )
        }
    }
}

private enum DroneFlattenStyle {
    static let moveUp = Color.teal
    static let trash = Color.red
    static let result = Color.green
}

private struct DroneFlattenChangesView: View {
    let mediaNames: [String]
    let config: DroneFinalizeConfig

    private var trashFolders: [String] {
        var folders = [config.exportDirectoryName]
        if !config.keepRawAfterFinalize {
            folders.insert(config.rawDirectoryName, at: 0)
        }
        return folders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DroneFlattenSummaryBar(
                fileCount: mediaNames.count,
                folderCount: trashFolders.count,
                preserveOrientationOnFlatten: config.preserveOrientationOnFlatten
            )

            VStack(alignment: .leading, spacing: 0) {
                DroneFlattenMoveUpSection(
                    mediaNames: mediaNames,
                    exportDirectoryName: config.exportDirectoryName
                )

                Divider()
                    .opacity(0.35)
                    .padding(.vertical, 12)

                DroneFlattenTrashSection(folders: trashFolders)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
    }
}

private struct DroneFlattenSummaryBar: View {
    let fileCount: Int
    let folderCount: Int
    let preserveOrientationOnFlatten: Bool

    var body: some View {
        HStack(spacing: 10) {
            summaryPill(
                icon: "arrow.up",
                label: "\(fileCount) file\(fileCount == 1 ? "" : "s") move up",
                tint: DroneFlattenStyle.moveUp
            )
            Text("+")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.7))
            summaryPill(
                icon: "trash",
                label: "\(folderCount) folders removed",
                tint: DroneFlattenStyle.trash
            )
            Text("=")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.7))
            summaryPill(
                icon: "folder",
                label: preserveOrientationOnFlatten ? "Organized project folder" : "Flat project folder",
                tint: DroneFlattenStyle.result
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryPill(icon: String, label: String, tint: Color) -> some View {
        Label(label, systemImage: icon)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private struct DroneFlattenMoveUpSection: View {
    let mediaNames: [String]
    let exportDirectoryName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Move up into project folder",
                icon: "arrow.up",
                tint: DroneFlattenStyle.moveUp,
                count: mediaNames.count
            )

            if mediaNames.isEmpty {
                Text("No media files to move.")
                    .font(.callout)
                    .foregroundStyle(.secondary.opacity(0.85))
            } else {
                VStack(spacing: 8) {
                    ForEach(mediaNames.prefix(60), id: \.self) { name in
                        DroneFlattenMoveUpRow(
                            from: "\(exportDirectoryName)/\(name)",
                            to: name
                        )
                    }
                    if mediaNames.count > 60 {
                        Text("And \(mediaNames.count - 60) more…")
                            .font(.footnote)
                            .foregroundStyle(.secondary.opacity(0.85))
                    }
                }
            }
        }
    }
}

private struct DroneFlattenTrashSection: View {
    let folders: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Move to Trash",
                icon: "trash",
                tint: DroneFlattenStyle.trash,
                count: folders.count
            )

            VStack(spacing: 8) {
                ForEach(folders, id: \.self) { folder in
                    DroneFlattenTrashRow(folderName: folder)
                }
            }
        }
    }
}

private func sectionHeader(title: String, icon: String, tint: Color, count: Int) -> some View {
    HStack {
        Label(title, systemImage: icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint.opacity(0.9))
        Spacer()
        Text("\(count) item\(count == 1 ? "" : "s")")
            .font(.callout)
            .foregroundStyle(.secondary.opacity(0.85))
    }
}

private struct DroneFlattenMoveUpRow: View {
    let from: String
    let to: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary.opacity(0.75))

            (Text(from)
                .foregroundColor(.secondary.opacity(0.85))
                + Text("  →  ")
                .foregroundColor(.secondary.opacity(0.55))
                + Text(to)
                .foregroundColor(DroneFlattenStyle.moveUp.opacity(0.92)))
                .font(.body.monospaced())
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(DroneFlattenStyle.moveUp.opacity(0.85))
        }
    }
}

private struct DroneFlattenTrashRow: View {
    let folderName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(DroneFlattenStyle.trash.opacity(0.85))

            Text("\(folderName)/")
                .font(.body.monospaced())
                .foregroundStyle(.primary.opacity(0.85))

            Spacer(minLength: 8)

            Text("Empty folder")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.primary.opacity(0.08))
                )

            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(DroneFlattenStyle.trash.opacity(0.85))
        }
    }
}

// MARK: - Done step

struct DroneDoneStepView: View {
    let projectPath: String?
    let config: DroneFinalizeConfig
    let onChooseAnother: () -> Void

    private var description: String {
        "Delivery files are ready in the project folder."
            + (config.preserveOrientationOnFlatten ? " Orientation subfolders were preserved where needed." : "")
    }

    var body: some View {
        GlassCard {
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
                        .pillActionButton()
                        .help("Reveal the project folder in Finder (⌘R)")
                        .keyboardShortcut("r", modifiers: .command)
                    }
                    Spacer()
                    Button("Choose Another Folder", action: onChooseAnother)
                        .pillActionButton(prominent: true)
                        .help("Choose another project folder (⌘O)")
                        .keyboardShortcut("o", modifiers: .command)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
