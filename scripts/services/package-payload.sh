#!/usr/bin/env bash

extract_vendor_scanner() (
	local build_dir="$1"
	local mount_dir="$build_dir/vendor-mount"
	local expanded_dir="$build_dir/vendor-expanded"
	local app_name="Panasonic MFS Scanner.app"
	local mounted=0

	# Отсоединяем только образ этой сборки, в том числе при ошибке распаковки.
	cleanup_vendor_image() {
		if [ "$mounted" -eq 1 ]; then
			hdiutil detach "$mount_dir" >/dev/null
		fi
		rmdir "$mount_dir"
	}
	trap cleanup_vendor_image EXIT
	mkdir -p "$mount_dir"
	hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" \
		"$REPO_ROOT/artifacts/Mac_1.15.2.dmg" >/dev/null
	mounted=1

	# Из исходного пакета берём только ICA backend; остальные компоненты MFS не устанавливаем.
	pkgutil --expand-full "$mount_dir/Install.pkg" "$expanded_dir"
	mkdir -p "$build_dir/payload-scanner/Library/Image Capture/Devices"
	ditto --noextattr --noqtn \
		"$expanded_dir/panasonicMfsScanner.pkg/Payload/$app_name" \
		"$build_dir/payload-scanner/Library/Image Capture/Devices/$app_name"
	rm -rf "$expanded_dir"
)

prepare_scanner_payload() {
	local build_dir="$1"
	local app_path="$build_dir/payload-scanner/Library/Image Capture/Devices/Panasonic MFS Scanner.app"

	# Готовый подписанный backend позволяет установить сканер без компилятора на целевом Mac.
	extract_vendor_scanner "$build_dir"
	/bin/bash "$REPO_ROOT/scripts/repair-scanner-ica.sh" --prepare-app "$app_path"
	codesign --verify --deep --strict "$app_path"
}

prepare_print_payload() {
	local build_dir="$1"
	local payload="$build_dir/payload-print"
	local install_root="$payload/usr/local/haikiri/panasonic-kx-mb1500"
	local filter_path="$REPO_ROOT/printer/filter/bin/panasonic-kx-mb1500-gdi"

	# Печатные файлы находятся в своём компоненте и учитываются в receipt пакета.
	if [ ! -x "$filter_path" ]; then
		/bin/bash "$REPO_ROOT/scripts/build-filter.sh"
	fi
	mkdir -p "$payload/Library/Printers/PPDs/Contents/Resources" \
		"$payload/Library/Printers/Panasonic/Filter" "$install_root/scripts/helper"
	install -m 0644 "$REPO_ROOT/printer/ppd/Panasonic_KX-MB1500-haikiri.ppd" \
		"$payload/Library/Printers/PPDs/Contents/Resources/"
	install -m 0755 "$filter_path" "$payload/Library/Printers/Panasonic/Filter/"
	install -m 0755 "$REPO_ROOT/scripts/install-driver.sh" "$REPO_ROOT/scripts/verify-print.sh" \
		"$install_root/scripts/"
	install -m 0644 "$REPO_ROOT/scripts/helper/panasonic_model.sh" "$install_root/scripts/helper/"
}
