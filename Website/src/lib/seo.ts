import { benchmarkRecords, data } from "$lib/benchmarks";
import {
  allPosts,
  postForPath,
  postImageUrl,
  publishedPosts,
  siteOrigin,
} from "$lib/posts";

export const repositoryUrl = "https://github.com/RangeLang/Range";
export const homepageTitle =
  "Range Programming Language — Self-Hosting and Native";
export const homepageDescription =
  "Range is an open-source, self-hosting programming language with graph-aware macros and a native LLVM compiler.";
export const defaultSocialImage = `${siteOrigin}/og-homepage.png`;

export type SeoPage = {
  path: string;
  title: string;
  description: string;
  canonicalUrl?: string;
  image: string;
  imageAlt: string;
  openGraphType: "website" | "article";
  indexable: boolean;
  structuredData?: Record<string, unknown> | Record<string, unknown>[];
};

const languageIdentity = `${siteOrigin}/#language`;
const websiteIdentity = `${siteOrigin}/#website`;
const benchmarkDatasetIdentity = `${siteOrigin}/benchmarks#dataset`;

function canonicalUrl(path: string) {
  return new URL(path, siteOrigin).href;
}

function homepageSeo(): SeoPage {
  return {
    path: "/",
    title: homepageTitle,
    description: homepageDescription,
    canonicalUrl: canonicalUrl("/"),
    image: defaultSocialImage,
    imageAlt: "Range programming language",
    openGraphType: "website",
    indexable: true,
    structuredData: [
      {
        "@context": "https://schema.org",
        "@type": "WebSite",
        "@id": websiteIdentity,
        url: canonicalUrl("/"),
        name: "Range",
        description: homepageDescription,
        about: { "@id": languageIdentity },
      },
      {
        "@context": "https://schema.org",
        "@type": "ComputerLanguage",
        "@id": languageIdentity,
        name: "Range",
        url: canonicalUrl("/"),
        description: homepageDescription,
        sameAs: [repositoryUrl],
      },
    ],
  };
}

function benchmarkIndexSeo(): SeoPage {
  const description =
    "Reproducible native performance measurements for the Range programming language compared with C, C++, Rust, Go, and Swift.";
  return {
    path: "/benchmarks",
    title: "Range Programming Language Benchmarks — Native Performance",
    description,
    canonicalUrl: canonicalUrl("/benchmarks"),
    image: defaultSocialImage,
    imageAlt: "Range programming language benchmark suite",
    openGraphType: "website",
    indexable: true,
    structuredData: {
      "@context": "https://schema.org",
      "@type": "Dataset",
      "@id": benchmarkDatasetIdentity,
      name: "Range Programming Language Benchmarks",
      description,
      url: canonicalUrl("/benchmarks"),
      dateModified: data.generatedAt,
      about: { "@id": languageIdentity },
      isAccessibleForFree: true,
      distribution: {
        "@type": "DataDownload",
        contentUrl: canonicalUrl("/benchmarks.json"),
        encodingFormat: "application/json",
      },
    },
  };
}

function benchmarkDetailSeo(record: any): SeoPage {
  const path = `/benchmarks/${record.leaf.id}`;
  const name = `${record.subcategory.name} · ${record.leaf.name}`;
  const description = record.leaf.description;
  return {
    path,
    title: `${record.leaf.name} Benchmark — Range Programming Language`,
    description,
    canonicalUrl: canonicalUrl(path),
    image: defaultSocialImage,
    imageAlt: `${name} benchmark for Range`,
    openGraphType: "website",
    indexable: true,
    structuredData: {
      "@context": "https://schema.org",
      "@type": "Dataset",
      name,
      description,
      url: canonicalUrl(path),
      dateModified: data.generatedAt,
      isPartOf: { "@id": benchmarkDatasetIdentity },
      about: { "@id": languageIdentity },
      isAccessibleForFree: true,
      distribution: {
        "@type": "DataDownload",
        contentUrl: canonicalUrl("/benchmarks.json"),
        encodingFormat: "application/json",
      },
    },
  };
}

function postSeo(post: (typeof allPosts)[number], indexable: boolean): SeoPage {
  const title = `${post.cardTitle} — Range Programming Language`;
  const image = postImageUrl(post);
  const page: SeoPage = {
    path: post.href,
    title,
    description: post.description,
    canonicalUrl: indexable ? canonicalUrl(post.href) : undefined,
    image,
    imageAlt: `${post.cardTitle} — ${post.cardDescription}`,
    openGraphType: "article",
    indexable,
  };

  if (indexable) {
    page.structuredData = {
      "@context": "https://schema.org",
      "@type": "BlogPosting",
      headline: post.cardTitle,
      description: post.description,
      url: canonicalUrl(post.href),
      mainEntityOfPage: canonicalUrl(post.href),
      image,
      about: { "@id": languageIdentity },
      isPartOf: { "@id": websiteIdentity },
    };
  }

  return page;
}

export const indexableSeoPages: SeoPage[] = [
  homepageSeo(),
  benchmarkIndexSeo(),
  ...benchmarkRecords()
    .filter(({ leaf }) => leaf.results.length > 0)
    .map(benchmarkDetailSeo),
  ...publishedPosts.map((post) => postSeo(post, true)),
];

const indexableSeoByPath = new Map(
  indexableSeoPages.map((page) => [page.path, page]),
);

export function seoForPath(pathname: string): SeoPage | undefined {
  const indexablePage = indexableSeoByPath.get(pathname);
  if (indexablePage) return indexablePage;
  const post = postForPath(pathname);
  return post ? postSeo(post, false) : undefined;
}

export function isDraftPath(pathname: string) {
  return allPosts.some((post) => post.draft && post.href === pathname);
}

export function isSearchPrivatePath(pathname: string) {
  return (
    isDraftPath(pathname) ||
    pathname.startsWith("/__preview/") ||
    pathname.startsWith("/__og-card/") ||
    pathname.startsWith("/api/") ||
    pathname === "/health" ||
    pathname === "/performance" ||
    pathname === "/design-knots"
  );
}
