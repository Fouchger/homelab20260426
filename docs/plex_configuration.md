# Plex Configuration

## Purpose

This repository includes an Ansible role for configuring Plex Media Server after the LXC or VM has been created and network media mounts have been applied.

The role manages these phases in order:

1. preflight validation;
2. Plex service baseline and local API readiness;
3. local server preferences in `Preferences.xml`;
4. Plex server claim when the server is not already claimed;
5. library creation through the local Plex API;
6. conservative multi-server configuration sync when more than one Plex host exists;
7. Plex.tv account-level Sync My Watch State and Ratings after the servers are configured and running.

This ordering avoids the bootstrap issue where account-level settings were requested before the Plex server existed and was reachable.

## Commands

Render inventory first so the generated `plex` group exists:

```bash
task ansible:inventory:render
```

Mount media shares first:

```bash
task plex:network-mounts:manage
```

Preview Plex configuration:

```bash
task plex:configure:check
```

Apply Plex configuration:

```bash
task plex:configure:manage
```

Limit to one Plex host:

```bash
ANSIBLE_PLEX_LIMIT=plex01 task plex:configure:manage
```

## Plex claim token

Local server baseline and preferences run before the role asks for any Plex token. If the server is not already claimed, the role stops at the claim phase and asks for a short-lived claim token.

Generate the claim token here:

```text
https://www.plex.tv/claim
```

Then re-run the same task quickly because Plex claim tokens are short-lived:

```bash
PLEX_CLAIM_TOKEN='claim-replace-with-real-token' task plex:configure:manage
```

The claim token is not stored by the role. After a successful claim, the role reads the local Plex server token from `Preferences.xml` and uses that for local API-managed library setup.

## Plex token and watch-state sync

Server claim and library setup run before the role asks for `PLEX_TOKEN`.

`PLEX_TOKEN` is required to complete the standard account-level setup:

```text
PUT https://plex.tv/api/v2/user/view_state_sync?consent=true
```

The token must belong to the Plex account that owns the server estate.

Run with an exported token:

```bash
export PLEX_TOKEN='replace-with-real-token'
task plex:configure:manage
```

Or set it from Ansible Vault:

```yaml
plex_server_config_token: 'replace-with-real-token'
```

When no token is supplied, the role still completes local server setup first, then stops at the final account watch-state phase with a clear message. Re-running with the token is safe and idempotent.

Set this only if you intentionally want local server setup without failing at the final account phase:

```yaml
plex_server_config_account_watch_state_sync_required: false
```

## Inventory grouping

The inventory renderer creates a service group for each Proxmox helper service. Plex hosts generated from `.env` values such as `PROXMOX_SCRIPT_PLEX_1_VAR_HOSTNAME=plex01` are placed in both:

```text
proxmox_helper_lxc
plex
```

The `plex` inventory group drives the playbook target and the multi-server sync decision. The first host in the generated `plex` group is the primary by default.

## Local Plex preferences

Server preferences are written directly to:

```text
/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml
```

The default friendly name is the Ansible inventory hostname. Override per host or group when required:

```yaml
plex_server_config_friendly_name: plex01
```

Common override example:

```yaml
plex_server_config_preferences:
  FriendlyName: plex01
  secureConnections: preferred
  ManualPortMappingMode: '1'
  ManualPortMappingPort: '32400'
  FSEventLibraryUpdatesEnabled: '1'
  ScheduledLibraryUpdatesEnabled: '1'
  ScheduledLibraryUpdateInterval: daily
  autoEmptyTrash: '0'
  DlnaEnabled: '0'
```

## Default libraries

The role defines default libraries for the current OMV mount layout:

- `Movies`
- `TV Shows`
- `Music`

The default locations are under:

```text
/mnt/TB5a
/mnt/TB10a
/mnt/TB10b
/mnt/TB4a
/mnt/TB16a
```

Missing paths are ignored by default. Set this only when you want Ansible to create the media folders:

```yaml
plex_server_config_create_missing_library_paths: true
```

Library creation uses the local Plex API. The role can use either `PLEX_TOKEN` or the local server token created by the claim phase. If the server is unclaimed, provide `PLEX_CLAIM_TOKEN` first, then re-run.

## Multi-server sync

Plex does not provide a supported multi-server configuration replication feature. When the generated `plex` group contains more than one host, this role configures a conservative primary-to-secondary `rsync` timer on secondary servers.

By default:

- the first host in the `plex` inventory group is the primary;
- secondaries pull configuration daily at 03:30;
- server-unique identity, tokens, preferences, cache, logs, codecs, diagnostics, updates, and library databases are excluded.

This sync is not Plex native watch-state sync. Watch-state and ratings sync is handled separately through the Plex.tv account API.

Override the primary when needed:

```yaml
plex_server_config_sync_primary: plex01
```

Disable configuration sync:

```yaml
plex_server_config_sync_enabled: false
```

## Idempotency

The role is safe to run repeatedly:

- service and systemd unit tasks converge on the same state;
- preferences are only rewritten when values change;
- library creation checks existing Plex sections before creating new ones;
- account watch-state sync sends the same consent state each run;
- sync timers are overwritten consistently.

If Plex settings are changed manually in the UI, the next Ansible run may return managed settings to the configured values.
