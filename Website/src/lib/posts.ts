export const siteOrigin = "https://rangelang.org";
const socialImageVersion = "2026-08-02-2";

export type Post = {
  slug: string;
  href: string;
  category: string;
  cardTitle: string;
  cardDescription: string;
  description: string;
  palette: number;
  draft?: boolean;
  socialShader?: "fibonacci-sphere" | "sphere-lines";
  cardPalette: {
    foreground: string;
    mutedForeground: string;
    background: string;
    contrast: number;
  };
};

export function postHref(post: Post) {
  return post.draft ? `${post.href}?preview=range-draft` : post.href;
}

export const posts: Post[] = [
  {
    slug: "intro-to-range",
    href: "/posts/intro-to-range",
    category: "Introduction",
    cardTitle: "Introduction to Range",
    cardDescription: "The basic building blocks of the graph",
    description:
      "Range begins with Identity : Value, then binding intents and the three concrete substrate forms.",
    palette: 5,
    socialShader: "fibonacci-sphere",
    cardPalette: {
      foreground: "rgb(94 0 34)",
      mutedForeground: "rgb(101 46 60)",
      background: "rgb(255 166 184)",
      contrast: 6.9,
    },
  },
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
    cardTitle: "Somewhere, Sometime",
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
  {
    slug: "class-v-struct",
    href: "/posts/class-v-struct",
    category: "Observation",
    cardTitle: "Class v. Struct",
    cardDescription:
      "The old argument is tired, but it keeps walking back into the room.",
    description:
      "Values should be understandable in isolation, and some things should keep a stable identity as they move through a system.",
    palette: 9,
    draft: true,
    cardPalette: {
      foreground: "rgb(33 25 18)",
      mutedForeground: "rgb(82 69 57)",
      background: "rgb(238 218 188)",
      contrast: 12.4,
    },
  },
  {
    slug: "intro-to-range-2",
    href: "/posts/intro-to-range-2",
    category: "Introduction",
    cardTitle: "Intro to Range: The Concrete",
    cardDescription:
      "Core becomes the Range compiler. The Range compiler becomes every project.",
    description:
      "How Range grows from its smallest compiler authority into a self-hosted compiler and the projects it compiles.",
    palette: 6,
    draft: true,
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
    category: "Observation",
    cardTitle: "One Source, Two Lenses",
    cardDescription:
      "In Range, written source and intended meaning share one typed graph.",
    description:
      "In Range, written source and intended meaning share one typed graph.",
    palette: 4,
    draft: true,
    socialShader: "sphere-lines",
    cardPalette: {
      foreground: "rgb(15 21 31)",
      mutedForeground: "rgb(53 59 68)",
      background: "rgb(246 249 252)",
      contrast: 17.2,
    },
  },
  {
    slug: "intro-to-range-3",
    href: "/posts/intro-to-range-3",
    category: "Introduction",
    cardTitle: "Intro to Range: The Meta",
    cardDescription:
      "Macros use identities, values, and relationships to make structure.",
    description:
      "How Range macros operate on the identity-bearing graph to make reusable program structure.",
    palette: 7,
    draft: true,
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
    category: "Introduction",
    cardTitle: "Intro to Range: The Substrate",
    cardDescription:
      "One graph pattern scales from syntax to databases and beyond.",
    description:
      "How one graph pattern can represent written syntax, databases, and anything else you need to express.",
    palette: 8,
    draft: true,
    cardPalette: {
      foreground: "rgb(24 28 65)",
      mutedForeground: "rgb(67 70 109)",
      background: "rgb(214 228 255)",
      contrast: 10.4,
    },
  },
  {
    slug: "programming-language-design-knots",
    href: "/posts/programming-language-design-knots",
    category: "Language design",
    cardTitle: "Programming Language Design Knots",
    cardDescription:
      "When every local rule changes the shape of the language beneath it.",
    description:
      "What it feels like to reason about syntax and semantics while the substrate itself keeps changing shape.",
    palette: 10,
    draft: true,
    cardPalette: {
      foreground: "rgb(37 25 69)",
      mutedForeground: "rgb(82 67 112)",
      background: "rgb(229 214 255)",
      contrast: 12.1,
    },
  },
  {
    slug: "optionality-vs-existentiality",
    href: "/posts/optionality-vs-existentiality",
    category: "Language design",
    cardTitle: "Optionality v. Existentiality",
    cardDescription:
      "Maybe a relationship. Somewhere a type. Two different kinds of unknown.",
    description:
      "Range separates the question of whether a value occurs from the question of which type a value is.",
    palette: 11,
    draft: true,
    cardPalette: {
      foreground: "rgb(18 39 48)",
      mutedForeground: "rgb(56 78 86)",
      background: "rgb(201 240 235)",
      contrast: 10.8,
    },
  },
  {
    slug: "requirement-and-provision",
    href: "/posts/requirement-and-provision",
    category: "Language design",
    cardTitle: "Requirement and Provision: A Modern Split",
    cardDescription:
      "One declaration in the environment can be both sides of the split.",
    description:
      "Requirement and provision were never two features; they are two consumption states of one environment contribution.",
    palette: 2,
    draft: true,
    cardPalette: {
      foreground: "rgb(0 85 0)",
      mutedForeground: "rgb(55 78 61)",
      background: "rgb(255 160 240)",
      contrast: 4.61,
    },
  },
];

export const publishedPosts = posts.filter((post) => !post.draft);
export const allPosts = posts;

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
  return `${siteOrigin}${postImagePath(post)}?v=${socialImageVersion}`;
}
