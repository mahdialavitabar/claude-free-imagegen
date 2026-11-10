#!/usr/bin/env bash
# macOS / Linux uninstall for the cloudflare-image-gen skill. Finds and removes, after asking:
#   - symlinks to this folder left in ~/.claude/skills by older installers (no prompt; files stay)
#   - a manually copied skill folder in ~/.claude/skills
#   - the saved Cloudflare keys (~/.config/cloudflare-image-gen)
# The copy uploaded to your Claude account is managed by the app: the script shows where it is and
# tells you to remove it in Claude (Customize > Skills); deleting it here would just re-download it.
# CLOUDFLARE_* variables in your shell profile are reported, not edited. This folder is never touched.
# Run:  bash /path/to/claude-skills/uninstall.sh [--yes]
set -euo pipefail

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/skill-paths.sh
. "$SOURCE/lib/skill-paths.sh"

assume_yes=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) assume_yes=1 ;;
    *) echo "Unknown option: $arg (use --yes to answer yes to every question)" >&2; exit 2 ;;
  esac
done
removed=0

# 1. Symlinks left by older installers (only the links; the files they point to stay).
while IFS= read -r link; do
  [ -n "$link" ] || continue
  echo "Removed old link: $link"; removed=$((removed + 1))
done < <(remove_links_into "$SOURCE")

# 2. A real (copied) skill folder in the global Claude skills folder.
local_copy="$CLAUDE_SKILLS_DIR/$SKILL_NAME"
if [ -d "$local_copy" ] && [ ! -L "$local_copy" ] && [ -f "$local_copy/SKILL.md" ]; then
  if confirm "Delete the copied skill folder $local_copy ?" "$assume_yes"; then
    rm -rf "$local_copy"
    echo "Deleted $local_copy"; removed=$((removed + 1))
  fi
fi

# 3. Saved Cloudflare keys.
if [ -d "$CREDENTIALS_DIR" ]; then
  if confirm "Delete the saved Cloudflare keys in $CREDENTIALS_DIR ?" "$assume_yes"; then
    rm -rf "$CREDENTIALS_DIR"
    echo "Deleted $CREDENTIALS_DIR"; removed=$((removed + 1))
  fi
fi

# 4. Shell variables: report where they are set; profiles are not edited automatically.
profiles="$(grep -l -E '^[[:space:]]*(export[[:space:]]+)?CLOUDFLARE_(ACCOUNT_ID|API_TOKEN)=' \
  "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" 2>/dev/null || true)"
if [ -n "$profiles" ]; then
  echo "CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN are set in:"
  printf '%s\n' "$profiles" | sed 's/^/  /'
  echo "Remove those lines yourself if nothing else uses them."
fi

# 5. The copy from your Claude account: report only.
copies="$(find_account_copies)"
echo
if [ -n "$copies" ]; then
  echo "The skill is still installed from your Claude account:"
  printf '%s\n' "$copies" | sed 's/^/  /'
  echo "Remove it in Claude: Customize > Skills > cloudflare-image-gen > ... > Delete (or switch it off)."
  echo "That removes it from every computer signed in to your account."
else
  echo "The skill is not installed from your Claude account on this computer."
fi

echo
if [ "$removed" -gt 0 ]; then echo "Done: removed $removed item(s). Restart Claude to apply."; else echo "Nothing removed."; fi
