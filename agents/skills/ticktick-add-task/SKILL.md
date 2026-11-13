---
name: ticktick-add-task
description: Add tasks to the user's TickTick inbox on this Mac, e.g. follow-ups or to-dos from a session. Use when the user asks to put something into TickTick, their inbox, or their to-do list.
---

# Add tasks to TickTick

The TickTick app on this Mac handles `ticktick://` URLs. There is no API
token: this route can add tasks but cannot read, edit or delete them.

## Writing the tasks

- Title: short and actionable, prefixed with the project, in the user's
  language (usually Chinese), e.g. `ytcc：用蓝牙耳机录一段测试`.
- Content: what to do and how to tell it is done; commands and commit IDs
  as plain text. Newlines are fine.
- One task per action the user has to take. Don't add tasks for work an
  agent can finish itself.

## Sending

TickTick brings itself to the front while it adds a task, even with
`open -g`, and AeroSpace follows it to its workspace. Remember the focused
window and return to it afterwards:

```bash
python3 - <<'PY'
import subprocess, time, urllib.parse

tasks = [
    ("项目：标题", "要做什么，怎样算完成"),
]
prev = subprocess.run(
    ["aerospace", "list-windows", "--focused", "--format", "%{window-id}"],
    capture_output=True, text=True,
).stdout.strip()
for title, content in tasks:
    query = urllib.parse.urlencode({"title": title, "content": content}, quote_via=urllib.parse.quote)
    subprocess.run(["open", "-g", "ticktick://x-callback-url/v1/add_task?" + query], check=True)
    time.sleep(1)
time.sleep(1)
if prev:
    subprocess.run(["aerospace", "focus", "--window-id", prev])
PY
```

`open` succeeding only means TickTick received the URL. The first time in a
session, send one task and ask the user to confirm it arrived before sending
the rest. Tell the user which tasks were sent.
