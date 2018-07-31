[ -z "$_u_common_loaded" ] || return 0
_u_common_loaded=1

_u_modules_loaded=""
_u_set_loaded() {
	expr match "$_u_modules_loaded" ".*${1:?}" > /dev/null || _u_modules_loaded="${_u_modules_loaded} ${1}"
}

### cleanup functions

u_cleanup () {
	# Calls module specific cleanup methods
	local usg="Usage: u_cleanup"
	local module
	for module in $_u_modules_loaded; do
		if type "u_cleanup_${module}" > /dev/null 2>&1; then
			"u_cleanup_${module}"
		fi
	done
}

u_set_autoclean () {
	# Calls u_cleanup at the end of the script or on error
	local usg="Usage: u_set_autoclean"
	trap 'u_cleanup' EXIT
}

### logging

# Default loglevels
readonly U_LOG_ERROR=40
readonly U_LOG_WARN=30
readonly U_LOG_INFO=20
readonly U_LOG_DEBUG=10

# defaults to warn
_u_loglevel=$U_LOG_WARN
_u_log_sub=0

_u_has_tput=
type tput > /dev/null 2>&1 && _u_has_tput=1

# main logging methods
u_set_loglevel () {
	# Sets logging level
	local usg="Usage: u_set_loglevel {loglevel}"
	# make sure the level is set and is an integer
	if ! [ "${1:?$usg}" -eq "$1" ] 2> /dev/null; then
		echo "Invalid loglevel '$1' specified!" >&2
		return 1
	fi
	_u_loglevel=$1
}

u_log_sub() {
	# Marks subsequent log messages as being from a sub log
	_u_log_sub=$((_u_log_sub + 1))
}

u_log_unsub() {
	# Marks subsequent log messages as being back on the current level
	[ $_u_log_sub -gt 0 ] || return 0
	_u_log_sub=$((_u_log_sub - 1))
}

u_log () {
	# Logs a message with the specified loglevel
	local usg="Usage: u_log {loglevel} {message} [arguments]..."
	local lvl="${1:?$usg}" msg="${2:?$usg}"
	local color c_s c_e
	shift 2
	[ "$lvl" -ge "$_u_loglevel" ] || return 0
	case "$lvl" in
		$U_LOG_ERROR)
			lvl="E"
			color=9 # red
			;;
		$U_LOG_WARN)
			lvl="W"
			color=11 # yellow
			;;
		$U_LOG_INFO)
			lvl="I"
			color=12 # blue
			;;
		$U_LOG_DEBUG)
			lvl="D"
			color=13 # purple
			;;
	esac
	if [ "$_u_has_tput" ] && [ -t 2 ] && [ -n "$color" ]; then
		c_s=$(tput setaf $color)
		c_e=$(tput sgr0)
	fi
	[ -n "$c_s" ] && echo -n "$c_s" >&2
	printf "${lvl}:$(printf '%*s' $((_u_log_sub * 2)) )${msg}\n" "$@" >&2
	[ -n "$c_e" ] && echo -n "$c_e" >&2
}

u_log_exec () {
	# Logs a command and then runs it
	local usg="Usage: u_log_exec {command} [arguments]..."
	# Make sure there is at least one argument
	: "${1:?$usg}"
	printf "$(printf '%*s' $((_u_log_sub * 2)) )%s\n" "$*" >&2
	"$@"
}

# helper logging methods
u_log_err () {
	# Logs an error message
	local usg="Usage: u_log_err {message} [arguments]..."
	local msg="${1:?$usg}"
	shift
	u_log $U_LOG_ERROR "$msg" "$@"
}

u_log_warn () {
	# Logs a warning message
	local usg="Usage: u_log_warn {message} [arguments]..."
	local msg="${1:?$usg}"
	shift
	u_log $U_LOG_WARN "$msg" "$@"
}

u_log_info () {
	# Logs an info message
	local usg="Usage: u_log_info {message} [arguments]..."
	local msg="${1:?$usg}"
	shift
	u_log $U_LOG_INFO "$msg" "$@"
}

u_log_dbg () {
	# Logs a debug message
	local usg="Usage: u_log_dbg {message} [arguments]..."
	local msg="${1:?$usg}"
	shift
	u_log $U_LOG_DEBUG "$msg" "$@"
}

