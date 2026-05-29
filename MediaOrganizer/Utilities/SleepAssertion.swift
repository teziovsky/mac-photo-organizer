import Foundation

/// Prevents idle system sleep while a long-running export is in progress.
final class SleepAssertion {
    private var activity: NSObjectProtocol?

    func acquire(reason: String) {
        release()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: reason
        )
    }

    func release() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    deinit {
        release()
    }
}
