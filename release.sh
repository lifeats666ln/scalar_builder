#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Publish release/ as a GitHub release, run by the workflow after build.sh.
# The notes carry a shortlog since the previous release of the same branch,
# laid out like the kernel.org announcements.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/lib/common.sh"
. "$ROOT/lib/toolchain.sh"

KERNEL_DIR=${KERNEL_DIR:-$ROOT/kernel}
repo=${KERNEL_REPO%.git}
head=$(kernel_git rev-parse "origin/$KERNEL_BRANCH")
date=$(jakarta_date +%Y-%m-%d)
tag=${CODENAME,,}-${date//-/}-r$GITHUB_RUN_NUMBER
zips=("$ROOT"/release/*.zip)
version=$(basename "${zips[0]}" | sed -E 's/.*-([0-9]+\.[0-9]+\.[0-9]+)-[0-9]{8}\.zip$/\1/')

# the previous release of this branch records its kernel head in a comment
base=$(gh api "repos/$GITHUB_REPOSITORY/releases?per_page=30" -q '.[].body' |
	sed -n "s/^<!-- head $KERNEL_BRANCH \([0-9a-f]\{40\}\) -->\$/\1/p" | head -n 1)
since=
if [ -n "$base" ]; then
	kernel_git cat-file -e "$base^{commit}" 2>/dev/null ||
		kernel_git fetch -q --deepen=2000 origin \
			"+refs/heads/$KERNEL_BRANCH:refs/remotes/origin/$KERNEL_BRANCH" || true
	kernel_git merge-base --is-ancestor "$base" "$head" 2>/dev/null && since=$base
fi

if [ -n "$since" ]; then
	heading="Changes since [${since:0:12}]($repo/commit/$since):"
	shortlog=$(kernel_git shortlog --no-merges "$since..$head")
	stat=$(kernel_git diff --shortstat "$since" "$head")
else
	heading="Last 10 commits:"
	shortlog=$(kernel_git shortlog --no-merges --max-count=10 "$head")
	stat=
fi

{
	echo "Scalar Kernel **$CODENAME**, \`$KERNEL_BRANCH\` at [${head:0:12}]($repo/commit/$head), $CLANG_VERSION, LTO $LTO."
	echo
	echo "| Variant | File | sha256 |"
	echo "|---|---|---|"
	for zip in "${zips[@]}"; do
		variant=$(basename "$zip" | sed -E "s/^Scalar-$CODENAME-([A-Za-z]+)-.*/\1/")
		echo "| $(variant_label "$variant") | \`$(basename "$zip")\` | \`$(sha256sum "$zip" | cut -c1-16)\` |"
	done
	echo
	echo "$heading"
	echo
	echo '```'
	echo "$shortlog"
	[ -z "$stat" ] || printf '\n%s\n' "$stat"
	echo '```'
	echo
	echo "<!-- head $KERNEL_BRANCH $head -->"
} > "$ROOT/release/notes.md"

prerelease=--prerelease
[ "$KERNEL_BRANCH" != android12-5.10 ] || prerelease=
gh release create "$tag" -R "$GITHUB_REPOSITORY" $prerelease \
	--title "Scalar Kernel $CODENAME $version ($date)" \
	--notes-file "$ROOT/release/notes.md" \
	"${zips[@]}" "$ROOT"/release/*-Image.gz
