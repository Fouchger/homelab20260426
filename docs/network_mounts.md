# Network Mounts

## Purpose

This repository includes a generic Ansible role for mounting network shares on Linux VMs and LXCs.

The role replaces ad-hoc shell updates to `/etc/fstab` with an idempotent workflow that:

- installs required client packages such as `cifs-utils`;
- writes SMB credentials to a root-only credentials file;
- creates mount points;
- manages fstab entries;
- mounts each configured share;
- verifies each mount with `findmnt`;
- prints a final summary by host.

## Commands

Run access governance first so the control node has SSH key access:

```bash
task ansible:ssh-access:manage
```

Preview network mounts:

```bash
task ansible:network-mounts:check
```

Apply network mounts:

```bash
task ansible:network-mounts:manage
```

Limit to one host or group:

```bash
ANSIBLE_NETWORK_MOUNTS_LIMIT=plex01 task ansible:network-mounts:manage
```

## Required SMB credentials

Do not store the SMB password in `/etc/fstab`.

The task reads OMV CIFS settings from:

```text
state/config/.env
```

If `OMV_CIFS_USERNAME` or `OMV_CIFS_PASSWORD` is missing, the task prompts once and saves the missing values to `state/config/.env` with mode `0600`.

```bash
task ansible:network-mounts:manage
```

For non-interactive runs, export credentials first. The task will still persist missing values to `state/config/.env` for future runs.

```bash
export OMV_SERVER_IP='192.168.30.20'
export OMV_CIFS_USERNAME='omvuser'
export OMV_CIFS_PASSWORD='replace-with-real-password'
task ansible:network-mounts:manage
```

The role writes credentials on each target host to:

```text
/root/.smbcredentials/omv.conf
```

with mode `0600`.

For Plex-only mounts, use:

```bash
task plex:network-mounts:manage
```

This runs a single idempotent apply pass against the `plex` inventory group. It does not run a pre-check and then a second apply.

## Default shares

The defaults mirror the previous shell script:

```yaml
linux_network_mounts_shares:
  - name: TB5a
    server: "{{ linux_network_mounts_omv_host }}"
    share: TB5a
    path: /mnt/TB5a
  - name: TB10a
    server: "{{ linux_network_mounts_omv_host }}"
    share: TB10a
    path: /mnt/TB10a
  - name: TB10b
    server: "{{ linux_network_mounts_omv_host }}"
    share: TB10b
    path: /mnt/TB10b
  - name: TB4a
    server: "{{ linux_network_mounts_omv_host }}"
    share: TB4a
    path: /mnt/TB4a
  - name: TB16a
    server: "{{ linux_network_mounts_omv_host }}"
    share: TB16a
    path: /mnt/TB16a
```

## Custom shares

Override `linux_network_mounts_shares` in inventory, group vars, host vars, or an extra vars file.

Example:

```yaml
linux_network_mounts_shares:
  - name: media
    src: //192.168.30.20/media
    path: /mnt/media
    fstype: cifs
    opts:
      - credentials=/root/.smbcredentials/omv.conf
      - uid=1000
      - gid=1000
      - iocharset=utf8
      - vers=3.0
      - _netdev
      - nofail
      - x-systemd.automount
```

## LXC note

Some unprivileged LXCs cannot mount CIFS directly unless the Proxmox host and container features allow it.

If a container cannot mount CIFS directly, the safer pattern is:

1. mount the CIFS share on the Proxmox host;
2. bind-mount the host path into the LXC;
3. use this role only for VMs and containers that support direct mounts.
