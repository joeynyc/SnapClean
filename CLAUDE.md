# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SnapClean is a native macOS screenshot app built with SwiftUI, targeting macOS 14.0+ (Sonoma). It provides region/window/full-screen capture, annotation tools, screenshot history, and pin-to-screen functionality. No external dependencies — built entirely on Apple frameworks (SwiftUI, AppKit, CoreGraphics, Core Image, Carbon).

## Build Commands

Prerequisites: Xcode 26.0+, XcodeGen (`brew install xcodegen`)

```bash
# Generate Xcode project from project.yml (required before first build or after changing project.yml)
xcodegen generate

# Build
./build.sh build

# Run unit tests
./build.sh test

# Build and run
./build.sh run

# Clean
./build.sh clean

# Manual build
xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug build
```

Unit tests live in `SnapCleanTests/`. GitHub Actions runs `xcodegen generate` and `./build.sh test`; there is no linting configured.

## Architecture

**MVVM with centralized state.** `AppState` is an `@Observable @MainActor` coordinator, split into `CaptureState`, `AnnotationState`, and `HistoryState`, and passed to views via `.environment(appState)`.

### App Entry & Lifecycle

`AppDelegate` (via `@NSApplicationDelegateAdaptor`) owns the single `AppState` instance, registers global hotkeys, and checks screen recording permission. `SnapCleanApp` (@main) declares the main `Window` scene (id `main`), the History and About window groups, the `MenuBarExtra`, and Settings, injecting `appDelegate.appState` into each. Owning `AppState` in the delegate keeps hotkeys working even when no window has been opened.

### Communication Pattern

Hotkey actions call `AppState.startCapture(mode:)` directly; shortcuts default to ⇧⌘F1/F2/F3 and can be changed in Preferences. `AppState` observes `NSApplication.didBecomeActiveNotification` in `setupNotifications()` to refresh permission status. Because `AppState` can't call SwiftUI's `openWindow`, the menu bar icon's label view hands it an `openMainWindow` closure, used when a capture finishes while the main window is closed. Pinned screenshots are shown by `PinWindowController` (Windows/) in a floating `NSPanel`, driven by `AppState.showPinWindow`/`pinnedImage`.

### Key Types in Screenshot.swift

- `AppState` — centralized observable state; owns `ScreenCaptureService` and `ScreenshotHistoryManager` instances
- `ScreenshotItem` — Codable model for persisted history entries (stored in `history.json` beside the saved screenshots)
- `AnnotationElement` — represents a single drawn annotation (arrow, text, shape, etc.)
- `CaptureMode` — enum: `.region`, `.window`, `.screen`
- `AnnotationTool` — enum with 8 tools: arrow, text, rectangle, oval, line, pencil, blur, pixelate
- `ScreenshotHistoryManager` — saves new screenshots to the user's real `~/Downloads` (`saveDirectory`) and keeps `history.json` plus older screenshots in the app container (`storeDirectory`). History trimming and Clear History only delete files inside `storeDirectory`; deleting a history item moves its file to the Trash. History limit defaults to 50
- `HotkeyShortcut` (HotkeyShortcut.swift) — user-recordable global shortcut per `CaptureMode`, stored in UserDefaults as `hotkey.<mode>`; `AppDelegate` re-registers hotkeys via `AppState.onHotkeysChanged`

### Services

- `ScreenCaptureService` (ScreenCapture.swift) — wraps ScreenCaptureKit for region/window/full-screen capture; also provides save-to-disk, copy-to-clipboard, and image processing (pixelate/blur via Core Image filters)
- `HotkeyManager` (HotkeyManager.swift) — singleton that registers global keyboard shortcuts using Carbon `RegisterEventHotKey`; global hotkeys are unregistered while the Preferences shortcut recorder is active

### View Hierarchy

`MainWindow` is the primary container, conditionally showing `CaptureOverlay` (during capture) or `AnnotationCanvasView` (after capture) based on `AppState` flags. `AnnotationCanvas` uses SwiftUI `Canvas` for rendering annotations. `ToolbarView` provides annotation tool selection. Reusable styles (GlassButtonStyle, ToolButtonStyle, IconButtonStyle) live in `Views/Components/Styles.swift`.

### Data Flow

1. Hotkey or menu action → `NotificationCenter` post → `AppState.startCapture(mode:)`
2. `CaptureOverlay` performs capture via `ScreenCaptureService` → `AppState.handleCapturedImage(_:)`
3. User annotates in `AnnotationCanvasView` → annotations stored in `AppState.annotations` with undo/redo stacks
4. Save → `ScreenCaptureService.saveImage(_:)` → `AppState.addToHistory(path:image:)` → persisted via `ScreenshotHistoryManager`

## Project Configuration

- **XcodeGen**: `project.yml` is the source of truth for project structure. Run `xcodegen generate` after modifying it.
- **Bundle ID**: `com.snapclean.app`
- **Code signing**: `project.yml` is configured for Apple Development signing with team `QNGW24R2UL`. Update `DEVELOPMENT_TEAM` before building under another Apple Developer account.
- **Entitlements**: App Sandbox enabled with read-only user-selected file access, Downloads read/write access, and network client access.
- **Required system permissions**: Screen Recording, Accessibility (for global hotkeys).
- **Permission troubleshooting**: If Screen Recording appears enabled in System Settings but SnapClean still reports blocked, quit SnapClean, reset/re-add the exact built `SnapClean.app` in Screen & System Audio Recording, then relaunch. Stable Apple Development signing prevents repeated prompts after normal rebuilds.
