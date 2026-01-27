#!/bin/bash
#
# create-dmg-simple.sh - Create a DMG using the create-dmg tool
#
# This script uses the 'create-dmg' Homebrew package for a simpler approach.
# Install with: brew install create-dmg
#
# Usage: ./scripts/create-dmg-simple.sh [path-to-app]
#

set -e

APP_NAME="RingBreak"
DMG_NAME="RingBreak"
VOLUME_NAME="Ring Break"
SCRIPT_DIR="$(dirname "$0")"
OUTPUT_DIR="${SCRIPT_DIR}/../build"
BACKGROUND_PNG="${SCRIPT_DIR}/dmg-resources/background.png"

# Window and icon settings
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128
APP_ICON_X=165
APP_ICON_Y=200
APPLICATIONS_ICON_X=495
APPLICATIONS_ICON_Y=200

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check for create-dmg
if ! command -v create-dmg &> /dev/null; then
    log_error "create-dmg is not installed"
    echo ""
    echo "Install it with Homebrew:"
    echo "  brew install create-dmg"
    echo ""
    echo "Or use the full script instead:"
    echo "  ./scripts/create-dmg.sh"
    echo ""
    exit 1
fi

# Find the app
find_app() {
    local app_path="$1"

    if [[ -n "$app_path" && -d "$app_path" ]]; then
        echo "$app_path"
        return 0
    fi

    local search_paths=(
        "build/Release/${APP_NAME}.app"
        "build/Debug/${APP_NAME}.app"
        "${HOME}/Library/Developer/Xcode/DerivedData/${APP_NAME}*/Build/Products/Release/${APP_NAME}.app"
        "${HOME}/Library/Developer/Xcode/DerivedData/${APP_NAME}*/Build/Products/Debug/${APP_NAME}.app"
    )

    for path in "${search_paths[@]}"; do
        for expanded_path in $path; do
            if [[ -d "$expanded_path" ]]; then
                echo "$expanded_path"
                return 0
            fi
        done
    done

    return 1
}

# Main
main() {
    echo ""
    echo "======================================"
    echo "  Ring Break DMG Creator (Simple)"
    echo "======================================"
    echo ""

    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script must be run on macOS"
        exit 1
    fi

    local app_path
    app_path=$(find_app "$1") || {
        log_error "Could not find ${APP_NAME}.app"
        echo ""
        echo "Build the app first, then run:"
        echo "  $0 /path/to/${APP_NAME}.app"
        echo ""
        exit 1
    }

    log_success "Found app: $app_path"

    mkdir -p "$OUTPUT_DIR"
    local final_dmg="${OUTPUT_DIR}/${DMG_NAME}.dmg"

    # Remove existing DMG
    rm -f "$final_dmg"

    log_info "Creating DMG..."

    # Build create-dmg arguments
    local args=(
        --volname "$VOLUME_NAME"
        --window-pos 200 120
        --window-size $WINDOW_WIDTH $WINDOW_HEIGHT
        --icon-size $ICON_SIZE
        --icon "${APP_NAME}.app" $APP_ICON_X $APP_ICON_Y
        --app-drop-link $APPLICATIONS_ICON_X $APPLICATIONS_ICON_Y
        --hide-extension "${APP_NAME}.app"
    )

    # Add background if it exists
    if [[ -f "$BACKGROUND_PNG" ]]; then
        args+=(--background "$BACKGROUND_PNG")
        log_info "Using custom background image"
    else
        log_warning "No background image found at $BACKGROUND_PNG"
        log_info "To add a background, convert the SVG to PNG:"
        log_info "  brew install librsvg"
        log_info "  rsvg-convert -w 660 -h 400 scripts/dmg-resources/background.svg -o scripts/dmg-resources/background.png"
    fi

    # Create the DMG
    create-dmg "${args[@]}" "$final_dmg" "$app_path"

    log_success "DMG created: $final_dmg"
    echo ""
}

main "$@"
