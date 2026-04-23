# Cliptara

Menu bar app for screenshots and screen recording.

## Hotkeys

- `Ctrl+\``: area screenshot
- `Ctrl+1`: full-screen screenshot
- `Ctrl+2`: start/stop video recording

All hotkeys are configurable in Settings.

## Default save folders

- Screenshots: `~/Documents/cliptaramaterials/Screenshots`
- Videos: `~/Documents/cliptaramaterials/Videos`

Screenshot action can be switched between:

- copy to clipboard
- save to files

## Build & Run

```bash
cd /Volumes/JINNLIVEUSB/Cliptara/shot
swift build -c release
.build/release/Cliptara
```

## Updates (GitHub Releases)

The app supports `Check for updates...` from the menu bar.

1. Upload new `Cliptara.dmg` to GitHub Release.
2. Publish `update.json` (use [update-manifest.example.json](./update-manifest.example.json) as template).
3. Build app with manifest URL:

```bash
cd /Volumes/JINNLIVEUSB/Cliptara/shot
UPDATE_MANIFEST_URL="https://raw.githubusercontent.com/medusa4111/Cliptara/main/update.json" ./package_cliptara_dmg.sh
```
