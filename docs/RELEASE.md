# Ring Break Release Guide

This document outlines the configuration and setup required for releasing Ring Break DMG installers via GitHub Actions.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Apple Developer Configuration](#apple-developer-configuration)
- [GitHub Secrets Configuration](#github-secrets-configuration)
- [Creating a Release](#creating-a-release)
- [Manual Releases](#manual-releases)
- [Troubleshooting](#troubleshooting)

## Overview

The CD (Continuous Deployment) workflow automatically:

1. Builds the Ring Break app with proper code signing
2. Creates a DMG installer using the custom script
3. Notarizes the DMG with Apple
4. Creates a GitHub Release with the DMG attached

## Prerequisites

Before setting up releases, you need:

- An [Apple Developer Account](https://developer.apple.com/) (requires annual membership)
- Admin access to the GitHub repository
- Xcode installed locally for certificate generation

## Apple Developer Configuration

### 1. Create a Developer ID Certificate

The Developer ID Application certificate is required for distributing apps outside the Mac App Store.

1. Open **Keychain Access** on your Mac
2. Go to **Keychain Access > Certificate Assistant > Request a Certificate from a Certificate Authority**
3. Enter your email and select **Saved to disk**
4. Log in to [Apple Developer Portal](https://developer.apple.com/account)
5. Navigate to **Certificates, Identifiers & Profiles > Certificates**
6. Click **+** to create a new certificate
7. Select **Developer ID Application** and continue
8. Upload your Certificate Signing Request (CSR)
9. Download and install the certificate by double-clicking it

### 2. Export the Certificate as .p12

1. Open **Keychain Access**
2. Find your **Developer ID Application** certificate under **My Certificates**
3. Expand the certificate to see the private key
4. Select both the certificate and private key
5. Right-click and choose **Export 2 items...**
6. Save as `.p12` format
7. Set a strong password (you'll need this for `P12_PASSWORD`)

### 3. Generate App-Specific Password

For notarization, you need an app-specific password:

1. Go to [appleid.apple.com](https://appleid.apple.com/)
2. Sign in and go to **Sign-In and Security > App-Specific Passwords**
3. Click **Generate an app-specific password**
4. Name it something like "GitHub Actions RingBreak"
5. Save the generated password (you'll need this for `APPLE_APP_PASSWORD`)

### 4. Find Your Team ID

1. Log in to [Apple Developer Portal](https://developer.apple.com/account)
2. Go to **Membership Details**
3. Your Team ID is listed there (10-character alphanumeric string)

## GitHub Secrets Configuration

Navigate to your repository's **Settings > Secrets and variables > Actions** and add the following secrets:

### Required Secrets

| Secret Name | Description | How to Get It |
|-------------|-------------|---------------|
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded .p12 certificate | See [Encoding Certificate](#encoding-certificate) |
| `P12_PASSWORD` | Password for the .p12 file | The password you set when exporting |
| `KEYCHAIN_PASSWORD` | Temporary keychain password | Any secure random string |
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID | 10-character ID from Apple Developer Portal |
| `CODE_SIGN_IDENTITY` | Certificate name for signing | `Developer ID Application: Your Name (TEAM_ID)` |
| `APPLE_ID` | Your Apple ID email | Your Apple Developer account email |
| `APPLE_APP_PASSWORD` | App-specific password | Generated from appleid.apple.com |
| `APPLE_TEAM_ID` | Your Apple Team ID | Same as `DEVELOPMENT_TEAM` |

### Encoding Certificate

To encode your .p12 certificate as base64, run:

```bash
base64 -i path/to/certificate.p12 | pbcopy
```

This copies the base64-encoded certificate to your clipboard. Paste it as the value for `BUILD_CERTIFICATE_BASE64`.

### Finding CODE_SIGN_IDENTITY

To find the exact certificate name:

```bash
security find-identity -v -p codesigning
```

Look for a line like:
```
"Developer ID Application: John Doe (ABC123XYZ)"
```

Use the full string in quotes as your `CODE_SIGN_IDENTITY`.

## Creating a Release

### Automatic Release (Recommended)

Releases are automatically triggered when you push a version tag:

```bash
# Ensure you're on the main branch with latest changes
git checkout main
git pull origin main

# Create and push a version tag
git tag v1.0.0
git push origin v1.0.0
```

The workflow will:
1. Build and sign the app
2. Create the DMG
3. Notarize with Apple
4. Create a GitHub Release with the DMG attached

### Version Tag Format

Use semantic versioning: `v{MAJOR}.{MINOR}.{PATCH}`

- `v1.0.0` - Major release
- `v1.1.0` - Minor release with new features
- `v1.1.1` - Patch release with bug fixes
- `v2.0.0-beta.1` - Pre-release (marked as pre-release on GitHub)

## Manual Releases

### Via GitHub UI

1. Go to **Actions** tab in the repository
2. Select **CD - Release DMG** workflow
3. Click **Run workflow**
4. Enter the version number (without 'v' prefix)
5. Click **Run workflow**

### Local DMG Creation

For testing or local distribution:

```bash
# Build the app in Xcode first (Product > Build)
# Or build from command line:
xcodebuild build \
  -project RingBreak.xcodeproj \
  -scheme RingBreak \
  -configuration Release \
  -derivedDataPath DerivedData

# Create the DMG
./scripts/create-dmg.sh "DerivedData/Build/Products/Release/RingBreak.app"
```

The DMG will be created at `build/RingBreak.dmg`.

## Workflow Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Push Tag      │────▶│  GitHub Actions  │────▶│  GitHub Release │
│   v1.0.0        │     │  CD Workflow     │     │  with DMG       │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │  Build Steps:    │
                        │  1. Checkout     │
                        │  2. Setup Xcode  │
                        │  3. Code Sign    │
                        │  4. Build App    │
                        │  5. Create DMG   │
                        │  6. Notarize     │
                        │  7. Release      │
                        └──────────────────┘
```

## Troubleshooting

### Certificate Issues

**"No signing certificate found"**
- Verify `BUILD_CERTIFICATE_BASE64` is correctly encoded
- Ensure the certificate hasn't expired
- Check that `CODE_SIGN_IDENTITY` matches exactly

**"Code signature invalid"**
- The certificate may not be a Developer ID Application certificate
- Ensure the private key was exported with the certificate

### Notarization Issues

**"Unable to authenticate"**
- Verify `APPLE_ID` is correct
- Regenerate `APPLE_APP_PASSWORD`
- Ensure 2FA is enabled on your Apple ID

**"Package Invalid"**
- Check that hardened runtime is enabled
- Ensure all binaries are properly signed
- Review notarization log for specific issues:

```bash
xcrun notarytool log <submission-id> \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "TEAM_ID"
```

### Build Issues

**"No such module"**
- Ensure Git LFS files are pulled: `git lfs pull`
- Clean derived data: `rm -rf DerivedData`

**"Provisioning profile not found"**
- For Developer ID distribution, no provisioning profile is needed
- Ensure `CODE_SIGN_STYLE` is set to `Manual`

### DMG Creation Issues

**"Could not find RingBreak.app"**
- Verify the build succeeded
- Check the app exists at `build/Release/RingBreak.app`

**"hdiutil: create failed"**
- Ensure sufficient disk space
- Try increasing the DMG size buffer in `create-dmg.sh`

## Security Best Practices

1. **Rotate Secrets Regularly**: Update your app-specific password periodically
2. **Use Environment Protection**: Consider requiring approval for production releases
3. **Monitor Notarization**: Apple may revoke notarization if malware is detected
4. **Backup Certificates**: Store your .p12 file securely offline
5. **Certificate Expiration**: Developer ID certificates expire after 5 years

## Additional Resources

- [Apple Developer Documentation - Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [GitHub Actions - Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
