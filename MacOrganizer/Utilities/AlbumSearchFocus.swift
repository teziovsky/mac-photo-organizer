import AppKit

enum AlbumSearchFocus {
    /// Focuses the window's album search field and selects all text (for ⌘F).
    @MainActor
    static func focusAndSelectAll(in window: NSWindow? = nil) {
        guard let window = window ?? NSApp.keyWindow else { return }

        let delays: [TimeInterval] = [0, 0.05, 0.12]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let searchField = findSearchField(in: window) else { return }
                window.makeFirstResponder(searchField)
                selectAllText(in: searchField)
            }
        }
    }

    private static func selectAllText(in searchField: NSSearchField) {
        if let editor = searchField.currentEditor() {
            editor.selectAll(nil)
        } else {
            searchField.selectText(nil)
        }
    }

    private static func findSearchField(in window: NSWindow) -> NSSearchField? {
        findSearchField(in: window.contentView)
    }

    private static func findSearchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let searchField = view as? NSSearchField {
            return searchField
        }
        for subview in view.subviews {
            if let found = findSearchField(in: subview) {
                return found
            }
        }
        return nil
    }
}
