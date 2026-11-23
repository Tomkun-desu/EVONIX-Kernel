#!/usr/bin/env bash
# Post-merge carve-out repair for the parent-fork sync.
#
# This fork keeps SUSFS, NoMount, Baseband-Guard and NTSync out of the tree and
# applies them at build time (the dispatch steps in build-evonix.yml). The
# parent ships all four in-tree, so a plain merge re-adds their sources,
# Kconfig/Makefile wiring, hook blocks and config symbols. This script removes
# exactly those and swaps in our curated config fragment; every other upstream
# change is left intact.
#
# usage: sync/resolve.sh <hyperos|coloros>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel)"
flavor="${1:?usage: sync/resolve.sh <hyperos|coloros>}"

# Files upstream only added hook code to: our hook-free side is the answer.
for f in $(git diff --name-only --diff-filter=U); do
	case "$f" in
	arch/arm64/configs/evonix.config | fs/susfs.c | include/linux/susfs.h | include/linux/susfs_def.h) ;;
	*)
		git checkout --ours -- "$f"
		git add -- "$f"
		echo "kept ours: $f"
		;;
	esac
done

# 1. Floated sources. The modify/delete conflicts leave the parent's copy behind.
git rm -q -f --ignore-unmatch fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h
rm -rf fs/nomount security/baseband-guard
rm -f drivers/misc/ntsync.c include/uapi/linux/ntsync.h

# 2. Floated Kconfig/Makefile wiring (the build-time patches add it back).
sed -i -E \
	-e '\#^obj-\$\(CONFIG_(KSU_SUSFS|NOMOUNT|BBG|NTSYNC)\)#d' \
	-e '\#^source "(fs/nomount|security/baseband-guard)/Kconfig"$#d' \
	fs/Makefile fs/Kconfig security/Makefile security/Kconfig drivers/misc/Makefile
python3 - drivers/misc/Kconfig <<'PY'
import sys

path = sys.argv[1]
kept, skipping = [], False
for line in open(path):
    if line.startswith('config NTSYNC'):
        skipping = True
        continue
    if skipping:
        if not line.strip():
            skipping = False
        continue
    kept.append(line)
open(path, 'w').write(''.join(kept))
PY

# 3. Hook blocks inside files upstream changed for real as well.
git diff --cached --name-only --diff-filter=ACMR |
	grep -E '(\.(c|h|S|cc)$|/Makefile$|Kconfig$)' |
	while read -r f; do
		awk -f "$here/strip-hooks.awk" "$f" >"$f.tmp"
		if cmp -s "$f" "$f.tmp"; then rm -f "$f.tmp"; else mv "$f.tmp" "$f"; fi
	done

# 4. Our config fragment: upstream V4.6 symbols, floated subsystems off,
#    Wild-port extras kept.
cp "$here/conf/evonix.$flavor.config" arch/arm64/configs/evonix.config
git add -A

# 5. Everything that must be gone really is gone.
test -z "$(git diff --name-only --diff-filter=U)" || { echo "unmerged paths remain" >&2; exit 1; }
leftover="$(git grep --cached -lE 'susfs_is_|susfs_spoof|susfs_fake_qstr|susfs_switch_to_ksu' -- '*.c' '*.h' || true)"
test -z "$leftover" || { echo "SUSFS hook code survived:" >&2; echo "$leftover" >&2; exit 1; }
leftover="$(git grep --cached -lE 'CONFIG_(KSU_SUSFS|NOMOUNT|BBG|NTSYNC|USER_NS)=' -- arch/arm64/configs/evonix.config || true)"
test -z "$leftover" || { echo "floated config symbols survived in evonix.config" >&2; exit 1; }
git grep --cached -q '^config NTSYNC$' -- '*Kconfig' && { echo "NTSYNC Kconfig block survived" >&2; exit 1; }
git grep --cached -q 'CONFIG_EVONIX_SCHEDUTIL=y' -- arch/arm64/configs/evonix.config || { echo "V4.6 config symbols missing" >&2; exit 1; }
bash -n build-evonix.sh
echo "carve-outs verified"
