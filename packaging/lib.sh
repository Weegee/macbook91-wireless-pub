# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=bash
#
# Text helpers shared by the development and packaging scripts
# (packaging/*.sh, tools/dev-*.sh). Sourced, never run. House text HIG: results
# go to stdout, messages to stderr as "prog: error: text", hints indented,
# exit status 0 / 1 / 2 (done, failed, invalid usage).
#
# The script sets PROG (its fixed name, as in the examples of its help) and a
# function usage that prints the help, then sources this file:
#
#   PROG=fetch-upstream.sh
#   usage() { cat <<USAGE ... USAGE; }
#   . "$(dirname "$0")/lib.sh"
#   help_or_version "$@"
#
# The packaged tools (tools/macbook91-wireless-verify, tools/kernel-series)
# carry the same few functions inline: they are installed on their own and must
# not depend on a file of the repository.

: "${PROG:?lib.sh: the script must set PROG before sourcing it}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$LIB_DIR")"
# shellcheck disable=SC2034  # read by the help text of the sourcing script
HOMEPAGE=https://github.com/Weegee/macbook91-wireless-pub

# err MESSAGE [HINT...]: a failure and what helps, hints indented (FEH-1, FEH-2).
err() { printf '%s: error: %s\n' "$PROG" "$1" >&2; shift; [ $# -eq 0 ] || printf '  %s\n' "$@" >&2; }
warn() { printf '%s: warning: %s\n' "$PROG" "$1" >&2; shift; [ $# -eq 0 ] || printf '  %s\n' "$@" >&2; }
note() { printf '%s: note: %s\n' "$PROG" "$1" >&2; shift; [ $# -eq 0 ] || printf '  %s\n' "$@" >&2; }
# step MESSAGE: a finished or running step, one line (ERF-2, FOR-4).
step() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { err "$@"; exit 1; }
# usage_error MESSAGE [HINT...]: invalid usage, exit 2 (KAN-3, HIL-3).
usage_error() {
	err "$@"
	printf "Run '%s --help' for usage\n" "$PROG" >&2
	exit 2
}
# plural COUNT SINGULAR PLURAL: "1 file", "3 files" (TXT-10).
plural() { if [ "$1" = 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }
# need_value OPTION ARGC: usage error unless the option has a value; call as
# need_value "$1" "$#" before reading "$2".
need_value() { [ "$2" -ge 2 ] || usage_error "$1 needs a value"; }
# need_number NAME VALUE: usage error unless VALUE is a non-negative integer.
need_number() { [[ $2 =~ ^[0-9]+$ ]] || usage_error "$1 must be a whole number, not '$2'"; }

print_version() {
	local v
	v=$(cat "$REPO_ROOT/VERSION" 2>/dev/null) || v=unknown
	printf '%s (macbook91-wireless-dkms) %s\nLicense: GPL-3.0-or-later\n' "$PROG" "$v"
}

# help_or_version "$@": -h, --help and -V, --version win over everything else
# on the line, so they fit any call (HIL-1, HIL-2). The script's usage prints
# the help.
help_or_version() {
	local a
	for a in "$@"; do
		case $a in
		--) return 0 ;;
		-h|--help) usage; exit 0 ;;
		-V|--version) print_version; exit 0 ;;
		esac
	done
}

# on_signal INT|TERM: report the cancel once, run the EXIT trap of the script
# (it removes scratch files) and end by the signal, so the caller sees 130 or
# 143 (SIG-1, SIG-4).
on_signal() {
	trap - "$1"
	printf '\n%s: cancelled\n' "$PROG" >&2
	kill -s "$1" "$$"
}
trap_signals() { trap 'on_signal INT' INT; trap 'on_signal TERM' TERM; }
