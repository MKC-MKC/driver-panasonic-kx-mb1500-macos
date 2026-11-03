#!/usr/bin/env bash

panasonic_user_path_allowed() {
	local path="$1"
	local relative home

	case "$path" in /Users/*) ;; *) return 1 ;; esac
	relative="${path#/Users/}"
	home="/Users/${relative%%/*}"
	case "${path%/*}" in
		"$home/Library/Preferences"|"$home/Library/Preferences/ByHost"|\
		"$home/Library/Caches"|"$home/Library/Logs"|"$home/Library/Logs/DiagnosticReports"|\
		"$home/Library/LaunchAgents"|"$home/Library/Saved Application State"|\
		"$home/Library/Application Support"|"$home/Library/Application Support/CrashReporter") ;;
		*) return 1 ;;
	esac
	case "${path##*/}" in
		com.panasonic.mfs*|com.panasonic.panasonicMfs*|com.panamfs*|\
		Panasonic*MFS*|Panasonic_MFS*|panasonic-kx-mb1500*|com.local.panasonic-kx-mb1500-*|\
		com.apple.print.custompresets.forprinter.Panasonic*) return 0 ;;
		*) return 1 ;;
	esac
}

panasonic_remove_path() {
	local path="$1"
	local parent

	# Общие каталоги системы и пользовательские документы не входят в список удаления.
	case "$path" in
		'/Applications/Panasonic MFS'|'/Library/Printers/Panasonic'|\
		'/Library/Frameworks/Panasonic_MFS_Shared.framework'|\
		'/Library/Frameworks/Panasonic_MFS_SharedGui.framework'|\
		'/Library/Frameworks/Ghostscript.framework'|\
		'/Library/Image Capture/Devices/Panasonic MFS Scanner.app'|\
		'/Library/Image Capture/TWAIN Data Sources/Panasonic_MFS_DS.ds'|\
		'/Library/Image Capture/Support/LegacyDeviceDiscoveryHelpers/PanasonicMFSScannerRegister.app'|\
		'/Library/StartupItems/Panasonic_LPD'|'/Library/StartupItems/Panasonic_MFS_PushServer'|\
		'/Library/Preferences/Panasonic MFS'|'/usr/local/haikiri/panasonic-kx-mb1500'|\
		'/Library/LaunchAgents/com.panamfs.help.agent.plist'|\
		'/Library/LaunchAgents/com.panamfs.secureprint.agent.plist'|\
		'/Library/LaunchDaemons/com.panamfs.lpd.plist'|'/Library/LaunchDaemons/com.panamfs.pushd.plist'|\
		/usr/local/lib/libjpeg.8.dylib|/usr/local/lib/libjpeg.a|\
		/usr/local/lib/libjpeg.dylib|/usr/local/lib/libjpeg.la|\
		/Library/Printers/PPDs/Contents/Resources/Panasonic*|\
		/Library/Printers/PPDs/Contents/Resources/*/Panasonic*) ;;
		*)
			if ! panasonic_user_path_allowed "$path"; then
				printf 'ERROR: путь не относится к Panasonic MFS: %s\n' "$path" >&2
				return 1
			fi
			;;
	esac
	case "$path" in
		*/../*|*/./*|*/..|*/.) return 1 ;;
	esac

	# Не позволяем ссылке в родительском каталоге вывести очистку за проверенную область.
	parent="$(/usr/bin/dirname "$path")"
	while [ "$parent" != / ]; do
		if [ -L "$parent" ]; then
			printf 'ERROR: родительский каталог является ссылкой: %s\n' "$parent" >&2
			return 1
		fi
		parent="$(/usr/bin/dirname "$parent")"
	done
	[ -e "$path" ] || [ -L "$path" ] || return 0

	# Ссылку удаляем отдельно: её цель может находиться вне драйвера.
	if [ -L "$path" ]; then
		/usr/bin/unlink "$path"
		return
	fi
	parent="$(/usr/bin/dirname "$path")"
	if [ "$(/usr/bin/stat -f '%d' "$path")" != "$(/usr/bin/stat -f '%d' "$parent")" ]; then
		printf 'ERROR: отказ удаления точки монтирования: %s\n' "$path" >&2
		return 1
	fi
	/usr/bin/find -P -x "$path" -depth -delete
}

panasonic_stop_services() {
	local home uid service process

	# Выгружаем только собственные фоновые службы Panasonic.
	for service in /Library/LaunchDaemons/com.panamfs.lpd.plist /Library/LaunchDaemons/com.panamfs.pushd.plist; do
		[ -f "$service" ] || continue
		/bin/launchctl bootout system "$service" >/dev/null 2>&1 || true
	done
	for home in /Users/*; do
		[ -d "$home/Library" ] && [ ! -L "$home" ] || continue
		uid="$(/usr/bin/stat -f '%u' "$home")"
		for service in /Library/LaunchAgents/com.panamfs.help.agent.plist \
			/Library/LaunchAgents/com.panamfs.secureprint.agent.plist \
			"$home"/Library/LaunchAgents/com.local.panasonic-kx-mb1500-*.plist; do
			[ -f "$service" ] || continue
			/bin/launchctl bootout "gui/$uid" "$service" >/dev/null 2>&1 || true
		done
	done
	for process in 'Panasonic MFS Scanner' Panasonic_MFS_SecurePrint Panasonic_MFS_Tools \
		Panasonic_MFS_PushScan PanasonicMFSScannerRegister panasoniclpd panasonicmfspushd icdd; do
		/usr/bin/killall "$process" >/dev/null 2>&1 || true
	done
}

panasonic_remove_queues() {
	local line queue lower

	# URI сетевой очереди может не содержать производителя, поэтому проверяем также её PPD.
	while IFS= read -r line; do
		queue="${line%%: *}"
		queue="${queue##* }"
		case "$queue" in ''|*[!a-zA-Z0-9_.-]*) continue ;; esac
		lower="$(printf '%s' "$line" | /usr/bin/tr '[:upper:]' '[:lower:]')"
		if [[ "$lower" == *panasonic* ]] || \
			/usr/bin/grep -qi 'Panasonic' "/private/etc/cups/ppd/$queue.ppd" 2>/dev/null; then
			/usr/sbin/lpadmin -x "$queue"
		fi
	done < <(LC_ALL=C /usr/bin/lpstat -v 2>/dev/null || true)
}

panasonic_remove_driver_files() {
	local path

	# Общие библиотеки убираем только при наличии receipt установщика Panasonic.
	if /usr/sbin/pkgutil --pkg-info com.panasonic.panasonicMfs.ghostscript.pkg >/dev/null 2>&1; then
		panasonic_remove_path '/Library/Frameworks/Ghostscript.framework'
	fi
	if /usr/sbin/pkgutil --pkg-info com.panasonic.panasonicMfs.libjpeg.pkg >/dev/null 2>&1; then
		for path in /usr/local/lib/libjpeg.8.dylib /usr/local/lib/libjpeg.a \
			/usr/local/lib/libjpeg.dylib /usr/local/lib/libjpeg.la; do
			panasonic_remove_path "$path"
		done
	fi

	# Каталоги производителя и отдельные системные файлы не затрагивают другие принтеры.
	while IFS= read -r path; do
		panasonic_remove_path "$path"
	done <<'PATHS'
/Applications/Panasonic MFS
/Library/Printers/Panasonic
/Library/Frameworks/Panasonic_MFS_Shared.framework
/Library/Frameworks/Panasonic_MFS_SharedGui.framework
/Library/Image Capture/Devices/Panasonic MFS Scanner.app
/Library/Image Capture/TWAIN Data Sources/Panasonic_MFS_DS.ds
/Library/Image Capture/Support/LegacyDeviceDiscoveryHelpers/PanasonicMFSScannerRegister.app
/Library/StartupItems/Panasonic_LPD
/Library/StartupItems/Panasonic_MFS_PushServer
/Library/Preferences/Panasonic MFS
/usr/local/haikiri/panasonic-kx-mb1500
/Library/LaunchAgents/com.panamfs.help.agent.plist
/Library/LaunchAgents/com.panamfs.secureprint.agent.plist
/Library/LaunchDaemons/com.panamfs.lpd.plist
/Library/LaunchDaemons/com.panamfs.pushd.plist
PATHS
	for path in /Library/Printers/PPDs/Contents/Resources/Panasonic* \
		/Library/Printers/PPDs/Contents/Resources/*/Panasonic*; do
		[ -e "$path" ] || [ -L "$path" ] || continue
		panasonic_remove_path "$path"
	done
	/bin/rmdir /usr/local/haikiri 2>/dev/null || true
}

panasonic_remove_user_files() {
	local home folder path

	# Ограничиваем поиск настройками, кешами и журналами в Library каждого локального пользователя.
	for home in /Users/*; do
		[ -d "$home/Library" ] && [ ! -L "$home" ] || continue
		for folder in "$home/Library/Preferences" "$home/Library/Preferences/ByHost" \
			"$home/Library/Caches" "$home/Library/Logs" "$home/Library/Logs/DiagnosticReports" \
			"$home/Library/LaunchAgents" "$home/Library/Saved Application State" \
			"$home/Library/Application Support" "$home/Library/Application Support/CrashReporter"; do
			[ -d "$folder" ] && [ ! -L "$folder" ] || continue
			for path in "$folder"/*; do
				[ -e "$path" ] || [ -L "$path" ] || continue
				if panasonic_user_path_allowed "$path"; then
					panasonic_remove_path "$path"
				fi
			done
		done
	done
}

panasonic_forget_packages() {
	local package
	local packages

	# Receipt самого компонента очистки оставляем установщику; он не содержит драйверов.
	packages="$(/usr/sbin/pkgutil --pkgs)"
	while IFS= read -r package; do
		case "$package" in
			ru.haikiri.panasonic-kx-mb1500.cleanup) continue ;;
			com.panasonic.panasonicMfs.*|ru.haikiri.panasonic-kx-mb1500|ru.haikiri.panasonic-kx-mb1500.*)
				/usr/sbin/pkgutil --forget "$package"
				;;
		esac
	done <<< "$packages"
}

uninstall_panasonic_mfs() {
	if [ "$(/usr/bin/id -u)" -ne 0 ]; then
		printf 'ERROR: очистка драйверов требует прав администратора\n' >&2
		return 1
	fi

	panasonic_stop_services
	panasonic_remove_queues
	panasonic_remove_driver_files
	panasonic_remove_user_files
	panasonic_forget_packages
	printf 'Удалены драйверы и настройки Panasonic MFS.\n'
}
