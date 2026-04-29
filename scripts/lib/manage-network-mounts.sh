#!/usr/bin/env bash
# =============================================================================
# File: scripts/lib/manage-network-mounts.sh
# Purpose:
#   Run homelab Linux network mount management host by host across inventory.
# Notes:
#   - Prints the server name, IP, user, and outcome before moving on.
#   - Skips routers/network devices because filesystem mounts are Linux-only.
#   - Uses existing SSH key access; run access governance first if a host fails.
# =============================================================================

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ANSIBLE_CONFIG_FILE="${ANSIBLE_CONFIG_FILE:-${ROOT_DIR}/ansible.cfg}"
ANSIBLE_INVENTORY_FILE="${ANSIBLE_INVENTORY_FILE:-${ROOT_DIR}/state/ansible/inventory.yml}"
ANSIBLE_BIN="${ANSIBLE_BIN:-${ROOT_DIR}/state/venv/ansible/bin/ansible}"
ANSIBLE_INVENTORY_BIN="${ANSIBLE_INVENTORY_BIN:-${ROOT_DIR}/state/venv/ansible/bin/ansible-inventory}"
ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-${ROOT_DIR}/state/venv/ansible/bin/ansible-playbook}"
ANSIBLE_PYTHON="${ANSIBLE_PYTHON:-${ROOT_DIR}/state/venv/ansible/bin/python}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/homelab_ed25519}"
SSH_KNOWN_HOSTS_FILE="${SSH_KNOWN_HOSTS_FILE:-${HOME}/.ssh/known_hosts}"
ANSIBLE_NETWORK_MOUNTS_LIMIT="${ANSIBLE_NETWORK_MOUNTS_LIMIT:-all}"
ANSIBLE_NETWORK_MOUNTS_CHECK_MODE="${ANSIBLE_NETWORK_MOUNTS_CHECK_MODE:-false}"

playbook_file="${ROOT_DIR}/ansible/playbooks/linux_network_mounts.yml"

require_file() {
  local file_path="$1"
  local message="$2"
  if [ ! -f "$file_path" ]; then
    echo "$message" >&2
    exit 1
  fi
}

require_executable() {
  local executable_path="$1"
  if [ ! -x "$executable_path" ]; then
    echo "Missing executable: ${executable_path}" >&2
    exit 1
  fi
}

get_env_file_value() {
  local env_key="$1"
  local env_file="${CONFIG_ENV_FILE:-${ROOT_DIR}/state/config/.env}"

  if [ -f "$env_file" ]; then
    grep -E "^${env_key}=" "$env_file" \
      | tail -n 1 \
      | cut -d= -f2- \
      | sed 's/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//'
  fi
}

prompt_network_mount_credentials() {
  local default_username

  export OMV_SERVER_IP="${OMV_SERVER_IP:-$(get_env_file_value OMV_SERVER_IP)}"
  export OMV_SERVER_IP="${OMV_SERVER_IP:-192.168.30.20}"

  export OMV_CIFS_USERNAME="${OMV_CIFS_USERNAME:-$(get_env_file_value OMV_CIFS_USERNAME)}"
  export OMV_CIFS_PASSWORD="${OMV_CIFS_PASSWORD:-$(get_env_file_value OMV_CIFS_PASSWORD)}"
  export OMV_CIFS_DOMAIN="${OMV_CIFS_DOMAIN:-$(get_env_file_value OMV_CIFS_DOMAIN)}"

  if [ -z "${OMV_CIFS_USERNAME}" ] || [ -z "${OMV_CIFS_PASSWORD}" ]; then
    if [ "${NONINTERACTIVE:-0}" = "1" ] || [ ! -t 0 ]; then
      echo "OMV CIFS username/password are required. Set OMV_CIFS_USERNAME and OMV_CIFS_PASSWORD, or run interactively." >&2
      exit 1
    fi
  fi

  if [ -z "${OMV_CIFS_USERNAME}" ]; then
    default_username="omvuser"
    read -r -p "Enter OMV CIFS username [${default_username}]: " OMV_CIFS_USERNAME
    export OMV_CIFS_USERNAME="${OMV_CIFS_USERNAME:-$default_username}"
  fi

  if [ -z "${OMV_CIFS_PASSWORD}" ]; then
    read -r -s -p "Enter OMV CIFS password for ${OMV_CIFS_USERNAME}@${OMV_SERVER_IP}: " OMV_CIFS_PASSWORD
    echo ""
    export OMV_CIFS_PASSWORD
  fi

  if [ -z "${OMV_CIFS_USERNAME}" ] || [ -z "${OMV_CIFS_PASSWORD}" ]; then
    echo "OMV CIFS username and password are required." >&2
    exit 1
  fi
}

inventory_hosts() {
  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
    "$ANSIBLE_BIN" "$ANSIBLE_NETWORK_MOUNTS_LIMIT" \
      -i "$ANSIBLE_INVENTORY_FILE" \
      --list-hosts \
    | awk '
        /^[[:space:]]*hosts \([0-9]+\):/ { next }
        /^[[:space:]]*$/ { next }
        { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print }
      '
}

host_var() {
  local host_name="$1"
  local var_name="$2"
  local default_value="$3"

  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
    "$ANSIBLE_INVENTORY_BIN" \
      -i "$ANSIBLE_INVENTORY_FILE" \
      --host "$host_name" \
    | "$ANSIBLE_PYTHON" -c '
import json
import sys

data = json.load(sys.stdin)
name = sys.argv[1]
default = sys.argv[2]
value = data.get(name, default)
if value is None or value == "":
    value = default
if isinstance(value, (list, dict)):
    print(json.dumps(value))
else:
    print(value)
' "$var_name" "$default_value"
}

is_network_device() {
  local connection="$1"
  local network_os="$2"
  if [ -n "$network_os" ]; then
    return 0
  fi
  case "$connection" in
    ansible.netcommon.network_cli|network_cli|httpapi|netconf) return 0 ;;
    *) return 1 ;;
  esac
}

run_key_ping() {
  local host_name="$1"

  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
  SSH_KEY_PATH="$SSH_KEY_PATH" \
  SSH_KNOWN_HOSTS_FILE="$SSH_KNOWN_HOSTS_FILE" \
    "$ANSIBLE_BIN" "$host_name" \
      -i "$ANSIBLE_INVENTORY_FILE" \
      --private-key "$SSH_KEY_PATH" \
      -m ansible.builtin.ping \
      -o >/dev/null 2>&1
}

run_mount_role() {
  local host_name="$1"
  local check_args=()

  if [ "$ANSIBLE_NETWORK_MOUNTS_CHECK_MODE" = "true" ]; then
    check_args=(--check)
  fi

  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
  SSH_KEY_PATH="$SSH_KEY_PATH" \
  SSH_KNOWN_HOSTS_FILE="$SSH_KNOWN_HOSTS_FILE" \
  ANSIBLE_NETWORK_MOUNTS_LIMIT="$host_name" \
    "$ANSIBLE_PLAYBOOK" \
      "${check_args[@]}" \
      -i "$ANSIBLE_INVENTORY_FILE" \
      --limit "$host_name" \
      --private-key "$SSH_KEY_PATH" \
      "$playbook_file"
}

append_summary() {
  local bucket_name="$1"
  local host_name="$2"
  local detail="$3"
  case "$bucket_name" in
    success) success_hosts+=("${host_name} - ${detail}") ;;
    failed) failed_hosts+=("${host_name} - ${detail}") ;;
    skipped) skipped_hosts+=("${host_name} - ${detail}") ;;
  esac
}

print_summary() {
  echo "============================================================"
  echo "Network mounts final summary"
  echo "Target limit: ${ANSIBLE_NETWORK_MOUNTS_LIMIT}"
  echo "OMV server: ${OMV_SERVER_IP:-192.168.30.20}"
  echo "Total hosts processed: ${#hosts[@]}"
  echo "Linux success: ${#success_hosts[@]}"
  echo "Linux failed: ${#failed_hosts[@]}"
  echo "Skipped: ${#skipped_hosts[@]}"

  if [ "${#success_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Successful Linux mount management:"
    printf '  - %s\n' "${success_hosts[@]}"
  fi
  if [ "${#skipped_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Skipped hosts:"
    printf '  - %s\n' "${skipped_hosts[@]}"
  fi
  if [ "${#failed_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Failed Linux mount management:"
    printf '  - %s\n' "${failed_hosts[@]}"
  fi
}

main() {
  require_file "$ANSIBLE_INVENTORY_FILE" "Inventory has not been generated yet. Run: task ansible:inventory:render"
  require_file "$playbook_file" "Missing playbook: ${playbook_file}"
  require_executable "$ANSIBLE_BIN"
  require_executable "$ANSIBLE_INVENTORY_BIN"
  require_executable "$ANSIBLE_PLAYBOOK"
  require_executable "$ANSIBLE_PYTHON"
  prompt_network_mount_credentials

  mapfile -t hosts < <(inventory_hosts)
  if [ "${#hosts[@]}" -eq 0 ]; then
    echo "No hosts matched limit: ${ANSIBLE_NETWORK_MOUNTS_LIMIT}"
    exit 0
  fi

  echo "Network mounts target limit: ${ANSIBLE_NETWORK_MOUNTS_LIMIT}"
  echo "OMV server: ${OMV_SERVER_IP:-192.168.30.20}"
  echo "Hosts to process: ${#hosts[@]}"
  echo ""

  success_hosts=()
  failed_hosts=()
  skipped_hosts=()

  for host_name in "${hosts[@]}"; do
    local host_ip
    local host_user
    local host_port
    local host_connection
    local host_network_os

    host_ip="$(host_var "$host_name" ansible_host "$host_name")"
    host_user="$(host_var "$host_name" ansible_user root)"
    host_port="$(host_var "$host_name" ansible_port 22)"
    host_connection="$(host_var "$host_name" ansible_connection ssh)"
    host_network_os="$(host_var "$host_name" ansible_network_os "")"

    echo "============================================================"
    echo "Server: ${host_name}"
    echo "Address: ${host_ip}:${host_port}"
    echo "User: ${host_user}"
    echo "Connection: ${host_connection}"

    if is_network_device "$host_connection" "$host_network_os"; then
      echo "Type: network device"
      echo "Result: skipped. Filesystem mounts are only applicable to Linux hosts."
      append_summary skipped "$host_name" "network device"
      echo ""
      continue
    fi

    echo "Type: Linux/server"
    echo "Result: checking SSH key access"
    echo "Attempting SSH key login..."

    if ! run_key_ping "$host_name"; then
      echo "Result: key access failed. Run task ansible:ssh-access:manage first, then retry." >&2
      append_summary failed "$host_name" "SSH key access failed"
      echo ""
      continue
    fi

    echo "Result: key access OK. Managing network mounts."
    if run_mount_role "$host_name"; then
      echo "Result: ${host_name} network mounts completed successfully."
      append_summary success "$host_name" "network mounts reconciled"
    else
      echo "Result: ${host_name} network mounts failed." >&2
      append_summary failed "$host_name" "mount role failed"
    fi
    echo ""
  done

  print_summary

  if [ "${#failed_hosts[@]}" -gt 0 ]; then
    exit 1
  fi

  echo "Network mounts completed successfully."
}

main "$@"
