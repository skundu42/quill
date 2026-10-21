# Underdog Bark 3.0

Quill uses the standard, English-only **Underdog Bark 3.0** model by Conway Research. It preserves spoken fillers and repetitions. Gemini remains available for Smart cleanup, other languages, and vocabulary hints.

Select **Models → Underdog Bark 3.0 → Download Bark**. Apple silicon and macOS 15 or later are required. Setup downloads approximately 202 MB, verifies every file against a pinned size and SHA-256, extracts the decoder arrays, and compiles the encoder using Core ML. First setup and cold model initialization after relaunch may take several minutes. Loaded encoders are reused for subsequent dictations; Escape can cancel a pending transcription. Audio is held in memory and transcribed on-device after recording ends; no audio is written to disk or sent to a service. Dictation is limited to five minutes and split at low-energy spans into pieces fitting the encoder's 15-second window. These cuts can affect words in continuous speech without pauses.

The native runtime uses Core ML's CPU/Neural Engine configuration and Accelerate for preprocessing and greedy TDT decoding. It does not require Python or an additional Swift package. Model files, attribution, and license are cached in `~/Library/Application Support/Quill/Models/`. Gemini retains its existing macOS 14 compatibility and streams audio to Google only when selected. Existing onboarded users retain their selected Gemini workflow; new installations default to Bark.

## Source, license, and changes

- [Official model and reference runtime](https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/tree/85db2ad18ab41e534a222ee253c29191d77ed919), revision `85db2ad18ab41e534a222ee253c29191d77ed919`.
- Model/runtime license: [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
- Upstream model: [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), © NVIDIA Corporation, through [Moondream Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra), © Moondream.
- Conway Research post-trained and compressed the model. Quill ports the published `coreml/ane/bark_coreml.py` frontend, decoder, and segmentation to Swift/Accelerate; it does not modify the model weights. Segmentation reserves room for the 250 ms leading silence and bounds every piece to the encoder window. These adapted runtime portions remain subject to CC BY 4.0. The rest of Quill retains its existing license.

The downloaded package includes the publisher's full `LICENSE` and `NOTICE` files. The Models screen links to the official model card and license.

## Validation

`BarkDecoderTests` checks numerical frontend behavior and malformed NPY input; `BarkTranscriberTests` checks PCM conversion, segment coverage, window limits, cancellation, silence, and model artifact integrity. The native runtime is additionally compared with the upstream Python implementation using identical input features and encoded frames during development. Full model inference requires downloading the model; the ordinary unit suite does not download it.

For an opt-in end-to-end check on a supported Mac, use the model folder installed by Quill and a known 16 kHz mono signed 16-bit little-endian PCM sample (without a WAV header):

```sh
./scripts/test-bark.sh /path/to/prepared/model /path/to/sample.pcm 'expected transcript'
```

This compiles the actual app runtime and compares the complete transcript exactly. It does not download a model or audio. A cold Core ML load can take several minutes.
