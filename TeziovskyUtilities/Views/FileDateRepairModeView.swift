import AppKit
import SwiftUI

struct FileDateRepairModeView: View {
    @EnvironmentObject private var appState: AppState

    private var service: FileDateRepairService { appState.fileDateRepairService }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                folderCard
                if service.isRunning {
                    progressCard
                }
                if service.directory != nil, !service.isScanning {
                    resultsCard
                }
                if !service.failures.isEmpty {
                    failuresCard
                }
            }
            .padding(24)
            .frame(maxWidth: 1_000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(AppBranding.fileDateRepairModeTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    service.reset()
                    appState.goHome()
                } label: {
                    Label("Home", systemImage: "house")
                }
                .help("Back to the home screen (⇧⌘H)")
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(service.isRunning)
            }
        }
        .onEscape {
            if service.isRunning {
                service.cancel()
            } else {
                service.reset()
                appState.goHome()
            }
        }
        .onDisappear {
            if !service.isRunning {
                service.reset()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppBranding.fileDateRepairModeTitle)
                .font(.largeTitle.bold())
            Text(AppBranding.fileDateRepairModeSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(
                "Only Finder’s creation date is changed. "
                    + "File contents, embedded metadata, and modification dates stay untouched."
            )
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var folderCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Media folder")
                        .font(.headline)
                    if let directory = service.directory {
                        Text(directory.path)
                            .font(.callout.monospaced())
                            .foregroundStyle(Color.green.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Choose a folder to scan recursively. Hidden files, packages, and links are skipped.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Button(service.directory == nil ? "Choose & Scan" : "Change & Rescan") {
                    chooseFolder()
                }
                .pillActionButton(prominent: service.directory == nil)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(service.isRunning)
            }
        }
    }

    private var progressCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(service.isScanning ? "Scanning media" : "Repairing current chunk")
                        .font(.headline)
                    Spacer()
                    Text("\(service.progress.processed) of \(service.progress.total)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: service.progress.fraction)
                Text(service.progress.currentPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Cancel") {
                    service.cancel()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var resultsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                resultSummary

                if !service.items.isEmpty {
                    Divider()
                    chunkControls
                    LazyVStack(spacing: 8) {
                        ForEach(service.items) { item in
                            FileDateRepairRow(
                                item: item,
                                isRepaired: service.repairedIDs.contains(item.id),
                                didFail: service.attemptedIDs.contains(item.id)
                                    && !service.repairedIDs.contains(item.id)
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSummary: some View {
        let remaining = service.pendingItems.count
        VStack(alignment: .leading, spacing: 5) {
            Text("Scan results")
                .font(.headline)
            Text(
                "\(service.scannedFileCount) supported files scanned · "
                    + "\(service.items.count) need repair · "
                    + "\(service.repairedIDs.count) repaired · \(remaining) remaining"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if service.items.isEmpty {
                Label("No incorrect creation dates found.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            } else if remaining == 0 {
                Label("All chunks have been processed.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            }
        }
    }

    private var chunkControls: some View {
        HStack(spacing: 12) {
            Picker("Chunk size", selection: serviceBinding(\.chunkSize)) {
                Text("25").tag(25)
                Text("100").tag(100)
                Text("250").tag(250)
                Text("500").tag(500)
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            Text("Next chunk: \(service.currentChunk.count) files")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Fix Current Chunk") {
                service.repairCurrentChunk()
            }
            .pillActionButton(prominent: true)
            .disabled(service.currentChunk.isEmpty || service.isRunning)
        }
    }

    private var failuresCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(service.failures.count) issues", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(service.failures.prefix(50)) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.relativePath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if service.failures.count > 50 {
                    Text("And \(service.failures.count - 50) more…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func serviceBinding<Value>(_ keyPath: ReferenceWritableKeyPath<FileDateRepairService, Value>) -> Binding<Value> {
        Binding(
            get: { service[keyPath: keyPath] },
            set: { service[keyPath: keyPath] = $0 }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a media folder"
        panel.prompt = "Scan"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        service.scan(directory: url)
    }
}

private struct FileDateRepairRow: View {
    let item: FileDateRepairItem
    let isRepaired: Bool
    let didFail: Bool

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(item.evidence) { evidence in
                    HStack {
                        Text(evidence.source.label)
                        Spacer()
                        Text(format(evidence.date))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                statusIcon
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.relativePath)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(format(item.currentCreationDate))
                            .strikethrough()
                        Image(systemName: "arrow.right")
                        Text(format(item.proposedCreationDate))
                            .foregroundStyle(.green)
                        Text("from \(item.proposedSource.label)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRepaired {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if didFail {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.blue)
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
