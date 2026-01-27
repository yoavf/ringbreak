#!/bin/bash
#
# create-dmg.sh - Create a DMG installer for Ring Break
#
# This script creates a professional DMG image with:
# - The Ring Break app
# - An alias to the Applications folder
# - A custom background with drag-to-install instructions
#
# Usage: ./scripts/create-dmg.sh [path-to-app]
#
# If no path is provided, it will look for the app in common build locations.
#

set -e

# Configuration
APP_NAME="RingBreak"
DMG_NAME="RingBreak"
VOLUME_NAME="Ring Break"
DMG_RESOURCES_DIR="$(dirname "$0")/dmg-resources"
OUTPUT_DIR="$(dirname "$0")/../build"
BACKGROUND_SVG="${DMG_RESOURCES_DIR}/background.svg"
BACKGROUND_PNG="${DMG_RESOURCES_DIR}/background.png"

# DMG window dimensions (should match background image)
WINDOW_WIDTH=660
WINDOW_HEIGHT=400

# Icon positions (centered vertically, with arrow between them)
APP_ICON_X=165
APP_ICON_Y=200
APPLICATIONS_ICON_X=495
APPLICATIONS_ICON_Y=200
ICON_SIZE=128

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Find the app bundle
find_app() {
    local app_path="$1"

    if [[ -n "$app_path" && -d "$app_path" ]]; then
        echo "$app_path"
        return 0
    fi

    # Common build locations
    local search_paths=(
        "build/Release/${APP_NAME}.app"
        "build/Debug/${APP_NAME}.app"
        "DerivedData/Build/Products/Release/${APP_NAME}.app"
        "DerivedData/Build/Products/Debug/${APP_NAME}.app"
        "${HOME}/Library/Developer/Xcode/DerivedData/${APP_NAME}*/Build/Products/Release/${APP_NAME}.app"
        "${HOME}/Library/Developer/Xcode/DerivedData/${APP_NAME}*/Build/Products/Debug/${APP_NAME}.app"
    )

    for path in "${search_paths[@]}"; do
        # Use glob expansion
        for expanded_path in $path; do
            if [[ -d "$expanded_path" ]]; then
                echo "$expanded_path"
                return 0
            fi
        done
    done

    return 1
}

# Convert SVG to PNG (requires rsvg-convert or qlmanage)
convert_background() {
    if [[ -f "$BACKGROUND_PNG" ]]; then
        log_info "Background PNG already exists, skipping conversion"
        return 0
    fi

    if ! [[ -f "$BACKGROUND_SVG" ]]; then
        log_warning "No background SVG found at $BACKGROUND_SVG"
        return 1
    fi

    log_info "Converting background SVG to PNG..."

    # Try rsvg-convert first (from librsvg)
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -w $WINDOW_WIDTH -h $WINDOW_HEIGHT "$BACKGROUND_SVG" -o "$BACKGROUND_PNG"
        log_success "Background converted using rsvg-convert"
        return 0
    fi

    # Try qlmanage (built into macOS)
    if command -v qlmanage &> /dev/null; then
        qlmanage -t -s ${WINDOW_WIDTH} -o "${DMG_RESOURCES_DIR}" "$BACKGROUND_SVG" 2>/dev/null
        if [[ -f "${DMG_RESOURCES_DIR}/background.svg.png" ]]; then
            mv "${DMG_RESOURCES_DIR}/background.svg.png" "$BACKGROUND_PNG"
            log_success "Background converted using qlmanage"
            return 0
        fi
    fi

    # Try sips with a temporary HTML approach
    if command -v /usr/bin/python3 &> /dev/null; then
        /usr/bin/python3 << EOF
import subprocess
import os

# Create a simple HTML wrapper for the SVG
html_content = f'''<!DOCTYPE html>
<html><head><style>body{{margin:0;padding:0;}}</style></head>
<body><img src="file://{os.path.abspath("$BACKGROUND_SVG")}" width="{$WINDOW_WIDTH}" height="{$WINDOW_HEIGHT}"></body></html>'''

# This is a fallback - in practice, you may need to install rsvg-convert
print("SVG conversion requires additional tools. Please install librsvg:")
print("  brew install librsvg")
EOF
        log_warning "SVG conversion requires librsvg. Install with: brew install librsvg"
        log_warning "Or manually convert the SVG to PNG and place it at: $BACKGROUND_PNG"
        return 1
    fi

    log_warning "Could not convert SVG to PNG. Background will be skipped."
    return 1
}

# Create the DMG
create_dmg() {
    local app_path="$1"
    local temp_dir
    local temp_dmg
    local final_dmg

    # Setup paths
    mkdir -p "$OUTPUT_DIR"
    temp_dir=$(mktemp -d)
    temp_dmg="${temp_dir}/${DMG_NAME}-temp.dmg"
    final_dmg="${OUTPUT_DIR}/${DMG_NAME}.dmg"

    log_info "Creating DMG installer..."
    log_info "App source: $app_path"
    log_info "Output: $final_dmg"

    # Remove existing DMG
    if [[ -f "$final_dmg" ]]; then
        log_info "Removing existing DMG..."
        rm -f "$final_dmg"
    fi

    # Create staging directory
    local staging_dir="${temp_dir}/staging"
    mkdir -p "$staging_dir"

    # Copy app to staging
    log_info "Copying app to staging area..."
    cp -R "$app_path" "$staging_dir/"

    # Create Applications symlink
    log_info "Creating Applications folder alias..."
    ln -s /Applications "$staging_dir/Applications"

    # Copy background if available
    local background_file=""
    if [[ -f "$BACKGROUND_PNG" ]]; then
        mkdir -p "$staging_dir/.background"
        cp "$BACKGROUND_PNG" "$staging_dir/.background/background.png"
        background_file=".background/background.png"
        log_info "Background image added"
    fi

    # Calculate DMG size (app size + 20MB buffer)
    local app_size
    app_size=$(du -sm "$app_path" | cut -f1)
    local dmg_size=$((app_size + 20))
    log_info "App size: ${app_size}MB, DMG size: ${dmg_size}MB"

    # Create temporary DMG
    log_info "Creating temporary DMG..."
    hdiutil create \
        -srcfolder "$staging_dir" \
        -volname "$VOLUME_NAME" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        -format UDRW \
        -size ${dmg_size}m \
        "$temp_dmg"

    # Mount the DMG
    log_info "Mounting DMG for customization..."
    local device
    device=$(hdiutil attach -readwrite -noverify -noautoopen "$temp_dmg" | grep -E '^/dev/' | head -1 | awk '{print $1}')
    local mount_point="/Volumes/${VOLUME_NAME}"

    # Wait for mount
    sleep 2

    if [[ ! -d "$mount_point" ]]; then
        log_error "Failed to mount DMG at $mount_point"
        hdiutil detach "$device" 2>/dev/null || true
        rm -rf "$temp_dir"
        exit 1
    fi

    # Apply custom view settings using AppleScript
    log_info "Configuring Finder view settings..."

    # Build the AppleScript
    local applescript="
tell application \"Finder\"
    tell disk \"${VOLUME_NAME}\"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, $((100 + WINDOW_WIDTH)), $((100 + WINDOW_HEIGHT))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to ${ICON_SIZE}"

    # Add background if available
    if [[ -n "$background_file" ]]; then
        applescript+="
        set background picture of viewOptions to file \"${background_file}\""
    fi

    applescript+="
        set position of item \"${APP_NAME}.app\" of container window to {${APP_ICON_X}, ${APP_ICON_Y}}
        set position of item \"Applications\" of container window to {${APPLICATIONS_ICON_X}, ${APPLICATIONS_ICON_Y}}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
"

    # Run AppleScript
    echo "$applescript" | osascript || log_warning "AppleScript customization may have partially failed"

    # Give Finder time to write changes
    sync
    sleep 3

    # Unmount
    log_info "Unmounting temporary DMG..."
    hdiutil detach "$device" -force || {
        sleep 5
        hdiutil detach "$device" -force
    }

    # Convert to compressed DMG
    log_info "Creating final compressed DMG..."
    hdiutil convert "$temp_dmg" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$final_dmg"

    # Cleanup
    log_info "Cleaning up temporary files..."
    rm -rf "$temp_dir"

    log_success "DMG created successfully: $final_dmg"

    # Print DMG info
    local final_size
    final_size=$(du -h "$final_dmg" | cut -f1)
    log_info "Final DMG size: $final_size"
}

# Main
main() {
    echo ""
    echo "======================================"
    echo "  Ring Break DMG Installer Creator"
    echo "======================================"
    echo ""

    # Check if running on macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script must be run on macOS"
        exit 1
    fi

    # Find the app
    local app_path
    app_path=$(find_app "$1") || {
        log_error "Could not find ${APP_NAME}.app"
        echo ""
        echo "Please either:"
        echo "  1. Build the app first in Xcode (Product > Archive or Product > Build)"
        echo "  2. Specify the path to the .app bundle:"
        echo "     $0 /path/to/${APP_NAME}.app"
        echo ""
        exit 1
    }

    log_success "Found app: $app_path"

    # Convert background image if needed
    convert_background || true

    # Create the DMG
    create_dmg "$app_path"

    echo ""
    log_success "Done! Your DMG installer is ready."
    echo ""
}

main "$@"
