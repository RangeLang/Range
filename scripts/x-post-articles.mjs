#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
loadEnv(path.join(root, ".env"));

const maxChars = Number(process.env.X_MAX_CHARS || "280");
const dryRun = !process.argv.includes("--publish") || process.env.X_DRY_RUN === "true";
const selectedArticle = argValue("--article");

const articles = {
  "value-generics": {
    title: "Value Generics & Macros",
    source: "docs/posts/dynamic-property-metadata.md",
    posts: [
      "Value Generics & Macros\n\nA construct can be empty because the meaningful shape is in the declaration header.",
      "@componentStorage\nconstruct Vector<let dimensionality: IntLiteral, Scalar> {}\n\nThe macro can add storage, accessors, and map while preserving dimensionality.",
      "Vector<3, Float> already says this is a 3-component Float vector.\n\nThe author should not need to repeat that fact in side metadata.",
      "The design surface is not finalized yet.\n\nThe direction is: value-generic facts should be visible to macros and to the graph before lowering.",
    ],
  },
  "namespace-collection": {
    title: "Namespace Declaration Collection",
    source: "docs/posts/namespace-declaration-collection.md",
    posts: [
      "Namespace Declaration Collection\n\nNamespace attributes can give the graph one collection boundary for declarations and their applications.",
      "#namespace\nconstruct Declaration {\n  function members(for declaration: Declaration.Type) -> [Declaration.Member]\n  function applications(of declaration: Declaration.Type) -> [Declaration.Application]\n}",
      "@Declaration can mark both the declaration and the application site.\n\nThe graph can collect both sides through the same namespace-backed attribute.",
      "The namespace owns shared behavior.\n\nThe attribute marks where that behavior applies.\n\nThe parser does not need a hardcoded rule for each domain.",
    ],
  },
};

if (process.argv.includes("--help")) {
  console.log(`Usage:
  npm run post:x -- --article value-generics
  npm run post:x -- --article namespace-collection
  npm run post:x -- --article value-generics --publish

Environment:
  X_ACCESS_TOKEN   OAuth user-context token with post.write permission.
  X_DRY_RUN        Defaults to true. Set false and pass --publish to post.
  X_MAX_CHARS      Defaults to 280.

No local draft files are written.`);
  process.exit(0);
}

if (!selectedArticle || !articles[selectedArticle]) {
  console.error(
    `Choose an article with --article: ${Object.keys(articles).join(", ")}`
  );
  process.exit(1);
}

const article = articles[selectedArticle];
const sourcePath = path.join(root, article.source);
if (!existsSync(sourcePath)) {
  console.error(`Missing source: ${article.source}`);
  process.exit(1);
}

const posts = article.posts.map((post, index) => `${index + 1}/${article.posts.length} ${post}`);
validatePosts(posts, article.title);

if (dryRun) {
  console.log(`Dry run for ${article.title}. No X API calls made.\n`);
  for (const post of posts) {
    console.log(post);
    console.log("\n---\n");
  }
  console.log("To publish, set X_DRY_RUN=false and run with --publish.");
  process.exit(0);
}

const token = process.env.X_ACCESS_TOKEN;
if (!token) {
  console.error("Missing X_ACCESS_TOKEN in .env or environment.");
  process.exit(1);
}

let replyToTweetId;
for (const [index, text] of posts.entries()) {
  const tweet = await createTweet({ text, replyToTweetId, token });
  replyToTweetId = tweet.data?.id;
  if (!replyToTweetId) {
    console.error(`X API response for post ${index + 1} did not include data.id.`);
    process.exit(1);
  }
  console.log(`Posted ${index + 1}/${posts.length}: ${replyToTweetId}`);
}

function validatePosts(posts, title) {
  let hadError = false;
  for (const [index, post] of posts.entries()) {
    if (post.length > maxChars) {
      console.error(`${title} post ${index + 1} is ${post.length}/${maxChars} characters.`);
      hadError = true;
    }
  }
  if (hadError) {
    process.exit(1);
  }
}

async function createTweet({ text, replyToTweetId, token }) {
  const body = { text };
  if (replyToTweetId) {
    body.reply = { in_reply_to_tweet_id: replyToTweetId };
  }

  const response = await fetch("https://api.x.com/2/tweets", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error(`X API error ${response.status}:`);
    console.error(JSON.stringify(json, null, 2));
    process.exit(1);
  }
  return json;
}

function argValue(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return undefined;
  return process.argv[index + 1];
}

function loadEnv(filePath) {
  if (!existsSync(filePath)) return;

  const text = readFileSync(filePath, "utf8");
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const equal = trimmed.indexOf("=");
    if (equal === -1) continue;
    const key = trimmed.slice(0, equal).trim();
    const value = trimmed.slice(equal + 1).trim();
    if (key && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}
