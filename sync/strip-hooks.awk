# Drop in-tree SUSFS / NoMount hook blocks.
#
# The fork floats both subsystems at build time (see build-evonix.yml), so the
# tree must stay hook-free. The parent ships them in-tree; this filter removes
# every `#if ... CONFIG_KSU_SUSFS*` / `CONFIG_NOMOUNT` block and their includes.
# `#ifdef HOOK ... #else ... #endif` keeps the plain (non-hook) `#else` branch.
BEGIN { depth = 0; mode = 0 }
{
	line = $0
	# mode 1: inside the hook branch, dropping lines
	if (mode == 1) {
		if (line ~ /^[ \t]*#[ \t]*if/) {
			depth++
		} else if (line ~ /^[ \t]*#[ \t]*endif/) {
			depth--
			if (depth == 0) mode = 0
		} else if (depth == 1 && line ~ /^[ \t]*#[ \t]*(else|elif)/) {
			mode = 2
		}
		next
	}
	# mode 2: inside the plain `#else` branch, keeping lines
	if (mode == 2) {
		if (line ~ /^[ \t]*#[ \t]*if/) {
			depth++
		} else if (line ~ /^[ \t]*#[ \t]*endif/) {
			depth--
			if (depth == 0) {
				mode = 0
				next
			}
		}
		print
		next
	}
	if (line ~ /^[ \t]*#[ \t]*(if|ifdef|ifndef|elif).*(CONFIG_KSU_SUSFS|CONFIG_NOMOUNT)/) {
		depth = 1
		mode = 1
		next
	}
	if (line ~ /^[ \t]*#[ \t]*include[ \t]*[<"]linux\/(susfs|nomount)/) next
	print
}
END {
	if (mode != 0) {
		printf "%s: unterminated hook block\n", FILENAME > "/dev/stderr"
		exit 3
	}
}
