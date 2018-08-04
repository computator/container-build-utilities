. ${UTILSDIR:?}/common.inc.sh; _u_set_loaded runc

test -x "${RUNC:=$(command -v runc)}" || return

u_cleanup_runc () {
	# Cleans up temporary containers
	local usg="Usage: u_cleanup_runc"
	local container
	u_log_dbg "Cleaning up temporary containers"
	for container in $(${RUNC} list -q | grep -o 'u_run-temp-instance-\w\{4\}'); do
		${RUNC} delete -f "$container"
	done
}

### execution

u_run () {
	# Runs the specified command in a container created using a bundle
	local usg="Usage: u_run {bundle} [exec_options]... -- {command} [arguments]..."
	local bundle instance options color
	bundle="${1:?$usg}"
	shift

	color=1
	options=""
	while [ -n "$1" -a "$1" != "--" ]; do
		options="${options} $1"
		# disable output colorizing if using a tty
		[ "$1" = "--tty" -o "$1" = "-t" ] && color=""
		shift
	done
	[ "$1" = "--" ] && shift

	[ $# -ge 1 ] || return

	_u_patch_bundle "$bundle"

	instance=$(_u_gen_instance_name)

	u_log_info "Creating container '%s' from bundle '%s'" "$instance" "$bundle"
	${RUNC} create -b "$bundle" "$instance"
	u_log_info "Running command in container '%s': %s" "$instance" "$*"
	if [ "$color" -a -t 1 ]; then
		{
			{
				${RUNC} exec $options "$instance" "$@" | sed -u "s/^/$(tput setaf 10)sout: /"
			} 3>&2 2>&1 1>&3 3>&- | sed -u "s/^/$(tput setaf 9)serr: /"
		} 2>&1 | sed -u "s/$/$(tput sgr0)/"
	else
		${RUNC} exec $options "$instance" "$@"
	fi
	u_log_info "Removing container '%s'" "$instance"
	${RUNC} delete "$instance"

	u_log_dbg "Restoring original config.json for bundle '%s'" "$bundle"
	mv -f "${bundle}/config.json.u_run_orig" "${bundle}/config.json"
}

### internal

_u_patch_bundle () {
	local bundle="${1:?}" bg=1
	[ "$2" = "--fg" ] && bg=""

	u_log_dbg "Patching config.json for bundle '%s'" "$bundle"
	mv "${bundle}/config.json" "${bundle}/config.json.u_run_orig"
	sed ${bg:+-e '
		# disable terminal
		/terminal/ s/\(terminal[": ]\+\)true/\1false/
		'} \
		-e '

		# remove network namespace to allow access to host network
		/namespaces/ { :n; s/,\?[[:space:]]*{[[:space:]]*"\?type[": ]\+network"\?[[:space:]]*}//; t e; N; b n; :e }

		# bind mount host resolv.conf in container to make internet work
		/mounts/ {
			:find_ins_point
			# try to add placeholder
			s/\(mounts"\?[: ]\+\[\)\([[:space:]]*\)\([]{]\)/\1\n\2ADDHOSTMNT\n\2\3/
			# continue if successful
			t print_before
			# failed, append another line and try again
			N
			b find_ins_point
			
			:print_before
			# check if lines to print before placeholder
			/\n[^\n]*ADDHOSTMNT/ {
				P
				s/[^\n]*\n//
				# loop until all lines before placeholder printed
				b print_before
			}

			# now that we are at the correct position remove the placeholder and insert the text
			s/ADDHOSTMNT\n//
			i {"type": "bind", "source": "/etc/resolv.conf", "destination": "/etc/resolv.conf", "options": ["rbind", "ro"]},
		}
		' "${bundle}/config.json.u_run_orig" > "${bundle}/config.json"
}

_u_gen_instance_name () {
	mktemp -u u_run-temp-instance-XXXX
}