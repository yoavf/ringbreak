# Ring Break

A macOS menu bar app for quick exercise breaks using the Nintendo Ring-Con controller.

![AppShowcase](https://github.com/user-attachments/assets/bbff4cae-deb7-4608-946f-9dd6c2e73258)

## Requirements

- macOS 13.0 or later
- Nintendo Joy-Con (R) controller
- Nintendo Ring-Con accessory
- Bluetooth

## Setup

1. Open System Settings > Bluetooth
2. Put Joy-Con (R) into pairing mode by holding the sync button until lights flash
3. Pair the Joy-Con in Bluetooth settings
4. Slide the Joy-Con into the Ring-Con rail until it clicks
5. Launch Ring Break and click "Connect"

## Building

This project uses Git LFS for large files. Install it before cloning:

```bash
brew install git-lfs
git lfs install
```

The repo includes a custom 3D model of the Ring-Con (hand-crafted with love) which is required for the app to run.

Open `RingBreak.xcodeproj` in Xcode and build the project.

## Usage

- Connect your Ring-Con and press Start
- Complete squeeze and pull exercises
- The app tracks daily sessions and streaks
- Optional reminders can be enabled in Settings

## Disclaimer

This project is not affiliated with, endorsed by, or connected to Nintendo in any way. We just really like squeezing their ring.

## License

MIT License - see [LICENSE](LICENSE) for details.
