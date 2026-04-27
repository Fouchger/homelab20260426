#!/usr/bin/env python3
"""Convert a dotenv file into shell-safe export statements.

This is used for decrypted SOPS dotenv files whose values may contain spaces,
quotes, dollar signs, backticks, or other shell-sensitive characters.
"""

from __future__ import annotations

import re
import shlex
import sys
from pathlib import Path

KEY_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: dotenv-to-shell-exports.py <source.env> <target.sh>", file=sys.stderr)
        return 2

    source_path = Path(sys.argv[1])
    target_path = Path(sys.argv[2])

    with source_path.open("r", encoding="utf-8") as source, target_path.open("w", encoding="utf-8") as target:
        target.write("# Shell-safe environment generated from decrypted SOPS dotenv.\n")
        for raw_line in source:
            line = raw_line.rstrip("\n")
            if not line or line.lstrip().startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if not KEY_PATTERN.match(key):
                continue
            target.write(f"export {key}={shlex.quote(value)}\n")

    target_path.chmod(0o600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
