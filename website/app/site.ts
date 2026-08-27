export const siteConfig = {
  name: "Quill",
  url: "https://www.quillvoice.xyz",
  googleAnalyticsId: "G-V3E9E92CHC",
  repositoryUrl: "https://github.com/skundu42/quill",
  authorName: "Sandipan Kundu",
  authorUrl: "https://x.com/SandipanKundu42",
  title: "Quill: Intelligent Voice Typing for macOS",
  description:
    "Quill is a free, open-source voice typing app for macOS. Hold a shortcut and get polished Gemini-powered dictation wherever your cursor is.",
  keywords: [
    "voice typing for Mac",
    "macOS dictation app",
    "speech to text for Mac",
    "open-source voice typing",
    "system-wide dictation",
    "Gemini transcription",
    "AI voice typing",
    "Quill macOS",
  ],
} as const;

export const latestDmgUrl = `${siteConfig.repositoryUrl}/releases/latest/download/Quill-macOS.dmg`;
