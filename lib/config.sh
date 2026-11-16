# SPDX-License-Identifier: GPL-2.0
#
# Settings from config.env, the environment or a prompt.

ask_choice() {
	local variable=$1 prompt=$2 PS3="> "

	shift 2
	echo "$prompt"
	select answer in "$@"; do
		[ -n "$answer" ] && break
	done
	printf -v "$variable" '%s' "$answer"
}

config_load() {
	[ ! -f "$ROOT/config.env" ] || . "$ROOT/config.env"

	KERNEL_REPO=${KERNEL_REPO:-https://github.com/itelrs4/kernel_common-5.10}
	KERNEL_BRANCH=${KERNEL_BRANCH:-android12-5.10-staging}
	KERNEL_DIR=${KERNEL_DIR:-$ROOT/kernel}
	KERNEL_REF=origin/$KERNEL_BRANCH
	ANYKERNEL_REPO=${ANYKERNEL_REPO:-https://github.com/lifeats666ln/AnyKernel3}
	SUSFS_DIR=${SUSFS_DIR:-}
	RELEASE_DIR=$ROOT/release
	LOG_FILE=$ROOT/build.log
	CURRENT_STAGE=

	if [ -t 0 ]; then
		[ -n "${LTO:-}" ] || ask_choice LTO "LTO:" full thin
		[ -n "${CODENAME:-}" ] || read -rp "Codename: " CODENAME
		[ -n "${CLEAN:-}" ] || read -rp "Clean build? [y/N] " CLEAN
	fi
	LTO=${LTO:-full}
	CLEAN=${CLEAN:-n}
	CODENAME=${CODENAME:-}
	[[ $LTO == full || $LTO == thin ]] || die "LTO must be full or thin"
	[[ $CODENAME =~ ^[A-Za-z0-9._-]{1,14}$ ]] || die "CODENAME must be 1-14 of [A-Za-z0-9._-]"
	telegram_validate

	VARIANTS=(Vanilla)
	if [ -n "$SUSFS_DIR" ]; then
		ls "$SUSFS_DIR"/*.patch >/dev/null 2>&1 || die "no patches in $SUSFS_DIR"
		VARIANTS=(SUSFS Vanilla)
	fi

	BUILD_TIMESTAMP=$(jakarta_date '+%a %b %-d %H:%M:%S %Z %Y')
}
