#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/services/package-payload.sh"
source "$REPO_ROOT/scripts/services/package-builder.sh"
source "$REPO_ROOT/scripts/services/package-distribution.sh"

main() {
	local version="${1:-$(plutil -extract tags.2 raw -o - "$REPO_ROOT/app-info.json")}"
	local build_dir="$REPO_ROOT/build/pkg"
	local output_path="$REPO_ROOT/dist/Panasonic-KX-MB1500-haikiri-$version.pkg"

	rm -rf "$build_dir"
	mkdir -p "$build_dir/components" "$REPO_ROOT/dist"
	export COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1

	prepare_scanner_payload "$build_dir"
	prepare_print_payload "$build_dir"
	build_component_packages "$build_dir" "$version"
	write_package_distribution "$build_dir/Distribution.xml" "$version"
	productbuild --distribution "$build_dir/Distribution.xml" \
		--package-path "$build_dir/components" "$output_path"
	printf '%s\n' "$output_path"
}

main "$@"
