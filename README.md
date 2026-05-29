# Media Organizer

Native macOS app for organizing media. From a home screen you pick a workflow:

- **Organize Photos** — review iCloud Photos albums and export them to a folder.
- **Organize Drone Footage** — finalize a graded project folder (fully native, no external tools).

> The Xcode target, scheme, and Swift module are all named `MediaOrganizer`; the user-facing app name is **Media Organizer** and the bundle ID is `com.teziovsky.media-organizer`.

## Features

### Organize Photos

- Browse non-empty albums (hide albums ending with a configurable suffix, default `_zgrane`)
- Lazy thumbnail **views** for large albums (PhotoKit loads item metadata per album; grid rows render on demand)
- Choose an export folder and **Organize** to copy originals with progress and cancel
- Quick Look preview for the selected item (⌘Y)

### Organize Drone Footage

Point the app at a project folder that contains a `raw/` and an `export/` subfolder (names configurable in Settings → Drone). The finalize action runs fully natively:

1. For every compressed file in `export/` (name ending with the configurable suffix, default `_COMPRESSED`), match its source original, copy the source's creation/modification dates (and, for video, best-effort QuickTime creation date / location via AVFoundation passthrough) onto the compressed file, delete the source, and rename the compressed file to drop the suffix.
2. Move the remaining images and videos from `export/` up one level into the project root.
3. Remove the now-empty `raw/` and `export/` folders.

The result is the finished media sitting directly in the project folder with no subdirectories. A preview lists every planned action before anything is changed (the operation deletes files). Video compression itself stays in HandBrake — this app handles the post-compression finalize.

### First launch

On first launch (before Photos access is granted) the app shows a short explainer with a button to grant Photos access. Drone footage organizing needs no Photos permission, so you can continue without granting it.

## Requirements

- macOS 14+
- Xcode 15+
- Photos library access (only for the Organize Photos workflow)

## SwiftLint

Style and conventions are enforced with [SwiftLint](https://realm.github.io/SwiftLint/). Configuration lives in [`.swiftlint.yml`](.swiftlint.yml).

| Command | Description |
|---------|-------------|
| `npm run lint` | Lint `MediaOrganizer/` and `Tests/` |
| `npm run lint:fix` | Auto-fix correctable issues, then lint again |

SwiftLint also runs during **Xcode** builds (Run Script phase after compile) and **SPM** builds via the [SwiftLintPlugins](https://github.com/SimplyDanny/SwiftLintPlugins) build-tool plugin (version **0.63.3**). The Xcode script uses the package’s bundled `swiftlint` binary when available, otherwise Homebrew’s.

For CI / unattended `xcodebuild`, pass `-skipPackagePluginValidation` when using the SPM plugin.

## Build & run

### Xcode

```bash
npm run open
```

Select the **MediaOrganizer** scheme and press **Run** (⌘R).

### npm scripts (Xcode — full `.app` bundle)

| Script | Description |
|--------|-------------|
| `npm run clean` | Remove `build/`, `dist/`, and run `xcodebuild clean` |
| `npm run build` | Debug build → `build/DerivedData/Build/Products/Debug/MediaOrganizer.app` |
| `npm run clean:build` | Clean, then debug build |
| `npm run run` | Debug build and launch the app |
| `npm run build:production` | Release build (optimized) |
| `npm run release` | Release build, copy `.app` to `dist/`, create `dist/MediaOrganizer-macOS.zip` |
| `npm run install` | Release build and install to `/Applications/Media Organizer.app` |
| `npm run install:open` | Same as `install`, then launch the app |

```bash
npm run run
npm run install
```

### Swift Package Manager (compile only)

This repo includes a [`Package.swift`](Package.swift) so you can compile from the CLI:

```bash
swift build          # or: npm run swift:build
swift package clean  # or: npm run swift:clean
```

SPM builds a bare executable in `.build/debug/` — **not** a signed `.app` with icons and Photos entitlements. To run the real app, use **`npm run run`** or Xcode (⌘R).

Set your development team in Xcode for signed release builds outside this repo (scripts use `CODE_SIGNING_ALLOWED=NO` for local CLI builds).

## App identity

- **Bundle ID:** `com.teziovsky.media-organizer`
- **Icons:** `MediaOrganizer/Assets.xcassets/AppIcon.appiconset` (also copied under `MediaOrganizer/Resources/AppIcon/`)

## Settings

- **Excluded album suffix** — albums whose names end with this suffix are hidden (default: `_zgrane`)
- **Omit from Organize** — hide albums from the sidebar and disable Organize for them
- **Export folder** — destination for the Organize action
- **Drone → Compressed suffix** — suffix HandBrake adds to compressed files (default: `_COMPRESSED`)
- **Drone → Raw / Export folder names** — subfolder names used by the drone finalize step (defaults: `raw`, `export`)

## Notes

The previous Raycast extension prototype was removed. This SwiftUI app uses PhotoKit directly for better performance on large holiday albums.
