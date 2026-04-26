#!/usr/bin/env bash
# ==============================================================================
# File: install.sh
# Purpose:
#   Bootstrap installer for the HomeLab20260424 project.
#
# Notes:
#   - Debian/Ubuntu oriented.
#   - Downloads or updates the repository, installs Task, and creates only the
#     local state required by this installer.
#   - Operational work is intentionally delegated to Taskfile.yml after install.
#   - SETUP is the target environment and must be either prod or dev.
#   - Existing state/config/.env values are preserved and updated only by key.
#   - Secrets are not created as plaintext by this installer. Encrypted secrets
#     are managed later through the repository secrets workflow.
# ============================================================================== 

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly REPO_NAME="${HOMELAB_REPO_NAME:-HomeLab20260426}"
readonly GITHUB_REPO="${GITHUB_REPO:-Fouchger/HomeLab20260426}"
readonly GITHUB_BRANCH="${GITHUB_BRANCH:-${HOMELAB_BRANCH:-main}}"
readonly GIT_PROTOCOL="${HOMELAB_GIT_PROTOCOL:-https}"
readonly NONINTERACTIVE="${NONINTERACTIVE:-0}"
readonly TASK_INSTALL_REQUIRED="${TASK_INSTALL_REQUIRED:-1}"

SETUP="${SETUP:-prod}"
TARGET_DIR="${TARGET_DIR:-}"
REPO_UPDATE_SKIPPED="0"
APT_UPDATED="0"

log_info() { printf 'INFO: %s\n' "$*"; }
log_warn() { printf 'WARN: %s\n' "$*"; }
log_error() { printf 'ERROR: %s\n' "$*" >&2; }
log_success() { printf 'SUCCESS: %s\n' "$*"; }

on_error() {
  local exit_code="$1"
  local line_no="$2"
  log_error "Install failed at line ${line_no} with exit code ${exit_code}."
  exit "$exit_code"
}
trap 'on_error "$?" "$LINENO"' ERR

is_debian_family() {
  [ -r /etc/os-release ] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) return 0 ;;
    *) return 1 ;;
  esac
}

have_root() { [ "$(id -u)" -eq 0 ]; }
have_sudo() { command -v sudo >/dev/null 2>&1; }

as_root() {
  if have_root; then
    "$@"
  elif have_sudo; then
    sudo -E "$@"
  else
    log_error 'Root privileges or sudo are required.'
    exit 1
  fi
}

apt_update_once() {
  if [ "$APT_UPDATED" = "1" ]; then
    return 0
  fi

  if [ "$NONINTERACTIVE" = "1" ]; then
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
  else
    as_root apt-get update -y
  fi

  APT_UPDATED="1"
}

apt_install() {
  apt_update_once

  if [ "$NONINTERACTIVE" = "1" ]; then
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
  else
    as_root apt-get install -y --no-install-recommends "$@"
  fi
}

ensure_command() {
  local command_name="$1"
  local package_name="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  log_info "Installing missing command ${command_name} from package ${package_name}."
  apt_install "$package_name"
}

ensure_package() {
  local package_name="$1"

  if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -Fq 'install ok installed'; then
    return 0
  fi

  log_info "Installing missing package ${package_name}."
  apt_install "$package_name"
}

ensure_prerequisites() {
  if ! is_debian_family; then
    log_error 'Unsupported operating system. This installer supports Debian/Ubuntu.'
    exit 1
  fi

  ensure_package ca-certificates
  ensure_command git git
  ensure_command curl curl
}

validate_branch_name() {
  if ! git check-ref-format --branch "$GITHUB_BRANCH" >/dev/null 2>&1; then
    log_error "Invalid branch name: ${GITHUB_BRANCH}"
    exit 1
  fi
}

validate_setup() {
  case "$SETUP" in
    prod|dev) return 0 ;;
    *)
      log_error 'SETUP must be prod or dev.'
      exit 1
      ;;
  esac
}

select_setup() {
  if [ "${SETUP_SOURCE:-}" = "prompt" ]; then
    return 0
  fi

  if [ -n "${SETUP:-}" ]; then
    validate_setup
    return 0
  fi

  if [ "$NONINTERACTIVE" = "1" ]; then
    SETUP="prod"
    return 0
  fi

  while :; do
    printf 'Select SETUP environment [prod/dev] (default: prod): ' > /dev/tty
    IFS= read -r SETUP < /dev/tty
    SETUP="${SETUP:-prod}"
    case "$SETUP" in
      prod|dev) return 0 ;;
      *) printf 'Please enter prod or dev.\n' > /dev/tty ;;
    esac
  done
}

resolve_target_dir() {
  if [ -n "$TARGET_DIR" ]; then
    mkdir -p "$(dirname "$TARGET_DIR")"
    return 0
  fi

  case "$SETUP" in
    prod) TARGET_DIR="${HOME}/app/${REPO_NAME}" ;;
    dev) TARGET_DIR="${HOME}/Github/${REPO_NAME}" ;;
  esac

  mkdir -p "$(dirname "$TARGET_DIR")"
}

repo_url() {
  case "$GIT_PROTOCOL" in
    ssh) printf 'git@github.com:%s.git\n' "$GITHUB_REPO" ;;
    https) printf 'https://github.com/%s.git\n' "$GITHUB_REPO" ;;
    *)
      log_warn "Unknown HOMELAB_GIT_PROTOCOL=${GIT_PROTOCOL}. Using https."
      printf 'https://github.com/%s.git\n' "$GITHUB_REPO"
      ;;
  esac
}

gh_usable() {
  command -v gh >/dev/null 2>&1 || return 1

  if [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ]; then
    return 0
  fi

  gh auth status -h github.com >/dev/null 2>&1
}

clone_repo() {
  local url

  if gh_usable; then
    log_info "Cloning ${GITHUB_REPO} with GitHub CLI."
    gh repo clone "$GITHUB_REPO" "$TARGET_DIR"
  else
    url="$(repo_url)"
    log_info "Cloning ${url}."
    git clone --branch "$GITHUB_BRANCH" --single-branch "$url" "$TARGET_DIR"
  fi
}

handle_dirty_repo() {
  if [ -z "$(git status --porcelain)" ]; then
    return 0
  fi

  log_warn "Local changes detected in ${TARGET_DIR}."

  if [ "$NONINTERACTIVE" = "1" ]; then
    git stash push -u -m "install: auto-stash before update ($(date -Is))"
    return 0
  fi

  printf 'Choose how to handle local changes:\n  [c] Commit and continue\n  [s] Stash and continue\n  [a] Abort update and keep local files\n' > /dev/tty

  while :; do
    printf 'Action [c/s/a] (default: a): ' > /dev/tty
    IFS= read -r action < /dev/tty
    action="${action:-a}"

    case "$action" in
      c|C)
        printf 'Commit message (default: WIP: local changes): ' > /dev/tty
        IFS= read -r commit_msg < /dev/tty
        commit_msg="${commit_msg:-WIP: local changes}"
        git add -A
        git commit -m "$commit_msg"
        return 0
        ;;
      s|S)
        git stash push -u -m "install: user stash before update ($(date -Is))"
        return 0
        ;;
      a|A)
        REPO_UPDATE_SKIPPED="1"
        return 0
        ;;
      *) printf 'Please enter c, s, or a.\n' > /dev/tty ;;
    esac
  done
}

update_repo() {
  if [ ! -d "${TARGET_DIR}/.git" ]; then
    log_error "Target exists but is not a git repository: ${TARGET_DIR}"
    exit 1
  fi

  cd "$TARGET_DIR"
  git fetch --prune origin

  if git show-ref --verify --quiet "refs/heads/${GITHUB_BRANCH}"; then
    git checkout "$GITHUB_BRANCH"
  elif git show-ref --verify --quiet "refs/remotes/origin/${GITHUB_BRANCH}"; then
    git checkout -B "$GITHUB_BRANCH" "origin/${GITHUB_BRANCH}"
  else
    log_error "Branch ${GITHUB_BRANCH} was not found on origin."
    exit 1
  fi

  handle_dirty_repo

  if [ "$REPO_UPDATE_SKIPPED" = "1" ]; then
    log_warn 'Repository update skipped.'
    return 0
  fi

  git pull --rebase --autostash origin "$GITHUB_BRANCH"
}

clone_or_update() {
  if [ ! -e "$TARGET_DIR" ]; then
    clone_repo
  elif [ -d "$TARGET_DIR" ]; then
    update_repo
  else
    log_error "Target path exists and is not a directory: ${TARGET_DIR}"
    exit 1
  fi
}

quote_dotenv_value() {
  local value="$1"
  printf '%q' "$value"
}

validate_env_key() {
  local key_name="$1"

  case "$key_name" in
    ''|*[!A-Za-z0-9_]*)
      log_error "Invalid environment key name: ${key_name}"
      exit 1
      ;;
    [0-9]*)
      log_error "Environment key must not start with a number: ${key_name}"
      exit 1
      ;;
  esac
}

upsert_env() {
  local file_path="$1"
  local key_name="$2"
  local key_value="$3"
  local quoted_value
  local tmp_file

  validate_env_key "$key_name"
  quoted_value="$(quote_dotenv_value "$key_value")"
  tmp_file="$(mktemp)"

  cleanup_tmp_file() {
    rm -f "$tmp_file"
  }
  trap cleanup_tmp_file RETURN

  mkdir -p "$(dirname "$file_path")"
  [ -f "$file_path" ] || install -m 0600 /dev/null "$file_path"

  if grep -Fq "${key_name}=" "$file_path"; then
    awk -v key="$key_name" -v value="$quoted_value" '
      index($0, key "=") == 1 { print key "=" value; next }
      { print }
    ' "$file_path" > "$tmp_file"
  else
    cat "$file_path" > "$tmp_file"
    printf '%s=%s\n' "$key_name" "$quoted_value" >> "$tmp_file"
  fi

  cat "$tmp_file" > "$file_path"
  chmod 600 "$file_path" 2>/dev/null || true
  trap - RETURN
  cleanup_tmp_file
}

create_state() {
  local env_file

  cd "$TARGET_DIR"

  mkdir -p state/config state/ansible
  env_file="${TARGET_DIR}/state/config/.env"

  upsert_env "$env_file" ROOT_DIR "$TARGET_DIR"
  upsert_env "$env_file" GITHUB_REPO "$GITHUB_REPO"
  upsert_env "$env_file" GITHUB_BRANCH "$GITHUB_BRANCH"
  upsert_env "$env_file" SETUP "$SETUP"
  upsert_env "$env_file" NONINTERACTIVE "$NONINTERACTIVE"

  if [ ! -f state/ansible/inventory.yml ] && [ -f templates/inventory.yml.tpl ]; then
    install -m 0600 templates/inventory.yml.tpl state/ansible/inventory.yml
  fi
}

ensure_executables() {
  cd "$TARGET_DIR"

  if [ -x scripts/lib/ensure-executable-scripts.sh ]; then
    scripts/lib/ensure-executable-scripts.sh "$TARGET_DIR"
  else
    find "$TARGET_DIR" -type f -name '*.sh' -exec chmod +x {} +
  fi
}

install_task() {
  if [ "$TASK_INSTALL_REQUIRED" != "1" ]; then
    return 0
  fi

  if command -v task >/dev/null 2>&1; then
    return 0
  fi

  ensure_command gpg gpg

  # Official Task Debian repository bootstrap. HTTPS/TLS is enforced and curl
  # retries transient network failures, but this remains an external trust point.
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 \
    https://dl.cloudsmith.io/public/task/task/setup.deb.sh | as_root bash

  apt_install task
}

main() {
  echo '=========================================================='
  echo '            HomeLab installer'
  echo '=========================================================='

  select_setup
  validate_setup
  ensure_prerequisites
  validate_branch_name
  resolve_target_dir
  clone_or_update
  create_state
  ensure_executables
  install_task

  log_success "Install complete. Next command: cd ${TARGET_DIR} && task bootstrap"
}

main "$@"
