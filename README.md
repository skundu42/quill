<p align="center">
  <img src="brand/quill-logo.svg" width="88" height="88" alt="Quill logo">
</p>

<h1 align="center">Quill</h1>

<p align="center">
  <strong>Fast, system-wide voice typing for macOS.</strong><br>
  Speak naturally, then let Quill place polished text wherever you are writing.
</p>

<p align="center">
  macOS 14+ &nbsp;·&nbsp; Open source &nbsp;·&nbsp; Bring your own Gemini API key
</p>

---

Quill lives quietly in the menu bar and turns your voice into text across macOS. Place your cursor in an editable field, hold <kbd>⌥ Option</kbd> + <kbd>Space</kbd>, speak, and release. Your transcript appears at the original cursor so you can keep working without changing context.


## Highlights

- **Dictate across macOS** — write in browsers, editors, messaging apps, and other standard text fields.
- **Use the workflow you prefer** — choose hold-to-speak or press-to-start/stop dictation.
- **Get cleaner text automatically** — Smart mode improves punctuation and readability; Verbatim mode stays closer to your exact words.
- **Speak in your language** — let Quill detect the language or select a preferred language.
- **Teach Quill your terminology** — add names, technical terms, acronyms, and product vocabulary.
- **See what is happening** — a lightweight floating indicator responds while Quill listens and processes speech.
- **Keep your clipboard intact** — text insertion preserves and restores the clipboard when a paste fallback is needed.
- **Track simple local usage** — view daily and lifetime dictation and word counts without saving transcript history.
- **Start when your Mac starts** — optionally launch Quill automatically at login.

## Getting started

### What you need

- A Mac running macOS 14 or later
- A Gemini API key with access to the Live transcription model

### Set up Quill

1. Move `Quill.app` to your **Applications** folder and open it.
2. Follow onboarding to allow **Microphone** and **Accessibility** access.
3. Paste your Gemini API key and finish setup.
4. Click inside any editable text field.
5. Hold <kbd>⌥ Option</kbd> + <kbd>Space</kbd>, speak, then release.

Quill remains available from the menu bar. Open its settings to change the shortcut, dictation behavior, transcription style, language, vocabulary, launch-at-login preference, or API key.

## Everyday controls

| Action | Default behavior |
| --- | --- |
| Start dictating | Hold <kbd>⌥ Option</kbd> + <kbd>Space</kbd> |
| Finish and insert | Release the shortcut |
| Cancel dictation | Press <kbd>Esc</kbd> |
| Open Quill | Select the Quill icon in the menu bar |
| Change the API key | Open **Settings → Privacy & Access** |

The shortcut can also be changed to <kbd>⌃ Control</kbd> + <kbd>Space</kbd> or <kbd>⇧ Shift</kbd> + <kbd>⌘ Command</kbd> + <kbd>Space</kbd>.

## Privacy and local data

Quill is bring-your-own-key software. It does not run an intermediary transcription service.

| Data | How Quill handles it |
| --- | --- |
| Microphone audio | Held in memory while dictating and streamed directly to Google's Gemini API. Quill never writes recordings to disk. |
| Transcripts | Inserted at the active cursor. Transcript history is not stored; the most recent transcript remains in memory only until Quill quits. |
| Usage statistics | Only dictation and word counts are stored locally on the Mac. They can be reset from **Privacy & Access**. |
| Gemini API key | Stored at `~/Library/Application Support/Quill/api-key` with owner-only (`0600`) permissions. It is not stored in Keychain and remains until replaced. |

Accessibility permission is used only to return focus to the original text field and insert the completed transcript. Microphone permission is used only while dictation is active.

## Build from source

### Developer requirements

- macOS 14 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Generate the Xcode project:

```sh
xcodegen generate
open Quill.xcodeproj
```

Select the **Quill** scheme, choose a development team under **Signing & Capabilities**, and run the app.

To produce a universal release build, use:

```sh
./scripts/build.sh
```

The release script expects a valid **Developer ID Application** signing identity and writes the signed application to `dist/Quill.app`. Public distribution also requires notarization.

### Run the tests

```sh
xcodebuild \
  -project Quill.xcodeproj \
  -scheme Quill \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Website preview

The Quill landing page is included in `index.html`, `styles.css`, and `app.js`. Preview it locally with:

```sh
python3 -m http.server 4173
```

## License

Quill is available under the [Apache License 2.0](LICENSE).
