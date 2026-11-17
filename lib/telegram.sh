# SPDX-License-Identifier: GPL-2.0
#
# One Telegram message per target, edited from [BUILDING] to [SUCCESS] or
# [FAILED]. Without a token or targets every call does nothing, and a target
# that fails never stops the build. Target syntax is in the README.

declare -A TELEGRAM_MESSAGES=()
TELEGRAM_FIELDS=
TELEGRAM_CHANGELOG=
PROGRESS_PID=

telegram_targets() {
	[ -n "${TELEGRAM_TOKEN:-}" ] || return 0
	tr -s ', ' '\n' <<< "${TELEGRAM_CHAT:-}" | sed '/^$/d'
}

telegram_validate() {
	local target

	for target in $(telegram_targets); do
		[[ $target =~ ^(-?[0-9]+|@[A-Za-z0-9_]{5,32})(/[0-9]+)?$ ]] ||
			die "TELEGRAM_CHAT: bad target '$target'"
	done
}

telegram_api() {
	local target=$1 method=$2 chat=${1%%/*} thread=()

	shift 2
	# only send* takes a thread, an edit addresses the message by id
	if [[ $target == */* && $method == send* ]]; then
		thread=(--form-string message_thread_id="${target#*/}")
	fi
	curl -fsS -m 120 "https://api.telegram.org/bot$TELEGRAM_TOKEN/$method" \
		--form-string chat_id="$chat" "${thread[@]}" "$@" 2>/dev/null
}

telegram_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<< "$1"; }

telegram_prepare() {
	local repo=${KERNEL_REPO%.git} head sha subject variant builds=

	head=$(kernel_git rev-parse "$KERNEL_REF")
	for variant in "${VARIANTS[@]}"; do
		builds+="${builds:+, }$(variant_label "$variant")"
	done
	TELEGRAM_FIELDS="📅 $(jakarta_date '+%Y-%m-%d %H:%M') WIB
🌿 <code>$KERNEL_BRANCH</code> @ <a href=\"$repo/commit/$head\">${head:0:7}</a>
🛠 $CLANG_VERSION · LTO $LTO · $(nproc) CPU
🧪 $builds"

	TELEGRAM_CHANGELOG="📋 <b>Changelog</b>"$'
'"<blockquote expandable>"
	while IFS=$'	' read -r sha subject; do
		TELEGRAM_CHANGELOG+="<a href=\"$repo/commit/$sha\">${sha:0:7}</a> $(telegram_escape "${subject:0:72}")"$'
'
	done < <(kernel_git log --no-merges -10 --format=$'%H	%s' "$KERNEL_REF")
	TELEGRAM_CHANGELOG="${TELEGRAM_CHANGELOG%$'
'}</blockquote>"
	[ -z "${GITHUB_RUN_ID:-}" ] ||
		TELEGRAM_CHANGELOG+=$'
'"🔗 <a href=\"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID\">Workflow run</a>"
}

telegram_render() {
	printf '%s <b>Scalar Kernel %s</b> · <code>%s</code>

<blockquote>%s</blockquote>

%s

%s' 		"$1" "$(telegram_escape "$CODENAME")" "$2" "$TELEGRAM_FIELDS" "$3" "$TELEGRAM_CHANGELOG"
}

telegram_post() {
	local text=$1 target

	for target in $(telegram_targets); do
		if [ -z "${TELEGRAM_MESSAGES[$target]:-}" ]; then
			TELEGRAM_MESSAGES[$target]=$(telegram_api "$target" sendMessage \
				--form-string parse_mode=HTML --form-string disable_web_page_preview=true \
				--form-string text="$text" |
				python3 -c 'import json, sys; print(json.load(sys.stdin)["result"]["message_id"])' \
				2>/dev/null) || TELEGRAM_MESSAGES[$target]=
		else
			telegram_api "$target" editMessageText \
				--form-string message_id="${TELEGRAM_MESSAGES[$target]}" \
				--form-string parse_mode=HTML --form-string disable_web_page_preview=true \
				--form-string text="$text" >/dev/null || true
		fi
	done
}

telegram_status() { telegram_post "$(telegram_render 🔨 BUILDING "⏳ $1")"; }

telegram_finish() {
	local emoji=✅

	case $1 in
		FAILED) emoji=❌ ;;
		CANCELLED) emoji=🚫 ;;
	esac
	telegram_post "$(telegram_render "$emoji" "$1" "$2")"
}

telegram_send_file() {
	local document=@$1 target file_id

	# the first upload yields a file id that the other targets reuse
	for target in $(telegram_targets); do
		file_id=$(telegram_api "$target" sendDocument -F document="$document" \
			--form-string parse_mode=HTML --form-string caption="$2" |
			python3 -c 'import json, sys; print(json.load(sys.stdin)["result"]["document"]["file_id"])' \
			2>/dev/null) || continue
		[ -z "$file_id" ] || document=$file_id
	done
}

progress_start() {
	[ -n "$(telegram_targets)" ] || return 0
	(
		started=$(date +%s)
		while sleep 60; do
			elapsed=$(( $(date +%s) - started ))
			line=$(grep -E '^ +(CC|LD|AR|AS|LTO|OBJCOPY|GZIP|MODPOST) ' "$LOG_FILE" | tail -n 1 | sed 's/^ *//' || true)
			telegram_status "$1, $((elapsed / 60))m $((elapsed % 60))s"$'\n'"<code>$(telegram_escape "$line")</code>"
		done
	) &
	PROGRESS_PID=$!
}

progress_stop() {
	[ -z "$PROGRESS_PID" ] || kill "$PROGRESS_PID" 2>/dev/null || true
	PROGRESS_PID=
}
