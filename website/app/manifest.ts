import type { MetadataRoute } from "next";

import { siteConfig } from "@/app/site";

export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Quill Voice Typing for macOS",
    short_name: siteConfig.name,
    description: siteConfig.description,
    start_url: "/",
    display: "standalone",
    background_color: "#f6f7f4",
    theme_color: "#153f37",
    icons: [
      {
        src: "/brand/quill-logo.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any",
      },
    ],
  };
}
