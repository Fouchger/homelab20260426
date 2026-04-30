#!/usr/bin/env bash
# ==============================================================================
# File: scripts/lib/ensure-executable-scripts.sh
# Purpose:
#   Ensure repository shell scripts and nominated entrypoint files have the
#   executable bit set.
#
# Usage:
#   ./scripts/lib/ensure-executable-scripts.sh
#   ./scripts/lib/ensure-executable-scripts.sh /path/to/repo
#
# Notes:
#   - Uses the Git repository root when available.
#   - Safe to re-run.
#   - Sets executable permissions only on files that should be executable.
#   - Keeps the logic generic and repository-friendly.
# ==============================================================================

set -euo pipefail
set -o errtrace

# Resolve repo root (prefer git when available)
if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  BASE_DIR="$git_root"
else
  BASE_DIR="$(pwd)"
fi

echo "Working directory: $BASE_DIR"

# 1) Make all *.sh files executable (recursive)
echo "Making all *.sh files executable..."
while IFS= read -r -d '' file; do
  chmod +x "$file"
  echo "  chmod +x $file"
done < <(find "$BASE_DIR" -type f -name "*.sh" -print0)

# 2) Make key Python entrypoints executable (if present)
TARGETS=(
  "$BASE_DIR/scripts/lib/render-ansible-inventory.py"

)

echo "Making target Python scripts executable (if they exist)..."
for target in "${TARGETS[@]}"; do
  if [[ -f "$target" ]]; then
    chmod +x "$target"
    echo "  chmod +x $target"
  else
    echo "  Skipped (not found): $target"
  fi
done

echo "Done."