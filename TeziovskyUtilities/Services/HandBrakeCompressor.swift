import Foundation

struct HandBrakeCompressionProgress: Equatable, Sendable {
    var current: Int
    var total: Int
    var filename: String
    var isComplete: Bool
    var wasCancelled: Bool
}

enum HandBrakeCompressorError: LocalizedError {
    case cliNotFound
    case presetListFailed(String)
    case compressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "HandBrakeCLI was not found. Set its path in Settings → Drone."
        case let .presetListFailed(message):
            return "Could not load HandBrake presets: \(message)"
        case let .compressionFailed(message):
            return message
        }
    }
}

enum HandBrakeCompressor {
    static func listPresets(cliURL: URL) async throws -> [String] {
        let output = try await runCLI(
            executable: cliURL,
            arguments: ["--preset-list"],
            currentFileLabel: nil
        )
        return parsePresetNames(from: output)
    }

    static func compress(
        cliURL: URL,
        inputURL: URL,
        outputURL: URL,
        preset: String
    ) async throws {
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        _ = try await runCLI(
            executable: cliURL,
            arguments: [
                "--input", inputURL.path,
                "--output", outputURL.path,
                "--preset", preset
            ],
            currentFileLabel: inputURL.lastPathComponent
        )
    }

    static func parsePresetNames(from output: String) -> [String] {
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let presetList = json["PresetList"] as? [[String: Any]] {
                let names = presetList.compactMap { $0["PresetName"] as? String }
                if !names.isEmpty { return names.sorted() }
            }
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("[")
                    && !line.hasPrefix("+")
                    && !line.hasPrefix("<")
                    && line != "Presets:"
            }
            .sorted()
    }

    private static func runCLI(
        executable: URL,
        arguments: [String],
        currentFileLabel: String?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let combined = String(data: outData + errData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: combined)
                } else {
                    let label = currentFileLabel.map { "\($0): " } ?? ""
                    continuation.resume(throwing: HandBrakeCompressorError.compressionFailed(label + combined.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

@MainActor
final class HandBrakeCompressionSession: ObservableObject {
    @Published private(set) var progress: HandBrakeCompressionProgress?
    @Published private(set) var failures: [OrganizeFailure] = []
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?
    private let sleepAssertion = SleepAssertion()

    func cancel() {
        task?.cancel()
    }

    func compressAll(
        projectDirectory: URL,
        exports: [DroneUncompressedExport],
        config: DroneFinalizeConfig,
        preset: String
    ) {
        cancel()
        failures = []
        isRunning = true
        progress = HandBrakeCompressionProgress(
            current: 0,
            total: exports.count,
            filename: "",
            isComplete: false,
            wasCancelled: false
        )

        if exports.count >= 3 {
            sleepAssertion.acquire(reason: "Compressing \(exports.count) drone exports")
        }

        task = Task {
            defer {
                sleepAssertion.release()
                isRunning = false
            }

            guard let cliURL = DroneToolPaths.resolveHandBrakeCLI(configuredPath: config.handBrakeCLIPath) else {
                failures = [OrganizeFailure(filename: "", message: HandBrakeCompressorError.cliNotFound.localizedDescription)]
                progress?.isComplete = true
                return
            }

            let exportDir = projectDirectory.appendingPathComponent(config.exportDirectoryName, isDirectory: true)
            var issues: [OrganizeFailure] = []

            for (index, export) in exports.enumerated() {
                if Task.isCancelled {
                    progress?.wasCancelled = true
                    progress?.isComplete = true
                    return
                }

                progress?.current = index + 1
                progress?.filename = export.relativePath

                let inputURL = exportDir.appendingPathComponent(export.relativePath)
                let outputRelative = DroneExportScanner.compressedRelativePath(for: export.relativePath, config: config)
                let outputURL = exportDir.appendingPathComponent(outputRelative)

                do {
                    try await HandBrakeCompressor.compress(
                        cliURL: cliURL,
                        inputURL: inputURL,
                        outputURL: outputURL,
                        preset: preset
                    )
                } catch {
                    issues.append(OrganizeFailure(filename: export.relativePath, message: error.localizedDescription))
                }
            }

            failures = issues
            progress?.isComplete = true
        }
    }
}

@MainActor
final class HandBrakePresetLoader: ObservableObject {
    @Published private(set) var presets: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(config: DroneFinalizeConfig) {
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            guard let cliURL = DroneToolPaths.resolveHandBrakeCLI(configuredPath: config.handBrakeCLIPath) else {
                errorMessage = HandBrakeCompressorError.cliNotFound.localizedDescription
                presets = []
                return
            }
            do {
                presets = try await HandBrakeCompressor.listPresets(cliURL: cliURL)
            } catch {
                errorMessage = error.localizedDescription
                presets = []
            }
        }
    }
}
