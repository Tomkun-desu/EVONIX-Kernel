# Drop in-tree SUSFS / NoMount hook blocks.
#
# The fork floats both subsystems at build time (see build-evonix.yml), so the
# tree must stay hook-free. The parent ships them in-tree; this filter removes
# every `#if ... CONFIG_KSU_SUSFS*` / `CONFIG_NOMOUNT` block and its includes.
# A block that also carries a non-hook `#else` branch aborts the filter instead
# of silently deleting live code.
BEGIN { depth = 0 }
{
	line = $0
	if (depth > 0) {
		if (line ~ /^[ \t]*#[ \t]*if/) {
			depth++
		} else if (line ~ /^[ \t]*#[ \t]*endif/) {
			depth--
		} else if (line ~ /^[ \t]*#[ \t]*(else|elif)/) {
			printf "%s:%d: hook block has an %s branch, refusing to strip\n", FILENAME, FNR, line > "/dev/stderr"
			exit 2
		}
		next
	}
	if (line ~ /^[ \t]*#[ \t]*(if|ifdef|ifndef|elif).*(CONFIG_KSU_SUSFS|CONFIG_NOMOUNT)/) {
		depth = 1
		next
	}
	if (line ~ /^[ \t]*#[ \t]*include[ \t]*[<"]linux\/(susfs|nomount)/) next
	print
}
