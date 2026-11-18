#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Build kernels, report KMI damage, and skip packaging or release.

set -uo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
for file in "$ROOT"/lib/*.sh; do
	. "$file"
done

abi_notify() {
	local failed=$1 text target
	[ "${NOTIFY:-on_failure}" != never ] || return 0
	[ "$NOTIFY" = always ] || [ "$failed" -ne 0 ] || return 0

	text="<b>ABI check $([ "$failed" -eq 0 ] && echo OK || echo BROKEN)</b>"
	text+=$'\n'"<code>$KERNEL_BRANCH</code> @ <code>$(kernel_git rev-parse --short=7 "$KERNEL_REF")</code>"
	if [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
		text+=$'\n'"<a href=\"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID\">details</a>"
	fi
	for target in $(telegram_targets); do
		telegram_api "$target" sendMessage \
			--form-string parse_mode=HTML \
			--form-string disable_web_page_preview=true \
			--form-string "text=$text" >/dev/null || true
	done
}

config_load
toolchain_setup
kernel_fetch

FAILED=0
variants=(Vanilla)
[ -z "$SUSFS_DIR" ] || variants=(SUSFS Vanilla)

for variant in "${variants[@]}"; do
	object_dir=$ROOT/out/${variant,,}
	CURRENT_STAGE=$variant
	kernel_prepare "$variant"
	kernel_configure "$variant" "$object_dir"
	if kernel_compile "$object_dir"; then
		(abi_check "$object_dir") || FAILED=1
		abi_report "$object_dir" "$variant" || FAILED=1
	else
		echo "compile failed: $variant" >&2
		FAILED=1
	fi
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	printf 'ABI result: %s\n' "$([ "$FAILED" -eq 0 ] && echo OK || echo BROKEN)" >> "$GITHUB_STEP_SUMMARY"
fi

abi_notify "$FAILED"
exit "$FAILED"
