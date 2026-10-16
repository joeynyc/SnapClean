#!/bin/bash

# SnapClean Build & Run Script
# Usage: ./build.sh [build|run|test|archive|dmg|clean]

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

XCODEBUILD_ARGS=()
if [ "${CI:-}" = "true" ]; then
    XCODEBUILD_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY=-
        DEVELOPMENT_TEAM=
    )
fi

case "${1:-build}" in
    build)
        echo "🔨 Building SnapClean..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug "${XCODEBUILD_ARGS[@]}" build
        echo "✅ Build succeeded!"
        ;;

    run)
        echo "🚀 Building and running SnapClean..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug "${XCODEBUILD_ARGS[@]}" build
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
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Debug "${XCODEBUILD_ARGS[@]}" test
        echo "✅ Tests passed!"
        ;;

    archive)
        echo "📦 Archiving SnapClean..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Release "${XCODEBUILD_ARGS[@]}" archive -archivePath "$PROJECT_DIR/build/SnapClean.xcarchive"
        echo "✅ Archive created at build/SnapClean.xcarchive"
        ;;

    dmg)
        # Builds a Developer ID-signed, notarized DMG in build/. See docs/RELEASE.md.
        #   VERSION                 Marketing version (default: MARKETING_VERSION in project.yml)
        #   BUILD_NUMBER            Bundle build number (default: CURRENT_PROJECT_VERSION in project.yml)
        #   NOTARY_PROFILE          notarytool keychain profile, for local releases
        #   NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER_ID   App Store Connect API key, for CI
        #   REQUIRE_NOTARIZATION=1  Fail instead of producing an un-notarized test DMG
        TEAM_ID="QNGW24R2UL"
        DEVELOPER_ID="Developer ID Application"
        VERSION="${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)}"
        BUILD_NUMBER="${BUILD_NUMBER:-$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)}"
        BUILD_DIR="$PROJECT_DIR/build"
        ARCHIVE_PATH="$BUILD_DIR/SnapClean.xcarchive"
        EXPORT_DIR="$BUILD_DIR/export"
        DMG_PATH="$BUILD_DIR/SnapClean-$VERSION.dmg"

        fail() { echo "❌ $1"; exit 1; }

        if [ -n "${NOTARY_KEY_PATH:-}" ]; then
            NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
        elif [ -n "${NOTARY_PROFILE:-}" ]; then
            NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
        else
            NOTARY_AUTH=()
        fi

        HAS_DEVELOPER_ID=false
        if security find-identity -v -p codesigning | grep -q "\"$DEVELOPER_ID"; then
            HAS_DEVELOPER_ID=true
        fi

        if [ "${REQUIRE_NOTARIZATION:-}" = "1" ]; then
            $HAS_DEVELOPER_ID || fail "No \"$DEVELOPER_ID\" certificate in the keychain."
            [ ${#NOTARY_AUTH[@]} -gt 0 ] || fail "Notarization credentials are not set."
        fi

        echo "📦 Building SnapClean $VERSION ($BUILD_NUMBER) DMG..."
        rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_PATH"
        mkdir -p "$BUILD_DIR"

        ARCHIVE_ARGS=(MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
        if $HAS_DEVELOPER_ID; then
            ARCHIVE_ARGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM_ID")
        fi
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean -configuration Release \
            "${ARCHIVE_ARGS[@]}" archive -archivePath "$ARCHIVE_PATH" -quiet

        if $HAS_DEVELOPER_ID; then
            cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>$DEVELOPER_ID</string>
    <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST
            xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_DIR" \
                -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" -quiet
        else
            echo "⚠️  No \"$DEVELOPER_ID\" certificate found. This DMG will only open on this Mac."
            mkdir -p "$EXPORT_DIR"
            ditto "$ARCHIVE_PATH/Products/Applications/SnapClean.app" "$EXPORT_DIR/SnapClean.app"
        fi

        # Lay out the DMG with an Applications shortcut for drag-to-install.
        STAGING_DIR="$BUILD_DIR/dmg"
        rm -rf "$STAGING_DIR"
        mkdir -p "$STAGING_DIR"
        ditto "$EXPORT_DIR/SnapClean.app" "$STAGING_DIR/SnapClean.app"
        ln -s /Applications "$STAGING_DIR/Applications"
        hdiutil create -volname "SnapClean" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDZO -ov "$DMG_PATH" -quiet
        rm -rf "$STAGING_DIR"

        if $HAS_DEVELOPER_ID; then
            codesign --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
        fi

        if $HAS_DEVELOPER_ID && [ ${#NOTARY_AUTH[@]} -gt 0 ]; then
            echo "🔏 Notarizing (this usually takes a few minutes)..."
            xcrun notarytool submit "$DMG_PATH" "${NOTARY_AUTH[@]}" --wait
            xcrun stapler staple "$DMG_PATH"
            spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
        else
            echo "⚠️  Skipping notarization. Gatekeeper will block this DMG on other Macs."
        fi

        (cd "$BUILD_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")
        echo "✅ DMG created at build/$(basename "$DMG_PATH")"
        ;;

    clean)
        echo "🧹 Cleaning build artifacts..."
        xcodebuild -project SnapClean.xcodeproj -scheme SnapClean "${XCODEBUILD_ARGS[@]}" clean
        echo "✅ Cleaned!"
        ;;

    *)
        echo "Usage: ./build.sh [build|run|test|archive|dmg|clean]"
        exit 1
        ;;
esac
