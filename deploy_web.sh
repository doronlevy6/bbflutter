#!/usr/bin/env bash

set -euo pipefail

# Build Flutter Web from BB_flutter and deploy the build artifact into BB_web.
# Optional overrides:
#   WEB_REPO_DIR=/path/to/BB_web ./deploy_web.sh
#   WEB_BRANCH=main ./deploy_web.sh
#   NO_PUSH=1 ./deploy_web.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_PROJECT_DIR="${SCRIPT_DIR}"
WEB_REPO_DIR="${WEB_REPO_DIR:-${SCRIPT_DIR}/../BB_web}"
WEB_BRANCH="${WEB_BRANCH:-main}"
NO_PUSH="${NO_PUSH:-0}"

echo "[deploy] Starting web deployment"
echo "[deploy] Flutter project: ${FLUTTER_PROJECT_DIR}"
echo "[deploy] Web repo: ${WEB_REPO_DIR}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "[deploy] ERROR: flutter command not found in PATH"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "[deploy] ERROR: git command not found in PATH"
  exit 1
fi

if [ ! -d "${WEB_REPO_DIR}/.git" ]; then
  echo "[deploy] ERROR: ${WEB_REPO_DIR} is not a git repository"
  exit 1
fi

echo "[deploy] Building Flutter web (release, deployment target: github_pages)"
(cd "${FLUTTER_PROJECT_DIR}" && flutter build web --release --dart-define=APP_ENV=PROD --dart-define=DEPLOY_TARGET=github_pages)

BUILD_DIR="${FLUTTER_PROJECT_DIR}/build/web"
if [ ! -d "${BUILD_DIR}" ]; then
  echo "[deploy] ERROR: build output not found at ${BUILD_DIR}"
  exit 1
fi

echo "[deploy] Syncing build output to ${WEB_REPO_DIR}"
rsync -av --delete \
  --exclude '.git' \
  --exclude '.last_build_id' \
  --exclude 'README.md' \
  "${BUILD_DIR}/" "${WEB_REPO_DIR}/"

# Prevent GitHub Pages from ignoring paths that start with underscore.
touch "${WEB_REPO_DIR}/.nojekyll"
# Keep repository clean from local Flutter build metadata.
rm -f "${WEB_REPO_DIR}/.last_build_id"

cd "${WEB_REPO_DIR}"
git add -A

if git diff --cached --quiet; then
  echo "[deploy] No web changes detected. Nothing to commit."
  exit 0
fi

DEPLOY_TS="$(date +"%Y-%m-%d %H:%M:%S %Z")"
git commit -m "Deploy web build: ${DEPLOY_TS}"

if [ "${NO_PUSH}" = "1" ]; then
  echo "[deploy] NO_PUSH=1 -> commit created locally, push skipped."
  exit 0
fi

echo "[deploy] Pushing to origin/${WEB_BRANCH}"
git push origin "${WEB_BRANCH}"
echo "[deploy] Deployment complete."
