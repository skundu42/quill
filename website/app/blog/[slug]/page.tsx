import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { blogPosts, getBlogPost } from "@/app/blog/posts";
import { createPageMetadata } from "@/app/seo";
import { siteConfig } from "@/app/site";
import { MarketingPage } from "@/components/MarketingPage";

type BlogPostPageProps = {
  params: Promise<{ slug: string }>;
};

export const dynamicParams = false;

export function generateStaticParams() {
  return blogPosts.map((post) => ({ slug: post.slug }));
}

export async function generateMetadata({ params }: BlogPostPageProps): Promise<Metadata> {
  const { slug } = await params;
  const post = getBlogPost(slug);
  if (!post) return {};
  return createPageMetadata({
    title: post.seoTitle,
    description: post.description,
    path: `/blog/${post.slug}`,
    keywords: post.keywords,
  });
}

export default async function BlogPostPage({ params }: BlogPostPageProps) {
  const { slug } = await params;
  const post = getBlogPost(slug);
  if (!post) notFound();

  const structuredData = {
    "@context": "https://schema.org",
    "@type": "Article",
    headline: post.title,
    description: post.description,
    datePublished: post.publishedISO,
    dateModified: post.publishedISO,
    mainEntityOfPage: `${siteConfig.url}/blog/${post.slug}`,
    author: { "@type": "Person", name: siteConfig.authorName, url: siteConfig.authorUrl },
    publisher: { "@type": "Organization", name: siteConfig.name, url: siteConfig.url },
  };

  return (
    <MarketingPage>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }}
      />
      <article className="article-page shell">
        <header className="article-header">
          <Link href="/blog">← All guides</Link>
          <div className="post-meta"><span>{post.category}</span><time dateTime={post.publishedISO}>{post.published}</time><span>{post.readingTime}</span></div>
          <h1>{post.title}</h1>
          <p>{post.excerpt}</p>
        </header>
        <div className="article-layout">
          <aside className="article-rail" aria-label="Article sections">
            <span>In this guide</span>
            {post.sections.map((section, index) => <a href={`#section-${index + 1}`} key={section.heading}>{section.heading}</a>)}
          </aside>
          <div className="article-body">
            {post.sections.map((section, index) => (
              <section id={`section-${index + 1}`} key={section.heading}>
                <span className="section-number">{String(index + 1).padStart(2, "0")}</span>
                <h2>{section.heading}</h2>
                {section.paragraphs.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
                {section.comparison && (
                  <div className="article-comparison" role="table" aria-label="Quill and Wispr Flow comparison">
                    <div className="article-comparison-row article-comparison-head" role="row">
                      <span role="columnheader">Compare</span>
                      <span role="columnheader">Quill</span>
                      <span role="columnheader">Wispr Flow</span>
                    </div>
                    {section.comparison.map((row) => (
                      <div className="article-comparison-row" role="row" key={row.label}>
                        <strong role="rowheader">{row.label}</strong>
                        <span role="cell" data-label="Quill">{row.quill}</span>
                        <span role="cell" data-label="Wispr Flow">{row.flow}</span>
                      </div>
                    ))}
                  </div>
                )}
                {section.bullets && <ul>{section.bullets.map((bullet) => <li key={bullet}>{bullet}</li>)}</ul>}
                {section.links && (
                  <div className="article-links">
                    {section.links.map((link) => <Link href={link.href} key={link.href}>{link.label} →</Link>)}
                  </div>
                )}
              </section>
            ))}
            <aside className="article-next">
              <span>Keep exploring</span>
              <h2>Set up Quill, or inspect exactly how it handles your voice.</h2>
              <div><Link href="/#how-it-works">See how Quill works →</Link><Link href="/#privacy">Read the privacy overview →</Link></div>
            </aside>
          </div>
        </div>
      </article>
    </MarketingPage>
  );
}
