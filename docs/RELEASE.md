# Release Checklist

This checklist is for preparing a public SnapClean release from a clean checkout.

## Prerequisites

- Xcode 26.0 or later
- XcodeGen
- An Apple Developer account with a valid Mac signing identity
- App-specific password or App Store Connect API credentials if notarizing

## Preflight

1. Confirm the working tree is clean:

   ```bash
   git status --short
   ```

2. Generate the project and run tests:

   ```bash
   xcodegen generate
   ./build.sh test
   ```

3. Launch the app and manually verify:

   - Region capture
   - Window capture
   - Full-screen capture
   - Annotation save/copy/pin
   - History actions
   - Screen Recording permission recovery

## Build

Create a release archive:

```bash
./build.sh archive
```

The archive is written to:

```text
build/SnapClean.xcarchive
```

## Signing Notes

`project.yml` is the source of truth for signing settings. Update `DEVELOPMENT_TEAM` before release builds under a different Apple Developer account, then regenerate the project:

```bash
xcodegen generate
```

Stable Apple Development or Distribution signing is important because macOS privacy permissions are tied to the app identity.

## Distribution

For a public downloadable `.app`, export the archive with Developer ID signing and notarize the result before publishing. Keep generated archives, exported apps, and notarization output out of git.

Recommended GitHub release contents:

- Signed and notarized app archive
- Versioned release notes
- SHA-256 checksum
- Minimum macOS version
- Known permission requirements
