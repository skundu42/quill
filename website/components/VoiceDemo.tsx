"use client";

import {
  type KeyboardEvent,
  type PointerEvent,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";

import { QuillLogo } from "@/components/QuillLogo";

const initialText = "Hey Sarah, can we move the meeting to Thursday at 3 PM?";
const spokenText = "hey Sarah um can we move the meeting to tomorrow actually make that Thursday at 3";
const polishedText = "Hey Sarah, can we move the meeting to Thursday at 3 PM?";

type DemoStage = "ready" | "listening" | "polishing" | "inserted";

const stageLabels: Record<DemoStage, string> = {
  ready: "Ready",
  listening: "Listening",
  polishing: "Polishing",
  inserted: "Inserted",
};

export function VoiceDemo() {
  const [transcript, setTranscript] = useState(initialText);
  const [stage, setStage] = useState<DemoStage>("ready");
  const isRecording = useRef(false);
  const transcriptionTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const polishingTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearTimers = useCallback(() => {
    if (transcriptionTimer.current) clearInterval(transcriptionTimer.current);
    if (polishingTimer.current) clearTimeout(polishingTimer.current);
    if (resetTimer.current) clearTimeout(resetTimer.current);
    transcriptionTimer.current = null;
    polishingTimer.current = null;
    resetTimer.current = null;
  }, []);

  const startRecording = useCallback(() => {
    if (isRecording.current) return;

    clearTimers();
    isRecording.current = true;
    setStage("listening");
    setTranscript("");

    let index = 0;
    transcriptionTimer.current = setInterval(() => {
      index = Math.min(index + 2, spokenText.length);
      setTranscript(spokenText.slice(0, index));

      if (index >= spokenText.length && transcriptionTimer.current) {
        clearInterval(transcriptionTimer.current);
        transcriptionTimer.current = null;
      }
    }, 34);
  }, [clearTimers]);

  const stopRecording = useCallback(() => {
    if (!isRecording.current) return;

    isRecording.current = false;
    if (transcriptionTimer.current) clearInterval(transcriptionTimer.current);
    transcriptionTimer.current = null;
    setStage("polishing");

    polishingTimer.current = setTimeout(() => {
      setTranscript(polishedText);
      setStage("inserted");
      resetTimer.current = setTimeout(() => setStage("ready"), 1100);
    }, 430);
  }, []);

  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.hidden) stopRecording();
    };

    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => {
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      clearTimers();
    };
  }, [clearTimers, stopRecording]);

  const handlePointerDown = (event: PointerEvent<HTMLButtonElement>) => {
    event.preventDefault();
    event.currentTarget.setPointerCapture?.(event.pointerId);
    startRecording();
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>) => {
    if ((event.code === "Space" || event.code === "Enter") && !event.repeat) {
      event.preventDefault();
      startRecording();
    }
  };

  const handleKeyUp = (event: KeyboardEvent<HTMLButtonElement>) => {
    if (event.code === "Space" || event.code === "Enter") {
      event.preventDefault();
      stopRecording();
    }
  };

  const listening = stage === "listening";
  const pillLabel = stage === "ready" ? "Hold to speak" : stage === "polishing" ? "Polishing…" : stageLabels[stage];

  return (
    <>
      <div className="voice-instrument" aria-label="Interactive Quill voice typing demonstration">
        <div className="instrument-topbar">
          <div className="app-identity">
            <QuillLogo />
            <span>Quill</span>
          </div>
          <span className="status-chip" aria-live="polite">
            {stageLabels[stage]}
          </span>
        </div>

        <div className="transcript-stage">
          <span className="stage-label">In Slack</span>
          <p className="transcript" aria-live="polite">
            {transcript}
          </p>
          <span className="cursor" aria-hidden="true" />
        </div>

        <div className={`recording-pill${listening ? " is-listening" : ""}`}>
          <span className="recording-dot" aria-hidden="true" />
          <div className="waveform" aria-hidden="true">
            {Array.from({ length: 9 }, (_, index) => (
              <i key={index} />
            ))}
          </div>
          <span className="pill-label">{pillLabel}</span>
        </div>
      </div>

      <div className="hero-actions" id="download">
        <a
          className="action-card action-primary"
          href="https://github.com/skundu42/quill/releases/latest"
        >
          <span>
            <small>macOS 14+</small>
            Download Quill
          </span>
          <span className="action-icon" aria-hidden="true">
            ↓
          </span>
        </a>
        <button
          className={`action-card action-demo${listening ? " is-active" : ""}`}
          type="button"
          aria-pressed={listening}
          onPointerDown={handlePointerDown}
          onPointerUp={stopRecording}
          onPointerCancel={stopRecording}
          onLostPointerCapture={stopRecording}
          onKeyDown={handleKeyDown}
          onKeyUp={handleKeyUp}
        >
          <span>
            <small>Interactive demo</small>
            <span>{listening ? "Release to insert" : "Hold to try Quill"}</span>
          </span>
          <span className="shortcut" aria-hidden="true">
            <kbd>⌥</kbd>
            <kbd>Space</kbd>
          </span>
        </button>
      </div>
    </>
  );
}
