# SnapClean

A fast, native macOS screenshot tool with annotation, history, and pin-to-screen — built entirely with SwiftUI and Apple frameworks. No dependencies.

## Features

**Capture** — Region select, ScreenCaptureKit-backed window pick, or full screen. Timed capture with 3/5/10s countdown. Auto-saves to `Documents/SnapClean/History` and copies to clipboard.

**Annotate** — Arrows, text, shapes, lines, freehand drawing, blur, and pixelate. Full color picker, undo/redo, and live preview before saving.

**Pin to Screen** — Float any screenshot as an always-on-top overlay with optional transparency.

**History** — Browse and manage your last 50 screenshots in a dedicated macOS window. Open in Finder, copy, copy path, or delete.

**Menu Bar** — Quick access from the menu bar, with History and About available as separate app windows.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+F1 | Capture Region |
| Cmd+Shift+F2 | Capture Window |
| Cmd+Shift+F3 | Capture Screen |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+S | Save |
| Cmd+C | Copy |

## Manual QA Checklist

- Region capture saves, previews, copies when enabled, and records history.
- Window capture highlights windows and captures the selected window.
- Full-screen capture honors the configured countdown.
- History opens from the main window and menu bar, and supports copy, copy path, show in Finder, and delete.
- Annotation tools save, copy, pin, undo, and redo correctly, including blur and pixelate.
- About opens from the app menu and shows the current version/build.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 26.0 or later (for building from source)
- Screen Recording and Accessibility permissions

## Build

```bash
brew install xcodegen    # one-time setup
xcodegen generate        # generate Xcode project
./build.sh build         # debug build
./build.sh test          # run unit tests
./build.sh run           # build and launch
./build.sh archive       # create a release archive at build/SnapClean.xcarchive
```

## License

MIT
