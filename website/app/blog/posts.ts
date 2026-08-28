export type BlogSection = {
  heading: string;
  paragraphs: readonly string[];
  bullets?: readonly string[];
  comparison?: readonly {
    label: string;
    quill: string;
    flow: string;
  }[];
  links?: readonly {
    label: string;
    href: string;
  }[];
};

export type BlogPost = {
  slug: string;
  title: string;
  seoTitle: string;
  description: string;
  excerpt: string;
  category: string;
  published: string;
  publishedISO: string;
  readingTime: string;
  keywords: readonly string[];
  sections: readonly BlogSection[];
};

export const blogPosts: readonly BlogPost[] = [
  {
    slug: "wispr-flow-alternative-for-mac",
    title: "Looking for a Wispr Flow alternative? Meet Quill for Mac",
    seoTitle: "Open-Source Wispr Flow Alternative for Mac",
    description:
      "Compare Quill and Wispr Flow for Mac voice typing, including pricing, privacy, platforms, languages, history, and open-source access.",
    excerpt:
      "Quill is a free, open-source Mac dictation app for people who want fewer accounts, less retained data, and their own Gemini API key.",
    category: "Comparison",
    published: "August 28, 2026",
    publishedISO: "2026-08-28",
    readingTime: "8 min read",
    keywords: [
      "Wispr Flow alternative",
      "open source Wispr Flow alternative",
      "free voice typing for Mac",
      "Mac dictation app",
    ],
    sections: [
      {
        heading: "The short version",
        paragraphs: [
          "Quill and Wispr Flow solve the same core problem: speak naturally and put polished text into the app where your cursor is. The meaningful difference is everything around that loop.",
          "Quill is the deliberately small option for Mac. It is free and open source, uses your own Gemini API key, does not require a Quill account, and does not keep a searchable transcript history. Wispr Flow is the more mature commercial product, with apps across multiple platforms, deeper personalization, cloud features, and team capabilities.",
          "That makes Quill a credible Wispr Flow alternative for people whose priority is a focused, inspectable Mac utility—not a claim that it replaces every Flow feature.",
        ],
      },
      {
        heading: "Quill vs. Wispr Flow at a glance",
        paragraphs: [
          "The best choice depends on what you want the product to remember, how many devices you use, and whether you prefer a subscription or a bring-your-own-key setup.",
        ],
        comparison: [
          {
            label: "Product model",
            quill: "Free, open source, Apache 2.0",
            flow: "Commercial service with Free and Pro plans",
          },
          {
            label: "Cost model",
            quill: "No Quill subscription; Gemini API usage or quotas still apply",
            flow: "Free tier with limits; paid Pro plan for unlimited dictation",
          },
          {
            label: "Account and API",
            quill: "No Quill account; bring your own Gemini API key",
            flow: "Wispr account; service manages the transcription stack",
          },
          {
            label: "Audio and history",
            quill: "Memory-only audio and no saved transcript archive in Quill",
            flow: "Configurable cloud and local data controls, with dictation history features",
          },
          {
            label: "Platforms",
            quill: "macOS",
            flow: "macOS, Windows, iOS, and Android",
          },
          {
            label: "Languages",
            quill: "85+ languages",
            flow: "100+ languages",
          },
          {
            label: "Best fit",
            quill: "A lightweight, inspectable Mac utility with minimal retained state",
            flow: "A polished cross-platform service with personalization and team features",
          },
        ],
      },
      {
        heading: "Where Quill is deliberately different",
        paragraphs: [
          "Quill has no subscription and no product account. You download the app, provide a Gemini API key, grant the required Mac permissions, and dictate. The Quill app itself is free, although Google API pricing and quotas can still apply to your key.",
          "The client is published under the Apache 2.0 license, so its behavior can be inspected and changed. Audio is buffered in memory only long enough to stream directly from the app to Gemini. Quill does not operate a transcription proxy, write recordings to disk, or build a transcript library. Only the latest transcript remains in memory while the app is running so Paste Last Transcript can work.",
          "This is still cloud speech-to-text. Audio reaches Google, and Google’s API terms and data policies apply. “Memory-only” describes what Quill itself stores; it does not mean the model runs locally.",
        ],
        links: [
          { label: "Read Quill’s privacy overview", href: "/#privacy" },
          { label: "Inspect Quill on GitHub", href: "https://github.com/skundu42/quill" },
        ],
      },
      {
        heading: "Where Wispr Flow offers more",
        paragraphs: [
          "Flow is the stronger fit when you need the same product across Mac, Windows, iPhone, and Android. Its official materials list more than 100 languages, vocabulary and style adaptation, dictation history, a notetaker, cloud sync controls, and business features. Quill is Mac-only, supports 85+ languages, and intentionally avoids a persistent transcript archive.",
          "As of August 28, 2026, Wispr’s official pricing page lists the desktop Free plan at 2,000 words per week. Pro is listed at $15 per user monthly, or $12 per user per month when billed annually, and includes unlimited dictation. Pricing and plan limits can change, so check Wispr’s current page before deciding.",
          "Flow also provides more product-managed convenience. That convenience comes with an account and a larger data surface. Wispr offers controls for model improvement, context awareness, and local or cloud dictation storage; those choices are different from Quill’s smaller no-history design, not inherently wrong.",
        ],
        links: [
          { label: "Wispr Flow pricing", href: "https://wisprflow.ai/pricing" },
          { label: "Wispr Flow data controls", href: "https://wisprflow.ai/data-controls" },
          { label: "Wispr Flow product guide", href: "https://docs.wisprflow.ai/articles/2772472373-what-is-flow" },
        ],
      },
      {
        heading: "Choose Quill if you want the smaller tool",
        paragraphs: [
          "Quill makes sense when your workflow lives on a Mac and you want dictation to feel like a system capability rather than another content library. It is especially suited to developers, privacy-conscious users, and anyone comfortable managing an API key.",
        ],
        bullets: [
          "You want a free and open-source client.",
          "You do not want another product account or subscription.",
          "You prefer no saved recording or transcript archive in the dictation app.",
          "You are comfortable using your own Gemini API key.",
          "You mainly dictate on macOS and value a focused menu-bar utility.",
        ],
      },
      {
        heading: "Choose Flow if you want the broader service",
        paragraphs: [
          "Flow is likely the better choice if you dictate across several operating systems, want the product to learn more about your writing over time, or need collaboration, administration, and a company-supported service.",
        ],
        bullets: [
          "You need Windows or mobile apps alongside macOS.",
          "You want 100+ languages and deeper adaptive personalization.",
          "You rely on transcript history, cloud sync, or notetaking features.",
          "You need centralized business or enterprise controls.",
          "You prefer a managed subscription over bringing your own model key.",
        ],
      },
      {
        heading: "Try Quill without rebuilding your workflow",
        paragraphs: [
          "You do not need to migrate a library because Quill does not create one. Install it, add your Gemini key, and compare both tools on the writing you actually do: a short reply, a paragraph with corrections, technical vocabulary, and a long thought in your most-used editor.",
          "The useful question is not which product wins every row. It is whether you value Flow’s broader service enough to want its account, history, and subscription model—or whether Quill’s smaller open-source boundary is the feature you were looking for.",
        ],
        links: [
          { label: "Set up Quill", href: "https://github.com/skundu42/quill/blob/main/README.md" },
          { label: "See how Quill works", href: "/#how-it-works" },
        ],
      },
    ],
  },
  {
    slug: "how-to-use-voice-typing-on-mac",
    title: "How to use voice typing on Mac without leaving your current app",
    seoTitle: "How to Use Voice Typing on Mac",
    description:
      "Learn how to set up voice typing on a Mac, dictate into any standard text field, choose the right workflow, and fix common permission issues.",
    excerpt:
      "A practical setup and workflow guide for turning speech into text wherever your cursor is on macOS.",
    category: "Guide",
    published: "August 28, 2026",
    publishedISO: "2026-08-28",
    readingTime: "6 min read",
    keywords: ["how to use voice typing on Mac", "voice typing Mac", "Mac speech to text"],
    sections: [
      {
        heading: "Start with the workflow, not the transcript window",
        paragraphs: [
          "The most useful kind of Mac voice typing begins where you are already writing. Click into an email, document, chat, issue, or browser field; invoke dictation; speak; and let the text return to that same cursor. A separate transcript app adds a review-and-paste loop that is useful for long recordings but cumbersome for everyday writing.",
          "Quill is built around the first model. It keeps a small menu-bar presence and uses a global shortcut, so the current app remains the center of the task.",
        ],
      },
      {
        heading: "Set up the three things dictation needs",
        paragraphs: [
          "Install Quill in Applications, add a Gemini API key, and grant Microphone and Accessibility access. Microphone permission supplies the live audio. Accessibility permission lets Quill remember the original text field and insert the final result there.",
          "The API key belongs to you and connects the Mac app directly to Gemini. Quill stores it locally in an owner-readable file rather than asking you to create a Quill account.",
        ],
        bullets: [
          "macOS 14 or later",
          "A Gemini API key with Live transcription access",
          "Microphone and Accessibility permission",
        ],
      },
      {
        heading: "Use a short, repeatable dictation loop",
        paragraphs: [
          "Place the cursor, hold Option–Space, and speak while the indicator says Listening. Release the shortcut when the thought is complete. Quill finalizes the text and inserts it at the original cursor. Escape cancels an active session.",
          "For longer passages, switch from hold-to-speak to toggle mode. Press once to begin and once to finish. The important habit is to finish one coherent thought at a time; smaller turns are easier to review and place correctly than a five-minute monologue.",
        ],
      },
      {
        heading: "Choose Smart or Verbatim for the job",
        paragraphs: [
          "Smart mode is useful for messages, notes, and drafts. It removes filler words, follows spoken corrections, and adds readable punctuation. Verbatim mode stays closer to the words you actually said, which helps with quotations, interview notes, or rough material where the original phrasing matters.",
          "Neither setting has to be permanent. Treat transcription style like a writing tool: Smart for clean output, Verbatim for faithful capture.",
        ],
      },
      {
        heading: "Fix the two most common Mac issues",
        paragraphs: [
          "If Quill cannot hear you, confirm Microphone access and check which input device is selected. If text does not appear at the cursor, confirm Accessibility access. Some applications use custom editors that do not expose a normal insertion target; in that case Quill preserves the result on the clipboard so you can paste it manually.",
          "Once those permissions are stable, voice typing becomes a small motor skill: cursor, shortcut, speech, release.",
        ],
      },
    ],
  },
  {
    slug: "dictate-in-any-mac-app",
    title: "How to dictate in any Mac app and keep your writing flow",
    seoTitle: "How to Dictate in Any Mac App",
    description:
      "Use system-wide dictation across browsers, editors, email, messaging, and other Mac apps without copying text between windows.",
    excerpt:
      "Why cursor-first dictation feels faster than recording elsewhere, plus a reliable workflow for cross-app text insertion.",
    category: "Workflow",
    published: "August 28, 2026",
    publishedISO: "2026-08-28",
    readingTime: "5 min read",
    keywords: ["dictate in any Mac app", "system-wide dictation Mac", "voice typing in browser Mac"],
    sections: [
      {
        heading: "System-wide dictation is really a focus problem",
        paragraphs: [
          "Capturing speech is only half of a good dictation workflow. The other half is returning the result to the exact field that had your attention before the microphone started. That field may live in a browser tab, a native editor, a chat window, or a cross-platform application.",
          "Quill captures the insertion target at the beginning of dictation. While you speak, you can watch the lightweight indicator instead of switching windows. When transcription finishes, Quill restores focus and inserts the text where the turn began.",
        ],
      },
      {
        heading: "Use direct insertion for daily writing",
        paragraphs: [
          "Direct insertion is the most fluid choice for ordinary Mac text fields. It avoids replacing the clipboard and makes a spoken sentence feel similar to typing one. This works well for email replies, issue descriptions, notes, search fields, and messages.",
          "Quill prepares the insertion route while transcription is running so less work remains after you release the shortcut. That reduces the moment where the app says Polishing and helps the text land quickly.",
        ],
      },
      {
        heading: "Keep a clipboard fallback for unusual editors",
        paragraphs: [
          "Not every app exposes its editor through standard macOS accessibility interfaces. Web canvases, remote desktops, games, and heavily customized text controls can make direct insertion unreliable. A responsible dictation app should not discard a finished transcript just because the destination disappeared.",
          "When Quill cannot safely type into the remembered target, it keeps the transcript on the clipboard and explains what happened. You can paste once and continue instead of repeating the dictation.",
        ],
      },
      {
        heading: "Match the shortcut behavior to the length of the thought",
        paragraphs: [
          "Hold-to-speak gives a clear physical boundary for short text: releasing the keys means the turn is done. Toggle mode is more comfortable for paragraphs because you do not have to keep two keys held down.",
          "Use a shortcut that does not collide with the applications you rely on. Quill accepts a non-modifier key combined with Command, Option, Control, or Shift, and lets you assign a separate shortcut for pasting the latest transcript again.",
        ],
        bullets: [
          "Hold-to-speak for commands, replies, and short notes",
          "Toggle mode for paragraphs and longer explanations",
          "Paste Last Transcript when the same text belongs in a second field",
        ],
      },
      {
        heading: "The best dictation interface is the one you stop noticing",
        paragraphs: [
          "A useful Mac dictation tool should not become another place to organize content. It should borrow the cursor, microphone, and a shortcut for a few seconds, then disappear again. That is the difference between a transcription workflow and a typing capability.",
        ],
      },
    ],
  },
  {
    slug: "private-speech-to-text-on-mac",
    title: "Private speech to text on Mac: what “no recordings stored” should mean",
    seoTitle: "Private Speech to Text on Mac",
    description:
      "Understand memory-only audio, bring-your-own-key transcription, local data, and the privacy boundaries of cloud speech to text on Mac.",
    excerpt:
      "A plain-language privacy model for cloud transcription that does not quietly build a local recording archive.",
    category: "Privacy",
    published: "August 28, 2026",
    publishedISO: "2026-08-28",
    readingTime: "7 min read",
    keywords: ["private speech to text Mac", "voice typing no recordings stored", "BYOK dictation app"],
    sections: [
      {
        heading: "Privacy claims need a data-flow diagram behind them",
        paragraphs: [
          "“Private” can describe several different architectures. Audio may remain entirely on the device, travel to a cloud model, be stored as a recording, or exist only long enough to stream. Those choices are not interchangeable, so a useful privacy page should say exactly which one applies.",
          "Quill uses cloud transcription but does not create a local recording archive. Microphone samples are buffered in memory, streamed from the Mac app to Gemini, and released when the live session ends.",
        ],
      },
      {
        heading: "Memory-only audio limits what the app can retain",
        paragraphs: [
          "Volatile memory is used for the small buffers needed to convert and send live audio reliably. Quill does not write those buffers to an audio file. When dictation completes, is cancelled, or fails, the session disconnects and the pending buffers are cleared.",
          "That means Quill cannot offer playback of old dictations—and cannot expose a library of old voice recordings—because that library does not exist.",
        ],
      },
      {
        heading: "Bring your own key removes an extra account layer",
        paragraphs: [
          "A bring-your-own-key app asks you to authenticate directly with the model provider. Quill does not operate an account system or a proxy transcription server. Your Gemini API key is stored locally with owner-only file permissions and used by the Mac app to open the live session.",
          "BYOK does not make cloud processing local. Audio still reaches Google for transcription, and Google’s API terms and data policies remain relevant. What it removes is an additional Quill-controlled server and credential database.",
        ],
      },
      {
        heading: "Transcript history and usage counts are different data",
        paragraphs: [
          "A transcript history preserves the content of what you said. A usage counter preserves a number. Quill stores daily and lifetime dictation and word counts locally, but not the text behind those counts. You can reset the numbers in Privacy & Access.",
          "The latest transcript stays in memory while Quill runs so Paste Last Transcript can work. It disappears when the app quits and is not added to a searchable archive.",
        ],
      },
      {
        heading: "Questions to ask any voice typing app",
        paragraphs: [
          "The best privacy comparison starts with concrete questions rather than a badge. Ask where audio is processed, whether recordings are written to disk, whether transcript history is enabled, what account is required, what permissions are used, and whether the implementation can be inspected.",
        ],
        bullets: [
          "Is microphone audio stored locally or remotely?",
          "Does the app retain transcript content or only aggregate counts?",
          "Does audio pass through the developer’s own server?",
          "Can the API credential and local data be removed or reset?",
          "Is the client source available for inspection?",
        ],
      },
    ],
  },
  {
    slug: "smart-vs-verbatim-dictation",
    title: "Smart vs. verbatim dictation: when should speech-to-text clean your words?",
    seoTitle: "Smart vs. Verbatim Dictation on Mac",
    description:
      "Compare smart and verbatim speech-to-text modes for Mac writing, including filler-word removal, spoken corrections, quotations, and rough notes.",
    excerpt:
      "Two transcription modes solve different writing problems. Here is how to choose without losing your voice.",
    category: "Writing",
    published: "August 28, 2026",
    publishedISO: "2026-08-28",
    readingTime: "5 min read",
    keywords: ["smart dictation Mac", "verbatim transcription Mac", "remove filler words speech to text"],
    sections: [
      {
        heading: "Speech and finished writing are not the same artifact",
        paragraphs: [
          "Natural speech contains pauses, restarts, filler words, and corrections that help a listener follow the thought in real time. On the page, those same cues often become clutter. Smart transcription treats speech as drafting material; verbatim transcription treats it as a record.",
          "Neither approach is universally better. The right choice depends on whether you are composing new text or preserving spoken language.",
        ],
      },
      {
        heading: "Use Smart mode when the destination is finished prose",
        paragraphs: [
          "Smart mode removes common fillers, follows corrections, and formats punctuation, dates, and numbers for readability. If you say, “Meet Tuesday—sorry, Wednesday at three,” the useful output is usually “Meet Wednesday at 3:00.”",
          "This mode is a strong default for email, messages, project updates, notes, and first drafts. It reduces cleanup while keeping the meaning of the turn.",
        ],
        bullets: [
          "Email and chat replies",
          "Meeting notes written in your own words",
          "Drafts, outlines, and task descriptions",
          "Text where spoken self-corrections should disappear",
        ],
      },
      {
        heading: "Use Verbatim mode when the wording itself is evidence",
        paragraphs: [
          "Verbatim mode stays closer to the original speech. It is useful when recording a quotation, capturing an interview note, drafting dialogue, studying speech patterns, or preserving a rough thought before editing it yourself.",
          "Verbatim does not mean a forensic transcript with speaker labels or word-level timestamps. It means Quill avoids the stronger rewriting behavior of Smart mode and keeps more of the spoken phrasing.",
        ],
      },
      {
        heading: "Custom vocabulary helps both modes hear the right words",
        paragraphs: [
          "Transcription style controls cleanup; vocabulary controls recognition hints. Add uncommon names, technical terms, acronyms, and product language that the model may otherwise replace with a more common phrase.",
          "A short, focused vocabulary list is more useful than a dictionary dump. Include terms that are both important and genuinely easy to mishear.",
        ],
      },
      {
        heading: "Switch modes by task, not by identity",
        paragraphs: [
          "You do not have to decide whether you are a “smart” or “verbatim” user. Choose Smart before writing a polished reply, switch to Verbatim before capturing a quotation, and change back when the task changes. The global shortcut stays the same; only the treatment of the final text changes.",
        ],
      },
    ],
  },
];

export function getBlogPost(slug: string) {
  return blogPosts.find((post) => post.slug === slug);
}
