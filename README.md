# Quill

Open-source, system-wide voice typing for macOS.

Hold **⌥ Space**, speak, and release. Quill streams microphone audio to Gemini Live Transcription, receives a polished transcript, and inserts it at the active cursor.

## What is implemented

- Native SwiftUI menu-bar app (`LSUIElement`)
- Global push-to-talk and toggle shortcuts via Carbon hot keys
- `AVAudioEngine` microphone capture and 16 kHz mono PCM conversion
- 100 ms audio chunking
- Gemini Live API WebSocket client using `gemini-3.5-transcribe-live`
- Smart and verbatim transcription modes
- Automatic language detection and language hints
- Custom vocabulary biasing
- Accessibility API insertion with clipboard-preserving paste fallback
- Gemini API-key storage in macOS Keychain
- Non-activating floating dictation indicator
- Three-step onboarding for permissions and BYOK setup
- General, Voice, Dictionary, and Advanced settings
- Launch-at-login support through `SMAppService`

## Requirements

- macOS 14 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A Gemini API key with Live API access

## Build and run

Generate the Xcode project:

```sh
xcodegen generate
open Quill.xcodeproj
```

Choose the **Quill** scheme, select your development team under Signing & Capabilities, then run the app.

For an ad-hoc signed local Release build:

```sh
./scripts/build.sh
open dist/Quill.app
```

The script creates a bundle that runs on the build machine. Public distribution still requires a Developer ID signature and notarization.

## Test

```sh
xcodebuild \
  -project Quill.xcodeproj \
  -scheme Quill \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Privacy

Quill keeps raw audio in memory only and sends it directly to Google's Gemini API for transcription. Raw audio is never written to disk. Transcript history is disabled; the current build retains only the most recent transcript in memory until the app quits.

The API key is stored as a generic password in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

## Website prototype

The landing-page prototype remains in `index.html`, `styles.css`, and `app.js`. Preview it with:

```sh
python3 -m http.server 4173
```

## License

Apache-2.0 / MIT
