#!/usr/bin/env bash
# =============================================================================
# File: scripts/lib/manage-linux-ssh-access.sh
# Purpose:
#   Run homelab access governance host by host across the generated inventory.
# Notes:
#   - Prints the target host and IP before doing any connection work.
#   - Linux servers are reconciled for users, SSH keys, sudo policy, and audit.
#   - Network devices such as MikroTik routers are connectivity-tested and then
#     reported as unsupported for Linux account governance.
#   - Uses key authentication first and prompts for the specific host password
#     only when Linux key access fails.
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
ANSIBLE_SSH_ACCESS_LIMIT="${ANSIBLE_SSH_ACCESS_LIMIT:-${ANSIBLE_ACCESS_GOVERNANCE_LIMIT:-all}}"
ANSIBLE_SSH_ACCESS_CHECK_MODE="${ANSIBLE_SSH_ACCESS_CHECK_MODE:-false}"
HOMELAB_TEST_NETWORK_DEVICES="${HOMELAB_TEST_NETWORK_DEVICES:-true}"

playbook_file="${ROOT_DIR}/ansible/playbooks/linux_ssh_access.yml"

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

ensure_control_key() {
  mkdir -p "$(dirname "$SSH_KEY_PATH")"
  chmod 700 "$(dirname "$SSH_KEY_PATH")"

  if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Control SSH key not found. Generating: ${SSH_KEY_PATH}"
    ssh-keygen -t ed25519 -C "homelab-control@local" -f "$SSH_KEY_PATH" -N ""
  fi

  chmod 600 "$SSH_KEY_PATH"
  if [ -f "${SSH_KEY_PATH}.pub" ]; then
    chmod 644 "${SSH_KEY_PATH}.pub"
  fi
}

inventory_hosts() {
  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
    "$ANSIBLE_BIN" "$ANSIBLE_SSH_ACCESS_LIMIT" \
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

run_network_test() {
  local host_name="$1"
  local extra_args=()

  if [ -n "${MIKROTIK_ROUTER_ADMIN_PASSWORD:-}" ]; then
    extra_args+=(--extra-vars "ansible_password=${MIKROTIK_ROUTER_ADMIN_PASSWORD}")
  fi

  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
  SSH_KEY_PATH="$SSH_KEY_PATH" \
  SSH_KNOWN_HOSTS_FILE="$SSH_KNOWN_HOSTS_FILE" \
    "$ANSIBLE_BIN" "$host_name" \
      -i "$ANSIBLE_INVENTORY_FILE" \
      --private-key "$SSH_KEY_PATH" \
      "${extra_args[@]}" \
      -m community.routeros.command \
      -a 'commands="/system identity print"' \
      -o >/dev/null 2>&1
}

run_role_with_key() {
  local host_name="$1"
  local check_args=()

  if [ "$ANSIBLE_SSH_ACCESS_CHECK_MODE" = "true" ]; then
    check_args=(--check)
  fi

  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
  SSH_KEY_PATH="$SSH_KEY_PATH" \
  SSH_KNOWN_HOSTS_FILE="$SSH_KNOWN_HOSTS_FILE" \
  ANSIBLE_SSH_ACCESS_LIMIT="$host_name" \
    "$ANSIBLE_PLAYBOOK" \
      "${check_args[@]}" \
      -i "$ANSIBLE_INVENTORY_FILE" \
      --limit "$host_name" \
      --private-key "$SSH_KEY_PATH" \
      "$playbook_file"
}

write_password_vars_file() {
  local password="$1"
  local vars_file="$2"

  HOMELAB_BOOTSTRAP_PASSWORD="$password" "$ANSIBLE_PYTHON" -c '
import json
import os
import sys

password = os.environ["HOMELAB_BOOTSTRAP_PASSWORD"]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "ansible_password": password,
        "ansible_become_password": password,
    }, handle)
    handle.write("\n")
' "$vars_file"
  chmod 600 "$vars_file"
}

run_role_with_password() {
  local host_name="$1"
  local password="$2"
  local vars_file

  vars_file="$(mktemp)"
  trap 'rm -f "$vars_file"' RETURN
  write_password_vars_file "$password" "$vars_file"

  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" \
  SSH_KEY_PATH="$SSH_KEY_PATH" \
  SSH_KNOWN_HOSTS_FILE="$SSH_KNOWN_HOSTS_FILE" \
  ANSIBLE_SSH_ACCESS_LIMIT="$host_name" \
    "$ANSIBLE_PLAYBOOK" \
      -i "$ANSIBLE_INVENTORY_FILE" \
      --limit "$host_name" \
      --extra-vars "@$vars_file" \
      "$playbook_file"

  rm -f "$vars_file"
  trap - RETURN
}

append_summary() {
  local bucket_name="$1"
  local host_name="$2"
  local detail="$3"
  case "$bucket_name" in
    success) success_hosts+=("${host_name} - ${detail}") ;;
    failed) failed_hosts+=("${host_name} - ${detail}") ;;
    skipped) skipped_hosts+=("${host_name} - ${detail}") ;;
    network_ok) network_ok_hosts+=("${host_name} - ${detail}") ;;
    network_failed) network_failed_hosts+=("${host_name} - ${detail}") ;;
  esac
}

print_summary() {
  echo "============================================================"
  echo "Access governance final summary"
  echo "Target limit: ${ANSIBLE_SSH_ACCESS_LIMIT}"
  echo "Total hosts processed: ${#hosts[@]}"
  echo "Linux success: ${#success_hosts[@]}"
  echo "Linux failed: ${#failed_hosts[@]}"
  echo "Network devices reachable: ${#network_ok_hosts[@]}"
  echo "Network devices failed: ${#network_failed_hosts[@]}"
  echo "Skipped: ${#skipped_hosts[@]}"

  if [ "${#success_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Successful Linux governance:"
    printf '  - %s\n' "${success_hosts[@]}"
  fi
  if [ "${#network_ok_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Reachable network devices:"
    printf '  - %s\n' "${network_ok_hosts[@]}"
  fi
  if [ "${#network_failed_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Network device failures:"
    printf '  - %s\n' "${network_failed_hosts[@]}"
  fi
  if [ "${#skipped_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Skipped hosts:"
    printf '  - %s\n' "${skipped_hosts[@]}"
  fi
  if [ "${#failed_hosts[@]}" -gt 0 ]; then
    echo ""
    echo "Failed Linux governance:"
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
  ensure_control_key

  mapfile -t hosts < <(inventory_hosts)
  if [ "${#hosts[@]}" -eq 0 ]; then
    echo "No hosts matched limit: ${ANSIBLE_SSH_ACCESS_LIMIT}"
    exit 0
  fi

  echo "Access governance target limit: ${ANSIBLE_SSH_ACCESS_LIMIT}"
  echo "Hosts to process: ${#hosts[@]}"
  echo ""

  success_hosts=()
  failed_hosts=()
  skipped_hosts=()
  network_ok_hosts=()
  network_failed_hosts=()

  for host_name in "${hosts[@]}"; do
    local host_ip
    local host_user
    local host_port
    local host_connection
    local host_network_os
    local password

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
      if [ "$HOMELAB_TEST_NETWORK_DEVICES" != "true" ]; then
        echo "Result: network device test skipped by HOMELAB_TEST_NETWORK_DEVICES=${HOMELAB_TEST_NETWORK_DEVICES}."
        append_summary skipped "$host_name" "network device test disabled"
        echo ""
        continue
      fi
      echo "Result: testing router command channel"
      if run_network_test "$host_name"; then
        echo "Result: network device reachable. Linux users/SSH/sudo governance is not applicable."
        append_summary network_ok "$host_name" "router command channel OK at ${host_ip}:${host_port}"
      else
        echo "Result: network device connectivity failed. Check RouterOS password/key and ansible_network_os settings." >&2
        append_summary network_failed "$host_name" "router command channel failed at ${host_ip}:${host_port}"
      fi
      echo ""
      continue
    fi

    echo "Type: Linux/server"
    echo "Result: checking SSH key access"
    echo "Attempting SSH key login..."

    if run_key_ping "$host_name"; then
      echo "Result: key access OK. Running access governance."
      if run_role_with_key "$host_name"; then
        echo "Result: ${host_name} completed successfully."
        append_summary success "$host_name" "key access OK; governance reconciled"
      else
        echo "Result: ${host_name} failed during access governance." >&2
        append_summary failed "$host_name" "role failed after key login"
      fi
      echo ""
      continue
    fi

    if [ "$ANSIBLE_SSH_ACCESS_CHECK_MODE" = "true" ]; then
      echo "Result: key access failed. Check mode will not prompt for password." >&2
      append_summary failed "$host_name" "key access failed in check mode"
      echo ""
      continue
    fi

    echo "Result: key access failed. Password bootstrap required for ${host_user}@${host_ip}."
    read -rsp "Enter SSH password for ${host_user}@${host_ip} (${host_name}): " password
    echo ""

    if run_role_with_password "$host_name" "$password"; then
      echo "Result: password bootstrap completed. Re-checking key access."
      if run_key_ping "$host_name"; then
        echo "Result: key access OK after bootstrap. ${host_name} completed successfully."
        append_summary success "$host_name" "password bootstrap succeeded; governance reconciled"
      else
        echo "Result: bootstrap ran, but key access still failed for ${host_name}." >&2
        append_summary failed "$host_name" "bootstrap ran but key login still failed"
      fi
    else
      echo "Result: password bootstrap failed for ${host_name}." >&2
      append_summary failed "$host_name" "password bootstrap failed"
    fi
    echo ""
  done

  print_summary

  if [ "${#failed_hosts[@]}" -gt 0 ] || [ "${#network_failed_hosts[@]}" -gt 0 ]; then
    exit 1
  fi

  echo "Access governance completed successfully."
}

main "$@"
