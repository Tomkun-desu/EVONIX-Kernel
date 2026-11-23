# Drop in-tree SUSFS / NoMount hook blocks.
#
# The fork floats both subsystems at build time (see build-evonix.yml), so the
# tree must stay hook-free: the floating SUSFS patch has to apply to the exact
# pristine context. This filter removes every `#if ... CONFIG_KSU_SUSFS*` /
# `CONFIG_NOMOUNT` block plus its includes, keeps the plain `#else` branch of an
# `#ifdef HOOK ... #else ... #endif`, and collapses the blank line a removed
# block leaves behind (a double blank breaks the patch context).
BEGIN { depth = 0; mode = 0; last_blank = 0; suppress = 0 }

function emit(line) {
	if (suppress) {
		suppress = 0
		if (line ~ /^[ \t]*$/) return
	}
	last_blank = (line ~ /^[ \t]*$/)
	print line
}

{
	line = $0
	# mode 1: inside the hook branch, dropping lines
	if (mode == 1) {
		if (line ~ /^[ \t]*#[ \t]*if/) {
			depth++
		} else if (line ~ /^[ \t]*#[ \t]*endif/) {
			depth--
			if (depth == 0) {
				mode = 0
				if (last_blank) suppress = 1
			}
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
		emit(line)
		next
	}
	if (line ~ /^[ \t]*#[ \t]*(if|ifdef|ifndef|elif).*(CONFIG_KSU_SUSFS|CONFIG_NOMOUNT)/) {
		depth = 1
		mode = 1
		next
	}
	if (line ~ /^[ \t]*#[ \t]*include[ \t]*[<"]linux\/(susfs|nomount)/) next
	emit(line)
}
END {
	if (mode != 0) {
		printf "%s: unterminated hook block\n", FILENAME > "/dev/stderr"
		exit 3
	}
}
