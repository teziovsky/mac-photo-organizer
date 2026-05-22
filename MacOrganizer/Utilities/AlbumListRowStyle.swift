import AppKit
import SwiftUI

enum AlbumListRowStyle {
    static let cornerRadius: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    static let labelSpacing: CGFloat = 4

    static let nameFont: Font = .system(size: 15, weight: .medium)
    static let detailFont: Font = .system(size: 13)
    static let shortcutFont: Font = .system(size: 13, weight: .medium)
    static let toolbarTitleFont: Font = .system(size: 17, weight: .semibold)

    static var hoverFill: Color {
        Color(nsColor: .quaternarySystemFill)
    }

    static var selectionFill: Color {
        Color.accentColor.opacity(0.2)
    }
}

struct AlbumListRowLabels: View {
    let album: PhotoAlbum
    let shortcutIndex: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
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

            if let shortcutIndex {
                Text("\(shortcutIndex)")
                    .font(AlbumListRowStyle.shortcutFont)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Pads the row and defines hit testing to match the hover/selection background.
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
