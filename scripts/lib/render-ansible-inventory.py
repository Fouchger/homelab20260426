#!/usr/bin/env python3
"""
File: scripts/lib/render-ansible-inventory.py
Purpose:
  Render state/ansible/inventory.yml from state/config/.env without executing
  shell code from the env file.
Notes:
  - The .env file is the source of truth for generated inventory entries.
  - Existing inventory content is replaced only by the complete rendered view from
    .env, so services already persisted in .env are retained.
  - Secrets are intentionally excluded from the inventory output.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        values[key] = value.strip()
    return values


def yaml_quote(value: object) -> str:
    text = "" if value is None else str(value)
    escaped = text.replace('"', '\\"')
    return f'"{escaped}"'


def cidr_to_ip(value: str) -> str:
    return value.split("/", 1)[0]


def normalise_key(value: str) -> str:
    key = re.sub(r"[^A-Za-z0-9]+", "_", value.upper()).strip("_")
    return key


def get_first(values: dict[str, str], keys: list[str], default: str = "") -> str:
    for key in keys:
        value = values.get(key, "")
        if value != "":
            return value
    return default


def append_mikrotik(lines: list[str], values: dict[str, str], ssh_key_path: str) -> None:
    default_name = values.get("MIKROTIK_NAME", "hap-ax2") or "hap-ax2"
    raw_routers = values.get("MIKROTIK_ROUTERS", default_name) or default_name
    routers = [item.strip() for item in raw_routers.split(",") if item.strip()]
    default_host = values.get("MIKROTIK_HOST", "")

    router_rows: list[tuple[str, dict[str, str]]] = []
    for router in routers:
        router_key = normalise_key(router)
        host = values.get(f"MIKROTIK_{router_key}_HOST", default_host)
        if host == "":
            continue
        router_rows.append(
            (
                router,
                {
                    "ansible_host": host,
                    "ansible_user": values.get(f"MIKROTIK_{router_key}_USER", values.get("MIKROTIK_USER", "admin") or "admin"),
                    "ansible_port": values.get(f"MIKROTIK_{router_key}_PORT", values.get("MIKROTIK_PORT", "22") or "22"),
                    "ansible_ssh_private_key_file": ssh_key_path,
                    "ansible_connection": "ansible.netcommon.network_cli",
                    "ansible_network_os": "community.routeros.routeros",
                    "ansible_command_timeout": values.get(
                        f"MIKROTIK_{router_key}_COMMAND_TIMEOUT",
                        values.get("MIKROTIK_COMMAND_TIMEOUT", "120") or "120",
                    ),
                },
            )
        )

    if not router_rows:
        return

    lines.extend([
        "    mikrotik:",
        "      hosts:",
    ])
    for router, router_values in router_rows:
        lines.append(f"        {router}:")
        lines.append(f"          ansible_host: {yaml_quote(router_values['ansible_host'])}")
        lines.append(f"          ansible_user: {yaml_quote(router_values['ansible_user'])}")
        lines.append(f"          ansible_port: {router_values['ansible_port']}")
        lines.append(f"          ansible_ssh_private_key_file: {yaml_quote(router_values['ansible_ssh_private_key_file'])}")
        lines.append(f"          ansible_connection: {yaml_quote(router_values['ansible_connection'])}")
        lines.append(f"          ansible_network_os: {yaml_quote(router_values['ansible_network_os'])}")
        lines.append(f"          ansible_command_timeout: {router_values['ansible_command_timeout']}")


def discover_services(values: dict[str, str]) -> list[str]:
    services: set[str] = set()
    for key in values:
        match = re.match(r"^PROXMOX_SCRIPT_([A-Z0-9_]+)_COUNT$", key)
        if match:
            services.add(match.group(1))
            continue
        match = re.match(r"^PROXMOX_SCRIPT_([A-Z0-9_]+)_([0-9]+)_VAR_HOSTNAME$", key)
        if match:
            services.add(match.group(1))
    return sorted(services)


def service_count(values: dict[str, str], service: str) -> int:
    count_value = values.get(f"PROXMOX_SCRIPT_{service}_COUNT", "")
    if count_value.isdigit():
        return int(count_value)

    indexes = []
    prefix = f"PROXMOX_SCRIPT_{service}_"
    for key in values:
        if not key.startswith(prefix):
            continue
        remainder = key[len(prefix):]
        index = remainder.split("_", 1)[0]
        if index.isdigit():
            indexes.append(int(index))
    return max(indexes, default=0)


def append_proxmox_helper_lxc(lines: list[str], values: dict[str, str], ssh_key_path: str) -> None:
    rows: list[tuple[str, dict[str, str]]] = []
    for service in discover_services(values):
        for index in range(1, service_count(values, service) + 1):
            prefix = f"PROXMOX_SCRIPT_{service}_{index}_"
            hostname = values.get(f"{prefix}VAR_HOSTNAME", "")
            network = values.get(f"{prefix}VAR_NET", "")
            if hostname == "" or network == "":
                continue
            rows.append(
                (
                    hostname,
                    {
                        "ansible_host": cidr_to_ip(network),
                        "ansible_user": "root",
                        "ansible_ssh_private_key_file": ssh_key_path,
                        "homelab_service": service.lower(),
                        "proxmox_ctid": values.get(f"{prefix}VAR_CTID", ""),
                        "proxmox_tags": values.get(f"{prefix}VAR_TAGS", ""),
                    },
                )
            )

    if not rows:
        return

    lines.extend([
        "    proxmox_helper_lxc:",
        "      hosts:",
    ])
    for hostname, host_values in rows:
        lines.append(f"        {hostname}:")
        lines.append(f"          ansible_host: {yaml_quote(host_values['ansible_host'])}")
        lines.append(f"          ansible_user: {yaml_quote(host_values['ansible_user'])}")
        lines.append(f"          ansible_ssh_private_key_file: {yaml_quote(host_values['ansible_ssh_private_key_file'])}")
        lines.append(f"          homelab_service: {yaml_quote(host_values['homelab_service'])}")
        if host_values["proxmox_ctid"] != "":
            lines.append(f"          proxmox_ctid: {host_values['proxmox_ctid']}")
        if host_values["proxmox_tags"] != "":
            lines.append(f"          proxmox_tags: {yaml_quote(host_values['proxmox_tags'])}")


def render_inventory(values: dict[str, str], ssh_key_path: str) -> str:
    lines = [
        "---",
        "# ==============================================================================" ,
        "# File: state/ansible/inventory.yml",
        "# Purpose:",
        "#   Generated Ansible inventory for homelab automation.",
        "# Notes:",
        "#   Generated by scripts/lib/render-ansible-inventory.py.",
        "#   Do not edit by hand; update state/config/.env and rerun inventory render.",
        "#   Secrets are intentionally not stored in this file.",
        "# ==============================================================================" ,
        "all:",
        "  children:",
    ]

    initial_length = len(lines)
    append_mikrotik(lines, values, ssh_key_path)
    append_proxmox_helper_lxc(lines, values, ssh_key_path)

    if len(lines) == initial_length:
        lines.extend([
            "    ungrouped:",
            "      hosts: {}",
        ])

    return "\n".join(lines) + "\n"


def main() -> int:
    root_dir = Path(os.environ.get("ROOT_DIR", Path.cwd())).resolve()
    state_dir = Path(os.environ.get("STATE_DIR", root_dir / "state")).resolve()
    env_file = Path(os.environ.get("CONFIG_ENV_FILE", state_dir / "config" / ".env")).resolve()
    inventory_file = Path(os.environ.get("ANSIBLE_INVENTORY_FILE", state_dir / "ansible" / "inventory.yml")).resolve()
    ssh_key_path = os.environ.get("SSH_KEY_PATH", str(Path.home() / ".ssh" / "homelab_ed25519"))

    values = read_env_file(env_file)
    inventory_file.parent.mkdir(parents=True, exist_ok=True)
    temp_file = inventory_file.with_suffix(".yml.tmp")
    temp_file.write_text(render_inventory(values, ssh_key_path), encoding="utf-8")
    temp_file.replace(inventory_file)
    inventory_file.chmod(0o600)
    print(f"Generated {inventory_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
