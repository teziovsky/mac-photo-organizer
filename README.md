# Photos Organizer

Native macOS app for reviewing Photos albums and exporting them to a folder.

## Features

- Browse non-empty albums (hide albums ending with a configurable suffix, default `_zgrane`)
- Lazy thumbnail **views** for large albums (PhotoKit loads item metadata per album; grid rows render on demand)
- Choose an export folder and **Organize** to copy originals with progress and cancel
- Quick Look preview for the selected item (⌘Y)

## Requirements

- macOS 14+
- Xcode 15+
- Photos library access

## Build & run

### Xcode

```bash
npm run open
```

Select the **MacPhotoOrganizer** scheme and press **Run** (⌘R).

### npm scripts (Xcode — full `.app` bundle)

| Script | Description |
|--------|-------------|
| `npm run clean` | Remove `build/`, `dist/`, and run `xcodebuild clean` |
| `npm run build` | Debug build → `build/DerivedData/Build/Products/Debug/MacPhotoOrganizer.app` |
| `npm run clean:build` | Clean, then debug build |
| `npm run run` | Debug build and launch the app |
| `npm run build:production` | Release build (optimized) |
| `npm run release` | Release build, copy `.app` to `dist/`, create `dist/MacPhotoOrganizer-macOS.zip` |

```bash
npm run run
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

- **Bundle ID:** `com.teziovsky.mac-photo-organizer`
- **Icons:** `MacPhotoOrganizer/Assets.xcassets/AppIcon.appiconset` (also copied under `MacPhotoOrganizer/Resources/AppIcon/`)

## Settings

- **Excluded album suffix** — albums whose names end with this suffix are hidden (default: `_zgrane`)
- **Omit from Organize** — hide albums from the sidebar and disable Organize for them
- **Export folder** — destination for the Organize action

## Notes

The previous Raycast extension prototype was removed. This SwiftUI app uses PhotoKit directly for better performance on large holiday albums.
