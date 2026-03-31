#!/usr/bin/env bash

set -euo pipefail

# Build Flutter Web from BB_flutter and deploy the build artifact into BB_web.
# Optional overrides:
#   WEB_REPO_DIR=/path/to/BB_web ./deploy_web.sh
#   WEB_BRANCH=main ./deploy_web.sh
#   NO_PUSH=1 ./deploy_web.sh
#   FLUTTER_PROD_BRANCH=master ./deploy_web.sh
#   MERGE_TO_PROD_BRANCH_FIRST=0 ./deploy_web.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_PROJECT_DIR="${SCRIPT_DIR}"
WEB_REPO_DIR="${WEB_REPO_DIR:-${SCRIPT_DIR}/../BB_web}"
WEB_BRANCH="${WEB_BRANCH:-main}"
NO_PUSH="${NO_PUSH:-0}"
FLUTTER_PROD_BRANCH="${FLUTTER_PROD_BRANCH:-master}"
MERGE_TO_PROD_BRANCH_FIRST="${MERGE_TO_PROD_BRANCH_FIRST:-1}"
RETURN_TO_SOURCE_BRANCH="${RETURN_TO_SOURCE_BRANCH:-1}"
APP_VERSION="$(awk -F': ' '/^version:/{print $2; exit}' "${FLUTTER_PROJECT_DIR}/pubspec.yaml" | tr -d '\r')"
DEPLOYED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SOURCE_BRANCH="$(git -C "${FLUTTER_PROJECT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
BUILD_GIT_SHA="$(git -C "${FLUTTER_PROJECT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "[deploy] Starting web deployment"
echo "[deploy] Flutter project: ${FLUTTER_PROJECT_DIR}"
echo "[deploy] Flutter source branch: ${SOURCE_BRANCH}"
echo "[deploy] Flutter production branch: ${FLUTTER_PROD_BRANCH}"
echo "[deploy] Web repo: ${WEB_REPO_DIR}"
echo "[deploy] App version: ${APP_VERSION}"
echo "[deploy] Build SHA: ${BUILD_GIT_SHA}"
echo "[deploy] Deployed at (UTC): ${DEPLOYED_AT}"

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

if [ "${MERGE_TO_PROD_BRANCH_FIRST}" = "1" ]; then
  if [ -n "$(git -C "${FLUTTER_PROJECT_DIR}" status --porcelain)" ]; then
    echo "[deploy] ERROR: BB_flutter has uncommitted changes. Commit or stash first."
    exit 1
  fi

  if ! git -C "${FLUTTER_PROJECT_DIR}" show-ref --verify --quiet "refs/heads/${FLUTTER_PROD_BRANCH}"; then
    echo "[deploy] ERROR: Branch '${FLUTTER_PROD_BRANCH}' does not exist in BB_flutter."
    exit 1
  fi

  echo "[deploy] Syncing flutter branch '${FLUTTER_PROD_BRANCH}' before web deploy"
  git -C "${FLUTTER_PROJECT_DIR}" fetch origin "${FLUTTER_PROD_BRANCH}"

  if [ "${SOURCE_BRANCH}" != "${FLUTTER_PROD_BRANCH}" ]; then
    git -C "${FLUTTER_PROJECT_DIR}" checkout "${FLUTTER_PROD_BRANCH}"
  fi

  git -C "${FLUTTER_PROJECT_DIR}" pull --ff-only origin "${FLUTTER_PROD_BRANCH}"

  if [ "${SOURCE_BRANCH}" != "${FLUTTER_PROD_BRANCH}" ]; then
    if git -C "${FLUTTER_PROJECT_DIR}" merge-base --is-ancestor "${SOURCE_BRANCH}" "${FLUTTER_PROD_BRANCH}"; then
      echo "[deploy] '${SOURCE_BRANCH}' is already included in '${FLUTTER_PROD_BRANCH}'."
    else
      echo "[deploy] Merging '${SOURCE_BRANCH}' -> '${FLUTTER_PROD_BRANCH}'"
      git -C "${FLUTTER_PROJECT_DIR}" merge --no-ff "${SOURCE_BRANCH}" -m "Merge '${SOURCE_BRANCH}' before web deploy"
    fi
  fi

  if [ "${NO_PUSH}" = "1" ]; then
    echo "[deploy] NO_PUSH=1 -> flutter '${FLUTTER_PROD_BRANCH}' push skipped."
  else
    echo "[deploy] Pushing flutter '${FLUTTER_PROD_BRANCH}' to origin"
    git -C "${FLUTTER_PROJECT_DIR}" push origin "${FLUTTER_PROD_BRANCH}"
  fi

  BUILD_GIT_SHA="$(git -C "${FLUTTER_PROJECT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

echo "[deploy] Building Flutter web (release, deployment target: github_pages)"
(cd "${FLUTTER_PROJECT_DIR}" && flutter build web --release \
  --dart-define=APP_ENV=PROD \
  --dart-define=DEPLOY_TARGET=github_pages \
  --dart-define=APP_VERSION="${APP_VERSION}" \
  --dart-define=DEPLOYED_AT="${DEPLOYED_AT}" \
  --dart-define=BUILD_GIT_SHA="${BUILD_GIT_SHA}")

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
  if [ "${MERGE_TO_PROD_BRANCH_FIRST}" = "1" ] && [ "${RETURN_TO_SOURCE_BRANCH}" = "1" ] && [ "${SOURCE_BRANCH}" != "${FLUTTER_PROD_BRANCH}" ]; then
    echo "[deploy] Returning to source branch '${SOURCE_BRANCH}'"
    git -C "${FLUTTER_PROJECT_DIR}" checkout "${SOURCE_BRANCH}"
  fi
  exit 0
fi

echo "[deploy] Pushing to origin/${WEB_BRANCH}"
git push origin "${WEB_BRANCH}"

if [ "${MERGE_TO_PROD_BRANCH_FIRST}" = "1" ] && [ "${RETURN_TO_SOURCE_BRANCH}" = "1" ] && [ "${SOURCE_BRANCH}" != "${FLUTTER_PROD_BRANCH}" ]; then
  echo "[deploy] Returning to source branch '${SOURCE_BRANCH}'"
  git -C "${FLUTTER_PROJECT_DIR}" checkout "${SOURCE_BRANCH}"
fi

echo "[deploy] Deployment complete."
