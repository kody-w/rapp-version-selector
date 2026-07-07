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
V="${1:?Usage: select.sh vX.Y.Z — see versions.json for mirrored versions}"
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
OLD_SRC=""
if [ -d "$BH/src" ]; then
    OLD_SRC="$BH/src-before-pin-$(date +%Y%m%d-%H%M%S)"
    mv "$BH/src" "$OLD_SRC"
fi
mkdir -p "$BH/src"
rsync -a "$SRC/" "$BH/src/"
echo "$V" > "$BH/.pinned-version"

# Carry auth + local config across the pin — these live in the src tree but
# belong to the DEVICE, not the version. Without this the pinned server comes
# up unauthenticated and silently falls back to gpt-4o.
if [ -n "$OLD_SRC" ]; then
    for f in .copilot_token .copilot_session .env .brainstem_model; do
        [ -f "$OLD_SRC/rapp_brainstem/$f" ] && cp "$OLD_SRC/rapp_brainstem/$f" "$BH/src/rapp_brainstem/$f"
    done
    # Carry USER agents too (#3): anything in agents/ that the mirror doesn't
    # ship is the user's, not the version's. Same principle as auth — the pin
    # changes the kernel, never the estate. Stock files are never overwritten,
    # so version-specific stock agents stay exactly as mirrored.
    carried=0
    for a in "$OLD_SRC"/rapp_brainstem/agents/*_agent.py; do
        [ -f "$a" ] || continue
        base=$(basename "$a")
        if [ ! -f "$BH/src/rapp_brainstem/agents/$base" ]; then
            cp "$a" "$BH/src/rapp_brainstem/agents/$base"
            carried=$((carried + 1))
        fi
    done
    # Memories are estate, not kernel — carry .brainstem_data when the mirror
    # tree starts empty (it always does).
    if [ -d "$OLD_SRC/rapp_brainstem/.brainstem_data" ] && [ ! -d "$BH/src/rapp_brainstem/.brainstem_data" ]; then
        cp -R "$OLD_SRC/rapp_brainstem/.brainstem_data" "$BH/src/rapp_brainstem/"
    fi
    echo "Carried across the pin: auth/config + $carried user agent(s) + memories"
fi

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
