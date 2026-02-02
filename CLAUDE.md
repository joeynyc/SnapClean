# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SnapClean is a native macOS screenshot app built with SwiftUI, targeting macOS 14.0+ (Sonoma). It provides region/window/full-screen capture, annotation tools, screenshot history, and pin-to-screen functionality. No external dependencies — built entirely on Apple frameworks (SwiftUI, AppKit, CoreGraphics, Core Image, Carbon).

## Build Commands

Prerequisites: Xcode 15.0+, XcodeGen (`brew install xcodegen`)

```bash
# Generate Xcode project from project.yml (required before first build or after changing project.yml)
xcodegen generate

# Build
./build.sh build

# Build and run
./build.sh run

# Clean
./build.sh clean

# Manual build
xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug build
```

There are no tests, linting, or CI configured.

## Architecture

**MVVM with centralized state.** `AppState` is a `@MainActor ObservableObject` that holds all app state and is passed to views via `@EnvironmentObject`.

### App Entry & Lifecycle

`SnapCleanApp` (@main) creates the `WindowGroup`, `MenuBarExtra`, and injects `AppState`. `AppDelegate` (via `@NSApplicationDelegateAdaptor`) handles status bar setup, global hotkey registration, and screen recording permission checks.

### Communication Pattern

`AppDelegate` communicates with `AppState` through `NotificationCenter` posts (`.startCapture`, `.openHistory`). `AppState` listens for these in `setupNotifications()`. This decouples AppKit delegate code from the SwiftUI state layer.

### Key Types in Screenshot.swift

- `AppState` — centralized observable state; owns `ScreenCaptureService` and `ScreenshotHistoryManager` instances
- `ScreenshotItem` — Codable model for persisted history entries (stored as JSON in UserDefaults)
- `AnnotationElement` — represents a single drawn annotation (arrow, text, shape, etc.)
- `CaptureMode` — enum: `.region`, `.window`, `.screen`
- `AnnotationTool` — enum with 8 tools: arrow, text, rectangle, oval, line, pencil, blur, pixelate
- `ScreenshotHistoryManager` — handles UserDefaults persistence and file cleanup; history capped at 50 items

### Services

- `ScreenCaptureService` (ScreenCapture.swift) — wraps CoreGraphics APIs (`CGDisplayCreateImage`, `CGWindowListCreateImage`) for capture; also provides save-to-disk, copy-to-clipboard, and image processing (pixelate/blur via Core Image filters)
- `HotkeyManager` (HotkeyManager.swift) — singleton that registers global keyboard shortcuts using `NSEvent.addGlobalMonitorForEvents`

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
- **Entitlements**: App Sandbox enabled with read-only file access, network client, Apple Events automation, and accessibility permissions.
- **Required system permissions**: Screen Recording, Accessibility (for global hotkeys).
