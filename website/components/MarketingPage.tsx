import type { ReactNode } from "react";

import { SiteFooter, SiteHeader } from "@/components/SiteChrome";

export function MarketingPage({ children }: { children: ReactNode }) {
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>
      <SiteHeader />
      <main id="main">{children}</main>
      <SiteFooter />
    </>
  );
}
