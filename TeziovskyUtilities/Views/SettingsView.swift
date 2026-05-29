import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var excludedSuffix: String = AppSettings.excludedAlbumSuffix
    @State private var omittedAlbumIDs: Set<String> = AppSettings.omittedFromOrganizeAlbumIDs
    @State private var droneCompressedSuffix: String = AppSettings.droneCompressedSuffix
    @State private var droneRawDirectoryName: String = AppSettings.droneRawDirectoryName
    @State private var droneExportDirectoryName: String = AppSettings.droneExportDirectoryName

    var body: some View {
        TabView {
            PhotosSettingsTab(
                excludedSuffix: $excludedSuffix,
                omittedAlbumIDs: $omittedAlbumIDs
            )
            .tabItem {
                Label("Photos", systemImage: "photo.on.rectangle.angled")
            }

            DroneSettingsTab(
                compressedSuffix: $droneCompressedSuffix,
                rawDirectoryName: $droneRawDirectoryName,
                exportDirectoryName: $droneExportDirectoryName
            )
            .tabItem {
                Label("Drone", systemImage: "airplane")
            }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            excludedSuffix = AppSettings.excludedAlbumSuffix
            omittedAlbumIDs = AppSettings.omittedFromOrganizeAlbumIDs
            droneCompressedSuffix = AppSettings.droneCompressedSuffix
            droneRawDirectoryName = AppSettings.droneRawDirectoryName
            droneExportDirectoryName = AppSettings.droneExportDirectoryName
            loadAlbumsIfNeeded()
        }
        .onChange(of: omittedAlbumIDs) { _, newValue in
            appState.syncOmittedFromOrganizeAlbums(newValue)
        }
        .onDisappear {
            AppSettings.excludedAlbumSuffix = excludedSuffix
            AppSettings.droneCompressedSuffix = droneCompressedSuffix
            AppSettings.droneRawDirectoryName = droneRawDirectoryName
            AppSettings.droneExportDirectoryName = droneExportDirectoryName
            appState.syncOmittedFromOrganizeAlbums(omittedAlbumIDs)
            Task { await appState.photosService.reloadAlbums() }
        }
    }

    private func loadAlbumsIfNeeded() {
        guard appState.photosService.canAccessLibrary,
              appState.photosService.albums.isEmpty else { return }
        Task { await appState.photosService.reloadAlbums() }
    }
}

private struct DroneSettingsTab: View {
    @Binding var compressedSuffix: String
    @Binding var rawDirectoryName: String
    @Binding var exportDirectoryName: String

    var body: some View {
        Form {
            Section("Compressed files") {
                TextField("Compressed suffix", text: $compressedSuffix)
                    .help("Suffix HandBrake adds to compressed files; removed during finalize.")
                Text("Default: _COMPRESSED")
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)
            }

            Section("Project folders") {
                TextField("Raw folder name", text: $rawDirectoryName)
                    .help("Subfolder holding raw source media; removed during finalize.")
                TextField("Export folder name", text: $exportDirectoryName)
                    .help("Subfolder holding graded/compressed media; flattened during finalize.")
                Text("Defaults: raw, export")
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PhotosSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @Binding var excludedSuffix: String
    @Binding var omittedAlbumIDs: Set<String>

    private var sortedAlbums: [PhotoAlbum] {
        appState.photosService.albums.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section("Album list") {
                TextField("Excluded album suffix", text: $excludedSuffix)
                    .help("Albums whose names end with this suffix are hidden from the list.")
                Text("Default: _zgrane")
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)
            }

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
        case .limited:
            PhotosLimitedAccessView()
                .frame(maxHeight: 200)
        case .denied, .restricted:
            PhotosAccessUnavailableView(
                title: "Photos Access Required",
                description: "Allow access in System Settings to manage omitted albums."
            )
            .frame(maxHeight: 200)
        case .authorized:
            if appState.photosService.isLoadingAlbums && sortedAlbums.isEmpty {
                AlbumsLoadingView()
                    .frame(maxHeight: 200)
            } else if sortedAlbums.isEmpty {
                let message = OrganizeCompleteMessaging.settingsAlbumList
                OrganizeCompleteEmptyView(title: message.title, description: message.description)
                    .frame(maxHeight: 200)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
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
        guard appState.photosService.canAccessLibrary,
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
        .onHover { isHovered = $0 }
        .accessibilityLabel(album.name)
        .accessibilityValue(isOmitted ? "Omitted from Organize" : "Included in Organize")
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
}
