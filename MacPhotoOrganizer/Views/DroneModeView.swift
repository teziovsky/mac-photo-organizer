import AppKit
import SwiftUI

struct DroneModeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var projectDirectory: URL?
    @State private var showConfirm = false
    @State private var showProgress = false

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
                if let plan = finalizer.previewPlan {
                    DroneFinalizePreview(plan: plan, config: config)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(AppBranding.droneModeTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.goHome()
                } label: {
                    Label("Home", systemImage: "house")
                }
                .help("Back to the home screen")
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Finalize") {
                    showConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canFinalize)
                .help("Merge metadata, drop the compressed suffix, and flatten into one folder")
            }
        }
        .confirmationDialog(
            "Finalize this project?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Finalize", role: .destructive) { runFinalize() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the source originals and removes the “\(config.rawDirectoryName)” and “\(config.exportDirectoryName)” folders. Review the planned actions first.")
        }
        .sheet(isPresented: $showProgress) {
            DroneFinalizeProgressView()
                .environmentObject(appState)
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
            Text(AppBranding.droneModeSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Project folder")
                    .font(.headline)
                Text("Pick the folder that contains your “\(config.rawDirectoryName)” and “\(config.exportDirectoryName)” subfolders.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Choose Project Folder…") { chooseFolder() }
                    if let path = projectDirectory?.path {
                        Text(path)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var canFinalize: Bool {
        guard !finalizer.isRunning, projectDirectory != nil else { return false }
        return finalizer.previewPlan?.hasWork == true
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the drone project folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectDirectory = url
        finalizer.loadPreview(projectDirectory: url, config: config)
    }

    private func runFinalize() {
        guard let url = projectDirectory else { return }
        showProgress = true
        finalizer.finalize(projectDirectory: url, config: config)
    }
}

private struct DroneFinalizePreview: View {
    let plan: DroneFinalizePlan
    let config: DroneFinalizeConfig

    var body: some View {
        GroupBox("Planned actions") {
            VStack(alignment: .leading, spacing: 14) {
                if !plan.hasWork && plan.leftoverFiles.isEmpty && plan.conflicts.isEmpty {
                    Text("Nothing to finalize in “\(config.exportDirectoryName)”.")
                        .foregroundStyle(.secondary)
                }

                section(
                    "Merge metadata & drop suffix",
                    icon: "wand.and.stars",
                    tint: .green,
                    items: plan.matchedPairs.map { "\($0.compressedName)  →  \($0.finalName)  (delete \($0.sourceName))" }
                )
                section(
                    "Rename without source (no metadata copy)",
                    icon: "questionmark.circle",
                    tint: .orange,
                    items: plan.unmatchedCompressed.map { "\($0.originalName)  →  \($0.finalName)" }
                )
                section(
                    "Keep & move up",
                    icon: "arrow.up.doc",
                    tint: .blue,
                    items: plan.passthroughMedia
                )
                section(
                    "Skipped (name conflict)",
                    icon: "exclamationmark.triangle",
                    tint: .red,
                    items: plan.conflicts
                )
                section(
                    "Will be removed with “\(config.exportDirectoryName)”",
                    icon: "trash",
                    tint: .secondary,
                    items: plan.leftoverFiles
                )

                Divider()
                Text("Then “\(config.rawDirectoryName)” and “\(config.exportDirectoryName)” are removed; the media above ends up directly in the project folder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, tint: Color, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(title) (\(items.count))", systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                ForEach(items.prefix(50), id: \.self) { item in
                    Text(item)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if items.count > 50 {
                    Text("And \(items.count - 50) more…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
