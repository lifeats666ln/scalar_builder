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
	# empty input would make the check pass vacuously
	[ -s "$object_dir/abi.expected" ] ||
		die "ABI check: no 'crc' symbols parsed from android/abi_gki_aarch64.xml (format changed?)"
	[ -s "$object_dir/abi.actual" ] ||
		die "ABI check: no __crc_ symbols in vmlinux (CONFIG_MODVERSIONS off or llvm-nm failed?)"
	LC_ALL=C join -a 1 -e missing -o 0,1.2,2.2 "$object_dir/abi.expected" "$object_dir/abi.actual" |
		awk '$2 != $3 { print $1 ": expected " $2 ", built " $3 }' > "$object_dir/abi.diff"

	mismatches=$(wc -l < "$object_dir/abi.diff")
	if [ "$mismatches" -gt 0 ]; then
		die "ABI check failed: $mismatches of $(wc -l < "$object_dir/abi.expected") symbols differ"
	fi
	echo "ABI OK: $(wc -l < "$object_dir/abi.expected") symbols"
}

abi_report() {
	local object_dir=$1 variant=$2 limit=${ABI_REPORT_LIMIT:-300}
	local report expected actual extra missing mismatched broken

	report=$object_dir/abi.report.txt
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
		echo "ABI CHECK: $(variant_label "$variant")"
		echo "branch:   $KERNEL_BRANCH @ $(kernel_git rev-parse --short=12 "$KERNEL_REF")"
		echo "toolchain: $CLANG_VERSION, LTO $LTO"
		echo
		printf '  %-26s %s\n' "KMI symbols expected" "$expected" \
			"CRC symbols in vmlinux" "$actual" \
			"extra, not in KMI" "$extra" \
			"missing from vmlinux" "$missing" \
			"CRC mismatch" "$mismatched"
		echo
		[ "$extra" -eq 0 ] || echo "Extra CRC symbols are expected; only missing or mismatched ones break modules."
		[ "$extra" -eq 0 ] || echo
		if [ "$expected" -eq 0 ] || [ "$actual" -eq 0 ]; then
			echo "NO DATA: expected=$expected actual=$actual, nothing was compared."
		elif [ "$broken" -eq 0 ]; then
			echo "KMI intact."
		else
			echo "KMI BROKEN: $missing missing, $mismatched CRC mismatch"
			echo
			printf '  %-26s %-10s %-12s %s\n' SYMBOL ISSUE EXPECTED BUILT
			awk -F'\t' -v limit="$limit" 'NR<=limit{printf "  %-26s %-10s %-12s %s\n", $2, $1, $3, $4}' \
				"$object_dir/abi.breakage.tsv"
			if [ "$broken" -gt "$limit" ]; then
				echo
				echo "Truncated at $limit of $broken. Full list: abi.breakage.tsv"
			fi
		fi
	} > "$report"

	{
		echo '<pre>'
		cat "$report"
		echo '</pre>'
	} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

	[ "$broken" -eq 0 ] && [ "$expected" -gt 0 ] && [ "$actual" -gt 0 ]
}
