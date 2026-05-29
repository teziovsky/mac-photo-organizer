import SwiftUI

/// Landing screen letting the user pick a workflow.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text(AppBranding.appName)
                    .font(.system(size: 34, weight: .bold))
                Text("Choose what you want to organize.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                HomeModeCard(
                    title: AppBranding.photosModeTitle,
                    subtitle: AppBranding.photosModeSubtitle,
                    systemImage: AppBranding.photosModeIcon
                ) {
                    appState.enterPhotosMode()
                }

                HomeModeCard(
                    title: AppBranding.droneModeTitle,
                    subtitle: AppBranding.droneModeSubtitle,
                    systemImage: AppBranding.droneModeIcon
                ) {
                    appState.enterDroneMode()
                }
            }
            .frame(maxWidth: 760)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeModeCard: View {
    static let cardHeight: CGFloat = 210

    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text("Open")
                    Image(systemName: "arrow.right")
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, height: Self.cardHeight, alignment: .topLeading)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.quaternary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isHovered ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.18), value: isHovered)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
