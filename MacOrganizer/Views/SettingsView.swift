import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var excludedSuffix: String = AppSettings.excludedAlbumSuffix

    var body: some View {
        Form {
            Section("Albums") {
                TextField("Excluded album suffix", text: $excludedSuffix)
                    .help("Albums whose names end with this suffix are hidden from the list.")
                Text("Default: _zgrane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Export") {
                if let path = appState.exportDirectoryPath {
                    Text(path)
                        .font(.caption)
                        .lineLimit(2)
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                }
                Button("Choose Export Folder…") {
                    chooseFolder()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onDisappear {
            AppSettings.excludedAlbumSuffix = excludedSuffix
            Task { await appState.photosService.reloadAlbums() }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.setExportDirectory(url)
        }
    }
}
