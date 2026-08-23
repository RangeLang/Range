/**
 * A design knot is a place where Range's notation states one decision more
 * than once. The number of restatements is the knot's shape: five corners for
 * a pentagon, down through the square and the triangle, to a circle — a shape
 * with no corners left, which from any distance is a dot.
 *
 * Collapsing a knot is not deletion. It is finding the single spelling that
 * the other spellings were approximating.
 */

import manySource from "../../../Projects/RangeCompilerB/Sources/CompilerB/Core/Macros/Many.range?raw";
import constraintSource from "../../../Projects/RangeView/Macros/Constraint.range?raw";
import commandGroupSource from "../../../RangeCompiler/Sources/Core/Macro/CommandGroup.range?raw";
import routesSource from "../../../Testing/CommandLine/Pass/Routes.range?raw";

export type KnotShape = "pentagon" | "square" | "triangle" | "circle";

export const shapeCorners: Record<KnotShape, number> = {
  pentagon: 5,
  square: 4,
  triangle: 3,
  circle: 0,
};

/** One corner of the knot: a place the notation says the thing again. */
export type KnotCorner = {
  /** The exact spelling as it appears in the source. */
  spelling: string;
  /** The job this occurrence is doing. */
  role: string;
};

/** A real file the knot appears in, shown through a fading viewport. */
export type KnotSource = {
  /** Repository-relative path, shown as the caption. */
  path: string;
  /** The file, verbatim. */
  source: string;
  /** 1-based line the viewport opens on. */
  focusLine: number;
};

export type DesignKnot = {
  id: string;
  title: string;
  shape: KnotShape;
  sources: KnotSource[];
  /** What the notation keeps saying. */
  says: string;
  corners: KnotCorner[];
  question: string;
};

/**
 * The window a knot's file is read through: where it opens, and how many lines
 * stay legible before the source fades back into the rest of the file.
 */
export const codeViewportLines = 12;

export function viewportStart(focusLine: number) {
  return Math.max(0, focusLine - 2);
}

export const designKnots: DesignKnot[] = [
  {
    id: "ordering",
    title: "Order, three times",
    shape: "triangle",
    sources: [
      {
        path: "Projects/RangeCompilerB/Sources/CompilerB/Core/Macros/Many.range",
        source: manySource,
        focusLine: 1,
      },
    ],
    says: "order",
    corners: [
      { spelling: "ordering", role: "the label the caller writes" },
      { spelling: "Ordering", role: "the type that names the same idea" },
      { spelling: ".ordered", role: "the default case, saying it a third time" },
    ],
    question:
      "When a parameter's label, its type, and its default all carry the same word, which two of the three is the reader allowed to infer?",
  },
  {
    id: "registration",
    title: "Registering what is already registered",
    shape: "pentagon",
    sources: [
      {
        path: "RangeCompiler/Sources/Core/Macro/CommandGroup.range",
        source: commandGroupSource,
        focusLine: 1,
      },
      {
        path: "Testing/CommandLine/Pass/Routes.range",
        source: routesSource,
        focusLine: 1,
      },
    ],
    says: "@command",
    corners: [
      {
        spelling: "macro command(): Function {}",
        role: "an empty macro declared only so that something can be applied",
      },
      {
        spelling: "@command",
        role: "the application, which is the actual mark",
      },
      {
        spelling: "Array<@command>",
        role: "the collection type, naming the marker again",
      },
      {
        spelling: "filter(all: @command)",
        role: "the query that gathers back what was just marked",
      },
      {
        spelling: '"… at least one @command function."',
        role: "the diagnostic, spelling it a fifth time",
      },
    ],
    question:
      "The empty macro exists so that declarations can carry a mark — but applying a macro already marks a declaration. Registration is not a mechanism the language needs; it is a thing macros already are. And the whole shape is copied per feature: @test / @testGroup in Test.range, @collectionModifier in Compiler B's Bool.range, the same five corners each time.",
  },
  {
    id: "resulting-value",
    title: "The calculation that remains",
    shape: "circle",
    sources: [
      {
        path: "Projects/RangeView/Macros/Constraint.range",
        source: constraintSource,
        focusLine: 37,
      },
    ],
    says: "the resulting value",
    corners: [],
    question:
      "At the end of the day, this is what matters most in a calculation or transformation: the final expression states the value that comes out. The surrounding macro can query the graph, constrain the domain, and emit diagnostics; this line is the transformation.",
  },
];

/** Sample a shape's outline as `samples` points, matched for morphing. */
export function shapeOutline(
  corners: number,
  samples = 96,
  radius = 1,
  // A four-corner shape reads as a square rather than a diamond when its
  // vertices are turned half an edge; the odd-cornered shapes point up.
  rotation = corners === 4 ? Math.PI / 4 : 0,
): { x: number; y: number }[] {
  const points: { x: number; y: number }[] = [];
  const spin = rotation;
  for (let index = 0; index < samples; index += 1) {
    const t = index / samples;
    if (corners < 3) {
      const angle = -Math.PI / 2 + t * Math.PI * 2;
      points.push({ x: Math.cos(angle) * radius, y: Math.sin(angle) * radius });
      continue;
    }
    const edge = Math.floor(t * corners);
    const local = t * corners - edge;
    const vertex = (index: number) => {
      const angle =
        -Math.PI / 2 + spin + ((index % corners) * Math.PI * 2) / corners;
      return { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius };
    };
    const from = vertex(edge);
    const to = vertex(edge + 1);
    points.push({
      x: from.x + (to.x - from.x) * local,
      y: from.y + (to.y - from.y) * local,
    });
  }
  return points;
}

/** Blend two outlines of equal length into a closed SVG path. */
export function outlinePath(
  from: { x: number; y: number }[],
  to: { x: number; y: number }[],
  progress: number,
  scale: number,
): string {
  let path = "";
  for (let index = 0; index < from.length; index += 1) {
    const x = from[index].x + (to[index].x - from[index].x) * progress;
    const y = from[index].y + (to[index].y - from[index].y) * progress;
    path += `${index === 0 ? "M" : "L"} ${(x * scale).toFixed(2)} ${(y * scale).toFixed(2)} `;
  }
  return `${path}Z`;
}
/**
 * The inverse knot. A polygon gathers its corners in one place, where they can
 * be counted and collapsed. A distributed knot spends one spelling across many
 * places and lets position decide the meaning — so it looks like a dot from
 * every individual site, and is only a polygon when the whole file is held at
 * once. Distance does not resolve it. It hides it.
 */
export type DistributedSite = {
  notation: string;
  /** Where the spelling sits, which is the only thing selecting the meaning. */
  position: string;
  meaning: string;
};

export type DistributedKnot = {
  spelling: string;
  language: string;
  sites: DistributedSite[];
};

export const falseCircle: DistributedKnot = {
  spelling: "static",
  language: "C",
  sites: [
    {
      notation: "static int counter;",
      position: "file scope",
      meaning:
        "Internal linkage. The name is not visible outside this translation unit — a statement about who may refer to it.",
    },
    {
      notation: "void tick(void) {\n    static int calls;\n    calls += 1;\n}",
      position: "block scope",
      meaning:
        "Static storage duration. The name is as private as any local; what changed is that it outlives the call — a statement about lifetime.",
    },
    {
      notation: "void take(int rows[static 4]);",
      position: "array parameter",
      meaning:
        "Neither linkage nor lifetime. A promise that the caller passes at least four elements — a statement about the argument.",
    },
  ],
};

/**
 * The same one-name-many-expansions shape Range accepts in macros, with the
 * position written down instead of remembered.
 */
export const macroContrast = `macro many(count: Int?, ordering: Ordering: .ordered): Member -> LLVM
macro bool(): Construct -> LLVM
macro collectionModifier(): Function`;


/** Turn one outline into a closed SVG path. */
export function pathFromOutline(
  outline: { x: number; y: number }[],
  scale: number,
): string {
  let path = "";
  for (const [index, point] of outline.entries()) {
    path += `${index === 0 ? "M" : "L"} ${(point.x * scale).toFixed(2)} ${(point.y * scale).toFixed(2)} `;
  }
  return `${path}Z`;
}
