const holdButton = document.querySelector("[data-hold-button]");
const buttonLabel = document.querySelector("[data-button-label]");
const transcript = document.querySelector("[data-transcript]");
const status = document.querySelector("[data-status]");
const pill = document.querySelector("[data-pill]");
const pillLabel = pill?.querySelector(".pill-label");

const initialText = "Hey Sarah, can we move the meeting to Thursday at 3 PM?";
const spokenText = "hey Sarah um can we move the meeting to tomorrow actually make that Thursday at 3";
const polishedText = "Hey Sarah, can we move the meeting to Thursday at 3 PM?";

let isRecording = false;
let transcriptionTimer;
let finalizeTimer;

function setTranscriptProgress() {
  let index = 0;
  transcript.textContent = "";
  transcriptionTimer = window.setInterval(() => {
    index = Math.min(index + 2, spokenText.length);
    transcript.textContent = spokenText.slice(0, index);
    if (index >= spokenText.length) window.clearInterval(transcriptionTimer);
  }, 34);
}

function startRecording() {
  if (isRecording || !holdButton) return;
  window.clearTimeout(finalizeTimer);
  isRecording = true;
  holdButton.classList.add("is-active");
  pill.classList.add("is-listening");
  holdButton.setAttribute("aria-pressed", "true");
  buttonLabel.textContent = "Release to insert";
  status.textContent = "Listening";
  pillLabel.textContent = "Listening";
  setTranscriptProgress();
}

function stopRecording() {
  if (!isRecording || !holdButton) return;
  isRecording = false;
  window.clearInterval(transcriptionTimer);
  holdButton.classList.remove("is-active");
  pill.classList.remove("is-listening");
  holdButton.setAttribute("aria-pressed", "false");
  buttonLabel.textContent = "Hold to try Quill";
  status.textContent = "Polishing";
  pillLabel.textContent = "Polishing…";

  finalizeTimer = window.setTimeout(() => {
    transcript.textContent = polishedText;
    status.textContent = "Inserted";
    pillLabel.textContent = "Inserted";
    finalizeTimer = window.setTimeout(() => {
      status.textContent = "Ready";
      pillLabel.textContent = "Hold to speak";
    }, 1100);
  }, 430);
}

if (holdButton) {
  holdButton.setAttribute("aria-pressed", "false");
  holdButton.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    holdButton.setPointerCapture?.(event.pointerId);
    startRecording();
  });
  holdButton.addEventListener("pointerup", stopRecording);
  holdButton.addEventListener("pointercancel", stopRecording);
  holdButton.addEventListener("lostpointercapture", stopRecording);
  holdButton.addEventListener("keydown", (event) => {
    if ((event.code === "Space" || event.code === "Enter") && !event.repeat) {
      event.preventDefault();
      startRecording();
    }
  });
  holdButton.addEventListener("keyup", (event) => {
    if (event.code === "Space" || event.code === "Enter") {
      event.preventDefault();
      stopRecording();
    }
  });
}

document.addEventListener("visibilitychange", () => {
  if (document.hidden && isRecording) stopRecording();
});

window.addEventListener("pageshow", () => {
  if (transcript && !transcript.textContent.trim()) transcript.textContent = initialText;
});
