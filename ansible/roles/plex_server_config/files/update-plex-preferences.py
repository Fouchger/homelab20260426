#!/usr/bin/env python3
"""
File: ansible/roles/plex_server_config/files/update-plex-preferences.py
Purpose:
  Update Plex Media Server Preferences.xml attributes idempotently.
Notes:
  - Values are supplied as a JSON object.
  - Empty or null values remove the attribute.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
from pathlib import Path


def load_tree(path: Path) -> ElementTree.ElementTree:
    if path.exists() and path.stat().st_size > 0:
        return ElementTree.parse(path)
    root = ElementTree.Element("Preferences")
    return ElementTree.ElementTree(root)


def normalise(value: object) -> str | None:
    if value is None:
        return None
    text = str(value)
    if text == "":
        return None
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description="Update Plex Preferences.xml attributes.")
    parser.add_argument("--file", required=True, help="Full path to Preferences.xml")
    parser.add_argument("--json", required=True, help="JSON object of preference attributes")
    parser.add_argument("--backup", action="store_true", help="Create a .bak copy before changing")
    args = parser.parse_args()

    path = Path(args.file)
    preferences = json.loads(args.json)
    if not isinstance(preferences, dict):
        print("Preferences JSON must be an object.", file=sys.stderr)
        return 2

    path.parent.mkdir(parents=True, exist_ok=True)
    tree = load_tree(path)
    root = tree.getroot()
    if root.tag != "Preferences":
        print(f"Unexpected XML root {root.tag!r}; expected 'Preferences'.", file=sys.stderr)
        return 3

    changed = False
    for key in sorted(preferences):
        desired_value = normalise(preferences[key])
        current_value = root.attrib.get(key)
        if desired_value is None:
            if key in root.attrib:
                del root.attrib[key]
                changed = True
            continue
        if current_value != desired_value:
            root.attrib[key] = desired_value
            changed = True

    if not changed:
        print("changed=false")
        return 0

    if args.backup and path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))

    with tempfile.NamedTemporaryFile("wb", delete=False, dir=str(path.parent)) as temp_file:
        tree.write(temp_file, encoding="utf-8", xml_declaration=True)
        temp_name = temp_file.name
    Path(temp_name).replace(path)
    print("changed=true")
    return 0


if __name__ == "__main__":
    sys.exit(main())
