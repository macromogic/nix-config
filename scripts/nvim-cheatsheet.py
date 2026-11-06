#!/usr/bin/env python3
"""Format the Neovim key mappings dumped by nvim-cheatsheet.lua as a cheatsheet.

Usage: nvim-cheatsheet.py base.json ["Section title=extra.json" ...]

base.json is the dump from a plain directory. Each extra dump comes from a
directory that turns on project-specific keys (a CMakeLists.txt, a
Cargo.toml); the keys it adds over base.json get their own section.

Run by the Raycast script command built in home/platforms/darwin.nix, at the
moment Raycast runs it, so the cheatsheet follows ~/.config/nvim without a
rebuild. Bindings that differ only in a direction (]d [d, <C-h> ... <C-l>)
are folded into one row, the way aerospace-cheatsheet.py does.
"""

import json
import re
import sys

LEADER = "<Space>"
MODES = {"n": "n", "x": "v", "o": "o", "i": "i", "t": "t"}

# second key after the leader -> section, following LazyVim's which-key groups
LEADER_GROUPS = {
    "<Tab>": "Tabs", "b": "Buffers", "c": "Code", "d": "Debug", "f": "Files / find",
    "g": "Git", "o": "Tasks", "q": "Quit / session", "s": "Search", "t": "Test",
    "u": "UI toggles", "w": "Windows", "x": "Diagnostics / quickfix",
}
SECTIONS = ["Leader", *LEADER_GROUPS.values(), "Goto (g)", "Jump ([ ])", "Ctrl / Alt", "Insert mode", "Other"]

# Nvim's own defaults (":help ...", "vim.lsp.buf...") and per-key plumbing
# that only adds noise to a cheatsheet.
SKIP_DESC = re.compile(
    r"^(:|vim\.|\+|which_key_ignore$|MiniPairs |(Open|Close|Closeopen) action for |(Up|Down)$)"
)

# words that make two bindings one row: "Prev Diagnostic" / "Next Diagnostic".
# Only words of the same kind fold together, so "First Tab" stays apart from
# "Next Tab"; folded keys follow the order listed here (h j k l for "side").
DIRECTION_KINDS = {
    "step": ["Prev", "Previous", "Next"],
    "end": ["First", "Last"],
    "side": ["Left", "Lower", "Down", "Upper", "Up", "Right", "Above", "Below"],
    "size": ["Decrease", "Increase"],
    "scroll": ["Backward", "Forward"],
}
DIRECTION_KIND = {w.lower(): kind for kind, words in DIRECTION_KINDS.items() for w in words}
DIRECTION_ORDER = [w.lower() for words in DIRECTION_KINDS.values() for w in words]
DIRECTION_RE = re.compile(r"\b(" + "|".join(DIRECTION_KIND) + r")\b", re.IGNORECASE)
MAX_LABEL = 60


def show_key(lhs):
    """'<Space>ff' -> '␣ff', '<C-H>' -> '<C-h>'."""
    lhs = lhs.replace("<Space>", "␣")
    return re.sub(r"<([CM])-([A-Z])>", lambda m: f"<{m[1]}-{m[2].lower()}>", lhs)


def split_key(lhs):
    """Split a key into (stem, varying part): ']d' -> ('_d', ']'), '<C-H>' -> ('<C-_>', 'H')."""
    if re.fullmatch(r"[\[\]]+", lhs):
        return "_" * len(lhs), lhs
    if lhs[0] in "[]":
        return "_" + lhs[1:], lhs[0]
    if m := re.fullmatch(r"(.*<[A-Z]-)(\w+)>", lhs):
        return m[1] + "_>", m[2]
    return lhs[:-1] + "_", lhs[-1]


def join_keys(lhs_list):
    """['[d', ']d'] -> '[d ]d'; ['<C-H>', '<C-L>'] -> '<C-h/l>'."""
    stem, _ = split_key(lhs_list[0])
    if lhs_list[0][0] in "[]":
        return " ".join(show_key(k) for k in lhs_list)
    parts = [split_key(k)[1] for k in lhs_list]
    if stem.endswith("_>"):
        parts = [p.lower() if len(p) == 1 else p for p in parts]
    return show_key(stem.replace("_", "/".join(parts)))


def section_of(lhs, modes):
    if lhs.startswith(LEADER):
        rest = lhs[len(LEADER):]
        for prefix, section in LEADER_GROUPS.items():
            if rest.startswith(prefix) and len(rest) > len(prefix):
                return section
        return "Leader"
    if modes == {"i"}:
        return "Insert mode"
    if lhs[0] in "[]":
        return "Jump ([ ])"
    if lhs.startswith("g") and len(lhs) > 1:
        return "Goto (g)"
    if lhs.startswith(("<C-", "<M-")):
        return "Ctrl / Alt"
    return "Other"


def entries(dump):
    """Merge one dump into {(lhs, label): set of modes}, in dump order."""
    merged = {}
    for m in dump:
        if SKIP_DESC.search(m["desc"]):
            continue
        label = m["desc"] + (f" ({m['server']})" if m.get("server") else "")
        merged.setdefault((m["lhs"], label), set()).add(m["mode"])
    return merged


def fold(items):
    """Fold rows whose keys differ in one part and labels in a direction word."""
    groups = {}  # (key stem, label stem, modes) -> [(lhs, label)]
    for lhs, label, modes in items:
        label_stem = DIRECTION_RE.sub(lambda m: "…" + DIRECTION_KIND[m[1].lower()], label)
        key_stem = split_key(lhs)[0] if label_stem != label else lhs
        groups.setdefault((key_stem, label_stem, frozenset(modes)), []).append((lhs, label))

    for (_, label_stem, modes), rows in groups.items():
        if len(rows) == 1:
            lhs, label = rows[0]
            yield lhs, show_key(lhs), label, modes
            continue
        rows.sort(key=lambda r: DIRECTION_ORDER.index(DIRECTION_RE.search(r[1])[1].lower()))
        words = [DIRECTION_RE.search(label)[1] for _, label in rows]
        yield rows[0][0], join_keys([lhs for lhs, _ in rows]), DIRECTION_RE.sub(" / ".join(words), rows[0][1], 1), modes


def render_rows(merged):
    items = [(lhs, label, modes) for (lhs, label), modes in merged.items()]
    by_section = {s: [] for s in SECTIONS}
    for lhs, keys, label, modes in fold(items):
        by_section[section_of(lhs, modes)].append((keys, label, modes))
    return by_section


def format_sections(sections, width):
    out = []
    for title, rows in sections:
        if not rows:
            continue
        out.append(re.sub(r"^[^(]*", lambda m: m[0].upper(), title))
        for keys, label, modes in sorted(rows, key=lambda r: (r[0].lower(), r[0].swapcase())):
            tag = "" if modes == {"n"} else "  [" + " ".join(MODES[m] for m in "nxoit" if m in modes) + "]"
            if len(label) > MAX_LABEL:
                label = label[: MAX_LABEL - 1] + "…"
            out.append(f"  {keys:<{width}}{label}{tag}")
        out.append("")
    return out


def render(base, extras):
    merged = entries(base)
    sections = list(render_rows(merged).items())
    for title, dump in extras:
        added = {k: v for k, v in entries(dump).items() if k not in merged}
        rows = [r for rs in render_rows(added).values() for r in rs]
        sections.append((title, rows))

    width = max(len(keys) for _, rows in sections for keys, _, _ in rows) + 3
    header = ["␣ = leader (Space).  Modes other than normal in [ ]: v visual, o operator, i insert, t terminal.", ""]
    return "\n".join(header + format_sections(sections, width))


if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        base = json.load(f)
    extras = []
    for arg in sys.argv[2:]:
        title, _, path = arg.partition("=")
        with open(path) as f:
            extras.append((title, json.load(f)))
    print(render(base, extras))
