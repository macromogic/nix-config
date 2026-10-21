#!/usr/bin/env python3
"""Advance flake inputs with a minimum release age.

For each named input, pick the newest upstream commit that is at least
--min-age-days old and newer than the locked one, but only if it adds no new
local compilation: every package a homeConfiguration needs must still come
from a binary cache. Uncached candidates are skipped in favour of the next
older one. Pins are written with `nix flake lock --override-input`, which
keeps each input's original URL in flake.lock.
"""

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.request

STORE_PREFIX = re.compile(r"^/nix/store/[a-z0-9]{32}-")
VERSION_SUFFIX = re.compile(r"-[0-9][^-]*(-[0-9a-z][^-]*)*$")


def run(*cmd, check=True):
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def github(path):
    req = urllib.request.Request("https://api.github.com" + path)
    req.add_header("Accept", "application/vnd.github+json")
    if os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def configs():
    out = run("nix", "eval", "--json", ".#homeConfigurations",
              "--apply", "builtins.attrNames").stdout
    return json.loads(out)


def local_only(drvs):
    """Derivations marked to always build locally (generated files etc.)."""
    if not drvs:
        return set()
    shown = json.loads(run("nix", "derivation", "show", *drvs).stdout)
    shown = shown.get("derivations", shown)
    trivial = set()
    for path, drv in shown.items():
        attrs = {**drv.get("env", {}), **(drv.get("structuredAttrs") or {})}
        if attrs.get("preferLocalBuild") in (True, "1") or \
                attrs.get("allowSubstitutes") in (False, ""):
            trivial.add(path.rsplit("/", 1)[-1])
    return trivial


def builds(cfgs):
    """Names (without hash/version) of what each config would compile."""
    names = set()
    for cfg in cfgs:
        res = run("nix", "build", "--dry-run",
                  f'.#homeConfigurations."{cfg}".activationPackage', check=False)
        if res.returncode != 0:
            raise RuntimeError(f"{cfg}: evaluation failed\n{res.stderr[-2000:]}")
        drvs, listing = [], False
        for line in res.stderr.splitlines():
            if "will be built" in line:
                listing = True
            elif "will be fetched" in line:
                listing = False
            elif listing and line.strip().endswith(".drv"):
                drvs.append(line.strip())
        trivial = local_only(drvs)
        for drv in drvs:
            base = drv.rsplit("/", 1)[-1]
            if base in trivial or not base.endswith(".drv"):
                continue
            name = STORE_PREFIX.sub("", drv)[: -len(".drv")]
            names.add(f"{cfg}: {VERSION_SUFFIX.sub('', name)}")
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--min-age-days", type=int, default=7)
    ap.add_argument("--max-candidates", type=int, default=30)
    ap.add_argument("--summary", help="append one line per update to this file")
    args = ap.parse_args()

    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.min_age_days)
    cfgs = configs()
    baseline = builds(cfgs)
    updated = []

    for name in args.inputs:
        with open("flake.lock") as f:
            nodes = json.load(f)["nodes"]
        # Node names can differ from input names (e.g. root's nixpkgs is
        # "nixpkgs_2" when another input brings its own nixpkgs).
        ref = nodes["root"]["inputs"].get(name)
        if not isinstance(ref, str):
            print(f"{name}: not a direct input of this flake, skipped")
            continue
        orig, locked = nodes[ref]["original"], nodes[ref]["locked"]
        if orig.get("type") != "github" or "rev" in orig:
            print(f"{name}: not a floating github input, skipped")
            continue
        query = f"?per_page={args.max_candidates}&until={cutoff:%Y-%m-%dT%H:%M:%SZ}"
        if orig.get("ref"):
            query += f"&sha={orig['ref']}"
        commits = github(f"/repos/{orig['owner']}/{orig['repo']}/commits{query}")

        for commit in commits:
            sha = commit["sha"]
            when = dt.datetime.fromisoformat(
                commit["commit"]["committer"]["date"].replace("Z", "+00:00"))
            if sha == locked["rev"] or when.timestamp() <= locked["lastModified"]:
                print(f"{name}: newest eligible commit is not newer than the lock")
                break
            with open("flake.lock") as f:
                saved = f.read()
            run("nix", "flake", "lock", "--override-input", name,
                f"github:{orig['owner']}/{orig['repo']}/{sha}")
            try:
                new = builds(cfgs)
            except RuntimeError as err:
                new, extra = None, [str(err).splitlines()[0]]
            else:
                extra = ["would compile " + n for n in sorted(new - baseline)]
            if new is not None and not extra:
                baseline = new
                line = f"{name}: {locked['rev'][:12]} -> {sha[:12]} ({when:%Y-%m-%d})"
                print(line)
                updated.append(line)
                break
            with open("flake.lock", "w") as f:
                f.write(saved)
            print(f"{name}: skip {sha[:12]} ({when:%Y-%m-%d}): " + "; ".join(extra[:5]))
        else:
            print(f"{name}: no cached candidate among the last {len(commits)} eligible commits")

    if args.summary and updated:
        with open(args.summary, "a") as f:
            f.write("\n".join(updated) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
