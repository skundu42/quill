import type { Metadata, Viewport } from "next";

import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://github.com/skundu42/quill"),
  title: "Quill | Voice typing for macOS",
  description:
    "Quill is open-source, system-wide voice typing for macOS. Hold a shortcut, speak, and polished text appears wherever you are typing.",
  icons: {
    icon: "/brand/quill-logo.svg",
  },
  openGraph: {
    title: "Quill | Voice typing for macOS",
    description:
      "Hold one shortcut, speak naturally, and Quill puts polished text wherever your cursor is.",
    type: "website",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#f6f7f4",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
