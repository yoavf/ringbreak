# CLAUDE.md — Ring Break

## Project Overview

Ring Break is a **macOS menu bar application** (Swift/SwiftUI) that provides quick desk exercise breaks using a Nintendo Ring-Con controller. It connects to a Joy-Con (R) via Bluetooth/HID, reads flex sensor data from the attached Ring-Con, and guides users through squeeze/pull exercises with rep tracking, streaks, and scheduled reminders.

**Repository:** https://github.com/yoavf/ringbreak
**License:** MIT
**Min macOS:** 13.0 (Ventura)
**Current Version:** 0.1.0

## Tech Stack

- **Language:** Swift (100% Swift codebase)
- **UI:** SwiftUI + AppKit (menu bar integration, window management)
- **3D Graphics:** SceneKit (Ring-Con visualization)
- **Device I/O:** IOKit HID, IOBluetooth, CoreBluetooth
- **Reactive:** Combine framework + Swift Concurrency (async/await)
- **Persistence:** UserDefaults (no database)
- **Notifications:** UserNotifications framework
- **Build System:** Xcode / xcodebuild
- **Distribution:** DMG installers (notarized via Apple)
- **Large Files:** Git LFS (`.scn` 3D model files)

## Directory Structure

```
RingBreak/
├── App/                        # App-level controllers and constants
│   ├── Constants.swift         # Thresholds, timers, URLs
│   ├── MenubarController.swift # NSStatusItem menu bar management
│   └── UserDefaultsKeys.swift  # Centralized UserDefaults key strings
├── Components/                 # Reusable UI components
│   ├── ConnectionStatus.swift  # Connection status indicator
│   ├── RingBreakLogo.swift     # Logo component
│   └── RingConSceneView.swift  # 3D Ring-Con SceneKit view
├── Game/
│   └── BreakGameState.swift    # State machine, rep detection, stats, streaks
├── RingConDriver/              # Bluetooth/HID device communication
│   ├── RingConManager.swift    # High-level device management (1054 lines, largest file)
│   ├── JoyConHID.swift         # Low-level IOKit HID read/write
│   ├── RingConState.swift      # State models (flex, IMU, orientation)
│   ├── MCUProtocol.swift       # HID report IDs and subcommand definitions
│   └── DebugLogger.swift       # Category-based debug logging
├── Services/
│   └── NotificationService.swift # Local notification scheduling/reminders
├── Theme/
│   └── AppColors.swift         # Centralized color definitions
├── Views/                      # SwiftUI screens
│   ├── ContentView.swift       # Root view (onboarding check)
│   ├── RingBreakView.swift     # Main navigation container
│   ├── ReadyView.swift         # Ready/countdown state
│   ├── ExerciseView.swift      # Active exercise gameplay
│   ├── CalibrationView.swift   # Ring-Con calibration flow
│   ├── CelebrationView.swift   # Session completion
│   ├── SettingsView.swift      # Settings (difficulty, notifications, dock/menubar)
│   ├── StreakGraphView.swift    # Weekly exercise history graph
│   ├── NotConnectedView.swift  # No controller state
│   └── OnboardingView.swift    # First-time setup
├── Resources/
│   ├── Assets.xcassets/        # Icons, colors, images
│   ├── Onboarding/             # Onboarding image assets
│   ├── ringcon2.scn            # 3D Ring-Con model (Git LFS)
│   └── texture_pbr_20250901.png # PBR texture (~17MB)
├── RingBreakApp.swift          # @main entry point + AppDelegate
└── Info.plist                  # Bluetooth and notification permission strings
```

Other top-level files:
```
RingBreak.xcodeproj/            # Xcode project and schemes
scripts/create-dmg.sh           # DMG installer creation script
scripts/dmg-resources/          # DMG background image and DS_Store layout
docs/RELEASE.md                 # Release process documentation
.github/workflows/ci.yml        # CI: build verification
.github/workflows/cd.yml        # CD: signed DMG release + notarization
.gitattributes                  # Git LFS tracking for *.scn
```

## Build & Run

### Prerequisites

```bash
brew install git-lfs
git lfs install
git lfs pull
```

### Build from command line

```bash
xcodebuild build \
  -project RingBreak.xcodeproj \
  -scheme RingBreak \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData
```

For CI (no code signing):
```bash
xcodebuild build \
  -project RingBreak.xcodeproj \
  -scheme RingBreak \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

### Run

Open `RingBreak.xcodeproj` in Xcode and press Cmd+R, or run the built binary directly:
```bash
./DerivedData/Build/Products/Release/RingBreak.app/Contents/MacOS/RingBreak
```

### Create DMG

```bash
./scripts/create-dmg.sh "DerivedData/Build/Products/Release/RingBreak.app"
# Output: build/RingBreak.dmg
```

### Tests

There is no automated test suite. CI runs build verification only. Testing requires physical Joy-Con (R) + Ring-Con hardware.

## Architecture

### High-level data flow

```
Joy-Con HID Device (Bluetooth)
        │
        ▼
  JoyConHID.swift          ← Low-level IOKit HID enumeration, read/write
        │
        ▼
  RingConManager.swift     ← Connection state machine, calibration, IMU processing
        │
        ▼
  BreakGameState.swift     ← Game phases, rep detection, statistics, streaks
        │
        ▼
  SwiftUI Views            ← ExerciseView, CelebrationView, etc.
        │
        ▼
  MenubarController.swift  ← Menu bar status item, last exercise time
  NotificationService.swift ← Scheduled exercise reminders
```

### Key concepts

- **Flex sensor:** Single byte (0x00-0x14) at HID report byte 40, normalized to 0.0-1.0 range
- **Game phases:** `notConnected → ready → squeezePhase ⟷ pullPhase → celebration`
- **Rep detection:** Flex value must exceed difficulty threshold and be held for `Constants.holdDuration` seconds
- **Calibration:** 3-step process — neutral hold (5s), pull (5s), squeeze (5s) — values saved to UserDefaults
- **Ring-Con init sequence:** Enable IMU → Set IMU sensitivity → Set input report mode → Enable MCU → Configure Ring-Con mode → Start polling

### State management pattern

- `@MainActor` classes with `ObservableObject` conformance
- `@Published` properties for reactive UI updates
- `@StateObject` at ownership boundaries, `@ObservedObject` for passed references
- `UserDefaults` for all persistence (keys centralized in `UserDefaultsKeys`)
- `NotificationCenter` for cross-component communication (e.g., `.sessionCompleted`)

## Code Conventions

### Naming

- **Types:** `PascalCase` — classes, structs, enums, protocols
- **Properties/methods:** `camelCase`
- **Enum cases:** `camelCase` (e.g., `squeezePhase`, `notConnected`)
- **Constants:** Static properties on caseless enums (`Constants`, `AppColors`, `UserDefaultsKeys`)
- **File names:** Match the primary type they contain

### File structure

Each Swift file follows this header pattern:
```swift
//
//  FileName.swift
//  RingBreak
//
//  Brief description of the file's purpose
//
```

Code sections use `// MARK: -` comments for organization.

### Patterns used

- **Caseless enums as namespaces** for constants: `enum Constants`, `enum AppColors`, `enum UserDefaultsKeys`
- **@MainActor** on all ObservableObject classes for thread safety
- **Delegate protocol** for HID callbacks (`JoyConHIDDelegate`)
- **Combine** publishers for reactive state
- **async/await** with `Task {}` blocks for async operations
- **View extensions** for reusable modifiers (e.g., `appBackground(for:)`)

### No external dependencies

The project uses zero third-party packages. All functionality is built on Apple frameworks only.

## CI/CD

### CI (`.github/workflows/ci.yml`)

- **Triggers:** Push to main/master, PRs targeting main/master
- **Runner:** macOS 14
- **Action:** Build verification only (no signing, no tests)

### CD (`.github/workflows/cd.yml`)

- **Triggers:** Version tags (`v*.*.*`) or manual workflow dispatch
- **Runner:** macOS 14
- **Steps:** Build → Code sign → Create DMG → Notarize with Apple → Staple → Create GitHub Release
- **Versioning:** Semantic versioning via git tags (`v1.0.0`, `v1.1.0-beta.1`)

See `docs/RELEASE.md` for full release process documentation including certificate setup and GitHub secrets.

## Important Files for Common Tasks

| Task | Key files |
|------|-----------|
| Add a new view/screen | `RingBreak/Views/`, wire into `RingBreakView.swift` |
| Modify exercise logic | `BreakGameState.swift`, `Constants.swift` |
| Change device communication | `RingConManager.swift`, `JoyConHID.swift`, `MCUProtocol.swift` |
| Update colors/theme | `AppColors.swift`, `Assets.xcassets` |
| Add a UserDefaults key | `UserDefaultsKeys.swift` (add key), then use in relevant class |
| Modify menu bar behavior | `MenubarController.swift` |
| Change notifications | `NotificationService.swift` |
| Update app permissions | `Info.plist` |
| Modify CI build | `.github/workflows/ci.yml` |
| Modify release process | `.github/workflows/cd.yml`, `scripts/create-dmg.sh` |

## Gotchas & Notes

- **Git LFS required:** The 3D Ring-Con model (`ringcon2.scn`) is tracked with Git LFS. Always run `git lfs pull` after cloning or the app will fail to load the 3D view.
- **Hardware-dependent:** Most features cannot be tested without a physical Joy-Con (R) + Ring-Con. The HID driver communicates directly via IOKit.
- **Menu bar app behavior:** The app hides rather than closes when the window is dismissed, keeping the menu bar icon active. Window restoration logic lives in `AppDelegate.openMainWindow()`.
- **No test suite:** There are no unit or UI tests. Validate changes by building successfully and manual testing where possible.
- **Single-scheme Xcode project:** One build scheme (`RingBreak`) for both Debug and Release configurations.
- **macOS only:** This is exclusively a macOS app (13.0+). No iOS/iPadOS support.
- **Largest/most complex file:** `RingConManager.swift` (~1054 lines) handles the entire device lifecycle — approach changes to this file carefully.
