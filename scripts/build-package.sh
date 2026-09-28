#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="@aztec-foundation/aztec-standards"
EXPORT_DIR="export/${PROJECT_NAME}"

# ── Compile artifacts to JS ──────────────────────────────────────────────────
mkdir -p dist/artifacts/
yarn tsc src/artifacts/*.ts --outDir dist/artifacts/ --skipLibCheck --target es2020 --module nodenext --moduleResolution nodenext --resolveJsonModule --declaration

# ── Prepare export directory ─────────────────────────────────────────────────
mkdir -p "${EXPORT_DIR}/artifacts"
mkdir -p "${EXPORT_DIR}/dist"

# Copy compiled JS artifacts
cp -r dist/artifacts/* "${EXPORT_DIR}/artifacts/"

# Copy compiled JS artifacts to dist/ (for pre-release dist.tar.gz)
cp -r dist/artifacts/* "${EXPORT_DIR}/dist/"

# Copy compiled Noir contracts, minus the *.json.bak pre-postprocessing copies that `aztec compile`
# (its `bb aztec_process` step) leaves next to each artifact — they ~double the package size
cp -r target "${EXPORT_DIR}/"
find "${EXPORT_DIR}/target" -name '*.bak' -delete

# Copy documentation
cp README.md "${EXPORT_DIR}/"
cp LICENSE "${EXPORT_DIR}/"

# Create trimmed package.json (strip dev-only fields)
jq 'del(.scripts, ."lint-staged", .packageManager, .devDependencies, .dependencies, .engines, .resolutions)' \
  package.json > "${EXPORT_DIR}/package.json"

echo "✔ Package prepared at ${EXPORT_DIR}"
