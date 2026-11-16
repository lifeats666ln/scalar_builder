# SPDX-License-Identifier: GPL-2.0
#
# AnyKernel3 packaging. Sets RELEASE_STRING and ZIP_FILE for the caller.

package() {
	local variant=$1 object_dir=$2 name image anykernel_dir

	RELEASE_STRING=$(cat "$object_dir/include/config/kernel.release")
	name=Scalar-$CODENAME-$variant-${RELEASE_STRING%%-*}-$(jakarta_date +%Y%m%d)
	image=$object_dir/arch/arm64/boot/Image.gz
	anykernel_dir=$object_dir/AnyKernel3

	rm -rf "$anykernel_dir"
	git clone -q --depth=1 "$ANYKERNEL_REPO" "$anykernel_dir"
	cp "$image" "$anykernel_dir/"
	# anykernel.sh reads the version from a raw Image, print it directly
	sed -i "s|^ui_print \"- Kernel: .*|ui_print \"- Kernel: $RELEASE_STRING\"\nui_print \"- Built: $BUILD_TIMESTAMP\"|" "$anykernel_dir/anykernel.sh"
	if [ "$variant" = Vanilla ]; then
		sed -i 's/ Install KernelSU-Next manager[^.]*after boot\.//; /KernelSU-Next/d' "$anykernel_dir/anykernel.sh"
		sed -i 's/KernelSU-Next + SUSFS/none (vanilla)/' "$anykernel_dir/banner"
	fi

	mkdir -p "$RELEASE_DIR"
	ZIP_FILE=$RELEASE_DIR/$name.zip
	rm -f "$ZIP_FILE"
	(cd "$anykernel_dir" && zip -qr9 "$ZIP_FILE" * -x README.md '*placeholder')
	cp "$image" "$RELEASE_DIR/$name-Image.gz"
}
