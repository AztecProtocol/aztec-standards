#!/usr/bin/env bash
# Fails unless every git dependency listed in noir-dep-revisions.txt (or the file given as $1) is declared by a
# tracked Nargo.toml and cached at its listed commit. nargo clones a `git` dependency once, into
# $HOME/nargo/<host>/<org>/<repo>/<tag>, and builds from that clone without ever re-fetching it, so run this after
# a compile and with the same HOME. nargo ignores NARGO_HOME (noirup's install dir). Reads Nargo.toml with the
# TOML parser in node_modules; never touches the network or writes to the cache.
set -euo pipefail

[[ ${HOME:-} == /* ]] || {
  echo "FAIL HOME must be an absolute path: nargo keeps its git cache under it" >&2
  exit 1
}
# GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE and the like would point the checks below at another repository.
git_env=$(git rev-parse --local-env-vars) || {
  echo "FAIL git rev-parse --local-env-vars failed" >&2
  exit 1
}
for var in $git_env; do unset "$var"; done

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest=${1:-$root/noir-dep-revisions.txt}
cache=$HOME/nargo
# The cache key of every git dependency in a tracked Nargo.toml, as nargo's resolve_folder_name builds it: URL host,
# URL path and tag joined as path components.
if ! declared=$(cd "$root" && git ls-files -z -- '*Nargo.toml' | node -e '
  const fs = require("fs");
  const { parse } = require("./node_modules/@iarna/toml");
  for (const file of fs.readFileSync(0, "utf8").split("\0").filter(Boolean)) {
    for (const dep of Object.values(parse(fs.readFileSync(file, "utf8")).dependencies ?? {})) {
      if (typeof dep.git !== "string" || typeof dep.tag !== "string") continue;
      const url = new URL(dep.git);
      const parts = [url.hostname, url.pathname, dep.tag].map((p) => p.replace(/^\/+|\/+$/g, ""));
      console.log(parts.filter(Boolean).join("/"));
    }
  }'); then
  echo "FAIL could not list the git dependencies of the Nargo.toml files tracked in $root" >&2
  exit 1
fi
# Keeps `git status` from refreshing the cached clone's index.
export GIT_OPTIONAL_LOCKS=0

failed=0
checked=0
fail() {
  echo "FAIL $*" >&2
  failed=1
}

while read -r key want extra || [ -n "$key" ]; do
  case $key in '' | '#'*) continue ;; esac
  if [ -n "$extra" ] || ! [[ $want =~ ^[0-9a-f]{40}$ ]] || ! [[ $key =~ ^[^/]+(/[^/]+){3,}$ ]] || [[ /$key/ == */../* ]]; then
    fail "malformed line in $manifest: $key $want $extra"
    continue
  fi
  checked=$((checked + 1))
  dir=$cache/$key
  if ! grep -qxF -- "$key" <<< "$declared"; then
    fail "$key: no tracked Nargo.toml declares this git dependency at this tag"
  elif [ ! -e "$dir/.git" ]; then
    fail "$key: no clone at $dir; compile first"
  elif ! have=$(git -C "$dir" rev-parse HEAD 2>&1); then
    fail "$key: $have"
  elif [ "$have" != "$want" ]; then
    fail "$key: cached clone is at $have, expected $want. If upstream moved, review the change and update" \
      "$manifest; if the clone is stale, delete $dir and compile again."
  elif ! changes=$(git -C "$dir" -c core.fsmonitor=false status --porcelain --untracked-files=all 2>&1) ||
    [ -n "$changes" ]; then
    fail "$key: $dir differs from its commit; delete it and compile again. ${changes}"
  else
    echo "ok   $key $have"
  fi
done < "$manifest"

[ "$checked" -gt 0 ] || fail "$manifest lists no dependencies"
exit "$failed"
