import { ImageResponse } from "next/og";

export const dynamic = "force-static";
export const alt = "Quill, intelligent real-time dictation for macOS";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          position: "relative",
          overflow: "hidden",
          background: "#f6f7f4",
          color: "#111312",
          fontFamily: "Arial, Helvetica, sans-serif",
          padding: 42,
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            display: "flex",
            flexDirection: "column",
            position: "relative",
            overflow: "hidden",
            border: "2px solid #111312",
            borderRadius: 32,
            background: "linear-gradient(118deg, #153f37 0%, #2c6a57 62%, #5c8b68 100%)",
            padding: "42px 54px 48px",
          }}
        >
          <div
            style={{
              position: "absolute",
              width: 520,
              height: 520,
              border: "2px solid rgba(202,255,112,.45)",
              borderRadius: 999,
              right: -105,
              top: -220,
              boxShadow: "0 0 0 76px rgba(202,255,112,.06), 0 0 0 152px rgba(202,255,112,.035)",
            }}
          />

          <div style={{ display: "flex", alignItems: "center", color: "white" }}>
            <div
              style={{
                width: 64,
                height: 64,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                borderRadius: 16,
                background: "#111312",
              }}
            >
              <svg width="48" height="48" viewBox="0 0 64 64">
                <path d="M45.8 14.4c-10.6 2.3-18.3 7.5-23.1 15.5-3 5-4.3 10.3-4 15.9l7.8-8.2 5.5-.3-4.1-2.2 5.7-6.1 5.7-.2-4.2-2.4c3.6-3.8 7.6-7.8 10.7-12Z" fill="#ddffc5" />
                <path d="M17 50c5.8-9.1 12.4-17.1 20-24" fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" />
              </svg>
            </div>
            <div style={{ display: "flex", marginLeft: 18, fontSize: 34, fontWeight: 700, letterSpacing: -1 }}>
              Quill
            </div>
            <div
              style={{
                display: "flex",
                marginLeft: "auto",
                padding: "10px 17px",
                border: "1px solid rgba(202,255,112,.6)",
                borderRadius: 999,
                background: "rgba(202,255,112,.12)",
                color: "#ddffc5",
                fontSize: 18,
                fontWeight: 700,
              }}
            >
              Free and open source
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", marginTop: 76 }}>
            <div style={{ display: "flex", color: "white", fontSize: 76, fontWeight: 700, letterSpacing: -4, lineHeight: 0.94 }}>
              Intelligent
            </div>
            <div style={{ display: "flex", color: "#caff70", fontSize: 76, fontWeight: 700, letterSpacing: -4, lineHeight: 0.94 }}>
              real-time dictation.
            </div>
          </div>

          <div
            style={{
              display: "flex",
              alignItems: "center",
              marginTop: "auto",
              color: "rgba(255,255,255,.82)",
              fontSize: 21,
              fontWeight: 600,
            }}
          >
            Voice typing for macOS
            <span style={{ display: "flex", margin: "0 14px", color: "#caff70" }}>•</span>
            Works wherever your cursor is
            <span style={{ display: "flex", margin: "0 14px", color: "#caff70" }}>•</span>
            Powered by Gemini
          </div>
        </div>
      </div>
    ),
    size,
  );
}
