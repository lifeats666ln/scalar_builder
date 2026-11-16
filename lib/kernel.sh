# SPDX-License-Identifier: GPL-2.0
#
# Kernel tree: fetch, per-variant checkout, configure and compile.

KVM_MAKEFILE=arch/arm64/kvm/Makefile

kernel_fetch() {
	if [ -d "$KERNEL_DIR/.git" ]; then
		kernel_git fetch -q --depth=1 origin \
			"+refs/heads/$KERNEL_BRANCH:refs/remotes/origin/$KERNEL_BRANCH"
	else
		git clone -q --depth=1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
	fi
	kernel_git rev-parse -q --verify "$KERNEL_REF^{commit}" >/dev/null ||
		die "$KERNEL_REF not found"
	eval "$(kernel_git show "$KERNEL_REF:build.config.common" | grep -E '^(BRANCH|KMI_GENERATION)=')"
}

kernel_restore() {
	[ ! -d "$(kernel_git rev-parse --absolute-git-dir 2>/dev/null)/rebase-apply" ] ||
		kernel_git am --abort
	kernel_git checkout -q -- "$KVM_MAKEFILE" 2>/dev/null || true
}

kernel_prepare() {
	kernel_restore
	kernel_git checkout -q -B "scalar-build-${1,,}" "$KERNEL_REF"
	if [ "$1" = SUSFS ]; then
		kernel_git -c user.name=Scalar -c user.email=scalar@localhost \
			am -q --3way "$SUSFS_DIR"/*.patch ||
			{ kernel_git am --abort; die "SUSFS patches do not apply on $KERNEL_REF"; }
	fi

	# some clang 21+ builds lack -Wuninitialized-const-pointer, probe it
	if grep -q 'CONFIG_CLANG_VERSION) -ge 210000' "$KERNEL_DIR/$KVM_MAKEFILE"; then
		sed -i '/CONFIG_CLANG_VERSION) -ge 210000/,/^endif$/c\ccflags-y += $(call cc-disable-warning, uninitialized-const-pointer)' "$KERNEL_DIR/$KVM_MAKEFILE"
	fi
}

kernel_make() {
	local object_dir=$1

	shift
	make -C "$KERNEL_DIR" O="$object_dir" -j"${JOBS:-$(nproc)}" \
		ARCH=arm64 LLVM=1 LLVM_IAS=1 CC="$CC" \
		CROSS_COMPILE=aarch64-linux-gnu- \
		CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
		KCFLAGS=-D__ANDROID_COMMON_KERNEL__ \
		BRANCH="$BRANCH" KMI_GENERATION="$KMI_GENERATION" \
		LOCALVERSION= KBUILD_BUILD_USER=Scalar KBUILD_BUILD_HOST="$CODENAME" \
		KBUILD_BUILD_TIMESTAMP="$BUILD_TIMESTAMP" "$@"
}

kernel_configure() {
	local variant=$1 object_dir=$2 has_kernelsu has_susfs
	local config_tool=("$KERNEL_DIR/scripts/config" --file "$object_dir/.config")

	[[ $CLEAN != [yY]* ]] || rm -rf "$object_dir"
	mkdir -p "$object_dir"

	kernel_make "$object_dir" gki_defconfig
	"${config_tool[@]}" --set-str LOCALVERSION "-Scalar-$CODENAME-$variant"
	# DWARF is only read by the ABI tooling and slows LTO down
	"${config_tool[@]}" -d DEBUG_INFO -d DEBUG_INFO_DWARF4
	[ "$LTO" = full ] || "${config_tool[@]}" -d LTO_CLANG_FULL -e LTO_CLANG_THIN
	kernel_make "$object_dir" olddefconfig

	grep -q '^CONFIG_KSU=y' "$object_dir/.config" && has_kernelsu=1 || has_kernelsu=0
	grep -q '^CONFIG_KSU_SUSFS=y' "$object_dir/.config" && has_susfs=1 || has_susfs=0
	case $variant:$has_kernelsu$has_susfs in
	Vanilla:00 | SUSFS:11) ;;
	*) die "$variant: unexpected CONFIG_KSU=$has_kernelsu CONFIG_KSU_SUSFS=$has_susfs" ;;
	esac
}

kernel_compile() {
	# KernelSU-Next builds its preinit runner against usr/include
	kernel_make "$1" headers
	kernel_make "$1" Image.gz
}
