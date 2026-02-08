#!/bin/bash

# SnapClean Build & Run Script
# Usage: ./build.sh [build|run|clean]

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

case "${1:-build}" in
    build)
        echo "🔨 Building SnapClean..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug build
        echo "✅ Build succeeded!"
        ;;

    run)
        echo "🚀 Building and running SnapClean..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug build
        APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SnapClean-*/Build/Products/Debug -name "SnapClean.app" -maxdepth 1 2>/dev/null | head -1)
        if [ -z "$APP_PATH" ]; then
            echo "❌ Could not find built app. Try building first with: ./build.sh build"
            exit 1
        fi
        open "$APP_PATH"
        echo "✅ App launched!"
        ;;

    clean)
        echo "🧹 Cleaning build artifacts..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean clean
        echo "✅ Cleaned!"
        ;;

    *)
        echo "Usage: ./build.sh [build|run|clean]"
        exit 1
        ;;
esac
