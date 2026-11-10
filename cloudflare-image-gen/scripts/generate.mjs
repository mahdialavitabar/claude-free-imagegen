#!/usr/bin/env node
// Generate an image with Cloudflare Workers AI and save it to disk.
// Default model is FLUX.2 [dev] (best quality). When the daily free allowance can't cover it,
// the script falls back automatically: flux-2-dev -> flux-2-klein-9b -> flux-2-klein-4b -> flux-1-schnell.
// Usage: node generate.mjs --prompt "..." [--out path] [--model name] [--width px] [--height px]
//                          [--steps n] [--seed n] [--guidance x] [--no-fallback]
// Credentials: CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN env vars, or
// ~/.config/cloudflare-image-gen/config.json as {"accountId": "...", "apiToken": "..."}.

import { readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";
import { parseArgs } from "node:util";

const CONFIG_PATH = join(homedir(), ".config", "cloudflare-image-gen", "config.json");

// Best quality first; this is also the automatic fallback order.
const MODELS = {
  "flux-2-dev": {
    id: "@cf/black-forest-labs/flux-2-dev",
    multipart: true,
    steps: { min: 1, max: 50, default: 20 },
    flux2: true,
  },
  "flux-2-klein-9b": { id: "@cf/black-forest-labs/flux-2-klein-9b", multipart: true, steps: null, flux2: true },
  "flux-2-klein-4b": { id: "@cf/black-forest-labs/flux-2-klein-4b", multipart: true, steps: null, flux2: true },
  "flux-1-schnell": {
    id: "@cf/black-forest-labs/flux-1-schnell",
    multipart: false,
    steps: { min: 1, max: 8, default: 4 },
    flux2: false,
  },
};
const ORDER = Object.keys(MODELS);
const ALIASES = { best: "flux-2-dev", dev: "flux-2-dev", "klein-9b": "flux-2-klein-9b", "klein-4b": "flux-2-klein-4b", schnell: "flux-1-schnell", fast: "flux-1-schnell" };
const USAGE =
  'Usage: node generate.mjs --prompt "..." [--out path] [--model ' + ORDER.join("|") + "]\n" +
  "                         [--width 256-1920] [--height 256-1920] [--steps n] [--seed n] [--guidance x] [--no-fallback]";

function fail(message, code = 1) {
  console.error(`Error: ${message}`);
  process.exit(code);
}
const note = (message) => console.error(message);

let args;
try {
  ({ values: args } = parseArgs({
    options: {
      prompt: { type: "string", short: "p" },
      out: { type: "string", short: "o" },
      model: { type: "string", short: "m" },
      width: { type: "string" },
      height: { type: "string" },
      steps: { type: "string", short: "s" },
      seed: { type: "string" },
      guidance: { type: "string" },
      "no-fallback": { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  }));
} catch (err) {
  fail(`${err.message}\n${USAGE}`);
}

if (args.help) {
  console.log(USAGE);
  process.exit(0);
}

// ---- Validate input ---------------------------------------------------------------------
const prompt = args.prompt?.trim();
if (!prompt) fail("--prompt is required");
if (prompt.length > 2048) fail("--prompt must be at most 2048 characters");

const modelName = ALIASES[args.model] ?? args.model ?? "flux-2-dev";
if (!MODELS[modelName]) fail(`unknown --model "${args.model}". Choose one of: ${ORDER.join(", ")}`);

function intOption(name, min, max) {
  if (args[name] === undefined) return undefined;
  const value = Number(args[name]);
  if (!Number.isInteger(value) || value < min || value > max) fail(`--${name} must be an integer from ${min} to ${max}`);
  return value;
}
const width = intOption("width", 256, 1920) ?? 1024;
const height = intOption("height", 256, 1920) ?? 1024;
const steps = intOption("steps", 1, 50);
const seed = intOption("seed", 0, 2_147_483_647);
let guidance;
if (args.guidance !== undefined) {
  guidance = Number(args.guidance);
  if (!Number.isFinite(guidance) || guidance < 0 || guidance > 20) fail("--guidance must be a number from 0 to 20");
}

const chosen = MODELS[modelName];
if (steps !== undefined && !chosen.steps) fail(`${modelName} uses a fixed number of steps; remove --steps`);
if (steps !== undefined && chosen.steps && steps > chosen.steps.max) fail(`--steps for ${modelName} must be 1 to ${chosen.steps.max}`);
if (!chosen.flux2 && (seed !== undefined || guidance !== undefined || args.width || args.height)) {
  fail(`${modelName} supports only --prompt and --steps (always 1024x1024)`);
}

// ---- Credentials ------------------------------------------------------------------------
function readConfig() {
  let raw;
  try {
    raw = readFileSync(CONFIG_PATH, "utf8");
  } catch (err) {
    if (err.code === "ENOENT") return {};
    fail(`cannot read ${CONFIG_PATH}: ${err.message}`, 2);
  }
  try {
    return JSON.parse(raw.replace(/^﻿/, ""));
  } catch (err) {
    fail(`${CONFIG_PATH} is not valid JSON: ${err.message}`, 2);
  }
}

let accountId = process.env.CLOUDFLARE_ACCOUNT_ID?.trim();
let token = process.env.CLOUDFLARE_API_TOKEN?.trim();
if (!accountId || !token) {
  const config = readConfig();
  accountId ||= typeof config.accountId === "string" ? config.accountId.trim() : "";
  token ||= typeof config.apiToken === "string" ? config.apiToken.trim() : "";
}
if (!accountId || !token) {
  fail(
    `Cloudflare credentials not found. Run the skill's setup script, or create ${CONFIG_PATH} ` +
      `({"accountId": "...", "apiToken": "..."}), or set CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN.`,
    2,
  );
}

// ---- Request ----------------------------------------------------------------------------
// Builds the request for one model, dropping options that model doesn't accept.
function buildRequest(name) {
  const model = MODELS[name];
  const stepCount = model.steps ? Math.min(steps ?? model.steps.default, model.steps.max) : undefined;
  if (!model.multipart) {
    // flux-1-schnell: JSON with prompt + steps only (other fields are rejected with HTTP 400).
    return { body: JSON.stringify({ prompt, steps: stepCount }), headers: { "Content-Type": "application/json" } };
  }
  // FLUX.2 models require multipart/form-data, even for prompt-only requests.
  const form = new FormData();
  form.append("prompt", prompt);
  form.append("width", String(width));
  form.append("height", String(height));
  if (stepCount !== undefined) form.append("steps", String(stepCount));
  if (seed !== undefined) form.append("seed", String(seed));
  if (guidance !== undefined) form.append("guidance", String(guidance));
  return { body: form, headers: {} }; // fetch sets the multipart boundary header
}

function isQuotaError(status, errors, text) {
  if (status === 429) return true;
  if (errors.some((e) => e.code === 4006)) return true;
  return /neuron|daily free allocation|quota|rate limit/i.test(text);
}

async function run(name) {
  const { body, headers } = buildRequest(name);
  let response;
  try {
    response = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountId)}/ai/run/${MODELS[name].id}`,
      { method: "POST", headers: { Authorization: `Bearer ${token}`, ...headers }, body, signal: AbortSignal.timeout(180_000) },
    );
  } catch (err) {
    return { error: `request failed: ${err.message}` };
  }
  const text = await response.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return { error: `HTTP ${response.status}: unexpected response: ${text.slice(0, 500)}` };
  }
  if (!response.ok || data.success === false) {
    const errors = data.errors ?? [];
    const details = errors.map((e) => `${e.code ?? ""} ${e.message ?? ""}`.trim()).join("; ") || text.slice(0, 500);
    return { error: `HTTP ${response.status}: ${details}`, quota: isQuotaError(response.status, errors, details) };
  }
  const image = data.result?.image;
  if (typeof image !== "string" || image.length === 0) return { error: "response did not contain an image" };
  return { image: image.replace(/^data:[^,]*,/, "") };
}

const candidates = args["no-fallback"] ? [modelName] : ORDER.slice(ORDER.indexOf(modelName));
let result;
let usedModel;
for (const name of candidates) {
  note(`Model: ${name}`);
  result = await run(name);
  if (result.image) {
    usedModel = name;
    break;
  }
  if (!result.quota || name === candidates.at(-1)) break;
  note(`  ${result.error}\n  Not enough free allowance left for ${name}; trying a cheaper model.`);
}
if (!usedModel) fail(result.error);

// ---- Save -------------------------------------------------------------------------------
const bytes = Buffer.from(result.image, "base64");
const isPng = bytes.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]));
const ext = isPng ? ".png" : ".jpg";

const stamp = new Date().toISOString().replace(/[:.]/g, "-");
let outPath = resolve(args.out ?? `generated-images/${stamp}${ext}`);
const currentExt = extname(outPath).toLowerCase();
if (currentExt !== ext && !(ext === ".jpg" && currentExt === ".jpeg")) {
  outPath = (currentExt ? outPath.slice(0, -currentExt.length) : outPath) + ext;
}

await mkdir(dirname(outPath), { recursive: true });
await writeFile(outPath, bytes);
if (usedModel !== modelName) note(`Used ${usedModel} instead of ${modelName}.`);
console.log(outPath);
