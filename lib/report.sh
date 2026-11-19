# SPDX-License-Identifier: GPL-2.0
#
# Build results, failure log and cancellation notice.

RESULTS=()
FINISH_LINES=
BUILD_CANCELLED=
CANCEL_SIGNAL=
BUILD_FINISHED=
ERROR_PATTERN='error:|Error [0-9]+|undefined reference|FAILED|ABI check failed'

# Shared result block for the status message and the file caption. Reads the
# ABI counts produced by abi_check() so the ABI line shows real numbers.
result_block() {
	local variant=$1 duration=$2 size sha name obj abi_bad=0 abi_expected=0 abi_matched head esc_release

	duration="$(( $2 / 60 ))m $(( $2 % 60 ))s"
	size=$(du -h "$ZIP_FILE" | cut -f1)
	sha=$(sha256sum "$ZIP_FILE" | cut -c1-16)
	name=$(variant_label "$variant")
	esc_release=$(telegram_escape "$RELEASE_STRING")
	head=$(kernel_git rev-parse --short=7 "$KERNEL_REF" 2>/dev/null)

	obj="$ROOT/out/${variant,,}"
	[ -f "$obj/abi.diff" ] && abi_bad=$(wc -l < "$obj/abi.diff")
	[ -f "$obj/abi.expected" ] && abi_expected=$(wc -l < "$obj/abi.expected")
	abi_matched=$((abi_expected - abi_bad))

	printf '%s' \
		"<code>$esc_release</code>"$'\n'$'\n' \
		"<blockquote>" \
		"Status <code>$RELEASE_TYPE build</code> - ABI <code>$abi_matched/$abi_expected</code> KMI symbols matched"$'\n' \
		"Toolchain <code>$CLANG_VERSION</code> - LTO <code>$LTO</code>"$'\n' \
		"Branch <code>$KERNEL_BRANCH</code> @ <code>$head</code> - $(jakarta_date '+%Y-%m-%d %H:%M') WIB"$'\n' \
		"Duration <code>$duration</code> - Image <code>$size</code>"$'\n' \
		"SHA256 <code>$sha</code> (prefix)" \
		"</blockquote>"
}

report_result() {
	local variant=$1 seconds=$2 name duration block

	name=$(variant_label "$variant")
	duration="$(( $2 / 60 ))m $(( $2 % 60 ))s"
	block=$(result_block "$variant" "$seconds")
	RESULTS+=("$RELEASE_STRING ($duration)" "  $ZIP_FILE")
	FINISH_LINES+="${FINISH_LINES:+$'\n'$'\n'}<b>$name</b>"$'\n'"$block"

	telegram_send_file "$ZIP_FILE" "<b>Build success</b> - $name"$'\n'$'\n'"$block"
}

report_failure() {
	local status=$1 stage=${CURRENT_STAGE:-setup} failure_log first_error error_count body

	failure_log=$RELEASE_DIR/build-failed-$stage-$(jakarta_date +%Y%m%d-%H%M).txt
	mkdir -p "$RELEASE_DIR"
	# let tee flush the last lines into the log
	sleep 1
	{
		echo "stage: $stage, exit $status, $KERNEL_REF @ $(kernel_git rev-parse --short=12 HEAD 2>/dev/null)"
		echo "toolchain: $CLANG_VERSION"
		echo
		grep -nE "$ERROR_PATTERN" "$LOG_FILE" | head -50 || true
		if [ -s "$ROOT/out/${stage,,}/abi.diff" ]; then
			echo
			cat "$ROOT/out/${stage,,}/abi.diff"
		fi
		echo
		cat "$LOG_FILE"
	} > "$failure_log" 2>/dev/null
	echo "failed: $stage (exit $status), log in $failure_log"

	first_error=$(grep -m 1 -E "$ERROR_PATTERN" "$LOG_FILE" || true)
	error_count=$(grep -cE "$ERROR_PATTERN" "$LOG_FILE" || true)
	[ -n "$first_error" ] || first_error="no line matched the error pattern, see the log"

	body="❌ <b>Build error</b> - $(variant_label "$stage") (exit $status)"$'\n'
	body+="🐞 <code>$error_count</code> error line(s): <code>$(telegram_escape "${first_error:0:300}")</code>"$'\n'
	body+="📄 Log: <code>$(basename "$failure_log")</code>"

	telegram_finish FAILED "$body"
	telegram_send_file "$failure_log" "📄 Build error - $(variant_label "$stage")"
}

# INT/TERM/HUP while the build runs: let the EXIT trap notify as CANCELLED
# instead of leaving the message on [BUILDING] or misreporting a failure.
on_signal() {
	[ -z "${BUILD_FINISHED:-}" ] || return 0
	CANCEL_SIGNAL=$1
	BUILD_CANCELLED=1
	exit 130
}

report_cancel() {
	local signal=${1:-TERM} stage=${CURRENT_STAGE:-setup} body

	body="🚫 <b>Build cancelled</b> - $(variant_label "$stage")"$'\n'
	body+="⏹ Signal: <code>$signal</code> - stage: <code>$stage</code>"$'\n'
	body+="📄 Partial log: <code>$(basename "$LOG_FILE")</code>"

	telegram_finish CANCELLED "$body"
}

on_exit() {
	local status=$?

	progress_stop
	kernel_restore
	[ ${#RESULTS[@]} -eq 0 ] || printf '%s\n' "${RESULTS[@]}"
	if [ -n "$BUILD_CANCELLED" ]; then
		report_cancel "$CANCEL_SIGNAL"
	elif [ $status -ne 0 ]; then
		report_failure $status
	fi
}
