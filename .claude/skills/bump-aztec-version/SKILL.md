---
name: bump-aztec-version
description: >-
  Upgrade this repo to a new aztec-packages version — bump every reference (all Nargo.toml
  aztec-nr git tags/revs + every @aztec/* npm dep + config.aztecVersion), install the matching
  toolchain, and validate the bump locally (compile, Noir tests, typecheck, build, dry-run).
  Produces a validated branch ready to merge. Publishing is the separate `release` skill.
  Use when adopting a new aztec-packages tag or commit.
---

# Bump the aztec-packages version

Adopts a new `aztec-packages` version across the repo and proves it works locally. Output: a branch
that compiles, tests, typechecks, and builds against the new deps — ready to open a PR to `main`.
**Publishing (rc / production) is handled by the separate `release` skill** — this skill stops at a
merged, validated bump.

## Step 0 — gather inputs (ask the user)
Use `AskUserQuestion` (or ask directly) for:
1. **Target version** — a **tag** (e.g. `v5.0.0`) or a **commit SHA** of `AztecProtocol/aztec-packages`.
2. **Source** — a **path to a local checkout** of aztec-packages, or the **GitHub repo** (`AztecProtocol/aztec-packages`). The source is for *diagnosis + toolchain*, not the dep URL (Nargo deps always point at the GitHub git URL).
3. Derive the **npm version**: for a tag `vX.Y.Z` → `X.Y.Z`; for a commit, find the matching published npm version (`npm view @aztec/aztec.js versions` — often a `-nightly.`/`-snapshot.` build) or confirm one exists. If none, stop and tell the user the npm packages aren't published for that commit.

Verify the target exists before touching anything:
- local: `git -C <path> cat-file -e <tag-or-sha>^{commit}`
- github: `gh api repos/AztecProtocol/aztec-packages/commits/<tag-or-sha> --jq .sha`
- npm: `npm view @aztec/aztec.js@<npmver> version`

## Step 1 — bump the Noir deps (all `Nargo.toml`)
```bash
find . -name Nargo.toml -not -path '*/node_modules/*'
```
In each, update **only** the deps whose `git = "https://github.com/AztecProtocol/aztec-packages/"`
(e.g. `aztec`, `serde`, `uint_note`, `balance_set`, `compressed_string`). For a tag set
`tag = "vX.Y.Z"`; for a commit set `rev = "<sha>"` (replacing the existing `tag`/`rev`).
**Do NOT touch** non-aztec-packages deps (e.g. `sha512`, `bignum`) — they version independently.

## Step 2 — bump the npm deps (`package.json`)
- Every `@aztec/*` dependency (accounts, aztec.js, noir-contracts.js, protocol-contracts, pxe, stdlib, wallet-sdk, wallets, …) → the npm version.
- `config.aztecVersion` → the npm version (the `setup-aztec` CI action reads this to install the toolchain).
- The package's own `version` is the *release* version — bump it too if this repo tracks aztec (it does), else leave.
- **`@aztec-foundation/aztec-benchmark` is a separate package** (its own repo/release). Only bump it if a matching release exists; it declares `@aztec/*` as **peerDependencies**, so it must resolve to the same aztec version — mismatches cause duplicate-type errors (see Gotchas).

## Step 3 — regenerate the lockfile + toolchain
```bash
yarn install                 # updates node_modules + yarn.lock to the new versions
aztec-up install <version>   # install the toolchain matching the target (do NOT rely on a stale nightly)
export PATH="$HOME/.aztec/current/bin:$PATH"
```
Confirm: `aztec --version`. If a local aztec-packages checkout was given, its toolchain can be used instead.

## Step 4 — local validation (prove the bump)
Run in order; stop and diagnose on the first failure:
```bash
yarn ccc                     # clean + compile + codegen against the new deps
yarn test:nr                 # Noir tests (aztec test)
# typecheck src + scripts (+ benchmarks if the benchmark dep resolves) via a temp tsconfig with noEmit
yarn format:check
yarn install --frozen-lockfile   # lockfile matches package.json
yarn build                   # assembles export/<pkg>
(cd export/@aztec-foundation/aztec-standards && npm publish --dry-run --access public)   # tarball sanity
# yarn test:js — only if a local network is up (aztec start --local-network); needs no npm creds
```
**Diagnosing failures:** a compile/test break is often a real API change in the new aztec version,
not a repo bug. Use the **local aztec-packages checkout / `gh api` at the target ref** to diff the
relevant internals and fix. See Gotchas.

## Step 5 — hand off
When everything is green: commit, open a PR to `main`, let CI pass, merge. Then invoke the
**`release`** skill to cut an `rc` prerelease and, once that's validated, the production release.

---

## Gotchas (bump-time — check these first)
- **Toolchain mismatch.** The default local `aztec`/`nargo` is often an older nightly that can't parse
  the target's aztec-nr (e.g. "Non-ASCII character in comment"). Always `aztec-up install <version>`.
- **Hand-rolled reproductions of aztec internals break on API changes.** `src/escrow_contract/src/key_derivation.nr`
  re-implements `deriveKeys`; when v5 added master message-signing/fallback keys, escrow addresses
  stopped matching. If `get_escrow`/derivation tests fail, diff the aztec-packages key-derivation
  constants/`PublicKeys` at the target ref and re-sync. Regenerate the hardcoded `get_test_vector` hashes.
- **v5 wallet API.** `createSchnorrAccount(secret, salt)` → now needs a 3rd `GrumpkinScalar` signing key;
  `Wallet` context types may need `EmbeddedWallet`. Deploy scripts derive the secret from the signing key
  (`deriveSecretKeyFromSigningKey`).
- **Benchmark peerDep / duplicate tree.** If `benchmarks/*.ts` typecheck shows `_branding` /
  `.../aztec-benchmark/node_modules/@aztec/...` errors, the benchmark pulled a *second* `@aztec` tree —
  it must be on a version whose `@aztec/*` are `peerDependencies` matching this repo's aztec version.
