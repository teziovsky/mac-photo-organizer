# AGENTS.md

## Cursor Cloud specific instructions

### Platform constraint (important)

Teziovsky Utilities is a **native macOS SwiftUI app** (imports `SwiftUI`, `AppKit`,
`Photos`, `Quartz`, `QuickLookUI`; `Package.swift` targets `macOS 14+` and links
macOS-only frameworks). The Cursor Cloud VM is **Linux (Ubuntu x86_64) with no
Xcode/Swift toolchain**, so the following **cannot** run here and require a macOS
host with Xcode 15+:

- Build: `npm run build` / `npm run run` (`xcodebuild`), and `swift build` (`swift` is absent and the module links macOS-only frameworks)
- Tests: `npm run test` (`swift test`) — the test target links the macOS-only app module
- Running the GUI app itself

Do not attempt these on the cloud VM; they will fail on missing `xcodebuild`/`swift`
or unavailable Apple frameworks. Run build/test/run on macOS + Xcode (see `README.md`).

### What DOES work on the Linux cloud VM

- **Lint:** `npm run lint` (and `npm run lint:fix`) work. They shell out to `swiftlint`,
  which has a Linux binary. SwiftLint lints Swift source as text/AST and does not need
  the macOS frameworks, so this is the primary runnable dev task here.

### Gotchas

- **Do not run `pnpm install` / `npm install` without `--ignore-scripts`.** `package.json`
  defines an `install` script (`bash scripts/install-to-applications.sh`) that npm/pnpm
  execute as a lifecycle hook; it calls `xcodebuild` and fails on Linux. The startup
  update script uses `pnpm install --ignore-scripts`. There are no JS runtime deps
  (`pnpm-lock.yaml` is empty), so this is effectively a no-op.
- `swiftlint` is installed to `$HOME/.local/bin/swiftlint` (already on PATH via `~/.profile`)
  by the startup update script, pinned to the project's SwiftLint version (`0.63.3`).
