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

Since v6 Aztec ships from three places, each with its own `vX.Y.Z` tags:
- **aztec-nr** crates (`aztec`, `uint-note`, `balance-set`, `compressed-string`, …): `aztec-labs-eng/aztec-nr`, flat crate dirs.
- **protocol crates** (`serde`, `types`) and the `@aztec-foundation/*` npm packages (`bb.js`, `noir-*`):
  `AztecProtocol/aztec-packages`, the crates under `noir-projects/fnd/noir-protocol-circuits/crates/`.
- **npm SDK + toolchain** (`@aztec-labs/*`, `aztec-up`): built from `aztec-labs-eng/aztec-node`; its
  `docs/docs-developers/docs/resources/migration_notes.md` is the authoritative changelog.

aztec-nr and the SDK share a version; aztec-packages numbers its releases independently, and an aztec-nr
release builds on whichever one it pins (6.0.0-rc.3 pins aztec-packages `v6.0.0-rc.6`, which has no `rc.3`).

## Step 0 — gather inputs (ask the user)
Use `AskUserQuestion` (or ask directly) for:
1. **Target version** — an aztec-nr **tag** `vX.Y.Z[-suffix]` (release, rc, or nightly) whose `@aztec-labs/*`
   packages are on npm; the npm version is the tag without its `v`. The aztec-packages tag `vP` is derived
   from it below, never assumed equal. A bare commit identifies only one of the repos, so for an untagged
   commit stop and ask the user for the matching revision of each.
2. **Source** — a **path to a local checkout** of aztec-nr / aztec-node, or the GitHub repos. The source is for *diagnosis*, not the dep URL (Nargo deps always point at the GitHub git URL).

Verify the target exists before touching anything, and record the full SHAs for the PR body (Nargo
pins by tag only, and tags can move). An unmatched `ls-remote` pattern prints nothing and still exits 0,
hence `--exit-code`; query both refs because the repos mix annotated and lightweight tags, and record the
peeled `^{}` commit when present:
- `git ls-remote --exit-code https://github.com/aztec-labs-eng/aztec-nr 'refs/tags/vX.Y.Z' 'refs/tags/vX.Y.Z^{}'`
- `vP` is the tag aztec-nr's own `protocol_types` dependency pins at the target:
  `curl -fsSL https://raw.githubusercontent.com/aztec-labs-eng/aztec-nr/vX.Y.Z/aztec/Nargo.toml | grep protocol_types`,
  then `git ls-remote --exit-code https://github.com/AztecProtocol/aztec-packages 'refs/tags/vP' 'refs/tags/vP^{}'`.
- `npm view @aztec-labs/aztec.js@X.Y.Z version` must print the version (a missing one fails with E404), and
  `npm view @aztec-labs/stdlib@X.Y.Z dependencies` names the `@aztec-foundation/bb.js` version the SDK runs on.

## Step 1 — bump the Noir deps (all `Nargo.toml`)
```bash
find . -name Nargo.toml -not -path '*/node_modules/*'
```
- aztec-nr deps: `git = "https://github.com/aztec-labs-eng/aztec-nr"`, `tag = "vX.Y.Z"`,
  `directory = "<crate dir>"` (`aztec`, `uint-note`, `balance-set`, `compressed-string`).
- protocol crates: no `Nargo.toml` here depends on aztec-packages directly; they arrive through aztec-nr's
  own `protocol_types` dep, so there is nothing to bump. If a direct dependency returns (e.g. `serde`), give it
  `git = "https://github.com/AztecProtocol/aztec-packages"` (no trailing slash — the same string aztec-nr's
  `protocol_types` dep uses), `tag = "vP"` from Step 0 (not the aztec-nr tag) and its
  `directory = "noir-projects/fnd/noir-protocol-circuits/crates/<crate>"`. aztec-nr builds on that checkout
  (`types` reaches `serde` by path inside it), so any other tag adds a second, unrelated copy of the crate.
- **Do NOT touch** other deps: `bignum` versions independently, and `sha512` tracks upstream `master` (it
  has no tags). Instead refresh its entry in `noir-dep-revisions.txt`: if
  `git ls-remote https://github.com/noir-lang/sha512 refs/heads/master` no longer matches it, review the
  upstream diff before updating the SHA. Escrow key derivation hashes with it, so the `test_logic_contract`
  key-derivation vectors must still pass, and any change to the compiled `Escrow`/`TestLogic` artifacts
  (function bytecode, verification keys, class ids) must be called out.

## Step 2 — bump the npm deps (`package.json`)
- Every `@aztec-labs/*` dependency → the npm version, and `@aztec-foundation/bb.js` → the version that SDK
  depends on (Step 0), both **pinned exactly**: the `latest` dist-tag has pointed at a stale nightly, and any
  other bb.js pin installs a second Barretenberg next to the SDK's.
- `viem` → exactly the specifier the SDK itself depends on (`npm view @aztec-labs/aztec.js@X.Y.Z dependencies`):
  upstream `viem@2.57.1` since 6.0.0-rc.4, the `npm:@aztec/viem@…` alias before it. A spec that resolves to
  another version or package installs a second viem beside the SDK's.
- `config.aztecVersion` → the npm version (the `setup-aztec` CI action reads this to install the toolchain).
- The package's own `version` is the *release* version — bump it too if this repo tracks aztec (it does), else leave.
- **`@aztec-foundation/aztec-benchmark` is a separate package** (its own repo/release). Only bump it if a matching release exists; it declares the Aztec SDK as **peerDependencies**, so it must resolve to the same aztec version — mismatches cause duplicate-type errors (see Gotchas). Move the devDependency and the two reusable-workflow pins (`pr-checks.yml`, `update-baseline.yml`) to the same release commit together.

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
Confirm: `aztec --version`. The installer needs the Node that `install.aztec-labs.com/<version>/versions` names
(24.15 since 6.0.0-rc.4). Its foundryup step refuses to run while any `anvil` is running on the host, other
agents' included: then download that file's foundry release yourself, check it with
`gh attestation verify <tarball> --repo foundry-rs/foundry`, and run the version's `install` script with
`install_foundry` copying those binaries instead of calling foundryup.

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
yarn check:noir-deps         # cached git deps match noir-dep-revisions.txt; nargo never re-fetches, so on a
                             # stale clone delete it under ~/nargo and compile again
yarn test:nr                 # Noir tests (aztec test) — alone on the host only: it runs against whatever
                             # listens on 8081; with other agents around use the free-port recipe in Gotchas
yarn typecheck               # tsc --noEmit over src, scripts and benchmarks (CI runs it too)
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
- **The migration notes are not the diff.** 6.0.0-rc.3's notes omit that `txe_oracles::deploy` and
  `ContractDeployment` gained an `immutables_hash`, which the vault and escrow tests pass directly (0 is the
  `DeployOptions` default and what escrow's address derivation assumes), and they list a `Writer::advance_offset`
  removal the pinned protocol crates do not contain. Diff aztec-nr's `aztec/src` and the protocol crates between
  the old and target tags (nargo caches both under `~/nargo/github.com/<org>/<repo>/<tag>`) against what
  `src/**/*.nr` uses: a compile catches changed signatures, not changed behaviour.
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
- **On a loaded host a few TXE tests can fail with `Public keys not registered for account …`.** The TXE drops
  a test's session when its HTTP socket closes and answers the next call with a fresh, empty one, so a test
  whose connection closes mid-run (most likely Node's idle keep-alive timeout, 5 s plus a 1 s buffer, on a
  starved test) runs on without its accounts. Rerun the failures alone
  (`aztec-nargo test --package <crate> --exact <test>`, same `--oracle-resolver`) before blaming the bump.
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
  the installer's floor (24.12 for rc.1 and rc.3, 24.15 for rc.4). If CI fails installing the toolchain, that
  action needs a bump first.
- **Benchmark peerDep / duplicate tree.** `aztec-benchmark` 5.x peers `@aztec/*` `>=5 <6`; 6.0.0-rc.1 is
  the first release with `@aztec-labs/*` peers. Yarn only warns about a mismatch and tsx doesn't
  type-check, so run `yarn typecheck` (`tsconfig.json` includes `benchmarks/`) and then the benchmarks
  themselves; `_branding` / `.../aztec-benchmark/node_modules/@aztec…` errors mean the benchmark pulled a
  *second* SDK tree.
- **Benchmark DA cap.** `aztec start --local-network` defaults to 3s blocks, capping a tx at ~55.8k DA
  gas (mainnet's 6s blocks admit ~117k). Publishing the Vault class (~64k) needs `block-duration-ms:
  "6000"` on both aztec-benchmark workflows (6.0.0-rc.1+) and `SEQ_BLOCK_DURATION_MS` on the JS job.
  Re-check the cap whenever a bump touches stdlib's `gas/tx_gas_limits.ts`.
