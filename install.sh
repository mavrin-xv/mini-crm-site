#!/usr/bin/env bash
# mini-crm-site installer: copies the five skills into Claude Code.
#
#   ./install.sh             into ~/.claude/skills (all projects)
#   ./install.sh --project   into ./.claude/skills (this project only)
#
# The app itself (app/) is not installed anywhere: you deploy it from this folder
# with the crm-setup skill. Existing skills with the same name are backed up first.
set -euo pipefail

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
for a in "$@"; do
  case "$a" in
    --project) DEST="$(pwd)/.claude" ;;
    -h|--help) sed -n 2,8p "$0"; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

[ -d "$HERE/skills" ] || die "run this from the repo folder (skills/ not found)"
mkdir -p "$DEST/skills"
for s in "$HERE"/skills/*/; do
  name="$(basename "$s")"
  if [ -d "$DEST/skills/$name" ]; then
    mv "$DEST/skills/$name" "$DEST/skills/$name.bak.$(date +%s)"
    say "backed up existing $name"
  fi
  cp -R "$s" "$DEST/skills/$name"
  say "installed skill $name"
done

command -v python3 >/dev/null || command -v python >/dev/null || \
  warn "the helper scripts need Python 3.8+"
command -v node >/dev/null || warn "the app tests need Node 22+ and wrangler runs on Node"
say "done. Next: open this folder in Claude Code and say \"set up the CRM\"."
