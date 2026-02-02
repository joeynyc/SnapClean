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
        open /Users/joeyrodriguez/Library/Developer/Xcode/DerivedData/SnapClean-*/Build/Products/Debug/SnapClean.app
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
