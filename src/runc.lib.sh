. ${UTILSDIR:?}/common.inc.sh; _u_set_loaded runc

test -x "${RUNC:=$(command -v runc)}" || return

u_cleanup_runc () {
	# Cleans up temporary containers
	local usg="Usage: u_cleanup_runc"
	local container
	for container in $(${RUNC} list -q | grep -o 'u_run-temp-instance-\w{4}'); do
		${RUNC} delete -f "$container"
	done
}

### execution

u_run () {
	# Runs the specified command in a container created using a bundle
	local usg="Usage: u_run {bundle} [exec_options]... -- {command} [arguments]..."
	local bundle instance options
	bundle="${1:?$usg}"
	shift

	options=""
	while [ -n "$1" -a "$1" != "--" ]; do
		options="${options} $1"
		shift
	done
	[ "$1" = "--" ] && shift

	[ $# -ge 1 ] || return

	mv "${bundle}/config.json" "${bundle}/config.json.u_run_orig"
	sed -e '
		# disable terminal
		/terminal/ s/\(terminal[": ]\+\)true/\1false/

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

	instance=$(mktemp -u u_run-temp-instance-XXXX)
	${RUNC} create -b "$bundle" "$instance"
	${RUNC} exec $options "$instance" "$@"
	${RUNC} delete "$instance"

	mv -f "${bundle}/config.json.u_run_orig" "${bundle}/config.json"
}