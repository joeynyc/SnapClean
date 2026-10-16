# Releasing SnapClean

Releases are a signed, notarized DMG attached to a GitHub Release. Pushing a version tag builds and publishes one automatically:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The [Release workflow](../.github/workflows/release.yml) then:

1. Builds a universal (Apple silicon and Intel) Release archive, using the version from the tag.
2. Signs the app with your Developer ID certificate.
3. Packages it in a drag-to-Applications DMG, then signs and notarizes the DMG.
4. Publishes a GitHub Release with the DMG, its SHA-256 checksum, and notes generated from the commits.

The build number is the workflow's run number, so it always goes up.

## One-time setup

You need a paid Apple Developer Program membership for team `QNGW24R2UL`. Add five repository secrets in **GitHub → Settings → Secrets and variables → Actions**.

### 1. Developer ID certificate

Only the account holder can create this certificate.

1. In Xcode, open **Settings → Accounts**, select your team, and click **Manage Certificates…**.
2. Click **+** and choose **Developer ID Application**.
3. In **Keychain Access**, find **Developer ID Application: …** under **My Certificates**. Right-click it, choose **Export**, and save it as a `.p12` with a strong password.
4. Add these secrets:

   | Secret | Value |
   | --- | --- |
   | `DEVELOPER_ID_CERT_P12` | Output of `base64 -i DeveloperID.p12 \| pbcopy` |
   | `DEVELOPER_ID_CERT_PASSWORD` | The `.p12` password |

Delete the exported `.p12` afterwards.

### 2. Notarization API key

1. Go to [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api).
2. Create a key with the **Developer** role and download the `.p8` file. You can only download it once.
3. Add these secrets:

   | Secret | Value |
   | --- | --- |
   | `NOTARY_API_KEY` | Output of `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |
   | `NOTARY_KEY_ID` | The key ID shown next to the key |
   | `NOTARY_ISSUER_ID` | The Issuer ID shown at the top of the page |

## Before you tag

1. Make sure `main` is green in CI.
2. Launch a build and check the basics: region, window, and full-screen capture, annotating, save, copy, pin, history, and permission recovery.
3. Optionally, bump `MARKETING_VERSION` in `project.yml` to match the tag, so local builds report the same version.

## Building a DMG locally

```bash
./build.sh dmg
```

The DMG and its checksum are written to `build/`.

- **With a Developer ID certificate in your keychain**, the app and the DMG are signed with it.
- **Notarization** needs credentials. For local use, store them once:

  ```bash
  xcrun notarytool store-credentials snapclean --key AuthKey_XXXXXXXXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
  NOTARY_PROFILE=snapclean ./build.sh dmg
  ```

- **Without either**, you still get a DMG for testing, but it only opens on your own Mac. The script prints a warning when that happens.

Set `REQUIRE_NOTARIZATION=1` to fail instead of falling back. `VERSION` and `BUILD_NUMBER` override the versions in `project.yml`.

## Troubleshooting

- **Notarization rejected:** run `xcrun notarytool log <submission-id>` with the same credentials to see Apple's reasons.
- **`No "Developer ID Application" certificate`:** the certificate or its private key is missing from the keychain. Export it again from the Mac where it was created, with the private key included.
- **Users asked for Screen Recording again after an update:** the app was signed with a different identity. Always release with the same Developer ID certificate.
