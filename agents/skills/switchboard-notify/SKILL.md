---
name: switchboard-notify
description: Send the user a notification on Discord with the `switchboard-notify` command. Use when the user asks to be notified, pinged or told when something finishes, or when a scheduled or long-running task should report its result.
---

# Notify the user on Discord

`switchboard-notify` posts to the user's Discord through their Switchboard
server. It works from any shell on any of their machines.

```sh
switchboard-notify -t <topic> [-l info|success|warning|error] [-T "<title>"] "<message>"
some-command 2>&1 | tail -20 | switchboard-notify -t <topic> -l error -T "<title>"
switchboard-notify -L    # list the channels and forum posts you can send to
```

## Where the message goes

- **If the user said where, send exactly there.** A channel name goes to
  `-c <channel>`; a topic name, a post id or a Discord post link
  (`https://discord.com/channels/...`) goes to `-t` as given. Don't rename,
  "fix" or replace it. If it is rejected, report the error instead of
  picking somewhere else.
- **If they named it loosely** ("the eval post", "weekly brief"), run
  `switchboard-notify -L` and use the matching channel or post. Ask if
  nothing matches clearly.
- **Otherwise use a topic** (`-t`): each topic is its own Discord forum post,
  opened on first use. Pick a short, stable name for the job in lowercase
  words joined by `-` (e.g. `paper-build`, `nightly-eval`), check `-L` for an
  existing one that fits, and reuse it every time that job reports so its
  history stays in one post. Don't invent a new topic per message.

## What to send

- **Level** (`-l`): `success` or `error` for a finished job, `warning` for
  something that needs a look, `info` otherwise.
- **Message**: Markdown, ideally under ~1500 characters (longer is cut
  off). Say what happened and what, if anything, the user should do; include
  the machine or path when it matters. Never include secrets.
- Send one message when there is a result, not a stream of progress updates.

Exit status 3 means Switchboard isn't configured on this machine
(`SWITCHBOARD_URL` / `SWITCHBOARD_TOKEN` missing): tell the user instead of
retrying. Any other failure prints Switchboard's error; report it rather than
working around it.
