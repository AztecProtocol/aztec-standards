---
name: release
description: >-
  Publish this repo to npm via the tag-driven release.yml — both rc prereleases
  (X.Y.Z-rc.N → `rc` dist-tag) and production releases (X.Y.Z → `latest`). Stamps and
  validates the version, pushes a `v*` tag, and verifies the publish (dist-tag, provenance,
  smoke install). Always rehearse with an rc before a production tag. Use to cut an rc or a
  final release.
---

# Release (rc prerelease or production)

One flow for both. The tag-driven `release.yml` (`on: push tags v*`) derives the dist-tag from the
version: `-rc.N` → `rc`, else `latest`. The `rc` is a **rehearsal** for the immutable production
publish — always do it first. Assumes the version bump is already merged to `main` (see the
`bump-aztec-version` skill).

## Preconditions (state them; don't assume)
- Fork workflows enabled; `NPM_TOKEN` in the `Production` environment with publish+**create** rights
  for the package scope; workflows on an available runner (standard `ubuntu-latest`); `v*` tag-push rights.

## Step 1 — pick mode + version (ALWAYS ASK — never infer)
**Always ask the user which release to cut** (use `AskUserQuestion`); never assume the mode from prior
context or conversation. This is a hard-to-reverse publish — the user chooses rc vs production every time.
- **rc rehearsal:** `X.Y.Z-rc.N` (do this first). Next `N` if a prior rc tag exists (`git ls-remote --tags origin`).
- **production:** `X.Y.Z` (only after a green rc).

## Step 2 — stamp the version (⚠️ from the repo ROOT, never `export/`)
`export/…` is a gitignored build artifact with its own trimmed `package.json`; `npm version` there is
a silent no-op on the real package. Always start with `cd "$(git rev-parse --show-toplevel)"`.

- **rc:** throwaway branch off `main` carrying the bump (keeps `main` at `X.Y.Z`):
  ```bash
  cd "$(git rev-parse --show-toplevel)"
  git checkout main && git pull
  git checkout -b rehearse/vX.Y.Z-rc.N
  npm version X.Y.Z-rc.N --no-git-tag-version      # edits the tracked ROOT package.json
  git commit -am "chore: rehearse X.Y.Z-rc.N"
  ```
- **production:** `main` is already `X.Y.Z` — no bump, no branch; you'll tag `main` directly.

## Step 3 — MANDATORY pre-tag guard (both modes)
Locally reproduce `release.yml`'s `tag == package.json` check *before* pushing the tag (this is the
assertion that fails the run on a mismatch):
```bash
cd "$(git rev-parse --show-toplevel)"
TARGET="X.Y.Z-rc.N"   # the version you're releasing: X.Y.Z (production) or X.Y.Z-rc.N (rc)
case "$TARGET" in *-*) DIST="${TARGET#*-}"; DIST="${DIST%%.*}";; *) DIST="latest";; esac   # rc/beta/... | latest — mirrors release.yml
echo "releasing v$TARGET → dist-tag '$DIST'"
[ "$(node -p "require('./package.json').version")" = "$TARGET" ] || { echo "ABORT: root package.json != $TARGET (bump didn't land — wrong dir / edited export/?)"; exit 1; }
git diff --quiet HEAD -- package.json || { echo "ABORT: bump uncommitted — the tag must point at the committed bump"; exit 1; }
grep -q "runs-on: ubuntu-latest$" .github/workflows/release.yml || echo "WARN: release.yml runner may be wrong (rebase onto main?)"
```

## Step 4 — tag & push
⚠️ **STOP — the tag push is the point of no return.** It fires `release.yml`, which publishes to npm,
and npm versions are **immutable**. Before running the push, show the user the exact `TARGET`, `DIST`,
and target commit, and get explicit confirmation. Do **not** push on your own initiative — even for an
rc. (The local tag/guard steps are safe to run first; only the `git push origin` line is gated.)
```bash
git tag -d "v$TARGET" 2>/dev/null; git push origin ":refs/tags/v$TARGET" 2>/dev/null   # clear any stale/orphaned tag
git tag "v$TARGET" && git push origin "v$TARGET"   # fires release.yml (tag-triggered; uses the file at this commit)
```
Approve the `Production` environment run if reviewers are set.

## Step 5 — verify, THEN report
Watch (`gh run watch`). The publish step succeeding (`+ pkg@ver`, provenance signed) is the source of
truth — the publish is immutable. Then verify the artifact (use `--prefer-online` to dodge cache/lag):
```bash
npm view @aztec-foundation/aztec-standards@"$TARGET" version --prefer-online     # exists
npm view @aztec-foundation/aztec-standards dist-tags --prefer-online             # $DIST -> $TARGET  (see latest gotcha)
cd "$(mktemp -d)" && npm init -y >/dev/null && npm i --prefer-online @aztec-foundation/aztec-standards@"$DIST"
```
For production `DIST=latest`, so `@latest` is what a plain `npm i @aztec-foundation/aztec-standards` resolves to.
Report success once the publish step is green (+ provenance) and the version resolves. A red
*smoke* step alone (propagation lag) is not a failed release — confirm the publish step + `npm view`.

**Order across releases:** rc first (`DIST=rc`, rehearsal), then production (`DIST=latest`) once it's green.

---

## Gotchas (release-time — check these first)
- **Run from the repo ROOT, never `export/`.** That dir is a gitignored build artifact with its own
  trimmed `package.json`; `npm version` there is a no-op (`npm error Version not changed`) and leaves the
  tag mismatched against the real version → `release.yml` validation fails. Step 3's guard catches it.
- **Registry propagation lag (esp. first publish).** A just-published version — particularly a package's
  first-ever publish — can take minutes to resolve; an immediate `npm install` 404s. Don't fail the
  release on a smoke miss (warn), and use `--prefer-online` to bypass the negative cache. Your *local*
  npm may also cache the 404 — re-check with `npm view … --prefer-online`.
- **The first publish claims `latest`.** npm sets `latest` on a package's first-ever publish regardless of
  `--tag`, so an `rc` rehearsal on a brand-new package leaves `latest` pointing at the rc. It self-corrects
  when the stable `X.Y.Z` publishes; you can't `dist-tag rm latest` (a package must have one). Don't
  announce the package until the stable is out.
- **Runners + fork state.** A GitHub fork has workflows disabled by default (enable in the Actions tab).
  Target `ubuntu-latest`; don't assume custom/larger-runner labels (e.g. `ubuntu-latest-m`) exist — jobs
  stuck `queued` are the symptom.
- **Pin CI to real tags.** Reusable-workflow refs (aztec-ci-actions / aztec-benchmark) should be pinned to a
  released tag SHA (with a `# vX` comment), not a transient `main` HEAD — a pre-re-scope commit can still
  `require('@defi-wonderland/…')`.
- **npm is immutable.** Always rehearse with an `rc` before the final tag. `release.yml` publishes
  idempotently (re-running a tag re-points the dist-tag instead of erroring) and smoke-tests, so a failed
  run is safe to re-trigger.
- **Provenance.** `release.yml` publishes with `--provenance` (needs `id-token: write` + `repository.url`
  matching the running repo). The `rc` run is the first to exercise it; a Sigstore transparency-log line
  in the publish output confirms it worked.
