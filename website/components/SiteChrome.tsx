import Link from "next/link";

import { latestDmgUrl, siteConfig } from "@/app/site";
import { QuillLogo } from "@/components/QuillLogo";

const navigation = [
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#privacy", label: "Privacy" },
  { href: "/blog", label: "Blog" },
];

export function SiteHeader() {
  return (
    <header className="site-header shell">
      <Link className="brand" href="/" aria-label="Quill home">
        <QuillLogo priority />
        <span>Quill</span>
      </Link>

      <nav className="desktop-nav" aria-label="Main navigation">
        {navigation.map((item) => (
          <Link href={item.href} key={item.href}>
            {item.label}
          </Link>
        ))}
      </nav>

      <div className="header-actions">
        <a className="header-download" href={latestDmgUrl} aria-label="Download the latest Quill DMG from GitHub">
          Download <span aria-hidden="true">↓</span>
        </a>
        <a className="header-cta" href={siteConfig.repositoryUrl} aria-label="Star Quill on GitHub">
          Star
          <span className="arrow-box" aria-hidden="true">★</span>
        </a>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="site-footer shell">
      <Link className="brand footer-brand" href="/">
        <QuillLogo />
        <span>Quill</span>
      </Link>
      <p>Open-source voice typing for macOS.</p>
      <div className="footer-links">
        <Link href="/blog">Blog</Link>
        <a href={siteConfig.repositoryUrl}>GitHub <span aria-hidden="true">↗</span></a>
        <Link href="/#privacy">Privacy</Link>
        <a href={`${siteConfig.repositoryUrl}/blob/main/README.md`}>Docs</a>
      </div>
      <small>
        © 2026 Quill. Apache-2.0. <span aria-hidden="true">·</span> Built by{" "}
        <a href={siteConfig.authorUrl}>Sandipan Kundu</a>
      </small>
    </footer>
  );
}
