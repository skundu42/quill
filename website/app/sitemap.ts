import type { MetadataRoute } from "next";

import { siteConfig } from "@/app/site";
import { blogPosts } from "@/app/blog/posts";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: siteConfig.url,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${siteConfig.url}/blog`,
      changeFrequency: "weekly",
      priority: 0.8,
    },
    ...blogPosts.map((post) => ({
      url: `${siteConfig.url}/blog/${post.slug}`,
      lastModified: post.publishedISO,
      changeFrequency: "monthly" as const,
      priority: 0.7,
    })),
  ];
}
