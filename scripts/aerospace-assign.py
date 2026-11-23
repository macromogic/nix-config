#!/usr/bin/env python3
"""Ask where windows of an app with no AeroSpace rule should go, and remember.

Usage: aerospace-assign.py [--no-prompt | --focused] [aerospace.toml]

The last on-window-detected rule in the config runs this for every window no
other rule matched; AeroSpace passes the window in AEROSPACE_WINDOW_ID.
Installed by home/platforms/darwin.nix as ~/.config/aerospace/assign.

The first window of an app brings up a list of the workspaces described in the
config's "#   <n>  role" comment block, plus Float and Leave here. The choice
is saved per app (bundle ID, or name if it has none) in
$XDG_STATE_HOME/aerospace/assignments.json (default ~/.local/state) and applied
to that app's later windows without asking. Cancel saves nothing, but stops
the asking until the app quits; its next launch asks again. To be asked again, delete the app's entry from that file;
to make a choice part of the config, add a rule for the app, which then wins.

After the dialog, focus returns to the window asked about, or, if it moved to
another workspace, to the window that had focus before the dialog.

--focused asks about the focused window's app even if it already has a saved
choice, saves the answer and applies it to all of the app's open windows;
service mode a runs it. --no-prompt, or AEROSPACE_ASSIGN_NO_PROMPT=1, applies
saved choices only; the regroup script uses it.
"""

import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib

DEFAULT_CONFIG = os.path.expanduser("~/.config/aerospace/aerospace.toml")
STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "aerospace"
)
STATE = os.path.join(STATE_DIR, "assignments.json")
# AeroSpace runs exec-and-forget with launchd's PATH, which lacks Homebrew.
AEROSPACE = shutil.which("aerospace") or "/opt/homebrew/bin/aerospace"
# Same shape as scripts/aerospace-cheatsheet.py reads.
WORKSPACE_LINE = re.compile(r"^#   (\d+)  (\S.*?)(?:\s{2,}(\S.*))?$")
SNOOZED = os.path.join(STATE_DIR, "snoozed.json")
FORMAT = "%{window-id} %{app-bundle-id} %{app-name} %{app-pid}"
FLOAT = "Float here"
STAY = "Leave here"

ASK = """
on run argv
    set appName to item 1 of argv
    set defaultChoice to item 2 of argv
    set choices to items 3 thru -1 of argv
    tell application "System Events"
        activate
        set picked to choose from list choices with title "AeroSpace" with prompt "Where should windows of " & appName & " go?" default items {defaultChoice}
    end tell
    if picked is false then return ""
    return item 1 of picked
end run
"""

TELL = """
on run argv
    tell application "System Events"
        activate
        display alert "AeroSpace" message (item 1 of argv)
    end tell
end run
"""


def aerospace(*args):
    result = subprocess.run([AEROSPACE, *args], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"aerospace {' '.join(args)}: {result.stderr.strip()}", file=sys.stderr)
    return result.stdout


def list_windows(*selector):
    return json.loads(aerospace("list-windows", *selector, "--json", "--format", FORMAT) or "[]")


def find_window(window_id):
    return next((w for w in list_windows("--all") if str(w["window-id"]) == window_id), None)


def app_windows(window):
    """IDs of the open windows of the same app."""
    if window["app-bundle-id"]:
        return [str(w["window-id"]) for w in list_windows("--monitor", "all", "--app-bundle-id", window["app-bundle-id"])]
    return [str(w["window-id"]) for w in list_windows("--all") if w["app-name"] == window["app-name"]]


def has_rule(config, window):
    """Whether a rule in the config names this app, so it never reaches us."""
    with open(config, "rb") as f:
        rules = tomllib.load(f).get("on-window-detected", [])
    for rule in rules:
        cond = rule.get("if", {})
        if not isinstance(cond, dict):
            continue
        if window["app-bundle-id"] and cond.get("app-id") == window["app-bundle-id"]:
            return True
        pattern = cond.get("app-name-regex-substring")
        if pattern and re.search(pattern, window["app-name"], re.IGNORECASE):
            return True
    return False


def ask(app_name, config, current=None):
    choices = [*workspaces(config), FLOAT, STAY]
    labels = {"float": FLOAT, "stay": STAY} | {c.split()[0]: c for c in choices}
    default = labels.get(current, choices[0])
    result = subprocess.run(
        ["osascript", "-", app_name, default, *choices], input=ASK, capture_output=True, text=True
    )
    picked = result.stdout.strip()
    if picked == FLOAT:
        return "float"
    if picked == STAY:
        return "stay"
    return picked.split()[0] if picked else None


def tell(message):
    subprocess.run(["osascript", "-", message], input=TELL, capture_output=True, text=True)


def workspaces(config):
    with open(config) as f:
        found = [WORKSPACE_LINE.match(line.rstrip("\n")) for line in f]
    return [f"{m[1]}  {m[2]}" for m in found if m]


def apply(action, window_id):
    if action == "float":
        aerospace("layout", "--window-id", window_id, "floating")
    elif action.isdigit():
        aerospace("move-node-to-workspace", "--window-id", window_id, action)


def load(path=STATE):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(state, path=STATE):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def main(argv):
    flags = {a for a in argv if a.startswith("--")}
    paths = [a for a in argv if not a.startswith("--")]
    config = paths[0] if paths else DEFAULT_CONFIG
    focused = "--focused" in flags
    no_prompt = "--no-prompt" in flags or os.environ.get("AEROSPACE_ASSIGN_NO_PROMPT") == "1"

    if focused:
        windows = list_windows("--focused")
        window = windows[0] if windows else None
    else:
        window_id = os.environ.get("AEROSPACE_WINDOW_ID")
        if not window_id:
            sys.exit("aerospace-assign: AEROSPACE_WINDOW_ID is not set")
        window = find_window(window_id)
    if window is None:
        return
    window_id = str(window["window-id"])
    key = window["app-bundle-id"] or window["app-name"]

    # The dialog activates System Events, which has no window, so when it
    # closes macOS hands focus to a window of its choosing and the accordion
    # shows that one. Remember what had focus to put it back.
    before = list_windows("--focused")
    before_id = str(before[0]["window-id"]) if before else None

    if focused and has_rule(config, window):
        tell(f"{window['app-name']} has a rule in aerospace.toml, which decides where it goes. "
             "Change it there.")
        return

    os.makedirs(STATE_DIR, exist_ok=True)
    # One dialog at a time: an app that opens several windows at once is asked
    # once, and the windows waiting here then find its saved choice.
    with open(os.path.join(STATE_DIR, "assignments.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load()
        saved = state.get(key, {}).get("action")
        if saved and not focused:
            apply(saved, window_id)
            return
        if no_prompt:
            return
        # Cancel snoozes the app until it quits: the snooze holds the PID it
        # had, and a relaunched app has a new one.
        snoozed = load(SNOOZED)
        pid = window["app-pid"]
        if not focused and snoozed.get(key) == pid:
            return
        action = ask(window["app-name"], config, saved)
        if action is None:
            if not focused:
                live = {str(w["app-pid"]) for w in list_windows("--all")}
                snoozed = {k: p for k, p in snoozed.items() if str(p) in live}
                snoozed[key] = pid
                save(snoozed, SNOOZED)
            refocus(None, window_id, before_id)
            return
        state[key] = {"app": window["app-name"], "action": action}
        save(state)
    for target in app_windows(window) if focused else [window_id]:
        apply(action, target)
    refocus(action, window_id, before_id)


def refocus(action, window_id, before_id):
    """Give focus back after the dialog: to the window asked about if it
    stays on this workspace, otherwise to what had focus before it opened."""
    if action is None or not action.isdigit():
        target = window_id
    elif before_id and before_id != window_id:
        target = before_id
    else:
        # The new window had focus itself. After the move AeroSpace already
        # treats another window of this workspace as focused; make macOS agree.
        now = list_windows("--focused")
        if not now or str(now[0]["window-id"]) == window_id:
            return
        target = str(now[0]["window-id"])
    aerospace("focus", "--window-id", target)


if __name__ == "__main__":
    main(sys.argv[1:])
