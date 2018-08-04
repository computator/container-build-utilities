#!/bin/sh
set -e

usg="Usage: $(basename "$0") {image[:tag]} [exec_options]... [ -- {command} [arguments]... ]"

[ -n "$UTILSDIR" ] || UTILSDIR="$(dirname "$0")"

. ${UTILSDIR}/runc.lib.sh
. ${UTILSDIR}/umoci.lib.sh

# get container and tag
if [ -z "$1" ]; then
	echo "$usg" >&2
	exit 1
fi
container="${1%%:*}"
tag="${1#*:}"
[ "$tag" != "$container" ] || tag="latest"
shift

# get all exec options
options=""
while [ -n "$1" -a "$1" != "--" ]; do
	options="${options} $1"
	shift
done
[ "$1" = "--" ] && shift

# setup
BUILDDIR="."
u_set_autoclean

# unpack image
bundle=$(u_open_layer "${container}:${tag}")

# run container
if [ $# -ge 1 ]; then
	# if stdout is a tty then add --tty to the options
	[ -t 1 ] && options="--tty $options"
	u_run "$bundle" $options -- "$@"
else
	_u_patch_bundle "$bundle" --fg

	instance=$(_u_gen_instance_name)

	u_log_info "Creating container '%s' from bundle '%s'" "$instance" "$bundle"
	u_log_info "Starting container '%s'" "$instance"
	${RUNC} run -b "$bundle" $options "$instance"
	u_log_info "Container '%s' exited" "$instance"
fi
