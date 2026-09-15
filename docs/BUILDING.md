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

Push a tag such as `v0.1.0` to run `.github/workflows/release.yml`, or run **Release macOS DMG** from GitHub Actions with an existing tag. The workflow tests Quill, sets the app version from the tag, builds a universal signed app, creates and notarizes a DMG, and generates a signed `appcast.xml` using the resolved Sparkle package's tools.

The workflow uploads all assets to a draft release before publishing it and marking a stable release latest. This keeps the website download and installed apps' update feed working throughout the build. You may prepare release notes in a draft for the tag; leave publication to the workflow.

Release runs queue instead of cancelling one another. Incomplete drafts can be rebuilt; already published releases retain their original binaries and signatures. Unpublished tags must be newer than the current stable release, so an older unfinished tag cannot replace a newer stable release.

A retry can finish updating the RC feed after publication when its history is available, or finish creating its first draft. If replacement of a published channel asset fails after deleting the old `appcast.xml`, restore the channel's last known appcast before retrying. The workflow fails rather than guessing which historical release should replace missing channel history.

## Release candidates

Release candidates use tags in the form `vX.Y.Z-rc.N`, starting at `rc.1`. Push the tag and the workflow creates a **prerelease** automatically. If you prepare a draft yourself, mark it as a prerelease. The workflow rejects an existing release whose prerelease setting disagrees with the tag, preventing an accidental public rollout.

The workflow publishes RC entries to Sparkle's `rc` channel and updates a permanent, prerelease-only `quill-rc-channel` feed. Normal Quill installations continue to use GitHub's latest stable release and do not allow the `rc` channel.

To enroll a client from Terminal, quit Quill and run:

```sh
defaults write com.quill.voice updateChannel -string rc
open -a Quill
```

Then choose **Check for Updates…**. Enrollment persists across launches, and an enrolled client receives RCs as well as the eventual stable release.

To return the client to stable-only updates, quit Quill and run:

```sh
defaults delete com.quill.voice updateChannel
open -a Quill
```

For a one-launch developer override, launch the executable directly with `QUILL_UPDATE_CHANNEL=rc`. `QUILL_UPDATE_FEED` remains available as the highest-priority custom-feed override.

Publish releases in increasing order. Sparkle compares Quill's numeric GitHub Actions build number, so an older maintenance line must not be published after a newer release train has begun.

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

The release checks simulate GitHub locally and do not publish anything:

```sh
./scripts/test-release-metadata.sh
python3 scripts/test-publish-release.py
```

```sh
xcodebuild \
  -project Quill.xcodeproj \
  -scheme Quill \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```
