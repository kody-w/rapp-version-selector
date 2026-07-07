#!/usr/bin/env bash
# select.sh — pin THIS device to a specific mirrored brainstem version.
# Replaces ~/.brainstem/src with the mirror, reuses the existing venv, and
# restarts the server. Re-running the PUBLIC installer un-pins (updates to
# latest) — that is the escape hatch, not a bug.
#
# Usage:
#   ./select.sh v0.6.5
#   curl -fsSL https://raw.githubusercontent.com/kody-w/rapp-version-selector/main/select.sh | bash -s v0.6.5

set -euo pipefail
V="${1:?Usage: select.sh vX.Y.Z — see versions.json for what's mirrored}"
BH="$HOME/.brainstem"
TARBALL_URL="https://codeload.github.com/kody-w/rapp-version-selector/tar.gz/refs/heads/main"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "Fetching mirror index..."
curl -fsSL "$TARBALL_URL" | tar xzf - -C "$WORK"
SRC=$(echo "$WORK"/rapp-version-selector-*/versions/"$V")
if [ ! -d "$SRC" ]; then
    echo "✗ $V is not mirrored. Available:"
    ls "$WORK"/rapp-version-selector-*/versions/ | sed 's/^/    /'
    exit 1
fi

# Stop whatever is serving 7071
pids=$(lsof -ti:7071 2>/dev/null || true)
[ -n "$pids" ] && { echo "$pids" | xargs kill 2>/dev/null || true; sleep 1; }

# Swap the source tree (backup the old one), keep the venv
if [ -d "$BH/src" ]; then
    mv "$BH/src" "$BH/src-before-pin-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$BH/src"
rsync -a "$SRC/" "$BH/src/"
echo "$V" > "$BH/.pinned-version"

# Ensure a venv (reuse if present)
if [ ! -x "$BH/venv/bin/python" ]; then
    python3.11 -m venv "$BH/venv" 2>/dev/null || python3 -m venv "$BH/venv"
fi
"$BH/venv/bin/pip" install -q -r "$BH/src/rapp_brainstem/requirements.txt"

# Launch and verify
cd "$BH/src/rapp_brainstem"
nohup "$BH/venv/bin/python" brainstem.py >> "$BH/brainstem.log" 2>&1 &
for _ in $(seq 1 60); do
    if curl -sf --max-time 1 http://localhost:7071/health >/dev/null 2>&1; then
        got=$(curl -sf http://localhost:7071/health | "$BH/venv/bin/python" -c "import json,sys; print(json.load(sys.stdin)['version'])")
        echo "✓ Pinned and running: v$got on http://localhost:7071"
        [ "v$got" = "$V" ] || echo "⚠ Server reports v$got, expected $V — check $BH/brainstem.log"
        exit 0
    fi
    sleep 1
done
echo "✗ Server did not come up within 60s — see $BH/brainstem.log"
exit 1
