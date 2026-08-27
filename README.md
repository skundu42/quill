<p align="center">
  <img src="website/public/brand/quill-logo.svg" width="88" height="88" alt="Quill logo">
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

Place your cursor in an editable field, hold <kbd>⌥ Option</kbd> + <kbd>Space</kbd>, speak, and release. Your transcript appears at the original cursor so you can keep working without changing context.

<p align="center">
  <img src="docs/images/quill-main-window.png" width="900" alt="Quill main app window showing dictation controls and local usage statistics">
</p>

## Features

- **Dictate across macOS:** Write in browsers, editors, messaging apps, and other standard text fields.
- **Use the workflow you prefer:** Choose hold-to-speak or press-to-start/stop dictation.
- **Customize every shortcut:** Record any modified-key shortcut for dictation and for pasting your latest transcript.
- **Choose your microphone:** Follow the macOS default input or select a specific connected microphone.
- **Get cleaner text automatically:** Smart mode improves punctuation and readability; Verbatim mode stays closer to your exact words.
- **Speak in your language:** Let Quill detect the language or select a preferred language.
- **Teach Quill your terminology:** Add names, technical terms, acronyms, and product vocabulary.
- **See what is happening:** A lightweight floating indicator responds while Quill listens and processes speech.
- **Track simple local usage:** View daily and lifetime dictation and word counts without saving transcript history.

## Getting started

### What you need

- A Mac running macOS 14 or later
- A Gemini API key with access to the Live transcription model

### Get a Gemini API key

1. Open the [Google AI Studio API keys page](https://aistudio.google.com/app/apikey) and sign in with your Google account.
2. Select **Create API key**, then choose or create a Google Cloud project when prompted.
3. Copy the generated key. Quill will ask for it during onboarding.

### Set up Quill

1. Move `Quill.app` to your **Applications** folder and open it.
2. Follow onboarding to allow **Microphone** and **Accessibility** access.
3. Paste your Gemini API key and finish setup.
4. Click inside any editable text field.
5. Hold <kbd>⌥ Option</kbd> + <kbd>Space</kbd>, speak, then release.

Quill remains available from the menu bar. Open its settings to change the shortcuts, microphone, dictation behavior, transcription style, language, vocabulary, launch-at-login preference, or API key.

## Everyday controls

| Action | Default behavior |
| --- | --- |
| Start dictating | Hold <kbd>⌥ Option</kbd> + <kbd>Space</kbd> |
| Finish and insert | Release the shortcut |
| Paste the latest transcript again | Press <kbd>⌃ Control</kbd> + <kbd>⌥ Option</kbd> + <kbd>V</kbd> |
| Cancel dictation | Press <kbd>Esc</kbd> |
| Open Quill | Select the Quill icon in the menu bar |
| Change the API key | Open **Settings → Privacy & Access** |
| Check for updates | Choose **Quill → Check for Updates…** or use the button in the app sidebar |

Both global shortcuts are customizable from **Settings → Dictation**. Click a shortcut field, then press any non-modifier key together with Command, Option, Control, or Shift. Microphone selection is on the same page. If a specifically selected microphone is unavailable, Quill temporarily uses the current macOS default without forgetting the preferred device.

## Privacy and local data

Accessibility permission is used only to return focus to the original text field and insert the completed transcript. Microphone permission is used only while dictation is active.

## Development

See [Building Quill from Source](docs/BUILDING.md) for local development, testing, release signing, and GitHub publishing instructions.

## License

Quill is available under the [Apache License 2.0](LICENSE).
