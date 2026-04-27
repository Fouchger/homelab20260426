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

resolve_base_dir() {
  local requested_dir="${1:-}"

  if [[ -n "${requested_dir}" ]]; then
    cd "${requested_dir}" >/dev/null 2>&1
  fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "${git_root}"
    return 0
  fi

  pwd
}

make_file_executable() {
  local target_file="$1"

  if [[ -f "${target_file}" ]]; then
    chmod +x "${target_file}"
    printf 'chmod +x %s\n' "${target_file}"
  fi
}

main() {
  local base_dir
  base_dir="$(resolve_base_dir "${1:-}")"

  printf 'Working directory: %s\n' "${base_dir}"

  printf 'Ensuring all shell scripts are executable...\n'
  while IFS= read -r -d '' file_path; do
    make_file_executable "${file_path}"
  done < <(find "${base_dir}" -type f -name '*.sh' -print0)

  printf 'Ensuring key task and bootstrap entrypoints are executable...\n'
  while IFS= read -r -d '' file_path; do
    make_file_executable "${file_path}"
  done < <(
    find "${base_dir}" -maxdepth 2 -type f \( \
      -name 'install.sh' -o \
      -name 'bootstrap.sh' -o \
      -name 'configure.sh' \
    \) -print0
  )

  printf 'Executable permission reconciliation complete.\n'
}

main "${1:-}"