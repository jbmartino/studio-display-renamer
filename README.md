# Studio Display Renamer

A lightweight macOS menu bar app for managing audio devices — built for people with multiple Apple Studio Displays that share identical names.

![Menu Bar](screenshots/menubar.png) ![Settings](screenshots/settings.png)

## Features

- **One-click switching** — set default input, output, or both from the menu bar
- **Custom device names** — rename "Studio Display Speakers" to "Left Desk" / "Right Desk"
- **Paired device grouping** — Studio Display speaker + mic are linked, name once and set both together
- **Auto-restore** — your preferred device is automatically re-selected when reconnected
- **Device testing** — play test sounds through speakers, monitor mic input levels
- **Persistent preferences** — settings survive app restarts

## Install

### Download

1. Grab the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag **StudioDisplayRenamer** to Applications
3. Launch from Applications (first time: right-click > Open to bypass Gatekeeper)

### Build from source

Requires macOS 14+ and Swift 5.9+.

```bash
git clone https://github.com/jbmartino/studio-display-renamer.git
cd studio-display-renamer
bash scripts/build-dmg.sh
open StudioDisplayRenamer.app
```

## Usage

1. Click the speaker icon (🔊) in the menu bar
2. **Use Both** — sets a paired device as both input and output
3. **Output / Input** — set them independently
4. **Settings (⌘,)** — rename devices, test speakers and mics
5. Add to **System Settings > General > Login Items** to launch at startup

## How it works

Each Apple Studio Display has a unique hardware serial embedded in its CoreAudio UID (e.g., `A1498802E` vs `C2210802E`). Studio Display Renamer uses these to tell identical-name devices apart and pairs speakers with their corresponding microphone automatically.

## Requirements

- macOS 14 (Sonoma) or later
- No Apple Developer account needed for personal use
