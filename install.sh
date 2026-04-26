#!/usr/bin/env bash
# ==============================================================================
# File: install.sh
# Purpose:
#   Bootstrap installer for HomeLab20260424.
# Notes:
#   - Downloads or updates the repository, installs Task, and creates local state.
#   - Operational work is intentionally delegated to Taskfile.yml after install.
#   - Debian/Ubuntu oriented.
#   - Existing state/config/.env values are preserved and updated only by key.
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

REPO_NAME="${HOMELAB_REPO_NAME:-HomeLab20260426}"
GITHUB_REPO="${GITHUB_REPO:-Fouchger/HomeLab20260426}"
GITHUB_BRANCH="${GITHUB_BRANCH:-${HOMELAB_BRANCH:-main}}"
GIT_PROTOCOL="${HOMELAB_GIT_PROTOCOL:-https}"
NONINTERACTIVE="${NONINTERACTIVE:-0}"
SETUP="${SETUP:-}"
TASK_INSTALL_REQUIRED="${TASK_INSTALL_REQUIRED:-1}"
TARGET_DIR="${TARGET_DIR:-}"
REPO_UPDATE_SKIPPED="0"

log_info() { printf 'INFO: %s\n' "$*"; }
log_warn() { printf 'WARN: %s\n' "$*"; }
log_error() { printf 'ERROR: %s\n' "$*" >&2; }
log_success() { printf 'SUCCESS: %s\n' "$*"; }

on_error() {
  exit_code="$1"
  line_no="$2"
  log_error "Install failed at line ${line_no} with exit code ${exit_code}."
  exit "$exit_code"
}
trap 'on_error "$?" "$LINENO"' ERR

is_debian_family() {
  [ -r /etc/os-release ] || return 1
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

apt_updated=0
apt_update_once() {
  if [ "$apt_updated" = "1" ]; then
    return 0
  fi
  if [ "$NONINTERACTIVE" = "1" ]; then
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
  else
    as_root apt-get update -y
  fi
  apt_updated=1
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
  command_name="$1"
  package_name="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi
  log_info "Installing missing command ${command_name} from package ${package_name}."
  apt_install "$package_name"
}

ensure_prerequisites() {
  if ! is_debian_family; then
    log_error 'Unsupported operating system. This installer supports Debian/Ubuntu.'
    exit 1
  fi
  ensure_command git git
  ensure_command curl curl
  apt_install ca-certificates
}

validate_branch_name() {
  if ! git check-ref-format --branch "$GITHUB_BRANCH" >/dev/null 2>&1; then
    log_error "Invalid branch name: ${GITHUB_BRANCH}"
    exit 1
  fi
}

select_setup() {
  if [ -n "$SETUP" ]; then
    case "$SETUP" in
      prod|dev) return 0 ;;
      *) log_error "SETUP must be prod or dev."; exit 1 ;;
    esac
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
    *) log_warn "Unknown HOMELAB_GIT_PROTOCOL=${GIT_PROTOCOL}. Using https."; printf 'https://github.com/%s.git\n' "$GITHUB_REPO" ;;
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

upsert_env() {
  file_path="$1"
  key_name="$2"
  key_value="$3"
  tmp_file="$(mktemp)"
  mkdir -p "$(dirname "$file_path")"
  [ -f "$file_path" ] || install -m 0600 /dev/null "$file_path"
  if grep -q "^${key_name}=" "$file_path"; then
    awk -v key="$key_name" -v value="$key_value" '$0 ~ "^" key "=" { print key "=" value; next } { print }' "$file_path" > "$tmp_file"
  else
    cat "$file_path" > "$tmp_file"
    printf '%s=%s\n' "$key_name" "$key_value" >> "$tmp_file"
  fi
  cat "$tmp_file" > "$file_path"
  rm -f "$tmp_file"
  chmod 600 "$file_path" 2>/dev/null || true
}

create_state() {
  cd "$TARGET_DIR"
  mkdir -p state/config state/secrets state/ansible state/terraform
  chmod 700 state/secrets 2>/dev/null || true
  env_file="${TARGET_DIR}/state/config/.env"
  upsert_env "$env_file" ROOT_DIR "$TARGET_DIR"
  upsert_env "$env_file" GITHUB_REPO "$GITHUB_REPO"
  upsert_env "$env_file" GITHUB_BRANCH "$GITHUB_BRANCH"
  upsert_env "$env_file" SETUP "$SETUP"
  upsert_env "$env_file" NONINTERACTIVE "$NONINTERACTIVE"
  [ -f state/secrets/passwords.env ] || install -m 0600 /dev/null state/secrets/passwords.env
  if [ ! -f state/ansible/inventory.yml ] && [ -f templates/inventory.yml.tpl ]; then
    cp templates/inventory.yml.tpl state/ansible/inventory.yml
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
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 \
    https://dl.cloudsmith.io/public/task/task/setup.deb.sh | as_root bash
  apt_install task
}

main() {
  echo '=========================================================='
  echo '            HomeLab20260424 installer'
  echo '=========================================================='
  select_setup
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
