import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var excludedSuffix: String = AppSettings.excludedAlbumSuffix
    @State private var omittedAlbumIDs: Set<String> = AppSettings.omittedFromOrganizeAlbumIDs
    @State private var organizeByYearEnabled: Bool = AppSettings.organizeByYearEnabled
    @State private var droneCompressedSuffix: String = AppSettings.droneCompressedSuffix
    @State private var droneRawDirectoryName: String = AppSettings.droneRawDirectoryName
    @State private var droneExportDirectoryName: String = AppSettings.droneExportDirectoryName
    @State private var droneVerticalDirectoryName: String = AppSettings.droneVerticalDirectoryName
    @State private var droneHorizontalDirectoryName: String = AppSettings.droneHorizontalDirectoryName
    @State private var droneHandBrakeCLIPath: String = AppSettings.droneHandBrakeCLIPath
    @State private var droneResolveAppPath: String = AppSettings.droneResolveAppPath
    @State private var droneHandBrakeOutputExtension: String = AppSettings.droneHandBrakeOutputExtension
    @State private var droneKeepRawAfterFinalize: Bool = AppSettings.droneKeepRawAfterFinalize
    @State private var dronePreserveOrientationOnFlatten: Bool = AppSettings.dronePreserveOrientationOnFlatten
    @State private var fileDateRepairExtensions: String = AppSettings.fileDateRepairExtensions

    var body: some View {
        TabView {
            PhotosSettingsTab(
                excludedSuffix: $excludedSuffix,
                omittedAlbumIDs: $omittedAlbumIDs,
                organizeByYearEnabled: $organizeByYearEnabled
            )
            .tabItem {
                Label("Photos", systemImage: "photo.on.rectangle.angled")
            }

            DroneSettingsTab(
                compressedSuffix: $droneCompressedSuffix,
                rawDirectoryName: $droneRawDirectoryName,
                exportDirectoryName: $droneExportDirectoryName,
                verticalDirectoryName: $droneVerticalDirectoryName,
                horizontalDirectoryName: $droneHorizontalDirectoryName,
                handBrakeCLIPath: $droneHandBrakeCLIPath,
                resolveAppPath: $droneResolveAppPath,
                handBrakeOutputExtension: $droneHandBrakeOutputExtension,
                keepRawAfterFinalize: $droneKeepRawAfterFinalize,
                preserveOrientationOnFlatten: $dronePreserveOrientationOnFlatten
            )
            .tabItem {
                Label("Drone", systemImage: "airplane")
            }

            FileDateRepairSettingsTab(extensions: $fileDateRepairExtensions)
                .tabItem {
                    Label("File Dates", systemImage: "calendar.badge.clock")
                }
        }
        .frame(width: 520, height: 640)
        .onAppear {
            excludedSuffix = AppSettings.excludedAlbumSuffix
            omittedAlbumIDs = AppSettings.omittedFromOrganizeAlbumIDs
            organizeByYearEnabled = AppSettings.organizeByYearEnabled
            droneCompressedSuffix = AppSettings.droneCompressedSuffix
            droneRawDirectoryName = AppSettings.droneRawDirectoryName
            droneExportDirectoryName = AppSettings.droneExportDirectoryName
            droneVerticalDirectoryName = AppSettings.droneVerticalDirectoryName
            droneHorizontalDirectoryName = AppSettings.droneHorizontalDirectoryName
            droneHandBrakeCLIPath = AppSettings.droneHandBrakeCLIPath
            droneResolveAppPath = AppSettings.droneResolveAppPath
            droneHandBrakeOutputExtension = AppSettings.droneHandBrakeOutputExtension
            droneKeepRawAfterFinalize = AppSettings.droneKeepRawAfterFinalize
            dronePreserveOrientationOnFlatten = AppSettings.dronePreserveOrientationOnFlatten
            fileDateRepairExtensions = AppSettings.fileDateRepairExtensions
            loadAlbumsIfNeeded()
        }
        .onChange(of: omittedAlbumIDs) { _, newValue in
            appState.syncOmittedFromOrganizeAlbums(newValue)
        }
        .onDisappear {
            AppSettings.excludedAlbumSuffix = excludedSuffix
            AppSettings.organizeByYearEnabled = organizeByYearEnabled
            AppSettings.droneCompressedSuffix = droneCompressedSuffix
            AppSettings.droneRawDirectoryName = droneRawDirectoryName
            AppSettings.droneExportDirectoryName = droneExportDirectoryName
            AppSettings.droneVerticalDirectoryName = droneVerticalDirectoryName
            AppSettings.droneHorizontalDirectoryName = droneHorizontalDirectoryName
            AppSettings.droneHandBrakeCLIPath = droneHandBrakeCLIPath
            AppSettings.droneResolveAppPath = droneResolveAppPath
            AppSettings.droneHandBrakeOutputExtension = droneHandBrakeOutputExtension
            AppSettings.droneKeepRawAfterFinalize = droneKeepRawAfterFinalize
            AppSettings.dronePreserveOrientationOnFlatten = dronePreserveOrientationOnFlatten
            AppSettings.fileDateRepairExtensions = fileDateRepairExtensions
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

private struct FileDateRepairSettingsTab: View {
    @Binding var extensions: String

    var body: some View {
        Form {
            Section("Supported files") {
                FileExtensionTagsInput(extensions: $extensions)
                Text(
                    "Only matching files are scanned. Enter extensions without a leading dot; "
                        + "type a comma or semicolon to add each extension."
                )
                .font(AlbumListRowStyle.detailFont)
                .foregroundStyle(.secondary)

                Button("Restore Defaults") {
                    extensions = FileDateRepairExtensions.defaults.joined(separator: ", ")
                }
            }

            Section("Repair behavior") {
                Text(
                    "Repair synchronizes Finder Created and every existing EXIF, TIFF, "
                        + "or video-container creation date to the oldest valid date found. "
                        + "Modification dates stay unchanged."
                )
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct FileExtensionTagsInput: View {
    @Binding var extensions: String
    @State private var draft = ""
    @FocusState private var isDraftFocused: Bool

    private var tags: [String] {
        FileDateRepairExtensions.parse(extensions).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsFlowLayout(spacing: 7) {
                ForEach(tags, id: \.self) { fileExtension in
                    extensionChip(fileExtension)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isDraftFocused = true
            }

            TextField("Extension", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isDraftFocused)
                .accessibilityLabel("Add file extension")
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, value in
                    commitValuesBeforeLastDelimiter(in: value)
                }
        }
        .help("Type an extension, then comma, semicolon, or Return.")
    }

    private func extensionChip(_ fileExtension: String) -> some View {
        HStack(spacing: 4) {
            Text(".\(fileExtension)")
                .font(.callout.monospaced())
            Button {
                remove(fileExtension)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove .\(fileExtension)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .padding(.vertical, 5)
        .foregroundStyle(Color.accentColor)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.25))
        }
    }

    private func commitValuesBeforeLastDelimiter(in value: String) {
        guard let delimiterIndex = value.lastIndex(where: { $0 == "," || $0 == ";" }) else {
            return
        }
        let committed = String(value[...delimiterIndex])
        let remainder = String(value[value.index(after: delimiterIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        add(committed)
        draft = remainder
    }

    private func commitDraft() {
        add(draft)
        draft = ""
    }

    private func add(_ value: String) {
        let additions = FileDateRepairExtensions.parse(value)
        guard !additions.isEmpty else { return }
        extensions = Set(tags)
            .union(additions)
            .sorted()
            .joined(separator: ", ")
    }

    private func remove(_ fileExtension: String) {
        extensions = tags
            .filter { $0 != fileExtension }
            .joined(separator: ", ")
    }
}

private struct SettingsFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var position = CGPoint.zero
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if position.x > 0, position.x + spacing + size.width > availableWidth {
                position.x = 0
                position.y += rowHeight + spacing
                rowHeight = 0
            }
            if position.x > 0 {
                position.x += spacing
            }
            position.x += size.width
            rowHeight = max(rowHeight, size.height)
            contentWidth = max(contentWidth, position.x)
        }

        return CGSize(
            width: proposal.width ?? contentWidth,
            height: position.y + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var position = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if position.x > bounds.minX,
               position.x + spacing + size.width > bounds.maxX {
                position.x = bounds.minX
                position.y += rowHeight + spacing
                rowHeight = 0
            }
            if position.x > bounds.minX {
                position.x += spacing
            }
            subview.place(
                at: position,
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            position.x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct DroneSettingsTab: View {
    @Binding var compressedSuffix: String
    @Binding var rawDirectoryName: String
    @Binding var exportDirectoryName: String
    @Binding var verticalDirectoryName: String
    @Binding var horizontalDirectoryName: String
    @Binding var handBrakeCLIPath: String
    @Binding var resolveAppPath: String
    @Binding var handBrakeOutputExtension: String
    @Binding var keepRawAfterFinalize: Bool
    @Binding var preserveOrientationOnFlatten: Bool

    var body: some View {
        Form {
            Section("External tools") {
                TextField("HandBrakeCLI path", text: $handBrakeCLIPath)
                    .help("Leave blank to auto-detect Homebrew or HandBrake.app.")
                TextField("DaVinci Resolve app path", text: $resolveAppPath)
                    .help("Leave blank to auto-detect in /Applications.")
            }

            Section("Compressed files") {
                TextField("Compressed suffix", text: $compressedSuffix)
                    .help("Suffix added to HandBrake outputs; removed during finalize.")
                Picker("Output extension", selection: $handBrakeOutputExtension) {
                    ForEach(DroneFinalizeConfig.supportedOutputExtensions, id: \.self) { fileExtension in
                        Text(".\(fileExtension)").tag(fileExtension)
                    }
                }
                .pickerStyle(.menu)
                .help("Container extension for HandBrake outputs.")
                Text("Defaults: _COMPRESSED, mp4")
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)
            }

            Section("Project folders") {
                TextField("Raw folder name", text: $rawDirectoryName)
                TextField("Export folder name", text: $exportDirectoryName)
                TextField("Vertical subfolder", text: $verticalDirectoryName)
                TextField("Horizontal subfolder", text: $horizontalDirectoryName)
                Toggle("Keep raw/ after finalize", isOn: $keepRawAfterFinalize)
                Toggle("Preserve vertical/horizontal after flatten", isOn: $preserveOrientationOnFlatten)
                Text("Defaults: raw, export, vertical, horizontal")
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
    @Binding var organizeByYearEnabled: Bool

    private var sortedAlbums: [PhotoAlbum] {
        appState.photosService.albums.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section("Organize export") {
                Toggle("Organize into year folders", isOn: $organizeByYearEnabled)
                    .help(
                        "When enabled, exports into year subfolders "
                            + "unless the chosen folder name already contains a year."
                    )
                Text(
                    "When on, photos are placed in a YEAR subfolder based on creation date. "
                        + "If the export folder name already contains a year (e.g. 2026 or 2026_10_test), "
                        + "all items go directly into that folder. "
                        + "When off, everything exports flat into the chosen folder."
                )
                .font(AlbumListRowStyle.detailFont)
                .foregroundStyle(.secondary)
            }

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
