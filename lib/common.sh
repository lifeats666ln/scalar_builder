# SPDX-License-Identifier: GPL-2.0

die() {
	echo "error: $*" >&2
	exit 1
}

kernel_git() { git -C "$KERNEL_DIR" "$@"; }

jakarta_date() { TZ=WIB-7 date "$@"; }

# the name people see, SUSFS also carries KernelSU-Next
variant_label() { [ "$1" = SUSFS ] && echo "KSUN + SUSFS" || echo "$1"; }

host_check() {
	local binary

	for binary in git curl tar make bc bison flex perl python3 zip lz4 cpio sha256sum; do
		command -v "$binary" >/dev/null || die "$binary not found"
	done
}
