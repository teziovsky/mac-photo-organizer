import AppKit
import SwiftUI

enum AlbumListRowStyle {
    // MARK: - Settings rows (two-line, no icon)

    static let cornerRadius: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    static let labelSpacing: CGFloat = 4

    static let nameFont: Font = .system(size: 15, weight: .medium)
    static let detailFont: Font = .system(size: 13)
    static let toolbarTitleFont: Font = .system(size: 17, weight: .semibold)
    static let navigationAlbumTitleFont: Font = .system(size: 15, weight: .semibold)
    static let navigationAlbumDetailFont: Font = .system(size: 12)

    static var hoverFill: Color {
        Color(nsColor: .quaternarySystemFill)
    }

    // MARK: - Sidebar rows (icon + label + count)

    static let sidebarIconName = "rectangle.stack"
    static let sidebarIconWidth: CGFloat = 20
    static let sidebarIconSpacing: CGFloat = 12
    static let sidebarCornerRadius: CGFloat = 8
    static let sidebarHorizontalPadding: CGFloat = 12
    static let sidebarVerticalPadding: CGFloat = 8
    static let sidebarListInset: CGFloat = 8
    static let sidebarRowSpacing: CGFloat = 2

    static let sidebarNameFont: Font = .system(size: 15)
    static let sidebarCountFont: Font = .system(size: 13)

    static var sidebarSelectionFill: Color {
        Color.primary.opacity(0.14)
    }

    static var sidebarHoverFill: Color {
        Color.primary.opacity(0.07)
    }
}

/// Sidebar: album icon, name, trailing media count (macOS sidebar style).
struct AlbumSidebarRowContent: View {
    let album: PhotoAlbum

    var body: some View {
        HStack(alignment: .center, spacing: AlbumListRowStyle.sidebarIconSpacing) {
            Image(systemName: AlbumListRowStyle.sidebarIconName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: AlbumListRowStyle.sidebarIconWidth, alignment: .center)

            Text(album.name)
                .font(AlbumListRowStyle.sidebarNameFont)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text("\(album.mediaCount)")
                .font(AlbumListRowStyle.sidebarCountFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings: album name and media summary (no icon).
struct AlbumListRowLabels: View {
    let album: PhotoAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: AlbumListRowStyle.labelSpacing) {
            Text(album.name)
                .font(AlbumListRowStyle.nameFont)
                .lineLimit(1)
                .foregroundStyle(.primary)
            Text(album.mediaSummary)
                .font(AlbumListRowStyle.detailFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func albumSidebarRowChrome(backgroundFill: Color) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AlbumListRowStyle.sidebarHorizontalPadding)
            .padding(.vertical, AlbumListRowStyle.sidebarVerticalPadding)
            .background {
                RoundedRectangle(cornerRadius: AlbumListRowStyle.sidebarCornerRadius)
                    .fill(backgroundFill)
            }
            .contentShape(RoundedRectangle(cornerRadius: AlbumListRowStyle.sidebarCornerRadius))
    }

    /// Pads the row and defines hit testing to match the hover/selection background (Settings).
    func albumListRowChrome(backgroundFill: Color) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AlbumListRowStyle.horizontalPadding)
            .padding(.vertical, AlbumListRowStyle.verticalPadding)
            .background {
                RoundedRectangle(cornerRadius: AlbumListRowStyle.cornerRadius)
                    .fill(backgroundFill)
            }
            .contentShape(RoundedRectangle(cornerRadius: AlbumListRowStyle.cornerRadius))
    }
}
