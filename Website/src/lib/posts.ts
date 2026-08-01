export const siteOrigin = "https://rangelang.org";

export type Post = {
  slug: string;
  href: string;
  previewHref?: string;
  category: string;
  cardTitle: string;
  cardDescription: string;
  description: string;
  palette: number;
  socialShader?: "sphere-lines" | "relationship-dots";
  cardPalette: {
    foreground: string;
    mutedForeground: string;
    background: string;
    contrast: number;
  };
};

export const posts: Post[] = [
  {
    slug: "command-group-registration",
    href: "/features/macros/command-group-registration",
    category: "Macro breakdown",
    cardTitle: "Registration by declaration",
    cardDescription: "A command group derives its closed command set.",
    description:
      "A source-first walkthrough of how @commandGroup discovers annotated functions and generates a command enum.",
    palette: 3,
    cardPalette: {
      foreground: "rgb(31 42 6)",
      mutedForeground: "rgb(72 75 44)",
      background: "rgb(221 244 134)",
      contrast: 8.84,
    },
  },
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
    category: "Macro breakdown",
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
];

export const draftPosts: Post[] = [
  {
    slug: "intro-to-range-2",
    href: "/posts/intro-to-range-2",
    previewHref: "/posts/intro-to-range-2?preview=range-draft",
    category: "Introduction",
    cardTitle: "Intro to Range: The Concrete",
    cardDescription:
      "One plotted graph. Values carry the metadata for their relationships.",
    description:
      "How the Range compiler uses typed relationship values to describe multiplicity, order, separators, and enclosure.",
    palette: 6,
    socialShader: "relationship-dots",
    cardPalette: {
      foreground: "rgb(40 20 88)",
      mutedForeground: "rgb(76 64 103)",
      background: "rgb(239 239 252)",
      contrast: 13.84,
    },
  },
  {
    slug: "one-source-two-lenses",
    href: "/posts/one-source-two-lenses",
    previewHref:
      "/posts/one-source-two-lenses?preview=range-draft",
    category: "Observation",
    cardTitle: "One Source, Two Lenses",
    cardDescription:
      "In Range, written source and intended meaning share one typed graph.",
    description:
      "In Range, written source and intended meaning share one typed graph.",
    palette: 4,
    socialShader: "sphere-lines",
    cardPalette: {
      foreground: "rgb(15 21 31)",
      mutedForeground: "rgb(53 59 68)",
      background: "rgb(246 249 252)",
      contrast: 17.2,
    },
  },
  {
    slug: "intro-to-range",
    href: "/posts/intro-to-range",
    previewHref: "/posts/intro-to-range?preview=range-draft",
    category: "Introduction",
    cardTitle: "Intro to Range: The Material",
    cardDescription:
      "Identity and value, four binding intents, three abstraction forms.",
    description:
      "The smallest pieces of Range: identity and value, binding intents, and the three abstraction forms.",
    palette: 5,
    cardPalette: {
      foreground: "rgb(94 0 34)",
      mutedForeground: "rgb(101 46 60)",
      background: "rgb(255 166 184)",
      contrast: 6.9,
    },
  },
  {
    slug: "intro-to-range-3",
    href: "/posts/intro-to-range-3",
    previewHref: "/posts/intro-to-range-3?preview=range-draft",
    category: "Introduction",
    cardTitle: "Intro to Range: The Meta",
    cardDescription:
      "Macros use identities, values, and relationships to make structure.",
    description:
      "How Range macros operate on the identity-bearing graph to make reusable program structure.",
    palette: 7,
    cardPalette: {
      foreground: "rgb(54 23 0)",
      mutedForeground: "rgb(101 62 35)",
      background: "rgb(255 226 180)",
      contrast: 9.2,
    },
  },
  {
    slug: "intro-to-range-4",
    href: "/posts/intro-to-range-4",
    previewHref: "/posts/intro-to-range-4?preview=range-draft",
    category: "Introduction",
    cardTitle: "Intro to Range: The Substrate",
    cardDescription:
      "One graph pattern scales from syntax to databases and beyond.",
    description:
      "How one graph pattern can represent written syntax, databases, and anything else you need to express.",
    palette: 8,
    cardPalette: {
      foreground: "rgb(24 28 65)",
      mutedForeground: "rgb(67 70 109)",
      background: "rgb(214 228 255)",
      contrast: 10.4,
    },
  },
];

export const allPosts = [...posts, ...draftPosts];

export function postForPath(pathname: string) {
  return allPosts.find((post) => post.href === pathname);
}

export function postForSlug(slug: string) {
  return allPosts.find((post) => post.slug === slug);
}

export function postImagePath(post: Post) {
  return `/og/posts/${post.slug}.png`;
}

export function postImageUrl(post: Post) {
  return `${siteOrigin}${postImagePath(post)}`;
}
