# Access Governance

## Purpose

This repo includes an access-governance workflow that reconciles inventory-defined Linux hosts and tests inventory-defined network devices.

The workflow is intentionally host-by-host so the operator can see the server name, address, user, connection type, and result before the next host starts.

## Main commands

```bash
task ansible:ssh-access:manage
```

Preview Linux changes without password prompts:

```bash
task ansible:ssh-access:check
```

Limit to a single host or group:

```bash
ANSIBLE_SSH_ACCESS_LIMIT=plex01 task ansible:ssh-access:manage
```

## Linux governance coverage

For Linux hosts, the workflow manages:

- control-node SSH key generation
- server `known_hosts` trust on the control node
- managed `authorized_keys` block
- stale homelab-managed key pruning
- expired key pruning from the managed block
- optional local users
- optional sudoers policy
- local audit JSON records under `state/audit/access-governance/`

Unknown unmanaged keys are reported but not removed by default. This avoids accidental lockout while still surfacing drift.

## Router coverage

Network devices such as MikroTik routers are not eligible for Linux users, sudoers, or `authorized_keys` governance. The workflow still tests RouterOS command-channel reachability and includes the result in the final summary.

If RouterOS password auth is needed, provide:

```bash
MIKROTIK_ROUTER_ADMIN_PASSWORD='replace-me' task ansible:ssh-access:manage
```

Disable router checks when needed:

```bash
HOMELAB_TEST_NETWORK_DEVICES=false task ansible:ssh-access:manage
```

## Central key registry

Add keys through inventory/group vars or extra vars using `linux_ssh_access_key_registry`:

```yaml
linux_ssh_access_key_registry:
  - key: "ssh-ed25519 AAAAC3... gert-laptop"
    comment: "gert-laptop"
    expires: "2026-12-31"
  - key: "ssh-ed25519 AAAAC3... temporary-admin"
    comment: "temporary-admin"
    expires: "2026-05-31"
```

Expired keys are automatically omitted from the managed block and are therefore removed on the next run.

## Optional user and sudo governance

```yaml
linux_access_governance_users:
  - name: admin
    state: present
    groups:
      - sudo
    append: true
    shell: /bin/bash
    sudo: true
    sudo_nopassword: false
```

Use this carefully. The safe default is to avoid creating extra users unless explicitly configured.
