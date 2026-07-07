#!/usr/bin/env bash
# mirror.sh — capture a released brainstem version into this repo (run at
# RELEASE TIME as part of the grail release ritual). Mirrors are permanent:
# they survive grail history rewrites, force-pushes, or deletion.
# Usage: ./mirror.sh v0.6.6 [grail-clone-path]

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="${1:?Usage: ./mirror.sh vX.Y.Z [grail-clone-path]}"
GRAIL="${2:-}"

if [ -z "$GRAIL" ]; then
    GRAIL=$(mktemp -d)/grail
    gh repo clone kody-w/rapp-installer "$GRAIL" -- --quiet
fi

actual="v$(tr -d '[:space:]' < "$GRAIL/rapp_brainstem/VERSION")"
[ "$actual" = "$V" ] || { echo "✗ Grail tree is $actual, not $V — checkout the right commit first"; exit 1; }
[ -d "$REPO_DIR/versions/$V" ] && { echo "✗ $V already mirrored — mirrors are immutable"; exit 1; }

mkdir -p "$REPO_DIR/versions/$V"
rsync -a --exclude '.git' --exclude '__pycache__' \
    "$GRAIL/rapp_brainstem" "$GRAIL/install.sh" "$GRAIL/install.ps1" \
    "$GRAIL/install.cmd" "$GRAIL/install.command" \
    "$REPO_DIR/versions/$V/"

commit=$(git -C "$GRAIL" rev-parse --short HEAD 2>/dev/null || echo unknown)
cd "$REPO_DIR"   # versions.json path below is repo-relative
python3 - "$V" "$commit" <<'PY'
import json, sys, datetime, pathlib
v, commit = sys.argv[1], sys.argv[2]
f = pathlib.Path('versions.json')
d = json.loads(f.read_text())
d['versions'][v] = {
    'source_commit': commit,
    'mirrored_at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'notes': '',
}
d['latest'] = v
f.write_text(json.dumps(d, indent=2) + '\n')
PY

cd "$REPO_DIR"
git add -A
git commit -q -m "mirror: $V (grail $commit)"
git push -q origin main
echo "✓ $V mirrored and pushed"
