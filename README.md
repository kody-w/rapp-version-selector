# rapp-version-selector

Pin any device to a **specific version** of the [RAPP Brainstem](https://github.com/kody-w/rapp-installer),
and a permanent mirror of every release going forward (starting at v0.6.5 —
not retroactive). Mirrors are immutable and survive anything that happens to
the grail repo.

## Pin a device

```bash
curl -fsSL https://raw.githubusercontent.com/kody-w/rapp-version-selector/main/select.sh | bash -s v0.6.5
```

Swaps `~/.brainstem/src` for the mirrored tree (old tree kept as a timestamped
backup), reuses the existing venv, restarts the server, and verifies the
running version. The pin is recorded in `~/.brainstem/.pinned-version`.

**Heads-up:** pinning swaps the whole source tree, so custom agents in
`agents/` go with the backup. Restore them from
[rapp-vault](https://github.com/kody-w/rapp-vault) (`restore.sh`) after
pinning — snapshot first.

**Un-pin** (back to latest): just re-run the public installer —
`curl -fsSL https://kody-w.github.io/rapp-installer/install.sh | bash`

## Why pin?

- Reproduce a user's issue on their exact version
- A/B two versions on two devices side by side
- A demo machine that must not change the week before the demo
- A dependency (twin, mirror, cubby) certified against one kernel version

## Mirroring a new release (release ritual)

```bash
./mirror.sh v0.6.6   # run from a grail clone checked out at the release commit
```

Add release notes to `versions.json` after. Mirrors are append-only:
`mirror.sh` refuses to overwrite an existing version.
