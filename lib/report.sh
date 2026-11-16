# SPDX-License-Identifier: GPL-2.0
#
# Build results and the failure log.

RESULTS=()
FINISH_LINES=
ERROR_PATTERN='error:|Error [0-9]+|undefined reference|FAILED|ABI check failed'

report_result() {
	local variant=$1 duration size label= newline=$'\n'

	duration="$(( $2 / 60 ))m $(( $2 % 60 ))s"
	size=$(du -h "$ZIP_FILE" | cut -f1)
	[ ${#VARIANTS[@]} -eq 1 ] || label=" ($variant)"

	RESULTS+=("$RELEASE_STRING ($duration)" "  $ZIP_FILE")
	FINISH_LINES+="${FINISH_LINES:+$newline}⏱ Build time$label: $duration${newline}📦 Size$label: $size"
	telegram_send_file "$ZIP_FILE" "<code>$(telegram_escape "$RELEASE_STRING")</code>
$variant, ABI OK
sha256 <code>$(sha256sum "$ZIP_FILE" | cut -c1-16)</code>"
}

report_failure() {
	local status=$1 stage=${CURRENT_STAGE:-setup} failure_log first_error

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
	telegram_finish FAILED "⚠️ Failed at: $stage (exit $status)"$'\n'"<code>$(telegram_escape "${first_error:0:300}")</code>"
	telegram_send_file "$failure_log" "$stage log"
}

on_exit() {
	local status=$?

	progress_stop
	kernel_restore
	[ ${#RESULTS[@]} -eq 0 ] || printf '%s\n' "${RESULTS[@]}"
	[ $status -eq 0 ] || report_failure $status
}
