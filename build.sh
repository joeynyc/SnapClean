#!/bin/bash

# SnapClean Build & Run Script
# Usage: ./build.sh [build|run|test|archive|clean]

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
        APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SnapClean-*/Build/Products/Debug -maxdepth 1 -name "SnapClean.app" -print0 2>/dev/null | xargs -0 ls -td 2>/dev/null | head -1)
        if [ -z "$APP_PATH" ]; then
            echo "❌ Could not find built app. Try building first with: ./build.sh build"
            exit 1
        fi
        open -n "$APP_PATH"
        echo "✅ App launched!"
        ;;

    test)
        echo "🧪 Testing SnapClean..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug test
        echo "✅ Tests passed!"
        ;;

    archive)
        echo "📦 Archiving SnapClean..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Release archive -archivePath "$PROJECT_DIR/build/SnapClean.xcarchive"
        echo "✅ Archive created at build/SnapClean.xcarchive"
        ;;

    clean)
        echo "🧹 Cleaning build artifacts..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean clean
        echo "✅ Cleaned!"
        ;;

    *)
        echo "Usage: ./build.sh [build|run|test|archive|clean]"
        exit 1
        ;;
esac
