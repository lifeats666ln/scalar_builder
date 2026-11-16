# SPDX-License-Identifier: GPL-2.0
#
# AOSP clang from a mirror, every binary verified against AOSP by blob id.

CLANG_VERSION=clang-r614150
CLANG_URL=https://github.com/bachnxuan/aosp_clang_mirror/releases/download/clang-r614150-16836431/$CLANG_VERSION.tar.gz
CLANG_AOSP_URL=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/mirror-goog-main-llvm-toolchain-source/$CLANG_VERSION/bin/
CLANG_DIR=$ROOT/toolchain/$CLANG_VERSION

toolchain_verify() {
	local listing blob_id name

	listing=$(curl -fsL "$CLANG_AOSP_URL?format=JSON" | tail -c +6 |
		python3 -c 'import json, sys; [print(entry["id"], entry["name"]) for entry in json.load(sys.stdin)["entries"] if entry["mode"] == 33261]')
	[ -n "$listing" ] || return 1
	while read -r blob_id name; do
		[ "$(git hash-object "$CLANG_DIR/bin/$name")" = "$blob_id" ] ||
			{ echo "$name differs from AOSP" >&2; return 1; }
	done <<< "$listing"
	echo "$CLANG_VERSION: $(wc -l <<< "$listing") binaries match AOSP"
}

toolchain_setup() {
	if [ ! -x "$CLANG_DIR/bin/clang" ]; then
		mkdir -p "$CLANG_DIR"
		curl -fL --retry 3 "$CLANG_URL" | tar -xz -C "$CLANG_DIR"
		toolchain_verify || { rm -rf "$CLANG_DIR"; die "$CLANG_VERSION failed verification"; }
	fi
	export PATH=$CLANG_DIR/bin:$PATH
	CC=clang
	if command -v ccache >/dev/null; then
		CC="ccache clang"
	fi
}
