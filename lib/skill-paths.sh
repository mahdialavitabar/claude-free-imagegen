# Shared helpers for install.sh and uninstall.sh (sourced; not meant to be run directly).

SKILL_NAME="cloudflare-image-gen"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CREDENTIALS_DIR="$HOME/.config/cloudflare-image-gen"
CREDENTIALS_FILE="$CREDENTIALS_DIR/config.json"

# Prints the folders where the Claude app keeps a skill uploaded to your account
# (Customize > Skills), one per line.
# Seen on macOS: ~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/<id>/<id>/skills/<name>
find_account_copies() {
  local name="${1:-$SKILL_NAME}" root dir
  local old_nullglob
  old_nullglob="$(shopt -p nullglob)"
  shopt -s nullglob
  for dir in "$CLAUDE_SKILLS_DIR"/synced/*/"$name"; do
    [ -f "$dir/SKILL.md" ] && echo "$dir"
  done
  for root in "$HOME/Library/Application Support" "$HOME/.config"; do
    [ -d "$root" ] || continue
    for dir in "$root"/Claude*/local-agent-mode-sessions/skills-plugin/*/*/skills/"$name" \
               "$root"/Claude*/*/local-agent-mode-sessions/skills-plugin/*/*/skills/"$name"; do
      [ -f "$dir/SKILL.md" ] && echo "$dir"
    done
  done
  eval "$old_nullglob"
}

# Removes symlinks in ~/.claude/skills that point into the given folder (left by older installers).
# Only the links are removed, never the files they point to. Prints the removed link paths.
remove_links_into() {
  local source="$1" source_real link dest
  source_real="$(cd "$source" && pwd -P)"
  [ -d "$CLAUDE_SKILLS_DIR" ] || return 0
  for link in "$CLAUDE_SKILLS_DIR"/*; do
    [ -L "$link" ] || continue
    dest="$(readlink "$link")"
    case "$dest" in
      "$source"/*|"$source_real"/*) rm "$link" && echo "$link" ;;
    esac
  done
}

# confirm "<question>" [assume_yes]: yes/no question, default No. Returns 0 for yes.
confirm() {
  local answer=""
  if [ "${2:-}" = "1" ]; then echo "$1 [y/N]: y"; return 0; fi
  read -r -p "$1 [y/N]: " answer || answer=""
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

mask() { local v="$1"; if [ ${#v} -le 4 ]; then echo "****"; else echo "****${v: -4}"; fi; }

# Warns when Node.js is missing or older than 18.
check_node() {
  local major
  if ! command -v node >/dev/null 2>&1; then
    echo "Warning: Node.js 18+ is required. Install it from https://nodejs.org (or your package manager)." >&2
    return 0
  fi
  major="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
  if [ "$major" -lt 18 ] 2>/dev/null; then
    echo "Warning: Node.js $major found; version 18 or newer is required (https://nodejs.org)." >&2
  fi
}
