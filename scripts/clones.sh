# Keep this machine's mutable git checkouts (home/clones.nix) in shape.
#
#   nix-config-clones sync    clone missing checkouts, run hooks, link skills
#   nix-config-clones pull    fast-forward each checkout when safe (autoupdate)
#   nix-config-clones status  show what would block a pull
#
# The manifest has one line per checkout, tab-separated, `-` for empty:
#   name  path(relative to $HOME)  url  branch  skill-dirs(:-separated)  hook
# A hook runs inside the checkout with OLD/NEW set to the revisions before
# and after (OLD empty right after cloning).

manifest=${NIX_CONFIG_CLONES:-$HOME/.config/nix-config/clones}
skill_targets=("$HOME/.claude/skills" "$HOME/.codex/skills")

log() { printf '%s clones: %s\n' "$(date '+%F %T')" "$*"; }

read_manifest() {
  [[ -f $manifest ]] || { log "no manifest at $manifest"; exit 0; }
  names=() paths=() urls=() branches=() skills=() hooks=()
  local name path url branch skill hook
  while IFS=$'\t' read -r name path url branch skill hook; do
    [[ -n $name ]] || continue
    names+=("$name") paths+=("$HOME/$path") urls+=("$url")
    branches+=("$branch") skills+=("$skill") hooks+=("$hook")
  done <"$manifest"
}

run_hook() { # index old new
  local hook=${hooks[$1]}
  [[ $hook != - ]] || return 0
  (cd "${paths[$1]}" && OLD=$2 NEW=$3 "$hook") ||
    log "${names[$1]}: hook failed"
}

# Link every skill folder (one holding SKILL.md) under the checkouts'
# skill dirs into each agent's skills dir. Never replaces anything this
# script didn't create; drops its own links whose skill went away.
link_skills() {
  local -A want=() owner=()
  local i dir d name roots=()
  for i in "${!names[@]}"; do
    [[ ${skills[$i]} != - ]] || continue
    roots+=("${paths[$i]}/")
    IFS=: read -ra dirs <<<"${skills[$i]}"
    for dir in "${dirs[@]}"; do
      for d in "${paths[$i]}/$dir"/*/; do
        [[ -f $d/SKILL.md ]] || continue
        d=${d%/} name=${d##*/}
        if [[ -n ${want[$name]:-} ]]; then
          log "skill $name in both ${owner[$name]} and ${names[$i]}; kept ${owner[$name]}"
          continue
        fi
        want[$name]=$d owner[$name]=${names[$i]}
      done
    done
  done

  local target link dest root ours
  for target in "${skill_targets[@]}"; do
    [[ -d ${target%/skills} ]] || continue # agent not set up here
    mkdir -p "$target"
    for link in "$target"/*; do
      [[ -L $link ]] || continue
      dest=$(readlink "$link") ours=0
      for root in "${roots[@]}"; do
        if [[ $dest == "$root"* ]]; then ours=1; fi
      done
      if ((ours)) && [[ ${want[${link##*/}]:-} != "$dest" ]]; then rm "$link"; fi
    done
    for name in "${!want[@]}"; do
      link=$target/$name
      if [[ -L $link && $(readlink "$link") == "${want[$name]}" ]]; then continue; fi
      if [[ -e $link || -L $link ]]; then
        log "$link exists and isn't ours; skill $name not linked"
        continue
      fi
      ln -s "${want[$name]}" "$link"
    done
  done
}

https() { local u=$1; printf '%s' "${u/#git@github.com:/https://github.com/}"; }

cmd_sync() {
  local i head
  for i in "${!names[@]}"; do
    if [[ ! -e ${paths[$i]} ]]; then
      if git clone --quiet --branch "${branches[$i]}" "${urls[$i]}" "${paths[$i]}"; then
        log "${names[$i]}: cloned into ${paths[$i]}"
        run_hook "$i" "" "$(git -C "${paths[$i]}" rev-parse HEAD)"
      else
        log "${names[$i]}: clone failed"
      fi
    elif git -C "${paths[$i]}" rev-parse --git-dir >/dev/null 2>&1; then
      head=$(git -C "${paths[$i]}" rev-parse HEAD)
      run_hook "$i" "$head" "$head"
    else
      log "${names[$i]}: ${paths[$i]} exists but isn't a git checkout"
    fi
  done
  link_skills
}

pull_one() { # index
  local name=${names[$1]} path=${paths[$1]} branch=${branches[$1]}
  [[ -d $path/.git ]] || { log "$name: not cloned, skipped"; return 0; }
  cd "$path"
  local current
  current=$(git symbolic-ref --short HEAD 2>/dev/null || echo detached)
  if [[ $current != "$branch" ]]; then log "$name: on $current, not $branch; skipped"; return 0; fi
  if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
    log "$name: uncommitted changes, skipped"; return 0
  fi
  git fetch --quiet "$(https "${urls[$1]}")" "$branch" || { log "$name: fetch failed"; return 0; }
  if [[ -n $(git rev-list FETCH_HEAD..HEAD) ]]; then
    log "$name: unpushed local commits, skipped"; return 0
  fi
  local before target
  before=$(git rev-parse HEAD) target=$(git rev-parse FETCH_HEAD)
  if [[ $before == "$target" ]]; then log "$name: up to date at ${before:0:7}"; return 0; fi
  git merge --quiet --ff-only "$target"
  git update-ref "refs/remotes/origin/$branch" "$target"
  log "$name: ${before:0:7} -> ${target:0:7}"
  run_hook "$1" "$before" "$target"
}

cmd_pull() {
  local i
  for i in "${!names[@]}"; do (pull_one "$i") || log "${names[$i]}: pull failed"; done
  link_skills
}

cmd_status() {
  local i path state ahead behind
  for i in "${!names[@]}"; do
    path=${paths[$i]}
    if [[ ! -d $path/.git ]]; then printf '%-8s not cloned (%s)\n' "${names[$i]}" "$path"; continue; fi
    state=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || echo detached)
    if git -C "$path" fetch --quiet "$(https "${urls[$i]}")" "${branches[$i]}" 2>/dev/null; then
      ahead=$(git -C "$path" rev-list --count FETCH_HEAD..HEAD)
      behind=$(git -C "$path" rev-list --count HEAD..FETCH_HEAD)
      state+=", $ahead ahead, $behind behind"
    else
      state+=", fetch failed"
    fi
    if [[ -n $(git -C "$path" status --porcelain --untracked-files=no) ]]; then state+=", uncommitted changes"; fi
    printf '%-8s %s (%s)\n' "${names[$i]}" "$state" "$path"
  done
}

read_manifest
case ${1:-status} in
  sync) cmd_sync ;;
  pull) cmd_pull ;;
  status) cmd_status ;;
  *) echo "usage: nix-config-clones [sync|pull|status]" >&2; exit 2 ;;
esac
