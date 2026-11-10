---
name: cloudflare-image-gen
description: Generate raster images (PNG/JPEG) from a text prompt with Cloudflare Workers AI on the free tier, using FLUX.2 [dev] (best quality) with automatic fallback to cheaper FLUX models. Use when the user asks to generate, create, draw, or render an image, picture, illustration, icon, hero image, placeholder photo, or other bitmap asset and save it to disk.
---

# Cloudflare image generation

Generates images through the Cloudflare Workers AI REST API and saves them to a file. Free allowance: 10,000 neurons/day, reset at 00:00 UTC. On the Workers Free plan, requests fail when the allowance runs out; nothing is billed.

Models, best quality first (this is also the automatic fallback order):

| `--model` | Quality | Free images/day (approx.) | Notes |
|---|---|---|---|
| `flux-2-dev` (default) | Best: most detailed and coherent | a few | `--steps` 1–50 (default 20), slower (~10 s) |
| `flux-2-klein-9b` | Very good | ~7 | fixed 4 steps |
| `flux-2-klein-4b` | Good, fast | ~90 | fixed 4 steps |
| `flux-1-schnell` | Older, weakest | ~170 | `--steps` 1–8, always 1024×1024, no seed/guidance/size |

If a model fails because the daily allowance is too low for it, the script automatically retries with the next cheaper model and says which one it used.

## Requirements

- Node.js 18+ (the script uses built-in `fetch`/`FormData`, no dependencies).
- Cloudflare credentials, from `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN` env vars or `~/.config/cloudflare-image-gen/config.json` (`{"accountId": "...", "apiToken": "..."}`). Works on Windows and macOS. If the script exits with code 2, tell the user to save their Cloudflare keys on this computer by running the setup script from their `claude-skills` folder (`install.ps1` on Windows, `install.sh` on macOS), or by creating that config file as described in README.md, and stop. Never ask the user to paste the token into chat, and never write it into project files.

## How to generate

Run the script with Bash or PowerShell (path is relative to this skill's folder):

```
node "<skill-dir>/scripts/generate.mjs" --prompt "<detailed prompt>" --out "<path/to/image.jpg>" [--model flux-2-dev] [--width 1024] [--height 1024] [--steps 20] [--seed 42] [--guidance 4]
```

- `--prompt` (required, ≤2048 chars). Expand short user requests into a concrete visual prompt: subject, style, composition, lighting, colors, background. FLUX.2 models can render short text in images; keep any text short and quoted.
- `--out` (optional). Defaults to `./generated-images/<timestamp>.jpg` in the current directory. Save inside the user's project where the asset is needed (e.g. `public/images/`). The extension is corrected to match the returned format.
- `--model` (optional): leave it at the default unless the user asks for speed or many images; then use `flux-2-klein-4b`. Aliases: `best`, `dev`, `klein-9b`, `klein-4b`, `schnell`.
- `--width` / `--height` 256–1920 (default 1024×1024) for FLUX.2 models, e.g. 1536×1024 for a landscape hero image. Larger images cost more neurons.
- `--steps`: only for `flux-2-dev` (1–50, default 20) and `flux-1-schnell` (1–8). More steps = more detail and more neurons.
- `--seed` integer (FLUX.2 only) for reproducible results; `--guidance` 0–20 (FLUX.2 only) for how literally to follow the prompt.
- `--no-fallback` to fail instead of switching to a cheaper model.
- For several images, run the command once per image.

The script prints the model it uses to stderr and the saved file path to stdout. After generating, show the image to the user (read the file so it renders, or send it), mention the path, and say which model was used if it fell back.

## Errors

- Exit code 2: missing credentials → explain the setup.
- HTTP 401/403: bad token or missing Workers AI permission.
- Daily allowance used up even for `flux-1-schnell`: the free quota resets at 00:00 UTC.
- Prompt rejected by the safety filter: rephrase the prompt and say so.

Report the error text faithfully; do not retry in a loop.
