#!/usr/bin/env bash
# Assembles the npm package under export/ from the `aztec compile` + `aztec codegen` output (`yarn ccc`).
set -euo pipefail

PROJECT_NAME="@aztec-foundation/aztec-standards"
EXPORT_DIR="export/${PROJECT_NAME}"
# shellcheck source=scripts/package-contents.sh
source "$(dirname "${BASH_SOURCE[0]}")/package-contents.sh"

wrappers=()
for name in "${PUBLISHED[@]}"; do
  [ -f "src/artifacts/${name}.ts" ] || { echo "error: src/artifacts/${name}.ts is missing; run \`yarn ccc\` first" >&2; exit 1; }
  wrappers+=("src/artifacts/${name}.ts")
done
for wrapper in src/artifacts/*.ts; do
  name=$(basename "${wrapper}" .ts)
  case " ${PUBLISHED[*]} ${TEST_FIXTURES[*]} " in
    *" ${name} "*) ;;
    *) echo "error: ${wrapper} is in neither PUBLISHED nor TEST_FIXTURES (scripts/package-contents.sh)" >&2; exit 1 ;;
  esac
done
for artifact in "${FIXTURE_ARTIFACTS[@]}"; do
  [ -f "target/${artifact}.json" ] || { echo "error: target/${artifact}.json is missing; run \`yarn ccc\` first" >&2; exit 1; }
done

# Rebuilt from scratch: a stale file would otherwise ride along into the tarball.
rm -rf "${EXPORT_DIR}"
mkdir -p "${EXPORT_DIR}"

# Each wrapper imports ../../target/<crate>-<Name>.json, so rooting tsc at the repo root emits
# artifacts/src/artifacts/<Name>.js beside artifacts/target/<crate>-<Name>.json, and only the JSON a published wrapper
# imports.
yarn tsc "${wrappers[@]}" --rootDir . --outDir "${EXPORT_DIR}/artifacts" --skipLibCheck --target es2020 --module nodenext --moduleResolution nodenext --resolveJsonModule --declaration

# tsc re-indents the JSON it emits (~10% larger); ship the compiler's bytes.
for json in "${EXPORT_DIR}"/artifacts/target/*.json; do
  cp "target/$(basename "${json}")" "${json}"
done

# Consumers import all of these paths, so each keeps resolving:
#   artifacts/src/artifacts/<Name>.js and artifacts/target/*.json  the one full copy
#   target/<crate>-<Name>.json                                       a second copy of the published artifacts
#   dist/src/artifacts/<Name>.js                                     re-exports of artifacts/. The upstream pre-release
#                                                                    workflow tars dist/ into dist.tar.gz, so it must
#                                                                    exist; that archive alone no longer runs.
cp -r "${EXPORT_DIR}/artifacts/target" "${EXPORT_DIR}/target"
for artifact in "${FIXTURE_ARTIFACTS[@]}"; do
  cp "target/${artifact}.json" "${EXPORT_DIR}/artifacts/target/"
done
mkdir -p "${EXPORT_DIR}/dist/src/artifacts"
for name in "${PUBLISHED[@]}"; do
  for ext in js d.ts; do
    echo "export * from '../../../artifacts/src/artifacts/${name}.js';" > "${EXPORT_DIR}/dist/src/artifacts/${name}.${ext}"
  done
done

cp README.md LICENSE "${EXPORT_DIR}/"

# Strip the dev-only fields. `files` keeps anything else that lands in the export dir (an earlier `npm pack`, say) out
# of the tarball; npm always adds package.json, README and LICENSE.
jq 'del(.scripts, ."lint-staged", .packageManager, .devDependencies, .dependencies, .engines, .resolutions) | .files = ["artifacts", "dist", "target"]' \
  package.json > "${EXPORT_DIR}/package.json"

echo "✔ Package prepared at ${EXPORT_DIR}"
