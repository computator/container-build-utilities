. ${UTILSDIR:?}/common.inc.sh; _u_set_loaded files

### file handling

u_get_asset () {
	local uri scheme path fname cdir
	uri="${1:?}"
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
	local archive="${1:?}" target="${2:?}"
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
	local uri fname hash
	uri="${1:?}"
	fname="$(echo -n "$uri" | tr -cs "[:alnum:]" "_" | sed 's/^_*//; s/_*$//')"
	hash="$(echo -n "$uri" | md5sum | cut -c -8)"
	echo "${fname#}-${hash}"
}