import AppKit
import SwiftUI

private enum HomeCardKind: Hashable {
    case photos
    case drone
}

/// Landing screen letting the user pick a workflow.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedCard: HomeCardKind?
    @Namespace private var homeFocusScope
    @State private var cardsAcceptFocus = false

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
                    acceptsFocus: cardsAcceptFocus,
                    focus: $focusedCard
                ) {
                    appState.enterPhotosMode()
                }
                .prefersDefaultFocus(false, in: homeFocusScope)

                HomeModeCard(
                    kind: .drone,
                    title: AppBranding.droneModeTitle,
                    subtitle: AppBranding.droneModeSubtitle,
                    systemImage: AppBranding.droneModeIcon,
                    acceptsFocus: cardsAcceptFocus,
                    focus: $focusedCard
                ) {
                    appState.enterDroneMode()
                }
                .prefersDefaultFocus(false, in: homeFocusScope)
            }
            .focusScope(homeFocusScope)
            .frame(maxWidth: 760)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: clearInitialFocus)
        .onChange(of: focusedCard) { _, newValue in
            guard !cardsAcceptFocus, newValue != nil else { return }
            clearInitialFocus()
        }
        .task {
            clearInitialFocus()
            try? await Task.sleep(for: .milliseconds(100))
            clearInitialFocus()
            cardsAcceptFocus = true
        }
    }

    private func clearInitialFocus() {
        focusedCard = nil
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

private struct HomeModeCard: View {
    static let cardHeight: CGFloat = 210

    let kind: HomeCardKind
    let title: String
    let subtitle: String
    let systemImage: String
    let acceptsFocus: Bool
    var focus: FocusState<HomeCardKind?>.Binding
    let action: () -> Void

    @State private var isHovered = false

    private var isFocused: Bool { focus.wrappedValue == kind }
    private var isActive: Bool { isHovered || isFocused }

    var body: some View {
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
        .liquidGlassCard(cornerRadius: 18, interactive: isActive)
        .overlay(ring)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .focusable(acceptsFocus, interactions: .activate)
        .focused(focus, equals: kind)
        .focusEffectDisabled()
        .onTapGesture(perform: action)
        .onKeyPress(.return) {
            action()
            return .handled
        }
        .onKeyPress(.space) {
            action()
            return .handled
        }
        .scaleEffect(isActive ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.18), value: isActive)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
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
