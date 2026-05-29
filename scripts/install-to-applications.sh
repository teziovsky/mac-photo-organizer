#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SOURCE_APP_NAME="MediaOrganizer"
DEST_APP_NAME="Media Organizer"
BUILD_APP="build/DerivedData/Build/Products/Release/${SOURCE_APP_NAME}.app"
INSTALL_PATH="/Applications/${DEST_APP_NAME}.app"
OPEN_AFTER=false

usage() {
	cat <<EOF
Usage: $(basename "$0") [options]

Build a Release .app and install it to ${INSTALL_PATH}.

Options:
  --open    Launch the app after installing
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--open)
		OPEN_AFTER=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

echo "Building ${DEST_APP_NAME} (Release)..."
xcodebuild \
	-project MediaOrganizer.xcodeproj \
	-scheme MediaOrganizer \
	-configuration Release \
	-derivedDataPath build/DerivedData \
	build \
	CODE_SIGNING_ALLOWED=NO

if [[ ! -d "$BUILD_APP" ]]; then
	echo "Build failed: ${BUILD_APP} not found" >&2
	exit 1
fi

echo "Installing to ${INSTALL_PATH}..."
ditto "$BUILD_APP" "$INSTALL_PATH"

echo "Installed ${INSTALL_PATH}"

if [[ "$OPEN_AFTER" == true ]]; then
	open "$INSTALL_PATH"
fi
