import SwiftUI

private enum HomeCardKind: Hashable {
    case photos
    case drone
}

/// Landing screen letting the user pick a workflow.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedCard: HomeCardKind?

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
                    kind: .photos,
                    title: AppBranding.photosModeTitle,
                    subtitle: AppBranding.photosModeSubtitle,
                    systemImage: AppBranding.photosModeIcon,
                    focus: $focusedCard
                ) {
                    appState.enterPhotosMode()
                }

                HomeModeCard(
                    kind: .drone,
                    title: AppBranding.droneModeTitle,
                    subtitle: AppBranding.droneModeSubtitle,
                    systemImage: AppBranding.droneModeIcon,
                    focus: $focusedCard
                ) {
                    appState.enterDroneMode()
                }
            }
            .frame(maxWidth: 760)
            .defaultFocus($focusedCard, nil)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { focusedCard = nil }
    }
}

private struct HomeModeCard: View {
    static let cardHeight: CGFloat = 210

    let kind: HomeCardKind
    let title: String
    let subtitle: String
    let systemImage: String
    var focus: FocusState<HomeCardKind?>.Binding
    let action: () -> Void

    @State private var isHovered = false

    private var isFocused: Bool { focus.wrappedValue == kind }
    private var isActive: Bool { isHovered || isFocused }

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
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.cardHeight, alignment: .topLeading)
            .padding(24)
            .liquidGlassCard(cornerRadius: 18, interactive: true)
            .overlay(ring)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused(focus, equals: kind)
        .focusEffectDisabled()
        .scaleEffect(isActive ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.18), value: isActive)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(ringColor, lineWidth: isFocused ? 3 : 1.5)
            .shadow(color: isFocused ? Color.accentColor.opacity(0.45) : .clear, radius: 5)
    }

    private var ringColor: Color {
        if isFocused { return .accentColor }
        if isHovered { return .accentColor.opacity(0.4) }
        return .clear
    }
}
