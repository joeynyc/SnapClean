# SnapClean

SnapClean is a native macOS screenshot app for capturing, annotating, saving, and pinning screenshots. It is built with SwiftUI and Apple frameworks only, with no third-party runtime dependencies.

![SnapClean app icon](SnapClean/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

## Features

- **Flexible capture modes:** Capture a selected region, a specific window, or the full screen.
- **Modern capture pipeline:** Uses ScreenCaptureKit for current macOS screen capture behavior.
- **Annotation tools:** Add arrows, text, rectangles, ovals, lines, freehand drawings, blur, and pixelation.
- **Undo and redo:** Iterate on annotations before saving or copying.
- **Screenshot history:** Keeps the latest 50 screenshots and stores image files in `~/Documents/SnapClean/History`.
- **Pin to screen:** Float a screenshot above other windows for reference.
- **Menu bar access:** Start captures and open history from the macOS menu bar.
- **Native macOS windows:** Dedicated windows for the main app, history, preferences, and about view.

## Requirements

- macOS 14.0 Sonoma or later
- Xcode 26.0 or later
- XcodeGen for project generation
- Screen Recording permission for capture
- Accessibility permission for global keyboard shortcuts

Install XcodeGen with Homebrew:

```bash
brew install xcodegen
```

## Build From Source

Generate the Xcode project after cloning and any time `project.yml` changes:

```bash
xcodegen generate
```

Build, test, and run from the command line:

```bash
./build.sh build
./build.sh test
./build.sh run
```

Other build commands:

```bash
./build.sh clean
./build.sh archive
```

`./build.sh run` launches the newest Debug build from Xcode DerivedData so stale archives are not accidentally opened.

## Continuous Integration

GitHub Actions runs the same generated-project test path used locally:

```bash
xcodegen generate
./build.sh test
```

The workflow lives at `.github/workflows/ci.yml`.

## Code Signing

The project is configured for Apple Development signing in `project.yml`.

```yaml
CODE_SIGN_IDENTITY: Apple Development
```

If you are building under a different Apple Developer account, update `DEVELOPMENT_TEAM` in `project.yml`, run `xcodegen generate`, and rebuild.

Stable signing matters for macOS privacy permissions. If the app is built with ad-hoc signing, macOS may repeatedly ask for Screen Recording access after rebuilds.

## Permissions

SnapClean needs Screen Recording permission to capture your display. It may also request Accessibility permission for global hotkeys.

To grant Screen Recording permission:

1. Open System Settings.
2. Go to Privacy & Security.
3. Open Screen & System Audio Recording.
4. Enable SnapClean.
5. Quit and reopen SnapClean.

If SnapClean still reports that Screen Recording is blocked, remove or toggle the SnapClean entry in System Settings, add the current built app again, and relaunch.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| Cmd+Shift+F1 | Capture Region |
| Cmd+Shift+F2 | Capture Window |
| Cmd+Shift+F3 | Capture Screen |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+S | Save |
| Cmd+C | Copy |

## Project Structure

```text
SnapClean/
  Models/          App state and screenshot models
  Services/        Capture, hotkey, and persistence services
  Views/           SwiftUI windows, overlays, and annotation UI
SnapCleanTests/    Unit tests
project.yml        XcodeGen project definition
build.sh           Build, test, run, archive, and clean helper
```

## Testing

Run the unit test suite with:

```bash
./build.sh test
```

Manual verification should cover:

- Region capture opens the annotation editor with the correct image orientation.
- Window capture selects real app windows, not desktop surfaces.
- Full-screen capture works after Screen Recording permission is granted.
- Save adds a screenshot to history.
- Copy writes the screenshot to the clipboard.
- Pin creates an always-on-top reference window.
- Blur and pixelate annotations render into saved output.
- History supports open, copy, copy path, show in Finder, and delete.
- Permissions UI correctly recovers after opening System Settings and rechecking access.

## License

SnapClean is available under the MIT License. See [LICENSE](LICENSE).

## Release Notes

See [docs/RELEASE.md](docs/RELEASE.md) for the release checklist, signing notes, and distribution guidance.
