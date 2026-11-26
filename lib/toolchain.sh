# SPDX-License-Identifier: GPL-2.0
#
# Neutron clang from its release catalogue, tarball pinned by sha256.

CLANG_VERSION=neutron-clang-06092026
CLANG_URL=https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/06092026/$CLANG_VERSION.tar.zst
CLANG_SHA256=531083928c8e37f6b31e324dbfd0b5a8323f989b1c57ff2c1368b889b5b1bd30
CLANG_DIR=$ROOT/toolchain/$CLANG_VERSION

toolchain_setup() {
	local archive=$ROOT/toolchain/$CLANG_VERSION.tar.zst

	if [ ! -x "$CLANG_DIR/bin/clang" ]; then
		mkdir -p "$CLANG_DIR"
		curl -fL --retry 3 -o "$archive" "$CLANG_URL"
		echo "$CLANG_SHA256  $archive" | sha256sum -c - ||
			{ rm -rf "$CLANG_DIR" "$archive"; die "$CLANG_VERSION failed sha256 check"; }
		tar --zstd -xf "$archive" -C "$CLANG_DIR"
		rm -f "$archive"
	fi
	export PATH=$CLANG_DIR/bin:$PATH
	CC=clang
	if command -v ccache >/dev/null; then
		CC="ccache clang"
	fi
}
