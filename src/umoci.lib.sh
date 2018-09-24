. ${UTILSDIR:?}/common.inc.sh; _u_set_loaded umoci

test -x "${UMOCI:=$(command -v umoci)}" || return

u_cleanup_umoci () {
	# Deletes temporary files from manipulating containers
	local usg="Usage: u_cleanup_umoci"
	u_log_dbg "Cleaning up temporary files"
	# use ???? to not accidentally delete other files
	rm -rf ${BUILDDIR:-.}/image.????
	rm -rf ${BUILDDIR:-.}/bundle.????
	rm -rf ${BUILDDIR:-.}/imgclone.????
	rm -rf ${BUILDDIR:-.}/imgopen.????
}

### images

u_create_image () {
	# Creates a blank image
	local usg="Usage: u_create_image"
	local path
	path=$(mktemp -udp "${BUILDDIR:-.}" image.XXXX)
	u_log_info "Creating image '%s'" "${path#"${BUILDDIR:-.}/"}"
	${UMOCI} init --layout "$path"
	if [ $? -ne 0 ]; then
		u_log_err "Failed to create image '%s'" "${path#"${BUILDDIR:-.}/"}"
		return 1
	fi
	echo "$path"
}

u_clone_image () {
	# Creates a copy of an existing image or serialized image
	# Uses hardlinks for the blob store when possible to save disk space
	local usg="Usage: u_clone_image {src_name}"
	local img path src
	img="${1:?$usg}"
	u_log_dbg "Cloning image '%s'" "${img#"${BUILDDIR:-.}/"}"
	if [ -d "${BUILDDIR:-.}/${img}" ]; then
		src="${BUILDDIR:-.}/${img}"
		u_log_dbg "Found image '%s'" "${src#"${BUILDDIR:-.}/"}"
		path=$(mktemp -dp "${BUILDDIR:-.}" imgclone.XXXX)
		# reset mode
		chmod $(printf %o $((0777 & ~$(umask)))) "$path"
		u_log_dbg "Created image '%s'" "${path#"${BUILDDIR:-.}/"}"
		u_log_info "Cloning image '%s' to '%s'" "${src#"${BUILDDIR:-.}/"}" "${path#"${BUILDDIR:-.}/"}"
		# check if we have permissions and whether we are on the same filesystem before trying to hardlink
		if [ -w "${src}/blobs" ] && [ "$(stat -c '%d' "${src}/blobs")" = "$(stat -c '%d' "$path")" ]; then
			# hardlink files in blobs to save space
			u_log_dbg "Hardlinking image blobs"
			cp -r -l "${src}/blobs" "$path"
		else
			u_log_dbg "Copying image blobs"
			cp -r "${src}/blobs" "$path"
		fi
		u_log_dbg "Copying other image files"
		# copy everything else normally
		cp -r $(find "$src" -mindepth 1 -maxdepth 1 ! -path "${src}/blobs") "$path"
		echo "$path"
	elif [ -f "${BUILDDIR:-.}/${img}.oci" ]; then
		src="${BUILDDIR:-.}/${img}.oci"
		path=$(mktemp -dp "${BUILDDIR:-.}" imgclone.XXXX)
		# reset mode
		chmod $(printf %o $((0777 & ~$(umask)))) "$path"
		u_log_dbg "Created image '%s'" "${path#"${BUILDDIR:-.}/"}"
		u_log_info "Cloning image '%s' to '%s'" "${src#"${BUILDDIR:-.}/"}" "${path#"${BUILDDIR:-.}/"}"
		u_log_dbg "Unserializing image '%s'" "${src#"${BUILDDIR:-.}/"}"
		tar -xzf "$src" -C "$path"
		echo "$path"
	else
		u_log_err "Failed to clone image '%s': Not found!" "${img#"${BUILDDIR:-.}/"}"
		return 1
	fi
}

u_open_image () {
	# Opens an existing image or serialized image for editing
	local usg="Usage: u_open_image {src_name}"
	local img path src
	img="${1:?$usg}"
	u_log_dbg "Opening image '%s'" "${img#"${BUILDDIR:-.}/"}"
	if [ -d "${BUILDDIR:-.}/${img}" ]; then
		src="${BUILDDIR:-.}/${img}"
		u_log_info "Opening image '%s'" "${src#"${BUILDDIR:-.}/"}"
		echo "$src"
	elif [ -f "${BUILDDIR:-.}/${img}.oci" ]; then
		src="${BUILDDIR:-.}/${img}.oci"
		path=$(mktemp -dp "${BUILDDIR:-.}" imgopen.XXXX)
		# reset mode
		chmod $(printf %o $((0777 & ~$(umask)))) "$path"
		u_log_dbg "Created image '%s'" "${path#"${BUILDDIR:-.}/"}"
		u_log_info "Opening image '%s' as '%s'" "${src#"${BUILDDIR:-.}/"}" "${path#"${BUILDDIR:-.}/"}"
		u_log_dbg "Unserializing image '%s'" "${src#"${BUILDDIR:-.}/"}"
		tar -xzf "$src" -C "$path"
		echo "$path"
	else
		u_log_err "Failed to open image '%s': Not found!" "${img#"${BUILDDIR:-.}/"}"
		return 1
	fi
}

u_set_image_name () {
	# Sets or updates the name for an image
	# This is how you "save" a temporary image created by
	# u_create_image or u_clone_image
	local usg="Usage: u_set_image_name {image} {new_name}"
	local newpath
	newpath="$(dirname "${1:?$usg}")/${2:?$usg}"
	u_log_info "Setting name for image '%s' to '%s'" "${1#"${BUILDDIR:-.}/"}" "${newpath#"${BUILDDIR:-.}/"}"
	mv -T "${1}" "$newpath"
	echo "$newpath"
}

u_clean_image () {
	# Garbage collects unreferenced blobs in an image
	local usg="Usage: u_clean_image {image}"
	local img="${1:?$usg}"
	u_log_info "Cleaning image '%s'" "${img#"${BUILDDIR:-.}/"}"
	${UMOCI} gc --layout "$img"
}

u_serialize_image () {
	# Saves an image as a serialized .oci image
	local usg="Usage: u_serialize_image {image} {name}"
	local img archive
	img="${1:?$usg}"
	archive="${BUILDDIR:-.}/${2:?$usg}.oci"
	u_log_info "Serializing image '%s' as '%s'" "${img#"${BUILDDIR:-.}/"}" "${archive#"${BUILDDIR:-.}/"}"
	( cd "$img" && find -mindepth 1 -maxdepth 1 | sed 's:^./::' ) | \
		tar -c --hard-dereference --numeric-owner --owner 0 --group 0 -z -f "$archive" -C "${1}" --files-from -
	echo "$archive"
}

### image refs

u_gen_refname () {
	# Generates a temporary reference name
	# If an image is specified it includes it in the generated reference
	local usg="Usage: u_gen_refname [image]"
	mktemp -u "${1:+$1:}XXXX"
}

u_create_ref () {
	# Creates a new blank reference
	local usg="Usage: u_create_ref {image}"
	local ref
	u_log_sub
	ref=$(u_gen_refname "${1:?$usg}")
	u_log_unsub
	u_log_info "Creating image ref '%s'" "${ref#"${BUILDDIR:-.}/"}"
	${UMOCI} new --image "$ref"
	echo "$ref"
}

u_clone_ref () {
	# Creates a copy of an existing reference
	local usg="Usage: u_clone_ref [ {imgref} | {image} {srcref} ]"
	local oldref tag
	u_log_sub
	oldref="${1:?$usg}"
	if [ "${oldref##*:}" = "$oldref" ]; then
		oldref=$(u_get_ref "$oldref" "${2:?$usg}")
	fi
	tag=$(u_gen_refname)
	u_log_unsub
	u_log_info "Cloning image reference '%s' as '%s'" "${oldref#"${BUILDDIR:-.}/"}" "$tag"
	u_log_sub
	u_write_ref "$oldref" "$tag"
	echo $(u_get_ref "${oldref%:*}" "$tag")
	u_log_unsub
}

u_get_ref () {
	# Gets am existing reference
	# This just combines an image and reference name into a full reference
	local usg="Usage: u_get_ref {image} {reference}"
	echo "${1:?$usg}:${2:?$usg}"
}

u_list_refs () {
	# Lists all the references in an image
	local usg="Usage: u_list_refs {image}"
	local img="${1:?$usg}"
	u_log_dbg "Listing references in image '%s'" "${img#"${BUILDDIR:-.}/"}"
	${UMOCI} list --layout "$img"
}

u_write_ref () {
	# Saves a copy of a reference under another name
	local usg="Usage: u_write_ref {img_srcref} {refname}"
	local imgref="${1:?$usg}" tag="${2:?$usg}"
	u_log_info "Writing image ref '%s' to '%s'" "${imgref#"${BUILDDIR:-.}/"}" "$tag"
	${UMOCI} tag --image "$imgref" "$tag"
}

u_remove_ref () {
	# Removes a reference from an image
	local usg="Usage: u_remove_ref {imgref}"
	local tag="${1:?$usg}"
	u_log_info "Removing image ref '%s'" "${tag#"${BUILDDIR:-.}/"}"
	${UMOCI} rm --image "$tag"
}

u_remove_refs_except () {
	# Removes all references from an image except for the specified references
	local usg="Usage: u_remove_refs_except {image} {references}..."
	local img ref exclude
	img="${1:?$usg}"
	shift
	[ $# -ge 1 ] || return
	for ref in "$@"; do
		# remove image prefix (if any) when adding to the exclude list
		exclude="${exclude} ${ref#*:}"
	done
	u_log_info "Removing image refs in image '%s' except for: %s" "${img#"${BUILDDIR:-.}/"}" "${exclude# }"
	u_log_sub
	for ref in $(u_list_refs "$img"); do
		if ! echo "$exclude" | grep -qwF "$ref"; then
			u_remove_ref $(u_get_ref "$img" "$ref")
		fi
	done
	u_log_unsub
}

### image ref layers

u_open_layer () {
	# Unpacks the layers from a reference into a bundle
	local usg="Usage: u_open_layer {imgref} [unpack_options]..."
	local img bundle
	img="${1:?$usg}"
	shift
	bundle=$(mktemp -udp "${BUILDDIR:-.}" bundle.XXXX)
	u_log_info "Unpacking image ref '%s' as '%s'" "${img#"${BUILDDIR:-.}/"}" "$bundle"
	${UMOCI} unpack "$@" --image "$img" "$bundle"
	echo "$bundle"
}

u_continue_layer () {
	# Repacks the changes to a bundle as a new layer in a reference and leaves the bundle open
	local usg="Usage: u_continue_layer {bundle} {imgref} [repack_options]..."
	local img bundle
	img="${2:?$usg}"
	bundle="${1:?$usg}"
	shift 2
	u_log_info "Repacking changes from '%s' into image ref '%s'" "$bundle" "${img#"${BUILDDIR:-.}/"}"
	${UMOCI} repack "$@" --refresh-bundle --image "$img" "$bundle"
}

u_close_layer () {
	# Repacks the changes to a bundle as a new layer in a reference and closes the bundle
	local usg="Usage: u_close_layer {bundle} {imgref} [repack_options]..."
	local img bundle
	img="${2:?$usg}"
	bundle="${1:?$usg}"
	shift 2
	u_log_info "Repacking changes from '%s' into image ref '%s'" "$bundle" "${img#"${BUILDDIR:-.}/"}"
	${UMOCI} repack "$@" --image "$img" "$bundle"
	u_log_info "Removing '%s'" "$bundle"
	rm -rf "$bundle"
}

### image ref config

u_config () {
	# Sets config options for a reference
	local usg="Usage: u_config {imgref} {config_opts}..."
	local img
	img="${1:?$usg}"
	shift
	u_log_info "Setting config options for image ref '%s': %s" "${img#"${BUILDDIR:-.}/"}" "$*"
	${UMOCI} config --image "$img" "$@"
}

### layer utilities

u_layer_path () {
	# Gets a full path to a location inside a bundle from a bundle and a path
	local usg="Usage: u_layer_path {bundle} {path}"
	local bundle="${1:?$usg}" path="${2:?$usg}"
	local outpath
	u_log_dbg "Calculating layer path for bundle '%s' and path '%s'" "$bundle" "$path"
	# make sure the path has a single leading slash and no trailing slashes
	path="$(echo -n "/${path}" | sed 's#^\s*/*\(/\([^/]\(.*[^/]\)\?\)\?\)/\?\s*$#\1#')"
	outpath="${bundle}/rootfs${path}"
	u_log_dbg "Layer path: %s" "$outpath"
	echo "$outpath"
}