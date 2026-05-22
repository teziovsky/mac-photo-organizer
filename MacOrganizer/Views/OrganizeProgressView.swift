import SwiftUI

struct OrganizeProgressView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Organizing Album")
                .font(.title2)
                .bold()

            if let album = appState.selectedAlbum {
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(AlbumListRowStyle.nameFont)
                    if let destination = appState.organizeExporter.destinationAlbumTitle {
                        Text("Moving to “\(destination)”")
                            .font(AlbumListRowStyle.detailFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let progress = appState.organizeExporter.progress {
                ProgressView(value: progress.fraction) {
                    Text("\(progress.current) / \(progress.total)")
                } currentValueLabel: {
                    Text(progress.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 16) {
                    if progress.failedCount > 0 {
                        Label("\(progress.failedCount) failed", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    if progress.skippedCount > 0 {
                        Label("\(progress.skippedCount) skipped", systemImage: "icloud.slash")
                            .foregroundStyle(.orange)
                    }
                }
                .font(AlbumListRowStyle.detailFont)

                if progress.isComplete {
                    completionMessage(progress: progress)
                }
            } else {
                ProgressView()
            }

            if !appState.organizeExporter.failures.isEmpty {
                failuresList
            }

            HStack {
                Spacer()
                if appState.organizeExporter.isRunning {
                    Button("Cancel") {
                        appState.organizeExporter.cancel()
                    }
                } else {
                    Button("Done") {
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
    private func completionMessage(progress: OrganizeProgress) -> some View {
        if progress.wasCancelled {
            Text("Organize cancelled.")
                .foregroundStyle(.secondary)
        } else {
            Text("Organize finished.")
                .foregroundStyle(.secondary)
        }
    }

    private var failuresList: some View {
        GroupBox("Issues") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.organizeExporter.failures.prefix(50)) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.filename)
                                .font(AlbumListRowStyle.detailFont)
                                .bold()
                            Text(failure.message)
                                .font(AlbumListRowStyle.detailFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
    }
}
