# cloudflare-image-gen (Claude Code skill)

Free image generation for Claude Code via Cloudflare Workers AI. Default model: **FLUX.2 [dev]**, Cloudflare's best-quality image model. When the free allowance (10,000 neurons/day, reset 00:00 UTC) gets too low for it, the script automatically falls back to FLUX.2 [klein] 9B → FLUX.2 [klein] 4B → FLUX.1 schnell. On the Workers Free plan, requests past the allowance fail; you are never billed.

Works on **Windows and macOS** (and Linux). Requires **Node.js 18+**.

## 1. Cloudflare account (once)

1. Sign up / log in at https://dash.cloudflare.com (free plan, no card).
2. **Account ID:** Dashboard → Workers & Pages (or any domain's Overview) → copy *Account ID*.
3. **API token:** My Profile → API Tokens → Create Token → **Workers AI** template (or a custom token with *Account → Workers AI → Read* and *Edit*) → copy the token.

## 2. Add the skill to your Claude account (once)

In the Claude desktop app: **Customize → Skills → upload** `cloudflare-image-gen.zip`. The app then downloads the skill on every computer you sign in on. After editing the skill, rebuild the zip and upload it again.

## 3. Save your keys on each computer

Install Node.js 18+ (https://nodejs.org), then run the setup script from the `claude-skills` folder:

**Windows** (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File D:\claude-skills\install.ps1
```

**macOS** (Terminal):

```bash
bash ~/claude-skills/install.sh
```

The script:
- finds the copy the Claude app downloaded from your account and shows its path, or tells you to upload the zip if it isn't there yet;
- asks for your **Account ID** and **Workers AI API token** (the token is typed hidden), checks them with Cloudflare, and saves them for your user in `~/.config/cloudflare-image-gen/config.json` (macOS: permissions 600);
- warns if Node.js is missing or older than 18;
- adds **nothing** to the Claude folders. It only removes links to this folder that older versions of the script created in `~/.claude/skills`.

**To update credentials, run the same script again.** It shows the saved Account ID and the last 4 characters of the token; type a new value to replace one, or press Enter to keep it. On Windows, if `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN` user environment variables exist, they are updated too so they never override the file with stale values.

Then **fully quit and reopen the Claude desktop app**, and ask Claude: *"generate an image of a cozy reading nook, save it to public/hero.jpg"*.

## Credentials

The script uses, in order:
1. `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` environment variables (or the `"env"` block of `~/.claude/settings.json`);
2. `~/.config/cloudflare-image-gen/config.json`:

```json
{ "accountId": "your-account-id", "apiToken": "your-token" }
```

The config file is recommended on macOS: desktop apps launched from the Dock don't see variables set in `~/.zshrc`. Never commit the config file or put the token in the `claude-skills` folder.

## Manual use

```bash
node /path/to/claude-skills/cloudflare-image-gen/scripts/generate.mjs --prompt "a red fox in snow, watercolor" --out fox.jpg --width 1536 --height 1024
# options: --model flux-2-dev|flux-2-klein-9b|flux-2-klein-4b|flux-1-schnell  --steps n  --seed n  --guidance x  --no-fallback
```

## Uninstall

Run the uninstall script from the `claude-skills` folder. It finds everything automatically and asks before deleting each item (add `-Yes` / `--yes` to skip the questions):

```powershell
powershell -ExecutionPolicy Bypass -File D:\claude-skills\uninstall.ps1
```

```bash
bash ~/claude-skills/uninstall.sh
```

It removes old links to the folder in `~/.claude/skills`, a manually copied skill folder there, and the saved keys (`~/.config/cloudflare-image-gen`). On Windows it can also remove `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN` user environment variables; on macOS it lists the shell profiles that set them. It never deletes the `claude-skills` folder.

The copy from your Claude account is managed by the app, so the script only shows where it is (Windows: `%LOCALAPPDATA%\Claude-Data\claude_<id>\local-agent-mode-sessions\skills-plugin\<id>\<id>\skills\cloudflare-image-gen`; macOS: `~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/<id>/<id>/skills/cloudflare-image-gen`). Delete it in **Customize → Skills**; that removes it from every computer on your account.
