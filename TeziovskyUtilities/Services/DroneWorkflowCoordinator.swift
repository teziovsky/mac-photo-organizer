import AppKit
import Combine
import Foundation

@MainActor
final class DroneWorkflowCoordinator: ObservableObject {
    @Published private(set) var phase: DroneWorkflowPhase = .validateLayout
    @Published private(set) var validationResult: DroneProjectValidationResult?
    @Published private(set) var uncompressedExports: [DroneUncompressedExport] = []
    @Published private(set) var selectedPreset: String = ""
    @Published private(set) var projectDirectoryPath: String?
    @Published private(set) var previewError: String?
    @Published private(set) var scanMessage: String?

    let finalizer = DroneFinalizer()
    let compressionSession = HandBrakeCompressionSession()
    let presetLoader = HandBrakePresetLoader()

    private(set) var config: DroneFinalizeConfig = .default
    private var projectDirectory: URL?

    var hasProject: Bool { projectDirectory != nil }

    init() {
        finalizer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        compressionSession.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        presetLoader.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func loadProject(projectDirectory: URL, config: DroneFinalizeConfig) {
        reset()
        self.config = config
        self.projectDirectory = projectDirectory
        projectDirectoryPath = projectDirectory.path

        let didAccess = projectDirectory.startAccessingSecurityScopedResource()
        defer { if didAccess { projectDirectory.stopAccessingSecurityScopedResource() } }

        let result = DroneProjectValidator.validate(projectDirectory: projectDirectory, config: config)
        validationResult = result

        if result.canContinue {
            previewError = nil
            phase = .validateLayout
        } else {
            previewError = result.messages.joined(separator: "\n")
        }
    }

    func createMissingOrientationDirectories() {
        guard let projectDirectory, let layoutMode = validationResult?.layoutMode else { return }
        let didAccess = projectDirectory.startAccessingSecurityScopedResource()
        defer { if didAccess { projectDirectory.stopAccessingSecurityScopedResource() } }
        do {
            try DroneProjectValidator.createMissingOrientationDirectories(
                projectDirectory: projectDirectory,
                config: config,
                layoutMode: layoutMode
            )
            validationResult = DroneProjectValidator.validate(projectDirectory: projectDirectory, config: config)
            previewError = validationResult?.status == .invalid
                ? validationResult?.messages.joined(separator: "\n")
                : nil
        } catch {
            previewError = error.localizedDescription
        }
    }

    func continueFromValidation() {
        guard validationResult?.canContinue == true else { return }
        phase = .waitForResolve
    }

    func openDaVinciResolve() {
        guard let url = DroneToolPaths.resolveDaVinciResolve(configuredPath: config.resolveAppPath) else {
            previewError = "DaVinci Resolve was not found. Set its path in Settings → Drone."
            return
        }
        previewError = nil
        NSWorkspace.shared.open(url)
    }

    func finishResolveEditing() {
        phase = .scanExport
        refreshExportScan()
    }

    func refreshExportScan() {
        guard let projectDirectory else { return }
        let didAccess = projectDirectory.startAccessingSecurityScopedResource()
        defer { if didAccess { projectDirectory.stopAccessingSecurityScopedResource() } }

        do {
            uncompressedExports = try DroneExportScanner.uncompressedExports(
                projectDirectory: projectDirectory,
                config: config
            )
            scanMessage = uncompressedExports.isEmpty
                ? "All exports already have compressed copies."
                : "\(uncompressedExports.count) file\(uncompressedExports.count == 1 ? "" : "s") need compression."
            previewError = nil
        } catch {
            previewError = error.localizedDescription
            uncompressedExports = []
        }
    }

    func continueFromScan() {
        if uncompressedExports.isEmpty {
            beginFinalize()
        } else {
            phase = .pickPreset
            if !AppSettings.droneLastHandBrakePreset.isEmpty {
                selectedPreset = AppSettings.droneLastHandBrakePreset
            }
            presetLoader.load(config: config)
        }
    }

    func selectPreset(_ preset: String) {
        selectedPreset = preset
    }

    func continueFromPresetPicker() {
        guard !selectedPreset.isEmpty else { return }
        phase = .compress
    }

    func startCompression() {
        guard let projectDirectory, !selectedPreset.isEmpty else { return }
        compressionSession.compressAll(
            projectDirectory: projectDirectory,
            exports: uncompressedExports,
            config: config,
            preset: selectedPreset
        )
    }

    func continueFromCompression() {
        refreshExportScan()
        beginFinalize()
    }

    func beginFinalize() {
        guard let projectDirectory else { return }
        phase = .finalize
        finalizer.loadProject(projectDirectory: projectDirectory, config: config)
    }

    func performFinalizeStep() {
        finalizer.performCurrentStep()
        if finalizer.step == .done {
            phase = .done
        }
    }

    func goBack() {
        switch phase {
        case .validateLayout:
            break
        case .waitForResolve:
            phase = .validateLayout
        case .scanExport:
            phase = .waitForResolve
        case .pickPreset:
            phase = .scanExport
        case .compress:
            phase = .pickPreset
        case .finalize:
            if finalizer.canUndo {
                finalizer.goBack()
            } else {
                phase = .compress
            }
        case .done:
            if finalizer.canUndo {
                finalizer.goBack()
                phase = .finalize
            } else {
                phase = .finalize
            }
        }
    }

    var canGoBack: Bool {
        switch phase {
        case .validateLayout:
            return false
        default:
            return true
        }
    }

    func reset() {
        compressionSession.cancel()
        finalizer.reset()
        phase = .validateLayout
        validationResult = nil
        uncompressedExports = []
        selectedPreset = ""
        projectDirectory = nil
        projectDirectoryPath = nil
        previewError = nil
        scanMessage = nil
        config = .default
    }
}
