# SnapClean

A beautiful, native macOS screenshot app built with SwiftUI to compete with CleanShot X.

## Features

### Screenshot Capture
- **Region selection** - Drag to capture a custom area
- **Window selection** - Click to capture any window
- **Full screen capture** - Capture the entire screen
- **Timed capture** - 3, 5, or 10 second countdown
- **Clipboard integration** - Copy instantly to clipboard
- **Auto-save** - Saves to Downloads folder

### Annotation Tools
- Arrow tool with customizable direction
- Text tool with font picker
- Rectangle and Oval shapes
- Line and Pencil drawing
- Blur/Pixelate for sensitive info
- Color picker with custom colors
- Undo/Redo support

### UI/UX
- Beautiful floating toolbar with glass effect (macOS 26+)
- Keyboard shortcuts (F1, F2, F3, ⌘Z, ⌘S, ⌘C)
- Preview before saving
- History strip of recent screenshots

### Pin to Screen
- Pin screenshots as desktop overlays
- Always on top functionality
- Transparent background option

### Quick Actions
- Copy to clipboard
- Save to disk
- Open in Finder
- Delete

## Requirements

- macOS 14.0 (Sonoma) or later
- macOS 26.0+ for Liquid Glass effects

## Building

### Prerequisites
- Xcode 15.0 or later
- XcodeGen (install via Homebrew: `brew install xcodegen`)

### Setup
```bash
# Generate the Xcode project
xcodegen generate

# Build the project
./build.sh build

# Build and run
./build.sh run
```

### Manual Build
```bash
cd /Users/joeyrodriguez/clawd/SnapClean
xcodegen generate
xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug build
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| F1 | Capture Region |
| F2 | Capture Window |
| F3 | Capture Screen |
| ⌘Z | Undo |
| ⌘⇧Z | Redo |
| ⌘S | Save |
| ⌘C | Copy |

## Project Structure

```
SnapClean/
├── SnapClean.xcodeproj/
├── SnapClean/
│   ├── SnapCleanApp.swift
│   ├── AppDelegate.swift
│   ├── Views/
│   │   ├── MainWindow.swift
│   │   ├── CaptureOverlay.swift
│   │   ├── AnnotationCanvas.swift
│   │   ├── ToolbarView.swift
│   │   ├── HistoryPanel.swift
│   │   ├── PinWindow.swift
│   │   ├── PreferencesView.swift
│   │   ├── MenuBarView.swift
│   │   └── Components/
│   │       └── Styles.swift
│   ├── Models/
│   │   └── Screenshot.swift
│   ├── Services/
│   │   ├── ScreenCapture.swift
│   │   └── HotkeyManager.swift
│   ├── Resources/
│   │   └── Assets.xcassets
│   ├── Info.plist
│   └── SnapClean.entitlements
├── project.yml
└── build.sh
```

## Permissions

SnapClean requires the following permissions:
- **Screen Recording** - To capture screenshots
- **Accessibility** - For keyboard shortcuts
- **Clipboard** - For copy/paste functionality

## License

MIT License - Feel free to contribute!

## Acknowledgments

- Built with SwiftUI and AppKit
- Uses CoreGraphics for screen capture
- Inspired by CleanShot X
