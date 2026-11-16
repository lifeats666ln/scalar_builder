# SPDX-License-Identifier: GPL-2.0
#
# One Telegram status message, edited at every stage. Without a token or chat
# every call does nothing, and a failed call never stops the build.

TELEGRAM_HEADER=
TELEGRAM_MESSAGE=
PROGRESS_PID=

telegram_enabled() { [ -n "${TELEGRAM_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT:-}" ]; }

telegram_validate() {
	[ -z "${TELEGRAM_CHAT:-}" ] ||
		[[ $TELEGRAM_CHAT =~ ^(-?[0-9]+|@[A-Za-z0-9_]{5,32})$ ]] ||
		die "TELEGRAM_CHAT: bad chat '$TELEGRAM_CHAT'"
}

telegram_api() {
	local method=$1

	telegram_enabled || return 1
	shift
	curl -fsS -m 120 "https://api.telegram.org/bot$TELEGRAM_TOKEN/$method" \
		--form-string chat_id="$TELEGRAM_CHAT" "$@" 2>/dev/null
}

telegram_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<< "$1"; }

telegram_header() {
	local run=

	[ -z "${GITHUB_RUN_ID:-}" ] ||
		run=$'\n'"<a href=\"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID\">workflow run</a>"
	TELEGRAM_HEADER="<b>Scalar Kernel</b> $(telegram_escape "$CODENAME")
<code>$KERNEL_BRANCH</code> @ <code>$(kernel_git rev-parse --short=12 "$KERNEL_REF")</code>
$(telegram_escape "$(kernel_git log -1 --format=%s "$KERNEL_REF")")
${VARIANTS[*]}, LTO $LTO, $CLANG_VERSION, $(nproc) CPU$run"
}

telegram_status() {
	local text="$TELEGRAM_HEADER"$'\n\n'"$1"

	if [ -z "$TELEGRAM_MESSAGE" ]; then
		TELEGRAM_MESSAGE=$(telegram_api sendMessage --form-string parse_mode=HTML \
			--form-string disable_web_page_preview=true --form-string text="$text" |
			python3 -c 'import json, sys; print(json.load(sys.stdin)["result"]["message_id"])' \
			2>/dev/null) || TELEGRAM_MESSAGE=
	else
		telegram_api editMessageText --form-string message_id="$TELEGRAM_MESSAGE" \
			--form-string parse_mode=HTML --form-string disable_web_page_preview=true \
			--form-string text="$text" >/dev/null || true
	fi
}

telegram_send_file() {
	telegram_api sendDocument -F document=@"$1" --form-string parse_mode=HTML \
		--form-string caption="$2" >/dev/null || true
}

progress_start() {
	telegram_enabled || return 0
	(
		started=$(date +%s)
		while sleep 60; do
			elapsed=$(( $(date +%s) - started ))
			line=$(grep -E '^ +(CC|LD|AR|AS|LTO|OBJCOPY|GZIP|MODPOST) ' "$LOG_FILE" | tail -n 1 | sed 's/^ *//' || true)
			telegram_status "$1, $((elapsed / 60))m$((elapsed % 60))s"$'\n'"<code>$(telegram_escape "$line")</code>"
		done
	) &
	PROGRESS_PID=$!
}

progress_stop() {
	[ -z "$PROGRESS_PID" ] || kill "$PROGRESS_PID" 2>/dev/null || true
	PROGRESS_PID=
}
