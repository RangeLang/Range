#!/usr/bin/env node
import crypto from "node:crypto";
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
  npm run post:x -- --check-auth

Environment:
  X_CONSUMER_KEY          OAuth 1.0a API key.
  X_CONSUMER_KEY_SECRET   OAuth 1.0a API key secret.
  X_ACCESS_TOKEN          OAuth 1.0a user access token.
  X_ACCESS_TOKEN_SECRET   OAuth 1.0a user access token secret.
  X_DRY_RUN        Defaults to true. Set false and pass --publish to post.
  X_MAX_CHARS      Defaults to 280.

No local draft files are written.`);
  process.exit(0);
}

if (process.argv.includes("--check-auth")) {
  const user = await checkAuth();
  console.log(`Authenticated as @${user.username} (${user.id}).`);
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

validateOAuth1Environment();

let replyToTweetId;
for (const [index, text] of posts.entries()) {
  const tweet = await createTweet({ text, replyToTweetId });
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

async function checkAuth() {
  validateOAuth1Environment();
  const url = "https://api.x.com/2/users/me";
  const response = await fetch(url, {
    headers: {
      Authorization: oauth1AuthorizationHeader("GET", url),
    },
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error(`X API auth check failed ${response.status}:`);
    console.error(JSON.stringify(safeXError(json), null, 2));
    process.exit(1);
  }
  return json.data;
}

async function createTweet({ text, replyToTweetId }) {
  const body = { text };
  if (replyToTweetId) {
    body.reply = { in_reply_to_tweet_id: replyToTweetId };
  }

  const url = "https://api.x.com/2/tweets";
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: oauth1AuthorizationHeader("POST", url),
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

function validateOAuth1Environment() {
  const missing = [
    "X_CONSUMER_KEY",
    "X_CONSUMER_KEY_SECRET",
    "X_ACCESS_TOKEN",
    "X_ACCESS_TOKEN_SECRET",
  ].filter((name) => !process.env[name]);

  if (missing.length > 0) {
    console.error(`Missing OAuth 1.0a setting(s): ${missing.join(", ")}`);
    process.exit(1);
  }
}

function oauth1AuthorizationHeader(method, rawUrl) {
  const url = new URL(rawUrl);
  const oauth = {
    oauth_consumer_key: process.env.X_CONSUMER_KEY,
    oauth_nonce: crypto.randomBytes(16).toString("hex"),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
    oauth_token: process.env.X_ACCESS_TOKEN,
    oauth_version: "1.0",
  };

  const parameters = [
    ...Array.from(url.searchParams.entries()),
    ...Object.entries(oauth),
  ].sort(([lhsKey, lhsValue], [rhsKey, rhsValue]) => {
    const keyComparison = oauthEncode(lhsKey).localeCompare(oauthEncode(rhsKey));
    if (keyComparison !== 0) return keyComparison;
    return oauthEncode(lhsValue).localeCompare(oauthEncode(rhsValue));
  });

  const parameterString = parameters
    .map(([key, value]) => `${oauthEncode(key)}=${oauthEncode(value)}`)
    .join("&");
  const baseUrl = `${url.protocol}//${url.host}${url.pathname}`;
  const signatureBase = [
    method.toUpperCase(),
    oauthEncode(baseUrl),
    oauthEncode(parameterString),
  ].join("&");
  const signingKey = `${oauthEncode(process.env.X_CONSUMER_KEY_SECRET)}&${oauthEncode(
    process.env.X_ACCESS_TOKEN_SECRET
  )}`;

  oauth.oauth_signature = crypto
    .createHmac("sha1", signingKey)
    .update(signatureBase)
    .digest("base64");

  return `OAuth ${Object.entries(oauth)
    .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
    .map(([key, value]) => `${oauthEncode(key)}="${oauthEncode(value)}"`)
    .join(", ")}`;
}

function oauthEncode(value) {
  return encodeURIComponent(value)
    .replace(/[!'()*]/g, (character) =>
      `%${character.charCodeAt(0).toString(16).toUpperCase()}`
    );
}

function safeXError(json) {
  return {
    title: json.title,
    detail: json.detail,
    errors: json.errors,
  };
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
