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

private func openPhotosPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
        NSWorkspace.shared.open(url)
    }
}
