#!/usr/bin/env bash
# create-new-feature.sh <description> --json --short-name <name>
# Creates a feature branch and spec directory, outputs JSON with paths.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../" && pwd)"
FEATURES_DIR="$REPO_ROOT/.specify/features"
TEMPLATES_DIR="$REPO_ROOT/.specify/templates"

DESCRIPTION=""
SHORT_NAME=""
JSON=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-Json) JSON=true; shift ;;
    --short-name|-ShortName) SHORT_NAME="$2"; shift 2 ;;
    --number|-Number) shift 2 ;;  # ignored — auto-detected
    *) DESCRIPTION="$1"; shift ;;
  esac
done

if [[ -z "$SHORT_NAME" ]]; then
  echo "ERROR: --short-name is required" >&2
  exit 1
fi

mkdir -p "$FEATURES_DIR"

# Find next number across existing feature dirs and git branches
NEXT_NUM=1

# Check existing feature dirs
if ls "$FEATURES_DIR" 2>/dev/null | grep -qE '^[0-9]+'; then
  LAST_DIR=$(ls "$FEATURES_DIR" | grep -E '^[0-9]+' | sort | tail -1 | grep -oE '^[0-9]+' || echo "0")
  if [[ "$LAST_DIR" -ge "$NEXT_NUM" ]]; then
    NEXT_NUM=$((10#$LAST_DIR + 1))
  fi
fi

# Check git branches
GIT_MAX=$(git -C "$REPO_ROOT" branch -a 2>/dev/null \
  | grep -oE 'feature/([0-9]+)' \
  | grep -oE '[0-9]+' \
  | sort -n \
  | tail -1 || echo "0")
if [[ -n "$GIT_MAX" && "$GIT_MAX" -ge "$NEXT_NUM" ]]; then
  NEXT_NUM=$((10#$GIT_MAX + 1))
fi

PADDED=$(printf "%03d" "$NEXT_NUM")
FEATURE_DIR="$FEATURES_DIR/$PADDED-$SHORT_NAME"
BRANCH_NAME="feature/$PADDED-$SHORT_NAME"
SPEC_FILE="$FEATURE_DIR/spec.md"

mkdir -p "$FEATURE_DIR/checklists"

# Copy spec template and seed with branch/date
cp "$TEMPLATES_DIR/spec-template.md" "$SPEC_FILE"
DATE_NOW=$(date +%Y-%m-%d)
sed -i "s|\[DATE\]|$DATE_NOW|g" "$SPEC_FILE"
sed -i "s|\[BRANCH_NAME\]|$BRANCH_NAME|g" "$SPEC_FILE"

# Create and checkout branch
if ! git -C "$REPO_ROOT" checkout -b "$BRANCH_NAME" 2>/dev/null; then
  echo "Branch $BRANCH_NAME already exists, switching to it" >&2
  git -C "$REPO_ROOT" checkout "$BRANCH_NAME"
fi

if $JSON; then
  printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_DIR":"%s","NUMBER":%d}\n' \
    "$BRANCH_NAME" "$SPEC_FILE" "$FEATURE_DIR" "$NEXT_NUM"
else
  echo "Branch:     $BRANCH_NAME"
  echo "Spec file:  $SPEC_FILE"
  echo "Feature dir: $FEATURE_DIR"
fi
