#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Build Scalar Kernel, check the ABI, package an AnyKernel3 zip and report
# progress to Telegram. The steps live in lib/.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
for file in "$ROOT"/lib/*.sh; do
	. "$file"
done

config_load
exec > >(tee "$LOG_FILE") 2>&1
trap on_exit EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_signal HUP' HUP

host_check
kernel_fetch
telegram_prepare
telegram_status "setup"
toolchain_setup

for variant in "${VARIANTS[@]}"; do
	CURRENT_STAGE=$variant
	object_dir=$ROOT/out/${variant,,}
	label=$(variant_label "$variant")

	telegram_status "$label: configure"
	kernel_prepare "$variant"
	kernel_configure "$variant" "$object_dir"

	started=$(date +%s)
	progress_start "$label: compile"
	kernel_compile "$object_dir"
	progress_stop

	telegram_status "$label: ABI check"
	abi_check "$object_dir"
	duration=$(( $(date +%s) - started ))

	telegram_status "$label: package"
	package "$variant" "$object_dir"
	report_result "$variant" "$duration"
done

CURRENT_STAGE=
BUILD_FINISHED=1
telegram_finish SUCCESS "$FINISH_LINES"
