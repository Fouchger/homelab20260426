#!/usr/bin/env python3
"""
File: ansible/roles/linux_ssh_access/files/render-managed-keys.py
Purpose:
  Normalise central SSH key registry entries and render the active managed
  authorized_keys block for the access-governance role.
Notes:
  - Expired or absent keys are omitted so the managed block prunes them.
  - Input is JSON written by Ansible; output is JSON consumed by Ansible.
"""

from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any


def parse_date(value: str) -> dt.date | None:
    if not value:
        return None
    try:
        return dt.date.fromisoformat(value[:10])
    except ValueError:
        return None


def normalise_entry(entry: Any, source: str) -> dict[str, str]:
    if isinstance(entry, str):
        return {"key": entry.strip(), "comment": "", "expires": "", "state": "present", "source": source}
    if isinstance(entry, dict):
        return {
            "key": str(entry.get("key", "")).strip(),
            "comment": str(entry.get("comment", "")).strip(),
            "expires": str(entry.get("expires", "")).strip(),
            "state": str(entry.get("state", "present")).strip() or "present",
            "source": str(entry.get("source", source)).strip() or source,
        }
    return {"key": "", "comment": "", "expires": "", "state": "absent", "source": source}


def render_line(entry: dict[str, str]) -> str:
    key = entry["key"].strip()
    comments: list[str] = []
    if entry.get("comment"):
        comments.append(entry["comment"])
    if entry.get("expires"):
        comments.append(f"homelab:expires={entry['expires']}")
    if entry.get("source"):
        comments.append(f"homelab:source={entry['source']}")
    if comments:
        return f"{key} {' '.join(comments)}".strip()
    return key


def main() -> int:
    payload_path = Path(sys.argv[1])
    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    today = parse_date(payload.get("today", "")) or dt.date.today()

    entries: list[dict[str, str]] = []
    control_key = str(payload.get("control_public_key", "")).strip()
    if control_key:
        entries.append({
            "key": control_key,
            "comment": str(payload.get("control_key_comment", "homelab-control")).strip(),
            "expires": "",
            "state": "present",
            "source": "control-node",
        })

    for item in payload.get("key_registry", []):
        entries.append(normalise_entry(item, "registry"))
    for item in payload.get("extra_public_keys", []):
        entries.append(normalise_entry(item, "extra"))

    active_lines: list[str] = []
    active_keys: list[str] = []
    expired: list[dict[str, str]] = []
    absent: list[dict[str, str]] = []
    seen: set[str] = set()

    for entry in entries:
        key = entry.get("key", "").strip()
        if not key:
            continue
        if entry.get("state", "present").lower() == "absent":
            absent.append(entry)
            continue
        expiry = parse_date(entry.get("expires", ""))
        if expiry is not None and expiry < today:
            expired.append(entry)
            continue
        key_identity = " ".join(key.split()[:2])
        if key_identity in seen:
            continue
        seen.add(key_identity)
        active_keys.append(key_identity)
        active_lines.append(render_line(entry))

    print(json.dumps({
        "block": "\n".join(active_lines),
        "active_key_identities": active_keys,
        "active_count": len(active_lines),
        "expired": expired,
        "absent": absent,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
