. ${UTILSDIR:?}/common.inc.sh; _u_set_loaded files

### file handling

u_get_asset () {
	# Gets the path to a file URI retriving and caching the file if necessary
	# Supported schemes: file (default), http, https
	local usg="Usage: u_get_asset {file_uri}"
	local uri scheme path fname cdir
	uri="${1:?$usg}"
	scheme="${uri%:*}"
	case "$scheme" in
		http|https)
			fname=$(_u_uri_as_fname "$uri")
			cdir="${ASSET_CACHEDIR:-${BUILDDIR:-.}/.assetcache}"
			path="$cdir/$fname"
			if [ ! -f "$path" ]; then
				[ -d "$cdir" ] || mkdir -p "$cdir"
				wget -nv --show-progress -O "$path" "$uri"
				if [ $? -ne 0 ]; then
					rm -f "$path"
					return 1
				fi
			fi
			;;
		file|"")
			path="${uri#file://}"
			;;
		*)
			echo "Unknown scheme '$scheme' in URI '$uri'" >&2
			return 1
			;;
	esac
	[ -f "$path" ] || return 1
	echo "$path"
}

u_extract () {
	# Fetches an archive and extracts it to a target location
	# Supported formats: zip, tar, tgz (and others supported by tar)
	# See u_get_asset for supported URI schemes
	local usg="Usage: u_extract {archive_uri} {target_path)"
	local archive="${1:?$usg}" target="${2:?$usg}"
	local apath
	apath="$(u_get_asset "$archive")"
	mkdir -p "$target"
	if [ "$(echo -n "${archive##*.}" | tr "[:upper:]" "[:lower:]")" = "zip" ]; then
		# handle zip
		unzip -qq "$apath" -d "$target"
	else
		# assume file is a tar
		tar -xf "$apath" -C "$target"
	fi
}

### internal

_u_uri_as_fname () {
	# Returns a unique filename based on a URI
	local uri fname hash
	uri="${1:?}"
	fname="$(echo -n "$uri" | tr -cs "[:alnum:]" "_" | sed 's/^_*//; s/_*$//')"
	hash="$(echo -n "$uri" | md5sum | cut -c -8)"
	echo "${fname#}-${hash}"
}