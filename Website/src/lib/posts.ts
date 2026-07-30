export const siteOrigin = "https://rangelang.org";

export type Post = {
  slug: string;
  href: string;
  category: string;
  cardTitle: string;
  cardDescription: string;
  description: string;
  palette: number;
  cardPalette: {
    foreground: string;
    mutedForeground: string;
    background: string;
    contrast: number;
  };
};

export const posts: Post[] = [
  {
    slug: "50-declarative-50-imperative",
    href: "/features/macros/50-declarative-50-imperative",
    category: "Language design",
    cardTitle: "50% Declarative, 50% Imperative",
    cardDescription: "Two modes of execution. Same baseline.",
    description:
      "Range macros combine declarative graph access with ordinary compile-time control flow.",
    palette: 0,
    cardPalette: {
      foreground: "rgb(0 8 94)",
      mutedForeground: "rgb(0 56 81)",
      background: "rgb(239 150 82)",
      contrast: 6.51,
    },
  },
  {
    slug: "somewhere-sometime-some-here",
    href: "/features/macros/somewhere-sometime-some-here",
    category: "Metaprogramming",
    cardTitle: "Somewhere, Sometime, Some-here",
    cardDescription: "Environment as place, phase, and local context.",
    description:
      "Somewhere gives a Range macro a place. Sometime gives it a phase. Some place gives it a boundary.",
    palette: 1,
    cardPalette: {
      foreground: "rgb(166 0 65)",
      mutedForeground: "rgb(127 56 71)",
      background: "rgb(50 240 229)",
      contrast: 4.59,
    },
  },
  {
    slug: "codability-under-100",
    href: "/features/macros/codability-under-100",
    category: "Metaprogramming",
    cardTitle: "Codability under 100",
    cardDescription: "One Range-authored macro, explained line by line.",
    description:
      "A line-by-line exploration of how Range implements Codable with graph queries, code expansion, splicing, and reusable nested macros.",
    palette: 2,
    cardPalette: {
      foreground: "rgb(0 85 0)",
      mutedForeground: "rgb(55 78 61)",
      background: "rgb(255 160 240)",
      contrast: 4.61,
    },
  },
  {
    slug: "strings-go-fast",
    href: "/optimizations/general/strings-go-fast",
    category: "Compiler update",
    cardTitle: "Strings Go Fast",
    cardDescription: "100k appends, from 491.2 ms to 4.1 ms.",
    description:
      "How Range made 100,000 String appends about 120 times faster while sharply reducing peak memory.",
    palette: 3,
    cardPalette: {
      foreground: "rgb(47 0 126)",
      mutedForeground: "rgb(40 28 86)",
      background: "rgb(196 202 68)",
      contrast: 4.67,
    },
  },
];

export function postForPath(pathname: string) {
  return posts.find((post) => post.href === pathname);
}

export function postForSlug(slug: string) {
  return posts.find((post) => post.slug === slug);
}

export function postImagePath(post: Post) {
  return `/og/posts/${post.slug}.png`;
}

export function postImageUrl(post: Post) {
  return `${siteOrigin}${postImagePath(post)}`;
}
