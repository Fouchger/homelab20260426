#!/usr/bin/env bash
# ==============================================================================
# File: scripts/lib/proxmox-helper-lxc-create.sh
# Purpose:
#   Reusable runner for Proxmox community helper LXC scripts over SSH.
# Notes:
#   - Prompts once and persists service-specific values in state/config/.env.
#   - Empty values are valid and are persisted as KEY=.
#   - Per-server values are scoped by service and index so future services can
#     reuse this flow without colliding with Plex settings.
# ==============================================================================

set -euo pipefail

service_name="${1:-}"
script_path="${2:-}"

if [ -z "$service_name" ] || [ -z "$script_path" ]; then
  echo "Usage: $0 <service-name> <helper-script-path>" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR:-$(pwd)}"
CONFIG_ENV_FILE="${CONFIG_ENV_FILE:-${ROOT_DIR}/state/config/.env}"
TMP_DIR="${TMP_DIR:-${ROOT_DIR}/state/tmp}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/homelab_ed25519}"
SSH_AUTHORIZED_KEY_FILE="${SSH_AUTHORIZED_KEY_FILE:-}"
SSH_KNOWN_HOSTS_FILE="${SSH_KNOWN_HOSTS_FILE:-${HOME}/.ssh/known_hosts}"
ANSIBLE_INVENTORY_FILE="${ANSIBLE_INVENTORY_FILE:-${ROOT_DIR}/state/ansible/inventory.yml}"

mkdir -p "$(dirname "$CONFIG_ENV_FILE")" "$TMP_DIR" "$(dirname "$ANSIBLE_INVENTORY_FILE")"
touch "$CONFIG_ENV_FILE"
chmod 600 "$CONFIG_ENV_FILE"
chmod 700 "$TMP_DIR" "$(dirname "$ANSIBLE_INVENTORY_FILE")"

service_upper="$(printf '%s' "$service_name" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')"
count_key="PROXMOX_SCRIPT_${service_upper}_COUNT"

# Ordered list of variables expected by the helper scripts. var_pw is included
# for helper scripts that require a root password prompt.
helper_vars="var_unprivileged var_cpu var_ram var_disk var_brg var_net var_gateway var_mtu var_vlan var_mac var_ns var_ipv6_method var_ssh var_ssh_authorized_key var_apt_cacher var_fuse var_tun var_gpu var_nesting var_keyctl var_mknod var_mount_fs var_protection var_timezone var_tags var_verbose var_ctid var_hostname var_primary_nic var_searchdomain var_template_storage var_container_storage var_pw"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  }
}

get_env_value() {
  env_key="$1"
  awk -F= -v key="$env_key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$CONFIG_ENV_FILE"
}

env_key_exists() {
  env_key="$1"
  grep -Eq "^${env_key}=" "$CONFIG_ENV_FILE"
}

upsert_env_value() {
  env_key="$1"
  env_value="$2"
  temp_file="$(mktemp "${TMP_DIR}/proxmox-helper-env.XXXXXX")"
  awk -F= -v key="$env_key" '$1 != key' "$CONFIG_ENV_FILE" > "$temp_file"
  printf '%s=%s\n' "$env_key" "$env_value" >> "$temp_file"
  mv "$temp_file" "$CONFIG_ENV_FILE"
  chmod 600 "$CONFIG_ENV_FILE"
}

prompt_if_missing() {
  env_key="$1"
  prompt_text="$2"
  default_value="$3"
  secret_value="${4:-no}"

  if env_key_exists "$env_key"; then
    get_env_value "$env_key"
    return 0
  fi

  if [ "${NONINTERACTIVE:-0}" = "1" ]; then
    value="$default_value"
  else
    if [ "$secret_value" = "yes" ]; then
      printf '%s [%s]: ' "$prompt_text" "$default_value" > /dev/tty
      IFS= read -r -s value < /dev/tty
      printf '\n' > /dev/tty
    else
      printf '%s [%s]: ' "$prompt_text" "$default_value" > /dev/tty
      IFS= read -r value < /dev/tty
    fi
    value="${value:-$default_value}"
  fi

  upsert_env_value "$env_key" "$value"
  printf '%s' "$value"
}

var_key() {
  server_index="$1"
  helper_var="$2"
  helper_key="$(printf '%s' "$helper_var" | tr '[:lower:]' '[:upper:]')"
  printf 'PROXMOX_SCRIPT_%s_%s_%s' "$service_upper" "$server_index" "$helper_key"
}

ip_increment() {
  cidr_value="$1"
  offset="$2"
  ip_part="${cidr_value%/*}"
  cidr_part="${cidr_value#*/}"
  IFS=. read -r octet1 octet2 octet3 octet4 <<IP_PARTS
$ip_part
IP_PARTS
  next_octet4=$((octet4 + offset))
  if [ "$next_octet4" -gt 254 ]; then
    echo "ERROR: IP auto-increment exceeded host range for ${cidr_value}." >&2
    exit 1
  fi
  printf '%s.%s.%s.%s/%s' "$octet1" "$octet2" "$octet3" "$next_octet4" "$cidr_part"
}

mac_increment() {
  mac_value="$1"
  offset="$2"
  prefix="${mac_value%:*}"
  last_hex="${mac_value##*:}"
  next_decimal=$((16#$last_hex + offset))
  if [ "$next_decimal" -gt 255 ]; then
    echo "ERROR: MAC auto-increment exceeded final octet range for ${mac_value}." >&2
    exit 1
  fi
  printf '%s:%02X' "$prefix" "$next_decimal"
}

hostname_increment() {
  host_value="$1"
  offset="$2"
  prefix="${host_value%[0-9][0-9]}"
  suffix="${host_value##*[!0-9]}"
  if [ -z "$prefix" ] || [ -z "$suffix" ]; then
    printf '%s-%02d' "$host_value" $((offset + 1))
  else
    width="${#suffix}"
    next_number=$((10#$suffix + offset))
    printf "%s%0${width}d" "$prefix" "$next_number"
  fi
}

default_for_var() {
  helper_var="$1"
  offset="$2"
  case "$helper_var" in
    var_unprivileged) printf '0' ;;
    var_cpu) printf '4' ;;
    var_ram) printf '4096' ;;
    var_disk) printf '50' ;;
    var_brg) printf 'vmbr0' ;;
    var_net) ip_increment '192.168.30.25/24' "$offset" ;;
    var_gateway) printf '192.168.30.1' ;;
    var_mtu) printf '' ;;
    var_vlan) printf '30' ;;
    var_mac) mac_increment '64:16:7F:52:5A:3E' "$offset" ;;
    var_ns) printf '' ;;
    var_ipv6_method) printf 'auto' ;;
    var_ssh) printf 'yes' ;;
    var_ssh_authorized_key) ssh_authorized_key_default ;;
    var_apt_cacher) printf 'no' ;;
    var_fuse) printf 'no' ;;
    var_tun) printf 'no' ;;
    var_gpu) printf 'yes' ;;
    var_nesting) printf '1' ;;
    var_keyctl) printf '0' ;;
    var_mknod) printf '0' ;;
    var_mount_fs) printf '' ;;
    var_protection) printf 'no' ;;
    var_timezone) printf 'Pacific/Auckland' ;;
    var_tags) printf 'media' ;;
    var_verbose) printf 'no' ;;
    var_ctid) printf '%s' $((21010 + offset)) ;;
    var_hostname) hostname_increment 'plex01' "$offset" ;;
    var_primary_nic) printf 'net0' ;;
    var_searchdomain) printf '' ;;
    var_template_storage) printf 'local' ;;
    var_container_storage) printf 'local-lvm' ;;
    var_pw) printf '' ;;
    *) printf '' ;;
  esac
}

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\''/g"
  printf "'"
}

cidr_to_ip() {
  printf '%s' "${1%/*}"
}

append_inventory_block() {
  inventory_temp="$(mktemp "${TMP_DIR}/inventory.XXXXXX")"
  {
    printf '%s\n' '---'
    printf '%s\n' '# =============================================================================='
    printf '%s\n' '# File: state/ansible/inventory.yml'
    printf '%s\n' '# Purpose:'
    printf '%s\n' '#   Generated Ansible inventory for homelab automation.'
    printf '%s\n' '# Notes:'
    printf '%s\n' '#   Generated by scripts/lib/proxmox-helper-lxc-create.sh.'
    printf '%s\n' '#   Do not edit by hand; update state/config/.env and rerun the task.'
    printf '%s\n' '#   Secrets are intentionally not stored in this file.'
    printf '%s\n' '# =============================================================================='
    printf '%s\n' 'all:'
    printf '%s\n' '  children:'
    printf '%s\n' '    proxmox_helper_lxc:'
    printf '%s\n' '      hosts:'

    index=1
    while [ "$index" -le "$server_count" ]; do
      hostname_value="$(get_env_value "$(var_key "$index" var_hostname)")"
      net_value="$(get_env_value "$(var_key "$index" var_net)")"
      ctid_value="$(get_env_value "$(var_key "$index" var_ctid)")"
      tags_value="$(get_env_value "$(var_key "$index" var_tags)")"
      service_value="$service_name"
      ansible_host_value="$(cidr_to_ip "$net_value")"
      printf '        %s:\n' "$hostname_value"
      printf '          ansible_host: "%s"\n' "$ansible_host_value"
      printf '          ansible_user: root\n'
      printf '          ansible_ssh_private_key_file: "%s"\n' "$SSH_KEY_PATH"
      printf '          homelab_service: "%s"\n' "$service_value"
      printf '          proxmox_ctid: %s\n' "$ctid_value"
      printf '          proxmox_tags: "%s"\n' "$tags_value"
      index=$((index + 1))
    done
  } > "$inventory_temp"
  mv "$inventory_temp" "$ANSIBLE_INVENTORY_FILE"
  chmod 600 "$ANSIBLE_INVENTORY_FILE"
}

run_remote_helper() {
  server_index="$1"
  remote_script="/tmp/homelab-${service_name}-${server_index}-$(basename "$script_path")"
  env_args=""

  for helper_var in $helper_vars; do
    value="$(get_env_value "$(var_key "$server_index" "$helper_var")")"
    env_args="${env_args} ${helper_var}=$(shell_quote "$value")"
  done

  scp \
    -i "$SSH_KEY_PATH" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$SSH_KNOWN_HOSTS_FILE" \
    -o ConnectTimeout="$ssh_connect_timeout" \
    -P "$proxmox_ssh_port" \
    "$script_path" \
    "${proxmox_ssh_user}@${proxmox_ssh_host}:${remote_script}"

  ssh -tt \
    -i "$SSH_KEY_PATH" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$SSH_KNOWN_HOSTS_FILE" \
    -o ConnectTimeout="$ssh_connect_timeout" \
    -p "$proxmox_ssh_port" \
    "${proxmox_ssh_user}@${proxmox_ssh_host}" \
    "chmod 700 $(shell_quote "$remote_script") && env TERM=xterm${env_args} bash $(shell_quote "$remote_script")"
}

require_command awk
require_command grep
require_command sed
require_command ssh
require_command scp
require_command mktemp

ssh_authorized_key_default() {
  if [ -n "$SSH_AUTHORIZED_KEY_FILE" ] && [ -f "$SSH_AUTHORIZED_KEY_FILE" ]; then
    awk 'NF { print; exit }' "$SSH_AUTHORIZED_KEY_FILE"
    return 0
  fi

  if [ -f "${SSH_KEY_PATH}.pub" ]; then
    awk 'NF { print; exit }' "${SSH_KEY_PATH}.pub"
    return 0
  fi

  for public_key_file in /root/.ssh/*.pub "${HOME}"/.ssh/*.pub; do
    if [ -f "$public_key_file" ]; then
      awk 'NF { print; exit }' "$public_key_file"
      return 0
    fi
  done

  printf ''
}

[ -f "$script_path" ] || { echo "ERROR: Helper script not found: $script_path" >&2; exit 1; }
[ -f "$SSH_KEY_PATH" ] || { echo "ERROR: SSH private key not found: $SSH_KEY_PATH. Run: task ssh:bootstrap" >&2; exit 1; }

proxmox_ssh_host="${PROXMOX_SSH_HOST:-$(get_env_value PROXMOX_SSH_HOST)}"
proxmox_ssh_port="${PROXMOX_SSH_PORT:-$(get_env_value PROXMOX_SSH_PORT)}"
proxmox_ssh_user="${PROXMOX_SSH_USER:-$(get_env_value PROXMOX_SSH_USER)}"
ssh_connect_timeout="${SSH_CONNECT_TIMEOUT:-$(get_env_value SSH_CONNECT_TIMEOUT)}"

proxmox_ssh_host="$(prompt_if_missing PROXMOX_SSH_HOST 'Proxmox SSH host or IP address' "$proxmox_ssh_host")"
proxmox_ssh_port="$(prompt_if_missing PROXMOX_SSH_PORT 'Proxmox SSH port' "${proxmox_ssh_port:-22}")"
proxmox_ssh_user="$(prompt_if_missing PROXMOX_SSH_USER 'Proxmox SSH user' "${proxmox_ssh_user:-root}")"
ssh_connect_timeout="$(prompt_if_missing SSH_CONNECT_TIMEOUT 'SSH connect timeout seconds' "${ssh_connect_timeout:-5}")"

[ -n "$proxmox_ssh_host" ] || { echo 'ERROR: PROXMOX_SSH_HOST is required.' >&2; exit 1; }

server_count="$(prompt_if_missing "$count_key" "Number of ${service_name} servers to create" '1')"
case "$server_count" in
  ''|*[!0-9]*) echo "ERROR: ${count_key} must be a positive integer." >&2; exit 1 ;;
esac
[ "$server_count" -ge 1 ] || { echo "ERROR: ${count_key} must be at least 1." >&2; exit 1; }

index=1
while [ "$index" -le "$server_count" ]; do
  offset=$((index - 1))
  echo
  echo "${service_name} server ${index} of ${server_count}"
  echo "================================"
  for helper_var in $helper_vars; do
    default_value="$(default_for_var "$helper_var" "$offset")"
    key="$(var_key "$index" "$helper_var")"
    prompt_name="${service_name} ${index} ${helper_var}"
    if [ "$helper_var" = "var_pw" ]; then
      prompt_if_missing "$key" "$prompt_name" "$default_value" yes >/dev/null
    else
      prompt_if_missing "$key" "$prompt_name" "$default_value" no >/dev/null
    fi
  done
  index=$((index + 1))
done

append_inventory_block

index=1
while [ "$index" -le "$server_count" ]; do
  hostname_value="$(get_env_value "$(var_key "$index" var_hostname)")"
  ctid_value="$(get_env_value "$(var_key "$index" var_ctid)")"
  net_value="$(get_env_value "$(var_key "$index" var_net)")"
  mac_value="$(get_env_value "$(var_key "$index" var_mac)")"
  echo
  echo "Creating ${service_name} LXC ${index}/${server_count}: ${hostname_value} / CTID ${ctid_value} / ${net_value} / ${mac_value}"
  run_remote_helper "$index"
  index=$((index + 1))
done

echo
echo "Generated inventory: ${ANSIBLE_INVENTORY_FILE}"
echo "Persisted defaults:  ${CONFIG_ENV_FILE}"
