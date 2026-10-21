#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 MODEL_DIR PCM_FILE EXPECTED_TEXT" >&2
  echo "PCM_FILE must contain signed 16-bit little-endian, 16 kHz mono audio." >&2
  exit 2
fi

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODEL_DIR=$1
PCM_FILE=$2
EXPECTED_TEXT=$3

if [ ! -d "$MODEL_DIR/BarkEncoder.mlmodelc" ] || \
   [ ! -d "$MODEL_DIR/decoder" ] || [ ! -f "$MODEL_DIR/vocab.json" ]; then
  echo "MODEL_DIR must contain BarkEncoder.mlmodelc, decoder/*.npy, and vocab.json." >&2
  exit 2
fi

if [ ! -f "$PCM_FILE" ]; then
  echo "PCM_FILE does not exist: $PCM_FILE" >&2
  exit 2
fi

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quill-bark-smoke.XXXXXX")
trap 'rm -rf "$TEST_DIR"' 0
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$TEST_DIR/Smoke.swift" <<'SWIFT'
import Foundation

@main
struct BarkSmokeTest {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            let transcriber = BarkTranscriber(directory: URL(fileURLWithPath: arguments[1]))
            let pcm = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            let actual = try await transcriber.transcribe(pcm: pcm)
            let expected = arguments[3]
            guard actual == expected else {
                fail("Bark transcript mismatch.\nExpected: \(expected.debugDescription)\nActual:   \(actual.debugDescription)")
            }
            print("Bark smoke test passed: \(actual.debugDescription)")
        } catch {
            fail("Bark smoke test failed: \(error.localizedDescription)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
SWIFT

xcrun swiftc -O -parse-as-library \
  "$ROOT_DIR/Quill/Bark/BarkDecoder.swift" \
  "$ROOT_DIR/Quill/Bark/BarkModelManager.swift" \
  "$ROOT_DIR/Quill/Bark/BarkTranscriber.swift" \
  "$TEST_DIR/Smoke.swift" \
  -o "$TEST_DIR/bark-smoke"

"$TEST_DIR/bark-smoke" "$MODEL_DIR" "$PCM_FILE" "$EXPECTED_TEXT"
