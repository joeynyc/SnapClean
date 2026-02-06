# SnapClean

A fast, native macOS screenshot tool with annotation, history, and pin-to-screen — built entirely with SwiftUI and Apple frameworks. No dependencies.

## Features

**Capture** — Region select, window pick, or full screen. Timed capture with 3/5/10s countdown. Auto-saves to `Documents/SnapClean/History` and copies to clipboard.

**Annotate** — Arrows, text, shapes, lines, freehand drawing, blur, and pixelate. Full color picker, undo/redo, and live preview before saving.

**Pin to Screen** — Float any screenshot as an always-on-top overlay with optional transparency.

**History** — Browse and manage your last 50 screenshots. Open in Finder, copy, or delete.

**Menu Bar** — Quick access from the menu bar without opening the main window.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| F1 | Capture Region |
| F2 | Capture Window |
| F3 | Capture Screen |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+S | Save |
| Cmd+C | Copy |

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 26.0 or later (for building from source)
- Screen Recording and Accessibility permissions

## Build

```bash
brew install xcodegen    # one-time setup
xcodegen generate        # generate Xcode project
./build.sh run           # build and launch
```

## License

MIT
