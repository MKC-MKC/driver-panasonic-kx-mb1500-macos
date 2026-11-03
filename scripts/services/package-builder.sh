#!/usr/bin/env bash

build_component_packages() {
	local build_dir="$1"
	local version="$2"
	local component

	# Пустой список исключает поиск и перенос scanner app по совпадающему bundle id.
	cat > "$build_dir/empty-components.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array/></plist>
PLIST
	for component in scanner print; do
		mkdir -p "$build_dir/scripts-$component"
		install -m 0755 "$REPO_ROOT/components/$component/scripts/"* "$build_dir/scripts-$component/"
		pkgbuild --root "$build_dir/payload-$component" \
			--scripts "$build_dir/scripts-$component" \
			--component-plist "$build_dir/empty-components.plist" \
			--identifier "ru.haikiri.panasonic-kx-mb1500.$component" \
			--version "$version" --install-location / --ownership recommended \
			--filter '/\._.*' --filter '/\.DS_Store$' \
			"$build_dir/components/$component.pkg"
	done

	# Очистка выполняется отдельным компонентом без установки файлов на диск.
	mkdir -p "$build_dir/scripts-cleanup"
	install -m 0755 "$REPO_ROOT/components/cleanup/scripts/postinstall" "$build_dir/scripts-cleanup/"
	install -m 0644 "$REPO_ROOT/scripts/services/panasonic-uninstaller.sh" "$build_dir/scripts-cleanup/"
	pkgbuild --nopayload --scripts "$build_dir/scripts-cleanup" \
		--identifier ru.haikiri.panasonic-kx-mb1500.cleanup --version "$version" \
		"$build_dir/components/cleanup.pkg"
}
