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

One flow for both. The tag-driven `release.yml` (`on: push tags v*`) derives the npm dist-tag from the
version — a prerelease such as `-rc.N` publishes under `rc`, a stable version under `latest` — and runs
**every** publish in the reviewer-gated `Production` environment. The `rc` is a **rehearsal** for the
immutable production publish — always do it first, and because it uses the same environment and
credential path, a green `rc` genuinely predicts the stable run. Assumes the version bump is already
merged to `main` (see the `bump-aztec-version` skill).

## Preconditions (state them; don't assume)

- Fork workflows enabled; npm Trusted Publishing configured for the package with organization
  `AztecProtocol`, repository `aztec-standards`, workflow `release.yml`, environment `Production`,
  and `npm publish` allowed; workflows on an available runner (standard `ubuntu-latest`); `v*`
  tag-push rights; a `Production` reviewer available to approve the deployment.
- The environment pin is load-bearing on both sides. npm allows one trusted publisher per package with
  one optional environment claim, and GitHub only stamps that claim when the job declares an
  environment — so `release.yml` must keep `environment: Production` on every path. A job running in
  any other environment (or none) mints a token npm rejects with `E404` on `PUT`, which reads as
  "missing" but means "unauthorized".

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

Locally reproduce `release.yml`'s `tag == package.json` check _before_ pushing the tag (this is the
assertion that fails the run on a mismatch):

```bash
cd "$(git rev-parse --show-toplevel)"
TARGET="X.Y.Z-rc.N"   # the version you're releasing: X.Y.Z (production) or X.Y.Z-rc.N (rc)
case "$TARGET" in
  *-*) DIST="${TARGET#*-}"; DIST="${DIST%%.*}";;
  *) DIST="latest";;
esac   # mirrors release.yml
ENVIRONMENT="Production"   # every tag, rc included
echo "releasing v$TARGET → dist-tag '$DIST' via '$ENVIRONMENT'"
[ "$(node -p "require('./package.json').version")" = "$TARGET" ] || { echo "ABORT: root package.json != $TARGET (bump didn't land — wrong dir / edited export/?)"; exit 1; }
git diff --quiet HEAD -- package.json || { echo "ABORT: bump uncommitted — the tag must point at the committed bump"; exit 1; }
grep -q "runs-on: ubuntu-latest$" .github/workflows/release.yml || echo "WARN: release.yml runner may be wrong (rebase onto main?)"
grep -q "^    environment: Production$" .github/workflows/release.yml || { echo "ABORT: release.yml does not pin environment: Production — the npm trusted publisher will reject the OIDC token"; exit 1; }
```

## Step 4 — tag & push

⚠️ **STOP — the tag push is the point of no return.** It fires `release.yml`, which publishes to npm,
and npm versions are **immutable**. Before running the push, show the user the exact `TARGET`, `DIST`,
`ENVIRONMENT`, and target commit, and get explicit confirmation. Do **not** push on your own initiative —
even for an rc. (The local tag/guard steps are safe to run first; only the `git push origin` line is gated.)

```bash
git tag -d "v$TARGET" 2>/dev/null; git push origin ":refs/tags/v$TARGET" 2>/dev/null   # clear any stale/orphaned tag
git tag "v$TARGET" && git push origin "v$TARGET"   # fires release.yml (tag-triggered; uses the file at this commit)
```

Every tag — rc included — parks on the `Production` environment waiting for a reviewer. Verify the run
shows `Production` before it publishes; anything else means the workflow drifted and the OIDC token will
be rejected. **The approval is the maintainer's to give, not yours**: report that the run is waiting and
let the user approve it. Do not approve the deployment on their behalf, even with working `gh`
credentials and even for an rc — that click is the human gate this design buys.

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
_smoke_ step alone (propagation lag) is not a failed release — confirm the publish step + `npm view`.

**Order across releases:** rc first (`DIST=rc`, rehearsal), then production (`DIST=latest`) once it's green.

---

## Gotchas (release-time — check these first)

- **Run from the repo ROOT, never `export/`.** That dir is a gitignored build artifact with its own
  trimmed `package.json`; `npm version` there is a no-op (`npm error Version not changed`) and leaves the
  tag mismatched against the real version → `release.yml` validation fails. Step 3's guard catches it.
- **Registry propagation lag (esp. first publish).** A just-published version — particularly a package's
  first-ever publish — can take minutes to resolve; an immediate `npm install` 404s. Don't fail the
  release on a smoke miss (warn), and use `--prefer-online` to bypass the negative cache. Your _local_
  npm may also cache the 404 — re-check with `npm view … --prefer-online`.
- **The first publish claims `latest`.** npm sets `latest` on a package's first-ever publish regardless of
  `--tag`, so an `rc` rehearsal on a brand-new package leaves `latest` pointing at the rc. It self-corrects
  when the stable `X.Y.Z` publishes; you can't `dist-tag rm latest` (a package must have one). Don't
  announce the package until the stable is out.
- **Runners + fork state.** A GitHub fork has workflows disabled by default (enable in the Actions tab).
  Target `ubuntu-latest`; don't assume custom/larger-runner labels (e.g. `ubuntu-latest-m`) exist — jobs
  stuck `queued` are the symptom.
- **One environment, pinned on both sides.** Every tag publishes through `Production`; the npm trusted
  publisher pins the same environment. Changing one without the other breaks publishing: loosen npm and
  you drop the gate, loosen `release.yml` and npm rejects the token. A prerelease waiting for Production
  approval is now correct, not a routing bug. (History: prereleases used to route through `Development`,
  so the rc rehearsed a credential path the stable release never took — `v5.1.0-rc.1` went green on
  2026-07-23 and `v5.1.0` then failed to publish on 2026-08-04. Same environment now means a green rc
  actually predicts the release.)
- **Pin CI to real tags.** Reusable-workflow refs (aztec-ci-actions / aztec-benchmark) should be pinned to a
  released tag SHA (with a `# vX` comment), not a transient `main` HEAD — a pre-re-scope commit can still
  `require('@defi-wonderland/…')`.
- **npm is immutable.** Always rehearse with an `rc` before the final tag. `release.yml` publishes
  idempotently when the expected dist-tag is already correct and smoke-tests the result. A rerun
  with a mismatched dist-tag fails safely and requires a maintainer to repair the tag manually.
- **OIDC + provenance.** `release.yml` uses npm Trusted Publishing (needs `id-token: write`, npm CLI
  11.5.1+, Node 22.14.0+, `repository.url` matching the running repo, and the job's `environment` claim
  matching the trusted publisher). npm generates provenance automatically; a Sigstore transparency-log
  line in the publish output confirms it worked.
- **`E404` on `PUT` means unauthorized, not missing.** npm answers an unauthenticated or unrecognised
  publish with `404 Not Found - PUT …/@aztec-foundation%2faztec-standards`. Do not read it as a registry
  or version problem. Check, in order: is a trusted publisher configured for the package at all; does its
  environment match the job's; did `setup-node` leave `NODE_AUTH_TOKEN` as the literal
  `XXXXX-XXXXX-XXXXX-XXXXX` placeholder with no OIDC exchange line in the log (the tell that npm fell
  back to anonymous). Nothing is published when this fires, so the tag is safe to reuse after the fix —
  re-run the failed job rather than churning the tag.
- **Reruns cannot repair dist-tags.** npm OIDC authenticates `npm publish`, not `npm dist-tag add`. A
  rerun skips an already-published version only when its expected dist-tag is already correct; otherwise
  the workflow fails with instructions to repair the tag using an authorized npm account.
