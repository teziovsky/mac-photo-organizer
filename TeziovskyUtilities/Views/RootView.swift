import SwiftUI

/// Top-level view. Shows the launch permissions explainer first (when Photos access is
/// undetermined), then routes between the home screen and the two organizing modes.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.showsPermissionsOnboarding {
                PermissionsOnboardingView()
            } else {
                switch appState.route {
                case .home:
                    HomeView()
                case .photos:
                    PhotosModeView()
                case .drone:
                    DroneModeView()
                case .localPhotos:
                    LocalPhotosModeView()
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: appState.route)
        .animation(.smooth(duration: 0.25), value: appState.showsPermissionsOnboarding)
    }
}
