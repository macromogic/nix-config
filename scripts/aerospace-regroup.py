#!/usr/bin/env python3
"""Re-apply AeroSpace's on-window-detected rules to every open window.

Usage: aerospace-regroup.py [--dry-run] [aerospace.toml]

AeroSpace only runs those rules when a window opens, so windows that were
open before a rule existed, or that were moved by hand, stay where they are.
This puts them back. Installed by home/platforms/darwin.nix as
~/.config/aerospace/regroup and bound to g in AeroSpace's service mode.

Only the rule features the config uses are understood: if.app-id, if.workspace,
if.app-name-regex-substring, if.window-title-regex-substring,
check-further-callbacks, and the 'layout ...' and
'move-node-to-workspace ...' commands. A rule with any other condition never
matches here.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tomllib

DEFAULT_CONFIG = os.path.expanduser("~/.config/aerospace/aerospace.toml")
# AeroSpace runs exec-and-forget with launchd's PATH, which lacks Homebrew.
AEROSPACE = shutil.which("aerospace") or "/opt/homebrew/bin/aerospace"


def aerospace(*args, dry_run=False):
    if dry_run:
        print("aerospace", *args)
        return ""
    result = subprocess.run([AEROSPACE, *args], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"aerospace {' '.join(args)}: {result.stderr.strip()}", file=sys.stderr)
    return result.stdout


def matches(condition, window):
    for key, value in condition.items():
        if key == "app-id":
            ok = window["app-bundle-id"] == value
        elif key == "app-name-regex-substring":
            ok = re.search(value, window["app-name"], re.IGNORECASE)
        elif key == "window-title-regex-substring":
            ok = re.search(value, window["window-title"], re.IGNORECASE)
        elif key == "workspace":
            # AeroSpace checks the workspace a new window opens on; for an
            # open window, the one it is on now is the closest match.
            ok = window["workspace"] == value
        else:
            ok = False
        if not ok:
            return False
    return True


def apply(command, window_id, dry_run):
    verb, _, arg = command.partition(" ")
    if verb == "layout":
        aerospace("layout", "--window-id", window_id, *arg.split(), dry_run=dry_run)
    elif verb == "move-node-to-workspace":
        aerospace("move-node-to-workspace", "--window-id", window_id, arg, dry_run=dry_run)
    else:
        print(f"skipping unsupported command: {command}", file=sys.stderr)


def main(argv):
    dry_run = "--dry-run" in argv
    paths = [a for a in argv if a != "--dry-run"]
    with open(paths[0] if paths else DEFAULT_CONFIG, "rb") as f:
        rules = tomllib.load(f).get("on-window-detected", [])

    fmt = "%{window-id} %{app-bundle-id} %{app-name} %{window-title} %{workspace}"
    windows = json.loads(aerospace("list-windows", "--all", "--json", "--format", fmt))
    for window in windows:
        window_id = str(window["window-id"])
        for rule in rules:
            if not matches(rule.get("if", {}), window):
                continue
            run = rule.get("run", [])
            for command in [run] if isinstance(run, str) else run:
                apply(command, window_id, dry_run)
            if not rule.get("check-further-callbacks", False):
                break


if __name__ == "__main__":
    main(sys.argv[1:])
