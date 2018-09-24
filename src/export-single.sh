#!/bin/sh
set -e

usg="Usage: $(basename "$0") [-q] {image[:tag]} [outfile]"

[ -n "$UTILSDIR" ] || UTILSDIR="$(dirname "$0")"

. ${UTILSDIR}/umoci.lib.sh

[ "$1" = "-q" ] && shift || u_set_loglevel $U_LOG_INFO

# get container and tag
if [ -z "$1" ]; then
	echo "$usg" >&2
	exit 1
fi
container="${1%%:*}"
tag="${1#*:}"
[ "$tag" != "$container" ] || tag="latest"

outfile="$2"

# setup
BUILDDIR="."
cleanup () {
	rm -rf ${BUILDDIR}/export-single.????.oci
	u_cleanup
}
trap 'cleanup' EXIT

img=$(u_clone_image "${container}")

u_write_ref "${img}:${tag}" "REMOVE_THIS_REF"
u_remove_refs_except "${img}" "REMOVE_THIS_REF"
u_clean_image "${img}" "${tag}"

sed -i "${img}/index.json" \
	-e 's/\(annotations"[[:space:]]*:[[:space:]]*{.*\)"org.opencontainers.image.ref.name"[[:space:]"]*:[[:space:]]*"REMOVE_THIS_REF"[[:space:]]*,\?/\1/' \
	-e 's/,\?[[:space:]]*"annotations"[[:space:]]*:[[:space:]]*{[[:space:]]*}//'

file=$(u_serialize_image "${img}" "$(mktemp -u export-single.XXXX)")
if [ -n "$outfile" ]; then
	u_log_info "Moving '%s' to '%s'" "$file" "$outfile"
	mv -fT "$file" "$outfile"
else
	u_log_info "Dumping '%s' to stdout" "$file"
	cat "$file"
	rm -f "$file"
fi