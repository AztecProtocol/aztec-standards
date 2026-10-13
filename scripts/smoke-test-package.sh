#!/usr/bin/env bash
# Installs the package into a scratch project and proves it is usable, not just present: the installed version is the
# expected one, the SDK version it declares installs beside it, it ships exactly the contracts package-contents.sh
# lists, and every wrapper loads its artifact through each import path consumers use.
#
#   scripts/smoke-test-package.sh <package-spec> <expected-version>
#
# <package-spec> is anything `npm install` accepts: a registry spec (@aztec-foundation/aztec-standards@6.0.0) or the
# tarball `npm pack` writes in the export dir. SMOKE_INSTALL_ATTEMPTS (default 1) is how many installs, 15s apart, it
# tries while the registry does not resolve the requested version yet. Exits 75 when it never does; every other failure
# exits 1.
set -euo pipefail

PROJECT_NAME="@aztec-foundation/aztec-standards"
SPEC="${1:?usage: $0 <package-spec> <expected-version>}"
EXPECTED_VERSION="${2:?usage: $0 <package-spec> <expected-version>}"
ATTEMPTS="${SMOKE_INSTALL_ATTEMPTS:-1}"
# shellcheck source=scripts/package-contents.sh
source "$(dirname "${BASH_SOURCE[0]}")/package-contents.sh"

# A tarball path must survive the cd into the scratch project.
local_tarball=false
if [ -f "${SPEC}" ]; then
  SPEC="$(cd "$(dirname "${SPEC}")" && pwd)/$(basename "${SPEC}")"
  local_tarball=true
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
cd "${workdir}"
npm init -y > /dev/null

installed=false
for attempt in $(seq 1 "${ATTEMPTS}"); do
  # --prefer-online skips a cached 404 for a version published moments ago.
  if npm install --prefer-online "${SPEC}"; then
    installed=true
    break
  fi
  [ "${local_tarball}" = false ] || { echo "smoke: installing ${SPEC} failed" >&2; exit 1; }
  # Only a version the registry does not resolve yet is worth waiting out. Once it resolves, a failed install is the
  # package's own fault; the one immediate retry absorbs propagation finishing between the two requests.
  if [ "$(npm view --prefer-online "${SPEC}" version 2> /dev/null)" = "${EXPECTED_VERSION}" ]; then
    npm install --prefer-online "${SPEC}" || { echo "smoke: ${SPEC} resolves but does not install" >&2; exit 1; }
    installed=true
    break
  fi
  if [ "${attempt}" -lt "${ATTEMPTS}" ]; then
    echo "install attempt ${attempt}/${ATTEMPTS} failed; retrying in 15s"
    sleep 15
  fi
done
if [ "${installed}" != true ]; then
  echo "smoke: the registry did not resolve ${SPEC} in ${ATTEMPTS} attempt(s)" >&2
  exit 75
fi
# Every failure from here on exits 1, whatever its own code.
trap 'exit 1' ERR

manifest="node_modules/${PROJECT_NAME}/package.json"
VERSION=$(node -p "require('./${manifest}').version")
if [ "${VERSION}" != "${EXPECTED_VERSION}" ]; then
  echo "smoke: installed ${PROJECT_NAME}@${VERSION}, expected ${EXPECTED_VERSION}" >&2
  exit 1
fi
AZTEC_VERSION=$(node -p "require('./${manifest}').config?.aztecVersion ?? ''")
[ -n "${AZTEC_VERSION}" ] || { echo "smoke: ${PROJECT_NAME}@${VERSION} declares no config.aztecVersion" >&2; exit 1; }

# The wrappers import @aztec-labs/aztec.js, which the package leaves to the consumer at config.aztecVersion.
npm install "@aztec-labs/aztec.js@${AZTEC_VERSION}"

# Importing a wrapper runs loadContractArtifact on the JSON it imports, so a wrapper shipped without its artifact, an
# artifact the SDK cannot parse, or a re-export pointing nowhere fails here.
cat > smoke.mjs << 'EOF'
import { readdirSync, readFileSync } from 'node:fs';

const pkg = '@aztec-foundation/aztec-standards';
const root = `node_modules/${pkg}`;
const [published, fixtureArtifacts] = process.argv.slice(2).map((list) => list.split(' '));
const sorted = (names) => [...names].sort().join(', ');
const expect = (what, actual, expected) => {
  if (sorted(actual) !== sorted(expected)) throw new Error(`${what}: ${sorted(actual)}; expected ${sorted(expected)}`);
};
const files = (dir, ext) => readdirSync(`${root}/${dir}`).filter((file) => file.endsWith(ext));
const contract = (dir, file) => JSON.parse(readFileSync(`${root}/${dir}/${file}`, 'utf8')).name;

for (const dir of ['artifacts/src/artifacts', 'dist/src/artifacts']) {
  for (const ext of ['.js', '.d.ts']) {
    expect(`${dir}/*${ext}`, files(dir, ext).map((file) => file.slice(0, -ext.length)), published);
  }
}
for (const name of published) {
  for (const path of [`artifacts/src/artifacts/${name}.js`, `dist/src/artifacts/${name}.js`]) {
    const wrapper = await import(`${pkg}/${path}`);
    const artifact = wrapper[`${name}ContractArtifact`];
    if (typeof wrapper[`${name}Contract`] !== 'function' || artifact?.name !== name || !(artifact.functions?.length > 0)) {
      throw new Error(`${path} did not load the ${name} artifact`);
    }
  }
}
// target/ holds the published artifacts; artifacts/target holds the same files plus the fixture artifacts.
expect('target/ contracts', files('target', '.json').map((file) => contract('target', file)), published);
expect('artifacts/target/', files('artifacts/target', '.json'), [...files('target', '.json'), ...fixtureArtifacts.map((a) => `${a}.json`)]);
for (const artifact of fixtureArtifacts) {
  const name = artifact.slice(artifact.indexOf('-') + 1);
  if (contract('artifacts/target', `${artifact}.json`) !== name) throw new Error(`artifacts/target/${artifact}.json is not ${name}`);
}
const { default: token } = await import(`${pkg}/target/token_contract-Token.json`, { with: { type: 'json' } });
if (token.name !== 'Token') throw new Error('target/token_contract-Token.json is not the Token artifact');
console.log(`smoke ok: ${published.length} wrappers load from artifacts/ and dist/; target/ and the fixture artifacts are complete`);
EOF
node smoke.mjs "${PUBLISHED[*]}" "${FIXTURE_ARTIFACTS[*]}"
echo "smoke: ${PROJECT_NAME}@${VERSION} works with @aztec-labs/aztec.js@${AZTEC_VERSION}"
