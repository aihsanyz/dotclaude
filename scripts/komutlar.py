#!/usr/bin/env python3
"""Print the `## Komutlar` section of a project's AGENTS.md as shell-safe KEY=value lines.

Usage: komutlar.py <AGENTS.md>   ->   HAS_KOMUTLAR=1 and K_SERVICE=..., K_MIGRATE=..., ...
Format in AGENTS.md:  - key: `value`
Keys: service, migrate, postdeploy, lint, test, seed, migrations.
"""
import re
import shlex
import sys

KEYS = ("service", "migrate", "postdeploy", "lint", "test", "seed", "migrations")


def parse(path):
    found, inside, out = False, False, {}
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return False, {}
    for line in lines:
        if re.match(r"^##\s+Komutlar\s*$", line):
            found = inside = True
            continue
        if inside and re.match(r"^#{1,2}\s", line):
            break
        m = re.match(r"^\s*[-*]\s*(%s)\s*:\s*`(.+)`\s*$" % "|".join(KEYS), line) if inside else None
        if m:
            out[m.group(1)] = m.group(2)
    return found, out


if __name__ == "__main__":
    found, cmds = parse(sys.argv[1] if len(sys.argv) > 1 else "AGENTS.md")
    print(f"HAS_KOMUTLAR={1 if found else 0}")
    for k in KEYS:
        print(f"K_{k.upper()}={shlex.quote(cmds.get(k, ''))}")
