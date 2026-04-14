#!/usr/bin/env bash
# check-prerequisites.sh [--json]
# Validates current branch is a feature branch and returns FEATURE_DIR + AVAILABLE_DOCS.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../" && pwd)"
FEATURES_DIR="$REPO_ROOT/.specify/features"

JSON=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-Json) JSON=true; shift ;;
    *) shift ;;
  esac
done

BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ ! "$BRANCH" =~ ^feature/ ]]; then
  echo "ERROR: Not on a feature branch (current: $BRANCH)" >&2
  exit 1
fi

SLUG="${BRANCH#feature/}"
FEATURE_DIR="$FEATURES_DIR/$SLUG"

if [[ ! -d "$FEATURE_DIR" ]]; then
  echo "ERROR: Feature dir not found: $FEATURE_DIR" >&2
  exit 1
fi

# Required: spec.md and plan.md
if [[ ! -f "$FEATURE_DIR/spec.md" ]]; then
  echo "ERROR: spec.md missing in $FEATURE_DIR" >&2
  exit 1
fi
if [[ ! -f "$FEATURE_DIR/plan.md" ]]; then
  echo "ERROR: plan.md missing — run /speckit.plan first" >&2
  exit 1
fi

AVAILABLE_DOCS=()
for f in spec.md plan.md data-model.md research.md quickstart.md; do
  [[ -f "$FEATURE_DIR/$f" ]] && AVAILABLE_DOCS+=("$f")
done
DOCS_JSON=$(printf '"%s",' "${AVAILABLE_DOCS[@]}")
DOCS_JSON="[${DOCS_JSON%,}]"

if $JSON; then
  printf '{"FEATURE_DIR":"%s","BRANCH":"%s","AVAILABLE_DOCS":%s}\n' \
    "$FEATURE_DIR" "$BRANCH" "$DOCS_JSON"
else
  echo "Feature dir: $FEATURE_DIR"
  echo "Branch:      $BRANCH"
fi
