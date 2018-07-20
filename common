[ -z "$_u_common_loaded" ] || return 0
_u_common_loaded=1

_u_modules_loaded=""
_u_set_loaded() {
	expr match "$_u_modules_loaded" ".*${1:?}" > /dev/null || _u_modules_loaded="${_u_modules_loaded} ${1}"
}

### cleanup functions

u_cleanup () {
	local module
	for module in $_u_modules_loaded; do
		if type "u_cleanup_${module}" > /dev/null 2>&1; then
			"u_cleanup_${module}"
		fi
	done
}

u_set_autoclean () {
	trap 'u_cleanup' EXIT
}