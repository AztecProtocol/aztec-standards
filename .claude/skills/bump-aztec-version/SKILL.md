---
name: bump-aztec-version
description: >-
  Upgrade this repo to a new Aztec version — bump every reference (all Nargo.toml aztec-nr git
  tags + every @aztec-labs/* npm dep + config.aztecVersion), install the matching toolchain,
  and validate the bump locally (compile, Noir tests, typecheck, build, dry-run). Produces a
  validated branch ready to merge. Publishing is the separate `release` skill.
  Use when adopting a new Aztec release, rc, or nightly tag.
---

# Bump the Aztec version

Adopts a new Aztec version across the repo and proves it works locally. Output: a branch that
compiles, tests, typechecks, and builds against the new deps — ready to open a PR to `main`.
**Publishing (rc / production) is handled by the separate `release` skill** — this skill stops at a
merged, validated bump.

Since v6 Aztec ships from three places, all tagged `vX.Y.Z`:
- **aztec-nr** crates (`aztec`, `uint-note`, `balance-set`, `compressed-string`, …): `aztec-labs-eng/aztec-nr`, flat crate dirs.
- **protocol crates** (`serde`, `types`): `AztecProtocol/aztec-packages`, under `noir-projects/fnd/noir-protocol-circuits/crates/`.
- **npm SDK + toolchain** (`@aztec-labs/*`, `aztec-up`): built from `aztec-labs-eng/aztec-node`; its
  `docs/docs-developers/docs/resources/migration_notes.md` is the authoritative changelog.

## Step 0 — gather inputs (ask the user)
Use `AskUserQuestion` (or ask directly) for:
1. **Target version** — a **tag** `vX.Y.Z[-suffix]` (release, rc, or nightly) that exists in aztec-nr,
   aztec-packages and npm alike; the npm version is the tag without its `v`. A bare commit identifies only
   one of the three repos, so for an untagged commit stop and ask the user for the matching revision of each.
2. **Source** — a **path to a local checkout** of aztec-nr / aztec-node, or the GitHub repos. The source is for *diagnosis*, not the dep URL (Nargo deps always point at the GitHub git URL).

Verify the target exists before touching anything, and record the full SHAs for the PR body (Nargo
pins by tag only, and tags can move). An unmatched `ls-remote` pattern prints nothing and still exits 0,
hence `--exit-code`; query both refs because the repos mix annotated and lightweight tags, and record the
peeled `^{}` commit when present:
- `git ls-remote --exit-code https://github.com/aztec-labs-eng/aztec-nr 'refs/tags/vX.Y.Z' 'refs/tags/vX.Y.Z^{}'`
- `git ls-remote --exit-code https://github.com/AztecProtocol/aztec-packages 'refs/tags/vX.Y.Z' 'refs/tags/vX.Y.Z^{}'`
- `npm view @aztec-labs/aztec.js@X.Y.Z version` must print the version (a missing one fails with E404).

## Step 1 — bump the Noir deps (all `Nargo.toml`)
```bash
find . -name Nargo.toml -not -path '*/node_modules/*'
```
- aztec-nr deps: `git = "https://github.com/aztec-labs-eng/aztec-nr"`, `tag = "vX.Y.Z"`,
  `directory = "<crate dir>"` (`aztec`, `uint-note`, `balance-set`, `compressed-string`).
- protocol deps (escrow's `serde`): `git = "https://github.com/AztecProtocol/aztec-packages"` (no trailing
  slash — the same string aztec-nr's own `protocol_types` dep uses), same tag,
  `directory = "noir-projects/fnd/noir-protocol-circuits/crates/serde"`.
- **Do NOT touch** other deps (e.g. `sha512`, `bignum`) — they version independently.

## Step 2 — bump the npm deps (`package.json`)
- Every `@aztec-labs/*` dependency and `@aztec-foundation/bb.js` → the npm version, **pinned exactly**: the
  `latest` dist-tag has pointed at a stale nightly, and a stale bb.js pin installs a second Barretenberg next
  to the SDK's.
- `viem` stays the `npm:@aztec/viem@…` alias the SDK itself uses.
- `config.aztecVersion` → the npm version (the `setup-aztec` CI action reads this to install the toolchain).
- The package's own `version` is the *release* version — bump it too if this repo tracks aztec (it does), else leave.
- **`@aztec-foundation/aztec-benchmark` is a separate package** (its own repo/release). Only bump it if a matching release exists; it declares the Aztec SDK as **peerDependencies**, so it must resolve to the same aztec version — mismatches cause duplicate-type errors (see Gotchas).

## Step 3 — regenerate the lockfile + toolchain
```bash
yarn install                 # updates node_modules + yarn.lock to the new versions
```
`aztec-up install <version>` repoints the host-global `~/.aztec/current`, and the installer also runs
noirup/foundryup into `$HOME/.nargo` and `$HOME/.foundry`. On a machine other agents share, install
into an isolated home instead of switching everyone's toolchain:
```bash
V=$HOME/.cache/aztec-homes/<version>
env -i HOME="$V" AZTEC_HOME="$V/.aztec" TMPDIR="$TMPDIR" LANG=C.UTF-8 AZTEC_NO_AUTO_UPDATE=1 \
  PATH="$(dirname "$(command -v node)"):/usr/local/bin:/usr/bin:/bin" \
  bash "$HOME/.aztec/bin/aztec-up" install <version>
export AZTEC_HOME="$V/.aztec" PATH="$V/.aztec/current/bin:$PATH"
```
Confirm: `aztec --version`. The v6 installer needs Node ≥ 24.12 (`install.aztec-labs.com/<version>/versions`).

## Step 4 — local validation (prove the bump)
Before running the checks, audit every local type/cast that exposes non-public Aztec APIs. These
shims are not checked against the upstream class, so a normal TypeScript build can stay green after
the real method signature changes:
```bash
rg -n 'WalletWithInternals|as unknown as.*Wallet|scopesFrom\(' src benchmarks scripts
# Compare every matching shim/method with the target version's source.
```

Run in order; stop and diagnose on the first failure:
```bash
yarn ccc                     # clean + compile + codegen against the new deps
yarn test:nr                 # Noir tests (aztec test) — alone on the host only: it runs against whatever
                             # listens on 8081; with other agents around use the free-port recipe in Gotchas
# typecheck src + scripts (+ benchmarks if the benchmark dep resolves) via a temp tsconfig with noEmit
yarn format:check
yarn install --frozen-lockfile   # lockfile matches package.json
yarn build                   # assembles export/<pkg>
(cd export/@aztec-foundation/aztec-standards && npm publish --dry-run --access public --tag rc)   # tarball sanity; prereleases need --tag
# With a local network up (aztec start --local-network; no npm creds needed). It defaults to ports 8080,
# 8880 and anvil 8545; with other agents around pick free ones (--port, --admin-port, ANVIL_PORT,
# ETHEREUM_HOSTS) and point the tests at it with NODE_URL:
yarn test:js
yarn bench
```
If a local network is unavailable, record both commands as deferred and keep the PR in draft until
the CI **JS Tests** and **Benchmark** jobs pass. Do not describe the bump as fully validated before
those runtime checks are green.

**Diagnosing failures:** a compile/test break is often a real API change in the new aztec version,
not a repo bug. Diff the relevant internals at the target tag and fix. See Gotchas.

## Step 5 — hand off
When everything is green: commit, open a PR to `main`, let CI pass, merge. Then invoke the
**`release`** skill to cut an `rc` prerelease and, once that's validated, the production release.

---

## Gotchas (bump-time — check these first)
- **Toolchain mismatch.** The default local `aztec`/`nargo` is often an older version that can't parse
  the target's aztec-nr. Always install the target version (isolated, per Step 3).
- **Worktrees inside the main checkout build the main checkout.** nargo roots itself at the *topmost*
  `[workspace]` Nargo.toml above its program dir, so in `.claude/worktrees/<slug>` every `aztec compile`,
  `aztec test`, and the pre-commit `aztec-nargo fmt` operate on the main checkout's sources (errors then
  cite the *old* tag's crates). `--program-dir <worktree>` doesn't help; a symlink to the worktree from
  outside the repo, passed as `--program-dir` (a `nargo` wrapper via `NARGO=` for `aztec compile`, and
  first on `PATH` as `aztec-nargo`), does.
- **`aztec test` uses a fixed TXE port (8081).** Two concurrent runs share or kill each other's TXE. On a
  shared host, reproduce the wrapper on a free port: `aztec start --txe --port <p>` and
  `NARGO_FOREIGN_CALL_TIMEOUT=300000 aztec-nargo test --silence-warnings --oracle-resolver http://127.0.0.1:<p>`.
  `aztec start --local-network` likewise defaults anvil to `ANVIL_PORT` 8545 and keeps any inherited
  `ETHEREUM_HOSTS`: set both explicitly.
- **Hand-rolled reproductions of aztec internals break on API changes.**
  - `src/escrow_contract/src/key_derivation.nr` re-implements `deriveKeys`; when v5 added master
    message-signing/fallback keys, escrow addresses stopped matching. If `get_escrow`/derivation tests
    fail, diff the key-derivation constants/`PublicKeys` at the target ref and re-sync. Regenerate the
    hardcoded `get_test_vector` hashes.
  - NFT/MultiToken partial notes import aztec-nr domain separators; v6 moved
    `DOM_SEP__PARTIAL_NOTE_COMMITMENT` and `DOM_SEP__NOTE_COMPLETION_LOG_TAG` to `aztec::note::partial_note`.
- **Removed CLI commands.** v6 dropped `aztec inspect-contract` (among others); check `scripts/` and
  `package.json` against the target's CLI reference.
- **v5 wallet API.** `createSchnorrAccount(secret, salt)` → now needs a 3rd `GrumpkinScalar` signing key;
  `Wallet` context types may need `EmbeddedWallet`.
- **Local wallet-internals shims hide upstream API drift.** `src/ts/test/utils.ts` casts wallets through
  `unknown` to a hand-written `WalletWithInternals`, so typechecking only verifies that local interface —
  not the real protected `BaseWallet` methods. Diff every shimmed method against both the old and target
  tags. In v5.1, `scopesFrom(from, additionalScopes = [])` became
  `scopesFrom(from, additionalScopes, sendMessagesAs)`; a stale one-argument shim compiled but crashed at
  runtime with `additionalScopes is not iterable`. Prefer constructing simple scopes directly (for a
  concrete `caller`, `[caller]`) instead of reaching through to this protected helper.
- **Network-only checks catch what typechecking cannot.** Both JS tests and benchmarks execute the wallet
  internals used by commitment helpers. Run `yarn test:js` and `yarn bench` against a local network, or
  require their CI jobs to pass before calling the bump validated.
- **CI Node floor.** The shared `aztec-ci-actions` `setup-aztec` action pins `setup-node` to 24.0.0, below
  the v6 installer's 24.12 floor. If CI fails installing the toolchain, that action needs a bump first.
- **Benchmark peerDep / duplicate tree.** `aztec-benchmark` 5.0.1 declares `@aztec/aztec.js` and
  `@aztec/wallets` `>=5 <6` as peers; on v6 yarn only warns. If `benchmarks/*.ts` typecheck shows
  `_branding` / `.../aztec-benchmark/node_modules/@aztec…` errors, the benchmark pulled a *second* SDK
  tree — it must be on a version whose SDK packages are `peerDependencies` matching this repo's version.
