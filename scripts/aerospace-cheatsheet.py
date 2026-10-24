#!/usr/bin/env python3
"""Render an AeroSpace config's key bindings as a Raycast script command.

Usage: aerospace-cheatsheet.py aerospace.toml > aerospace-keys.sh

Run at build time by home/platforms/darwin.nix, so the cheatsheet always
matches the config. Raycast shows the script's output as plain text. Bindings that differ only in a direction or workspace
number (alt-h/j/k/l, alt-1..9) are folded into one row.
"""

import sys
import tomllib

MODIFIERS = {"ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"}
KEY_NAMES = {
    "left": "←", "down": "↓", "up": "↑", "right": "→",
    "slash": "/", "comma": ",", "period": ".", "semicolon": ";",
    "minus": "−", "equal": "=", "tab": "⇥", "enter": "↩",
    "esc": "esc", "backspace": "⌫", "space": "␣",
}
DIRECTIONS = ["left", "down", "up", "right"]

# command (without its trailing direction/number) -> (section, description)
COMMANDS = {
    "focus": ("Windows", "Focus window"),
    "move": ("Windows", "Move window"),
    "resize smart": ("Windows", "Shrink / grow window"),
    "fullscreen": ("Windows", "Toggle fullscreen"),
    "layout tiles horizontal vertical": ("Layout", "Tiles (again: flip orientation)"),
    "layout accordion horizontal vertical": ("Layout", "Accordion / stack (again: flip)"),
    "workspace": ("Workspaces", "Go to workspace"),
    "summon-workspace": ("Workspaces", "Pull workspace to this monitor"),
    "move-node-to-workspace": ("Workspaces", "Send window to workspace"),
    "workspace-back-and-forth": ("Workspaces", "Previous workspace"),
    "move-workspace-to-monitor": ("Monitors", "Move workspace to monitor"),
    "move-workspace-to-monitor --wrap-around next": ("Monitors", "Move workspace to next monitor"),
    "focus-monitor": ("Monitors", "Focus monitor"),
    "mode service": ("Modes", "Enter service mode"),
    "reload-config": ("Service mode", "Reload config, back to main"),
    "flatten-workspace-tree": ("Service mode", "Reset layout"),
    "layout floating tiling": ("Service mode", "Toggle floating / tiling"),
    "close-all-windows-but-current": ("Service mode", "Close all other windows"),
    "join-with": ("Service mode", "Join with neighbour"),
}
SECTIONS = ["Windows", "Layout", "Workspaces", "Monitors", "Modes", "Service mode", "Other"]


def split_key(key):
    *mods, base = key.split("-")
    return "".join(MODIFIERS.get(m, m) for m in mods), base


def show_base(base):
    return KEY_NAMES.get(base, base.upper())


def split_command(command):
    """Return (command stem, trailing direction/number or None)."""
    if isinstance(command, list):
        command = next((c for c in command if c != "mode main"), command[0])
    stem, _, last = command.rpartition(" ")
    if stem and (last in DIRECTIONS or last.isdigit() or last.lstrip("+-").isdigit()):
        return stem, last
    return command, None


def fold_keys(bases):
    if len(bases) > 2 and all(b.isdigit() for b in bases):
        return f"{bases[0]}–{bases[-1]}"
    return " ".join(show_base(b) for b in bases)


def rows(bindings, default_section):
    groups = {}  # (mods, stem) -> [base keys], insertion-ordered
    for key, command in bindings.items():
        mods, base = split_key(key)
        stem, _ = split_command(command)
        groups.setdefault((mods, stem), []).append(base)
    for (mods, stem), bases in groups.items():
        section, label = COMMANDS.get(stem, ("Other", stem))
        if default_section and section not in ("Service mode",):
            section = default_section
        yield section, mods, fold_keys(bases), label


def render(config):
    modes = config.get("mode", {})
    by_section = {s: [] for s in SECTIONS}
    for section, mods, keys, label in rows(modes.get("main", {}).get("binding", {}), None):
        by_section[section].append((mods, keys, label))
    for section, mods, keys, label in rows(modes.get("service", {}).get("binding", {}), "Service mode"):
        by_section[section].append((mods, keys, label))

    width = max(len(f"{m} {k}") for rs in by_section.values() for m, k, _ in rs) + 3
    out = []
    for section in SECTIONS:
        if not by_section[section]:
            continue
        note = "  (enter with ⌥⇧ ; first)" if section == "Service mode" else ""
        out.append(f"{section.upper()}{note}")
        out += [f"  {(mods + ' ' + keys).strip():<{width}}{label}" for mods, keys, label in by_section[section]]
        out.append("")
    return "\n".join(out)


def raycast_script(text):
    return f"""#!/bin/bash
# Raycast script command, generated from aerospace.toml by
# scripts/aerospace-cheatsheet.py; edit those, not this file.
#
# @raycast.schemaVersion 1
# @raycast.title AeroSpace Keys
# @raycast.mode fullOutput
# @raycast.packageName AeroSpace
# @raycast.icon ⌨️
# @raycast.description Key bindings from the AeroSpace config

cat <<'CHEATSHEET'
{text}CHEATSHEET
"""


if __name__ == "__main__":
    with open(sys.argv[1], "rb") as f:
        sys.stdout.write(raycast_script(render(tomllib.load(f))))
