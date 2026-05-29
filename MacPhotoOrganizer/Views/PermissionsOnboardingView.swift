import SwiftUI

/// Shown on first launch (before Photos access is granted): explains why the app wants
/// Photos access and lets the user grant it or continue without it (drone mode needs none).
struct PermissionsOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                Text("Welcome to \(AppBranding.appName)")
                    .font(.title)
                    .bold()
                    .multilineTextAlignment(.center)

                Text(
                    """
                    To organize your iCloud Photos albums, \(AppBranding.appName) needs access to your \
                    Photos library. It uses this to list albums, show thumbnails, export originals to a folder, \
                    and move items between albums.
                    """
                )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Organizing drone footage works on regular files and needs no Photos access — you can continue without it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 420)

            VStack(spacing: 10) {
                Button {
                    isRequesting = true
                    Task {
                        await appState.requestPhotosAccess()
                        isRequesting = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Grant Photos Access")
                    }
                    .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)

                Button("Continue Without Photos") {
                    appState.continueWithoutPhotosAccess()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isRequesting)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
