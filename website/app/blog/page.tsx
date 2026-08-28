import type { Metadata } from "next";
import Link from "next/link";

import { blogPosts } from "@/app/blog/posts";
import { createPageMetadata } from "@/app/seo";
import { MarketingPage } from "@/components/MarketingPage";

export const metadata: Metadata = createPageMetadata({
  title: "Mac Voice Typing Guides",
  description:
    "Practical guides to Mac voice typing, private speech to text, dictation workflows, and open-source alternatives to tools such as Wispr Flow.",
  path: "/blog",
  keywords: ["Mac voice typing guides", "Mac dictation tips", "Wispr Flow alternative"],
});

export default function BlogPage() {
  return (
    <MarketingPage>
      <section className="blog-index shell">
        {blogPosts.map((post, index) => (
          <article className={index === 0 ? "blog-card featured-post" : "blog-card"} key={post.slug}>
            <div className="post-meta"><span>{post.category}</span><time dateTime={post.publishedISO}>{post.published}</time><span>{post.readingTime}</span></div>
            <h2><Link href={`/blog/${post.slug}`}>{post.title}</Link></h2>
            <p>{post.excerpt}</p>
            <Link className="read-link" href={`/blog/${post.slug}`}>Read guide <span aria-hidden="true">→</span></Link>
          </article>
        ))}
      </section>

    </MarketingPage>
  );
}
