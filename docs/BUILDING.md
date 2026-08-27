# Building Quill from Source

## Developer requirements

- macOS 14 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Run Quill locally

Generate the Xcode project:

```sh
xcodegen generate
open Quill.xcodeproj
```

Select the **Quill** scheme, choose a development team under **Signing & Capabilities**, and run the app.

## Create a release build

To produce a universal release build, use:

```sh
./scripts/build.sh
```

The release script expects a valid **Developer ID Application** signing identity and writes the signed application to `dist/Quill.app`. Public distribution also requires notarization.

## Automated GitHub releases

Publishing a GitHub release with a tag such as `v0.1.0` automatically runs `.github/workflows/release.yml`. The workflow tests Quill, sets the app version from the release tag, builds a universal signed app, creates a drag-to-Applications DMG, notarizes it with Apple, signs it for Sparkle, generates `appcast.xml`, and attaches both files to the release.

Configure these repository secrets under **Settings → Secrets and variables → Actions** before publishing the first release:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` containing the Developer ID Application certificate and private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` file |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer Team ID associated with the certificate |
| `SPARKLE_ED_PRIVATE_KEY` | Quill's private Sparkle EdDSA update-signing key, exported by `generate_keys` |

Create the certificate secret on macOS with:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste the copied value into `DEVELOPER_ID_CERTIFICATE_BASE64`. The certificate itself remains ignored by Git through the existing `*.p12` rule.

The matching Sparkle public key is pinned in Quill's `Info.plist`. Keep an offline backup of the private key: published copies require it to verify every future update.

## Run the tests

```sh
xcodebuild \
  -project Quill.xcodeproj \
  -scheme Quill \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```
