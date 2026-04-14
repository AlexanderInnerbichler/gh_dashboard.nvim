#!/usr/bin/env bash
# setup-plan.sh [--json]
# Detects current feature branch, returns paths for plan setup.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../" && pwd)"
FEATURES_DIR="$REPO_ROOT/.specify/features"
TEMPLATES_DIR="$REPO_ROOT/.specify/templates"

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

SPEC_FILE="$FEATURE_DIR/spec.md"
IMPL_PLAN="$FEATURE_DIR/plan.md"

# Copy plan template if not present
if [[ ! -f "$IMPL_PLAN" ]]; then
  cp "$TEMPLATES_DIR/plan-template.md" "$IMPL_PLAN"
  DATE_NOW=$(date +%Y-%m-%d)
  sed -i "s|\[DATE\]|$DATE_NOW|g" "$IMPL_PLAN"
  sed -i "s|\[SPEC_FILE\]|$SPEC_FILE|g" "$IMPL_PLAN"
  sed -i "s|\[BRANCH_NAME\]|$BRANCH|g" "$IMPL_PLAN"
fi

# Collect available docs
AVAILABLE_DOCS=()
for f in spec.md plan.md data-model.md research.md quickstart.md; do
  [[ -f "$FEATURE_DIR/$f" ]] && AVAILABLE_DOCS+=("$f")
done
DOCS_JSON=$(printf '"%s",' "${AVAILABLE_DOCS[@]}")
DOCS_JSON="[${DOCS_JSON%,}]"

if $JSON; then
  printf '{"FEATURE_SPEC":"%s","IMPL_PLAN":"%s","SPECS_DIR":"%s","BRANCH":"%s","AVAILABLE_DOCS":%s}\n' \
    "$SPEC_FILE" "$IMPL_PLAN" "$FEATURE_DIR" "$BRANCH" "$DOCS_JSON"
else
  echo "Spec:     $SPEC_FILE"
  echo "Plan:     $IMPL_PLAN"
  echo "Feature:  $FEATURE_DIR"
  echo "Branch:   $BRANCH"
fi
