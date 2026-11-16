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
