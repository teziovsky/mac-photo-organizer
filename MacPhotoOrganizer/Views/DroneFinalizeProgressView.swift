import SwiftUI

struct DroneFinalizeProgressView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var finalizer: DroneFinalizer { appState.droneFinalizer }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Finalizing Project")
                .font(.title2)
                .bold()

            if let progress = finalizer.progress {
                ProgressView(value: progress.fraction) {
                    Text("\(progress.current) / \(progress.total)")
                } currentValueLabel: {
                    Text(progress.detail)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 16) {
                    if progress.processedCount > 0 {
                        Label("\(progress.processedCount) processed", systemImage: "wand.and.stars")
                            .foregroundStyle(.green)
                    }
                    if progress.movedCount > 0 {
                        Label("\(progress.movedCount) moved", systemImage: "arrow.up.doc")
                            .foregroundStyle(.blue)
                    }
                    if progress.failedCount > 0 {
                        Label("\(progress.failedCount) failed", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                .font(AlbumListRowStyle.detailFont)

                if progress.isComplete {
                    completionMessage(progress: progress)
                }
            } else {
                ProgressView()
            }

            if !finalizer.failures.isEmpty {
                issuesList
            }

            HStack {
                Spacer()
                if finalizer.isRunning {
                    Button("Cancel") { finalizer.cancel() }
                } else {
                    Button("Done") {
                        finalizer.reset()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder
    private func completionMessage(progress: DroneFinalizeProgress) -> some View {
        if progress.wasCancelled {
            Text("Finalize cancelled. Some files may already have been changed or moved.")
                .foregroundStyle(.secondary)
        } else if progress.failedCount > 0 {
            Text("Finalize finished with issues. Review the list below; you can re-run on the same folder.")
                .foregroundStyle(.secondary)
        } else {
            Text("Finalize finished. The project folder now holds the flattened media.")
                .foregroundStyle(.secondary)
        }
    }

    private var issuesList: some View {
        let failures = finalizer.failures
        let visible = Array(failures.prefix(50))
        let hiddenCount = failures.count - visible.count

        return GroupBox("Notes") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visible) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.filename.isEmpty ? "(general)" : failure.filename)
                                .font(AlbumListRowStyle.detailFont)
                                .bold()
                            Text(failure.message)
                                .font(AlbumListRowStyle.detailFont)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if hiddenCount > 0 {
                        Text("And \(hiddenCount) more…")
                            .font(AlbumListRowStyle.detailFont)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
    }
}
