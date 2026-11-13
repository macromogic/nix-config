
## This machine
- My Mac. Repositories live in ~/dev; ~/Documents/dev is a symlink to it,
  kept for old paths. ~/Documents is synced by iCloud, which flags
  dot-folders as hidden, and Python >= 3.13 skips hidden .pth files, so
  editable installs in venvs there break. Keep repositories and venvs out of
  ~/Documents. If an editable install in ~/dev says "No module named ...",
  check for a leftover flag with `ls -lO` and clear it with
  `chflags -R nohidden <dir>`.
- To add tasks to my TickTick inbox, use the `ticktick-add-task` skill.
