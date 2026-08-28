import Image from "next/image";
import Link from "next/link";
import { QuillLogo } from "@/components/QuillLogo";
import { VoiceDemo } from "@/components/VoiceDemo";
import { latestDmgUrl, siteConfig } from "@/app/site";

const repositoryUrl = siteConfig.repositoryUrl;

const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": `${siteConfig.url}/#website`,
      url: siteConfig.url,
      name: siteConfig.name,
      description: siteConfig.description,
      inLanguage: "en-US",
    },
    {
      "@type": "SoftwareApplication",
      "@id": `${siteConfig.url}/#software`,
      name: siteConfig.name,
      url: siteConfig.url,
      description: siteConfig.description,
      applicationCategory: "ProductivityApplication",
      applicationSubCategory: "Voice typing and dictation",
      operatingSystem: "macOS 14 or later",
      isAccessibleForFree: true,
      downloadUrl: latestDmgUrl,
      codeRepository: siteConfig.repositoryUrl,
      license: "https://www.apache.org/licenses/LICENSE-2.0",
      author: {
        "@type": "Person",
        name: siteConfig.authorName,
        url: siteConfig.authorUrl,
      },
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
      },
      featureList: [
        "System-wide voice typing",
        "Gemini-powered smart transcription",
        "Automatic language detection",
        "Local usage statistics",
        "Open-source macOS application",
      ],
    },
  ],
};

export default function HomePage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }}
      />
      <a className="skip-link" href="#main">
        Skip to content
      </a>

      <header className="site-header shell">
        <a className="brand" href="#top" aria-label="Quill home">
          <QuillLogo priority />
          <span>Quill</span>
        </a>

        <nav className="desktop-nav" aria-label="Main navigation">
          <a href="#how-it-works">How it works</a>
          <a href="#privacy">Privacy</a>
          <Link href="/blog">Blog</Link>
          <a className="github-nav-link" href={repositoryUrl} aria-label="Quill on GitHub">
            GitHub <span aria-hidden="true">↗</span>
          </a>
        </nav>

        <div className="header-actions">
          <a className="header-download" href={latestDmgUrl} aria-label="Download the latest Quill DMG from GitHub">
            Download <span aria-hidden="true">↓</span>
          </a>
          <a className="header-cta" href={repositoryUrl} aria-label="Star Quill on GitHub">
            Star
            <span className="arrow-box" aria-hidden="true">
              ★
            </span>
          </a>
        </div>
      </header>

      <main id="main">
        <section className="hero shell" id="top">
          <div className="hero-copy">
            <div className="hero-meta">
              <span className="hero-badge open-source-badge">
                <span className="open-source-mark" aria-hidden="true">
                  &lt;/&gt;
                </span>
                Fully open source
              </span>
              <span className="hero-badge gemini-badge">
                <Image
                  className="gemini-mark"
                  src="/brand/gemini-spark.png"
                  alt=""
                  width={18}
                  height={18}
                  aria-hidden="true"
                />
                Powered by Gemini
              </span>
            </div>
            <h1>
              Intelligent
              <br />
              {" "}
              <span>realtime dictation.</span>
            </h1>
            <p className="hero-intro">
              Hold one shortcut, speak naturally, and Quill puts polished text wherever your cursor is. No window. No copy and paste.
            </p>
          </div>

          <VoiceDemo />
        </section>

        <section className="workflow shell section" id="how-it-works">
          <div className="section-heading">
            <p className="eyebrow">One gesture, everywhere</p>
            <h2>Stay in the flow.</h2>
            <p>
              Quill is designed as a system capability, not another destination. Your hands and attention never leave the app you’re using.
            </p>
          </div>

          <div className="workflow-board">
            <div className="workflow-step">
              <span className="step-index">Shortcut down</span>
              <div className="keycap-group" aria-hidden="true">
                <kbd>⌥</kbd>
                <kbd>Space</kbd>
              </div>
              <h3>Hold</h3>
              <p>Recording starts in under 150 milliseconds.</p>
            </div>
            <div className="flow-connector" aria-hidden="true">
              <span />
            </div>
            <div className="workflow-step is-signal">
              <span className="step-index">While held</span>
              <div className="mini-wave" aria-hidden="true">
                {Array.from({ length: 7 }, (_, index) => (
                  <i key={index} />
                ))}
              </div>
              <h3>Speak</h3>
              <p>Talk naturally, even with pauses and corrections.</p>
            </div>
            <div className="flow-connector" aria-hidden="true">
              <span />
            </div>
            <div className="workflow-step">
              <span className="step-index">Shortcut up</span>
              <div className="insert-preview" aria-hidden="true">
                Thursday at 3 PM.<b />
              </div>
              <h3>Done</h3>
              <p>Polished text lands at your active cursor.</p>
            </div>
          </div>
        </section>

        <section className="smart-section shell section">
          <div className="section-heading compact">
            <p className="eyebrow">Smart transcription</p>
            <h2>
              Speak messily.
              <br />
              Write clearly.
            </h2>
          </div>

          <div className="rewrite-demo">
            <div className="rewrite-row raw-row">
              <span className="rewrite-label">You say</span>
              <p>“So, um, can you send that to John? Actually, wait, send it to Alex tomorrow morning.”</p>
            </div>
            <div className="rewrite-arrow" aria-hidden="true">
              <span />
              <svg viewBox="0 0 18 18">
                <path d="M3 9h11M10 5l4 4-4 4" />
              </svg>
            </div>
            <div className="rewrite-row clean-row">
              <span className="rewrite-label">Quill types</span>
              <p>Can you send that to Alex tomorrow morning?</p>
              <span className="text-cursor" aria-hidden="true" />
            </div>
          </div>

          <div className="capability-ticker" aria-label="Smart transcription capabilities">
            <span>Removes filler words</span>
            <i />
            <span>Understands corrections</span>
            <i />
            <span>Adds punctuation</span>
            <i />
            <span>Formats dates &amp; numbers</span>
            <i />
            <span>Supports 85+ languages</span>
          </div>
        </section>

        <section className="privacy-section shell section" id="privacy">
          <div className="privacy-visual" aria-hidden="true">
            <div className="privacy-node mic-node">
              <svg viewBox="0 0 32 32">
                <rect x="11" y="4" width="10" height="17" rx="5" />
                <path d="M7 16a9 9 0 0 0 18 0M16 25v4M11 29h10" />
              </svg>
              <span>Microphone</span>
            </div>
            <div className="data-line">
              <i />
              <i />
              <i />
            </div>
            <div className="privacy-node memory-node">
              <span className="memory-glyph">00</span>
              <span>Memory only</span>
            </div>
            <div className="data-line reverse">
              <i />
              <i />
              <i />
            </div>
            <div className="privacy-node trash-node">
              <svg viewBox="0 0 32 32">
                <path d="M9 10h14l-1 18H10L9 10ZM7 7h18M12 7l1-3h6l1 3M13 14v9M19 14v9" />
              </svg>
              <span>Deleted</span>
            </div>
          </div>

          <div className="privacy-copy">
            <p className="eyebrow">Private by default</p>
            <h2>Your voice leaves no footprint.</h2>
            <p>
              Audio is streamed from memory directly to Gemini for transcription, then discarded. Quill stores no recordings or transcript history.
            </p>
            <div className="privacy-facts">
              <div>
                <strong>0</strong>
                <span>audio retained</span>
              </div>
              <div>
                <strong>BYOK</strong>
                <span>your Gemini key</span>
              </div>
              <div>
                <strong>Local</strong>
                <span>owner-only key file</span>
              </div>
            </div>
          </div>
        </section>

        <section className="open-source-section shell section" id="open-source">
          <div className="source-card">
            <div className="source-copy">
              <p className="eyebrow">Open source, by design</p>
              <h2>
                Your keyboard.
                <br />
                Your key.
                <br />
                Your code.
              </h2>
              <p>
                Inspect it, extend it, or run your own fork. Quill’s macOS client is open source under the Apache 2.0 license with no backend required.
              </p>
            </div>
            <div className="source-terminal" aria-label="Terminal setup example">
              <div className="terminal-bar">
                <i />
                <i />
                <i />
                <span>Terminal · zsh</span>
              </div>
              <pre>
                <code>
                  <span className="prompt">$</span> git clone https://github.com/skundu42/quill.git{"\n"}
                  <span className="prompt">$</span> cd quill &amp;&amp; xcodegen generate{"\n\n"}
                  <span className="success">✓</span> Quill.xcodeproj is ready.
                </code>
              </pre>
            </div>
          </div>
        </section>

        <section className="final-cta shell section">
          <div>
            <p className="eyebrow">Less typing. More thinking.</p>
            <h2>
              Give your keyboard
              <br />a quiet day off.
            </h2>
          </div>
          <a className="download-button" href={latestDmgUrl} aria-label="Download the latest Quill DMG from GitHub">
            <span>
              <small>Free &amp; open source</small>Get Quill for macOS
            </span>
            <span className="download-arrow" aria-hidden="true">
              ↓
            </span>
          </a>
        </section>
      </main>

      <footer className="site-footer shell">
        <a className="brand footer-brand" href="#top">
          <QuillLogo />
          <span>Quill</span>
        </a>
        <p>Open-source voice typing for macOS.</p>
        <div className="footer-links">
          <a href={repositoryUrl}>
            GitHub <span aria-hidden="true">↗</span>
          </a>
          <a href="#privacy">Privacy</a>
          <Link href="/blog">Blog</Link>
          <a href={`${repositoryUrl}/blob/main/README.md`}>Docs</a>
        </div>
        <small>
          © 2026 Quill. Apache-2.0. <span aria-hidden="true">·</span> Built by{" "}
          <a href="https://x.com/SandipanKundu42">Sandipan Kundu</a>
        </small>
      </footer>
    </>
  );
}
