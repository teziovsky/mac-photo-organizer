import AppKit
import SwiftUI

struct PhotosAccessUnavailableView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(title, systemImage: "lock.slash", description: Text(description))
            Button("Open System Settings") {
                openPhotosPrivacySettings()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PhotosLimitedAccessView: View {
    var body: some View {
        PhotosAccessUnavailableView(
            title: "Full Photos Access Required",
            description: "This app needs full Photos library access to browse albums and organize. Select “Allow Access to All Photos” in System Settings."
        )
    }
}

struct AlbumsLoadingView: View {
    var message: String = "Loading albums…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(AlbumListRowStyle.detailFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct OrganizeCompleteEmptyView: View {
    let title: String
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
        } description: {
            Text(description)
        }
    }
}

enum OrganizeCompleteMessaging {
    static func sidebar(
        allAlbums: [PhotoAlbum],
        selectableAlbums: [PhotoAlbum]
    ) -> (title: String, description: String) {
        if !allAlbums.isEmpty && selectableAlbums.isEmpty {
            return (
                "Good Job!",
                "Every album in the sidebar is hidden under Omit from Organize. Turn one back on in Photos settings when you want to process more."
            )
        }

        let suffix = AppSettings.excludedAlbumSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty {
            return (
                "All Organized!",
                "No albums left without the “\(suffix)” suffix. Your library is caught up."
            )
        }

        return (
            "All Organized!",
            "Nothing left to organize. You're all caught up."
        )
    }

    static var settingsAlbumList: (title: String, description: String) {
        let suffix = AppSettings.excludedAlbumSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty {
            return (
                "All Organized!",
                "Every album is hidden by the “\(suffix)” suffix or is empty. Adjust the suffix in General settings if needed."
            )
        }
        return (
            "All Organized!",
            "No albums to show. Add albums in Photos or relax your filters."
        )
    }
}

private func openPhotosPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
        NSWorkspace.shared.open(url)
    }
}
