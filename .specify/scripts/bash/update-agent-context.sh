#!/usr/bin/env bash
# update-agent-context.sh <agent>
# Updates the agent-specific context file for the current feature.
# Currently supports: claude

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../" && pwd)"
FEATURES_DIR="$REPO_ROOT/.specify/features"

AGENT="${1:-claude}"

BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ ! "$BRANCH" =~ ^feature/ ]]; then
  echo "ERROR: Not on a feature branch" >&2
  exit 1
fi

SLUG="${BRANCH#feature/}"
FEATURE_DIR="$FEATURES_DIR/$SLUG"
CONTEXT_FILE="$FEATURE_DIR/agent-context-$AGENT.md"

if [[ ! -f "$CONTEXT_FILE" ]]; then
  cat > "$CONTEXT_FILE" <<EOF
# Agent Context: $AGENT

**Feature**: $BRANCH
**Updated**: $(date +%Y-%m-%d)

## Technology Stack

<!-- BEGIN:MANAGED -->
<!-- END:MANAGED -->

## Manual Notes

<!-- Add any notes here that should persist between agent sessions -->
EOF
  echo "Created: $CONTEXT_FILE"
else
  # Update the date
  sed -i "s/\*\*Updated\*\*: .*/\*\*Updated\*\*: $(date +%Y-%m-%d)/" "$CONTEXT_FILE"
  echo "Updated: $CONTEXT_FILE"
fi
