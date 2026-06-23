#!/usr/bin/env bash
#
# install.sh — install infrapeek to /usr/local/bin (+ lib to /usr/local/lib).
#
#   git clone https://github.com/USER/infrapeek && cd infrapeek && sudo ./install.sh
#   curl -fsSL https://raw.githubusercontent.com/USER/infrapeek/main/install.sh | bash
#
set -e

REPO_URL="https://github.com/USER/infrapeek"

# --user installs into the home dir (no sudo). Default is system-wide.
if [ "$1" = "--user" ]; then
  BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
  LIB_DIR="${LIB_DIR:-$HOME/.local/lib/infrapeek}"
else
  BIN_DIR="${BIN_DIR:-/usr/local/bin}"
  LIB_DIR="${LIB_DIR:-/usr/local/lib/infrapeek}"
fi

bold=$'\033[1m'; grn=$'\033[32m'; yel=$'\033[33m'; rst=$'\033[0m'

say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$grn" "$rst" "$*"; }
warn() { printf '  %s‣%s %s\n' "$yel" "$rst" "$*"; }

# Use sudo automatically when we cannot write to the target dirs.
SUDO=""
# Use sudo only when a target dir isn't writable (so a user-owned prefix like
# ~/.local/bin installs without it).
need_sudo=0
for _d in "$BIN_DIR" "$LIB_DIR"; do
  _p="$_d"; while [ ! -e "$_p" ]; do _p=$(dirname "$_p"); done
  [ -w "$_p" ] || need_sudo=1
done
if [ "$need_sudo" -eq 1 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

# ---------------------------------------------------------------------------
# Locate the source tree. If run via `curl | bash`, clone it first.
# ---------------------------------------------------------------------------
SRC=""
if [ -n "${BASH_SOURCE[0]}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/infrapeek" ]; then
  SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
elif [ -f "./infrapeek" ]; then
  SRC=$(pwd)
else
  if ! command -v git >/dev/null 2>&1; then
    say "${yel}install.sh:${rst} git is required to bootstrap from a pipe." >&2
    exit 1
  fi
  TMP=$(mktemp -d)
  say "Cloning $REPO_URL ..."
  git clone --depth 1 "$REPO_URL" "$TMP/infrapeek" >/dev/null 2>&1
  SRC="$TMP/infrapeek"
fi

say "${bold}Installing infrapeek${rst}"
say ""

# ---------------------------------------------------------------------------
# Copy files
# ---------------------------------------------------------------------------
$SUDO mkdir -p "$BIN_DIR" "$LIB_DIR"
$SUDO cp "$SRC/infrapeek" "$BIN_DIR/infrapeek"
$SUDO chmod +x "$BIN_DIR/infrapeek"
$SUDO cp "$SRC"/lib/*.sh "$LIB_DIR/"
ok "installed $BIN_DIR/infrapeek"
ok "installed libraries to $LIB_DIR"

# ---------------------------------------------------------------------------
# Optional dependency checks
# ---------------------------------------------------------------------------
say ""
say "${bold}Optional dependencies${rst}"
if command -v dot >/dev/null 2>&1; then
  ok "graphviz (dot) found — PNG/SVG export available (--diagram)"
else
  warn "graphviz not found — install for --diagram:"
  warn "    macOS: brew install graphviz   |   Ubuntu: sudo apt-get install graphviz"
fi
if command -v fzf >/dev/null 2>&1; then
  ok "fzf found — interactive browser available (--interactive)"
else
  warn "fzf not found — install for --interactive:"
  warn "    macOS: brew install fzf        |   Ubuntu: sudo apt-get install fzf"
fi
if command -v jq >/dev/null 2>&1; then
  ok "jq found — used for richer CDK parsing"
else
  warn "jq not found (optional) — CDK parsing falls back to grep/awk"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
say ""
say "${grn}${bold}infrapeek installed!${rst}"
say ""
say "Try it:"
say "    cd your-infra-project"
say "    infrapeek"
say ""
say "Or point it at a path:"
say "    infrapeek ~/my-terraform-project --diagram"
