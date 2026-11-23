#!/usr/bin/env python3
"""Keep our side of a file when upstream only added hook code to it.

usage: hookonly.py <base> <upstream>   (run inside the merge worktree)

The floating SUSFS/NoMount patches apply to the *pristine* context, so for a
file where upstream's whole change is hook code, our pre-merge file is exactly
what the patch expects. Printing the paths lets resolve.sh restore them.
"""
import re
import subprocess
import sys

HOOK = re.compile(
    r'CONFIG_KSU_SUSFS|CONFIG_NOMOUNT|susfs|SUSFS_|ksu_handle_|ksu_is_|'
    r'nomount|bypass_orig'
)

base, up = sys.argv[1], sys.argv[2]
changed = subprocess.run(
    ['git', 'diff', '--name-only', base, up],
    capture_output=True, text=True, check=True).stdout.split()

for path in changed:
    diff = subprocess.run(
        ['git', 'diff', '-U0', base, up, '--', path],
        capture_output=True, text=True).stdout
    lines = [l for l in diff.splitlines()
             if l[:1] in '+-' and not l.startswith(('+++', '---'))]
    if lines and all(l[1:].strip() == '' or HOOK.search(l) for l in lines):
        print(path)
