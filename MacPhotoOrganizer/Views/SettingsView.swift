import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var excludedSuffix: String = AppSettings.excludedAlbumSuffix
    @State private var omittedAlbumIDs: Set<String> = AppSettings.omittedFromOrganizeAlbumIDs

    var body: some View {
        TabView {
            GeneralSettingsTab(excludedSuffix: $excludedSuffix)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AlbumsSettingsTab(omittedAlbumIDs: $omittedAlbumIDs)
                .tabItem {
                    Label("Albums", systemImage: "photo.on.rectangle.angled")
                }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            excludedSuffix = AppSettings.excludedAlbumSuffix
            omittedAlbumIDs = AppSettings.omittedFromOrganizeAlbumIDs
            loadAlbumsIfNeeded()
        }
        .onChange(of: omittedAlbumIDs) { _, newValue in
            appState.syncOmittedFromOrganizeAlbums(newValue)
        }
        .onDisappear {
            AppSettings.excludedAlbumSuffix = excludedSuffix
            appState.syncOmittedFromOrganizeAlbums(omittedAlbumIDs)
            Task { await appState.photosService.reloadAlbums() }
        }
    }

    private func loadAlbumsIfNeeded() {
        guard appState.photosService.authorizationState == .authorized,
              appState.photosService.albums.isEmpty else { return }
        Task { await appState.photosService.reloadAlbums() }
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @Binding var excludedSuffix: String

    var body: some View {
        Form {
            Section("Albums") {
                TextField("Excluded album suffix", text: $excludedSuffix)
                    .help("Albums whose names end with this suffix are hidden from the list.")
                Text("Default: _zgrane")
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)
            }

            Section("Export") {
                if let path = appState.exportDirectoryPath {
                    Text(path)
                        .font(AlbumListRowStyle.detailFont)
                        .lineLimit(2)
                } else {
                    Text("No folder selected")
                        .font(AlbumListRowStyle.detailFont)
                        .foregroundStyle(.secondary)
                }
                Button("Choose Export Folder…") {
                    chooseFolder()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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

private struct AlbumsSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @Binding var omittedAlbumIDs: Set<String>

    private var sortedAlbums: [PhotoAlbum] {
        appState.photosService.albums.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section("Omit from Organize") {
                Text("Omitted albums are hidden from the sidebar and cannot use Organize.")
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)

                organizeAlbumList
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadAlbumsIfNeeded() }
    }

    @ViewBuilder
    private var organizeAlbumList: some View {
        switch appState.photosService.authorizationState {
        case .notDetermined:
            ProgressView("Connecting to Photos…")
                .controlSize(.small)
        case .denied, .restricted:
            Text("Photos access is required to list albums.")
                .foregroundStyle(.secondary)
        case .authorized:
            if appState.photosService.isLoadingAlbums {
                ProgressView("Loading albums…")
                    .controlSize(.small)
            } else if sortedAlbums.isEmpty {
                Text("No albums available.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(sortedAlbums) { album in
                            OmitAlbumSettingsRow(
                                album: album,
                                omittedAlbumIDs: $omittedAlbumIDs
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func loadAlbumsIfNeeded() {
        guard appState.photosService.authorizationState == .authorized,
              appState.photosService.albums.isEmpty else { return }
        Task { await appState.photosService.reloadAlbums() }
    }
}

private struct OmitAlbumSettingsRow: View {
    let album: PhotoAlbum
    @Binding var omittedAlbumIDs: Set<String>
    @State private var isHovered = false

    private var isOmitted: Bool {
        omittedAlbumIDs.contains(album.id)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AlbumListRowLabels(album: album)

            Toggle("Omit", isOn: omitBinding)
                .toggleStyle(.checkbox)
                .font(AlbumListRowStyle.detailFont)
        }
        .albumListRowChrome(backgroundFill: isHovered ? AlbumListRowStyle.hoverFill : .clear)
        .onTapGesture {
            toggleOmit()
        }
        .onHover { isHovered = $0 }
    }

    private var omitBinding: Binding<Bool> {
        Binding(
            get: { isOmitted },
            set: { omit in
                if omit {
                    omittedAlbumIDs.insert(album.id)
                } else {
                    omittedAlbumIDs.remove(album.id)
                }
            }
        )
    }

    private func toggleOmit() {
        if isOmitted {
            omittedAlbumIDs.remove(album.id)
        } else {
            omittedAlbumIDs.insert(album.id)
        }
    }
}
