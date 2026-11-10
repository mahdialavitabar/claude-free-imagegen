#!/usr/bin/env bash
# macOS / Linux setup for the cloudflare-image-gen skill. The skill itself is installed by uploading
# cloudflare-image-gen.zip in Claude (Customize > Skills); this script adds nothing to the Claude
# folders. It finds the uploaded copy (or says how to upload it), checks Node.js, and asks for the
# Cloudflare Account ID and Workers AI API token and saves them for your user. Run it again any
# time to update them. Undo with uninstall.sh.
# Run:  bash /path/to/claude-skills/install.sh
set -euo pipefail

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/skill-paths.sh
. "$SOURCE/lib/skill-paths.sh"

# Remove symlinks that older versions of this script created in the Claude skills folder.
remove_links_into "$SOURCE" | while IFS= read -r link; do echo "Removed old link: $link"; done

check_node

# Is the skill installed in Claude (uploaded to your account and downloaded by the app)?
copies="$(find_account_copies)"
if [ -n "$copies" ]; then
  echo "Skill installed from your Claude account:"
  printf '%s\n' "$copies" | sed 's/^/  /'
else
  zip="$SKILL_NAME.zip"; [ -f "$SOURCE/$zip" ] && zip="$SOURCE/$zip"
  echo "Warning: the $SKILL_NAME skill isn't in Claude on this computer yet." >&2
  echo "  Upload $zip in Claude: Customize > Skills > upload, then restart Claude."
fi

# ---- Cloudflare credentials --------------------------------------------------------------
CONFIG_DIR="$CREDENTIALS_DIR"
CONFIG="$CREDENTIALS_FILE"
VALID='^[A-Za-z0-9_-]+$'

json_value() { # json_value <key> <file>: reads a "key": "value" pair written by this installer
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" | head -n 1
}

current_id=""
current_token=""
if [ -f "$CONFIG" ]; then
  current_id="$(json_value accountId "$CONFIG")"
  current_token="$(json_value apiToken "$CONFIG")"
fi

echo
if [ -n "$current_id" ] && [ -n "$current_token" ]; then
  echo "Cloudflare credentials found in $CONFIG"
  echo "  Account ID: $current_id"
  echo "  API token:  $(mask "$current_token")"
  echo "Enter new values to update them, or press Enter to keep the current ones."
else
  echo "Cloudflare setup: enter your Account ID and a Workers AI API token (see cloudflare-image-gen/README.md)."
fi

account_id=""
while :; do
  if [ -n "$current_id" ]; then prompt="Cloudflare Account ID [$current_id]: "; else prompt="Cloudflare Account ID: "; fi
  if ! read -r -p "$prompt" account_id; then
    echo; echo "No input; credentials left unchanged." >&2; exit 0
  fi
  account_id="${account_id//[[:space:]]/}"
  [ -z "$account_id" ] && account_id="$current_id"
  if [[ "$account_id" =~ $VALID ]]; then break; fi
  echo "  The Account ID may contain only letters, digits, '-' and '_'. Try again." >&2
done

api_token=""
while :; do
  if [ -n "$current_token" ]; then prompt="Workers AI API token [keep $(mask "$current_token")] (hidden): "; else prompt="Workers AI API token (hidden): "; fi
  if ! read -r -s -p "$prompt" api_token; then
    echo; echo "No input; credentials left unchanged." >&2; exit 0
  fi
  echo
  api_token="${api_token//[[:space:]]/}"
  [ -z "$api_token" ] && api_token="$current_token"
  if [[ "$api_token" =~ $VALID ]]; then break; fi
  echo "  The token may contain only letters, digits, '-' and '_'. Try again." >&2
done

if [ "$account_id" = "$current_id" ] && [ "$api_token" = "$current_token" ]; then
  echo "Credentials unchanged."
  exit 0
fi

# Check the pair against Cloudflare (lists one Workers AI model; uses no neurons).
if command -v curl >/dev/null 2>&1; then
  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    -H "Authorization: Bearer $api_token" \
    "https://api.cloudflare.com/client/v4/accounts/$account_id/ai/models/search?per_page=1" || true)"
  if [ "$status" = "200" ]; then
    echo "Verified with Cloudflare."
  else
    echo "Warning: Cloudflare rejected these credentials (HTTP ${status:-no response})." >&2
    read -r -p "Save them anyway? [y/N] " answer || answer=""
    case "$answer" in [Yy]*) ;; *) echo "Not saved; credentials left unchanged."; exit 1 ;; esac
  fi
fi

mkdir -p "$CONFIG_DIR"
( umask 077; printf '{\n  "accountId": "%s",\n  "apiToken": "%s"\n}\n' "$account_id" "$api_token" > "$CONFIG.tmp" )
mv "$CONFIG.tmp" "$CONFIG"
chmod 600 "$CONFIG"
echo "Saved to $CONFIG (readable only by you)."

if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] || [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "Note: CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN are set in your shell and take priority over this file." >&2
  echo "      Remove them from your shell profile (e.g. ~/.zshrc) so the saved values are used." >&2
fi
echo "Restart the Claude app to pick up the new credentials."
