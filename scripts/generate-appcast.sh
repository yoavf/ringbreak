#!/bin/bash
# Generates appcast.xml for Sparkle auto-updates
#
# Usage: ./generate-appcast.sh <version> <dmg_path> <signature>
#
# Arguments:
#   version   - Version string (e.g., "0.2.2")
#   dmg_path  - Path to the notarized DMG file
#   signature - EdDSA signature from sign_update tool

set -euo pipefail

VERSION="$1"
DMG_PATH="$2"
SIGNATURE="$3"

if [[ -z "$VERSION" || -z "$DMG_PATH" || -z "$SIGNATURE" ]]; then
    echo "Usage: $0 <version> <dmg_path> <signature>"
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: DMG file not found: $DMG_PATH"
    exit 1
fi

# Get file size in bytes
DMG_SIZE=$(stat -f%z "$DMG_PATH")

# Construct download URL
DMG_URL="https://github.com/yoavf/ringbreak/releases/download/v${VERSION}/RingBreak-${VERSION}.dmg"

# RFC 2822 date format for pubDate
PUB_DATE=$(date -R)

# Generate appcast.xml
cat > appcast.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>RingBreak Updates</title>
    <link>https://github.com/yoavf/ringbreak</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="${DMG_URL}"
                 length="${DMG_SIZE}"
                 type="application/octet-stream"
                 sparkle:edSignature="${SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF

echo "Generated appcast.xml for version ${VERSION}"
echo "  DMG URL: ${DMG_URL}"
echo "  DMG Size: ${DMG_SIZE} bytes"
