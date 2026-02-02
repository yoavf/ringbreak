#!/bin/bash
#
# bump-version.sh - Update MARKETING_VERSION in Xcode project from git tag
#
# Usage:
#   ./scripts/bump-version.sh          # Uses latest git tag (strips leading 'v')
#   ./scripts/bump-version.sh 0.3.0    # Sets specific version
#

set -e

PBXPROJ="$(dirname "$0")/../RingBreak.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
    echo "Error: project.pbxproj not found at $PBXPROJ"
    exit 1
fi

if [[ -n "$1" ]]; then
    NEW_VERSION="$1"
else
    # Get latest git tag, strip leading 'v'
    TAG=$(git describe --tags --abbrev=0 2>/dev/null) || {
        echo "Error: No git tags found. Pass a version explicitly: $0 0.2.0"
        exit 1
    }
    NEW_VERSION="${TAG#v}"
fi

# Validate semver-ish format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: '$NEW_VERSION' is not a valid version (expected X.Y.Z)"
    exit 1
fi

CURRENT=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;.*//')

if [[ "$CURRENT" == "$NEW_VERSION" ]]; then
    echo "Version is already $NEW_VERSION"
    exit 0
fi

sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"

echo "Updated MARKETING_VERSION: $CURRENT → $NEW_VERSION"
