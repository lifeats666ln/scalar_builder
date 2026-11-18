# SPDX-License-Identifier: GPL-2.0
#
# Vendor modules are never rebuilt, so vmlinux must still export every symbol
# of android/abi_gki_aarch64.xml with the same checksum.

abi_check() {
	local object_dir=$1 mismatches

	sed -n "s/.*<elf-symbol name='\([^']*\)'.* crc='0x0*\([0-9a-f]*\)'.*/\1 \2/p" \
		"$KERNEL_DIR/android/abi_gki_aarch64.xml" | LC_ALL=C sort > "$object_dir/abi.expected"
	llvm-nm "$object_dir/vmlinux" |
		awk '$3 ~ /^__crc_/ { value = tolower($1); sub(/^0+/, "", value); print substr($3, 7), value }' |
		LC_ALL=C sort > "$object_dir/abi.actual"
	LC_ALL=C join -a 1 -e missing -o 0,1.2,2.2 "$object_dir/abi.expected" "$object_dir/abi.actual" |
		awk '$2 != $3 { print $1 ": expected " $2 ", built " $3 }' > "$object_dir/abi.diff"

	mismatches=$(wc -l < "$object_dir/abi.diff")
	if [ "$mismatches" -gt 0 ]; then
		head -20 "$object_dir/abi.diff" >&2
		die "ABI check failed: $mismatches of $(wc -l < "$object_dir/abi.expected") symbols differ"
	fi
	echo "ABI OK: $(wc -l < "$object_dir/abi.expected") symbols"
}

abi_report() {
	local object_dir=$1 variant=$2 limit=${ABI_REPORT_LIMIT:-300}
	local report expected actual extra missing mismatched broken

	report=$object_dir/abi.report.md
	expected=$(wc -l < "$object_dir/abi.expected")
	actual=$(wc -l < "$object_dir/abi.actual")
	extra=$(awk 'NR==FNR{e[$1]=1;next} !($1 in e){n++} END{print n+0}' \
		"$object_dir/abi.expected" "$object_dir/abi.actual")

	awk 'NR==FNR{a[$1]=$2;next}
		!($1 in a){print "missing\t" $1 "\t" $2 "\t-"; next}
		a[$1]!=$2{print "mismatch\t" $1 "\t" $2 "\t" a[$1]}' \
		"$object_dir/abi.actual" "$object_dir/abi.expected" > "$object_dir/abi.breakage.tsv"

	broken=$(wc -l < "$object_dir/abi.breakage.tsv")
	missing=$(awk -F'\t' '$1=="missing"{n++}END{print n+0}' "$object_dir/abi.breakage.tsv")
	mismatched=$(awk -F'\t' '$1=="mismatch"{n++}END{print n+0}' "$object_dir/abi.breakage.tsv")

	{
		echo "### ABI: $(variant_label "$variant")"
		echo
		echo "- branch: <code>$KERNEL_BRANCH</code> @ <code>$(kernel_git rev-parse --short=12 "$KERNEL_REF")</code>"
		echo "- toolchain: <code>$CLANG_VERSION</code> · LTO <code>$LTO</code>"
		echo
		echo "| check | count |"
		echo "|---|---|"
		echo "| KMI symbols expected | $expected |"
		echo "| CRC symbols in vmlinux | $actual |"
		echo "| extra, not in KMI | $extra |"
		echo "| missing from vmlinux | $missing |"
		echo "| CRC mismatch | $mismatched |"
		echo
		[ "$extra" -eq 0 ] || echo "Extra CRC symbols are expected, only missing or mismatched ones break modules."
		[ "$extra" -eq 0 ] || echo
		if [ "$broken" -eq 0 ]; then
			echo "KMI intact."
		else
			echo "KMI broken. First $limit of $broken:"
			echo
			echo "| symbol | issue | expected | built |"
			echo "|---|---|---|---|"
			awk -F'\t' -v limit="$limit" 'NR<=limit{print "| <code>" $2 "</code> | " $1 " | <code>" $3 "</code> | <code>" $4 "</code> |"}' \
				"$object_dir/abi.breakage.tsv"
			if [ "$broken" -gt "$limit" ]; then
				echo
				echo "Full list in <code>abi.breakage.tsv</code> artifact."
			fi
		fi
		echo
	} > "$report"

	cat "$report" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
	[ "$broken" -eq 0 ]
}
