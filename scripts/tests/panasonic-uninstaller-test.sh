#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Подключаем код пакетного удалятора, а системные операции ниже заменяем безопасными функциями.
source "$SCRIPT_DIR/../services/panasonic-uninstaller.sh"

assert_eq() {
	local expected="$1"
	local actual="$2"
	local message="$3"

	if [ "$expected" != "$actual" ]; then
		printf 'ASSERTION FAILED: %s\nExpected: %s\nActual: %s\n' "$message" "$expected" "$actual" >&2
		exit 1
	fi
}

assert_true() {
	local message="$1"
	shift

	if ! "$@"; then
		printf 'ASSERTION FAILED: %s\n' "$message" >&2
		exit 1
	fi
}

assert_false() {
	local message="$1"
	shift

	if "$@" >/dev/null 2>&1; then
		printf 'ASSERTION FAILED: %s\n' "$message" >&2
		exit 1
	fi
}

# Даже при ошибке в проверке путей тест не сможет удалить настоящий файл.
function /usr/bin/find() { printf 'blocked find\n'; }
function /usr/bin/unlink() { printf 'blocked unlink\n'; }

function /usr/bin/lpstat() {
	assert_eq '-v' "$1" 'queue inspection must request device URIs'
	cat <<'QUEUES'
device for Panasonic_KX_MB1500RU: usb://Panasonic/KX-MB1500RU
device for Office_Epson: usb://Epson/WorkForce
устройство для Shared_Panasonic: dnssd://Panasonic%20KX-MB1500._ipp._tcp.local
устройство для Router: socket://192.0.2.1
device for Router_HP: socket://192.0.2.2
device for Invalid/Queue: usb://Panasonic/KX-MB1500RU
QUEUES
}

function /usr/sbin/lpadmin() {
	assert_eq '-x' "$1" 'cleanup must only remove matching queues'
	printf 'removed:%s\n' "$2"
}

function /usr/bin/grep() {
	assert_eq '-qi' "$1" 'PPD inspection must ignore letter case'
	assert_eq 'Panasonic' "$2" 'PPD inspection must identify Panasonic'
	[ "$3" = '/private/etc/cups/ppd/Router.ppd' ]
}

function /usr/sbin/pkgutil() {
	case "$1" in
		--pkgs)
			cat <<'PACKAGES'
com.panasonic.panasonicMfs.panasonicMfsScanner5.pkg
com.panasonic.panasonicMfs.ghostscript.pkg
com.panasonic.LUMIX
com.panasonic.panasonicMfsOther.pkg
ru.haikiri.panasonic-kx-mb1500
ru.haikiri.panasonic-kx-mb1500.print
ru.haikiri.panasonic-kx-mb1500.scanner
ru.haikiri.panasonic-kx-mb1500.mfs
ru.haikiri.panasonic-kx-mb1500.repair
ru.haikiri.panasonic-kx-mb1500.cleanup
ru.haikiri.panasonic-kx-mb1500-other
ru.haikiri.other-application
com.apple.pkg.OtherPrinter
PACKAGES
			;;
		--forget) printf 'forgot:%s\n' "$2" ;;
		*) printf 'Unexpected pkgutil operation: %s\n' "$1" >&2; return 1 ;;
	esac
}

test_path_boundaries() {
	local path

	# Не допускаем удаления общих каталогов и выхода через относительные компоненты пути.
	for path in / /Library /Applications /Users/test/Documents/Panasonic \
		'/Library/Printers/PPDs/Contents/Resources/../Panasonic' \
		'/Users/test/Library/Preferences/../../Documents/com.panasonic.mfs.plist'; do
		assert_false 'unsafe paths must be rejected' panasonic_remove_path "$path"
	done

	# Настройки MFS и принтера разрешены, настройки другого ПО Panasonic остаются на месте.
	for path in '/Users/test/Library/Preferences/com.panasonic.mfs.ica.plist' \
		'/Users/test/Library/Preferences/ByHost/com.panasonic.panasonicMfs.settings.plist' \
		'/Users/test/Library/Caches/com.panamfs.cache' \
		'/Users/test/Library/Logs/panasonic-kx-mb1500-runtime.log' \
		'/Users/test/Library/Logs/DiagnosticReports/Panasonic MFS Scanner.ips' \
		'/Users/test/Library/Application Support/Panasonic MFS' \
		'/Users/test/Library/Application Support/CrashReporter/Panasonic_MFS_Scanner.plist' \
		'/Users/test/Library/Preferences/com.apple.print.custompresets.forprinter.Panasonic_KX_MB1500RU.plist'; do
		assert_true 'MFS user paths must be recognized' panasonic_user_path_allowed "$path"
	done
	for path in '/Users/test/Library/Preferences/com.panasonic.LUMIX.plist' \
		'/Users/test/Library/Application Support/Panasonic LUMIX' \
		'/Users/test/Library/Caches/com.apple.ImageCapture' \
		'/Users/test/Documents/Panasonic MFS' \
		'/Users/test/Library/Preferences/Other/com.panasonic.mfs.plist'; do
		assert_false 'unrelated user paths must be rejected' panasonic_user_path_allowed "$path"
		assert_false 'unrelated user paths must not reach removal' panasonic_remove_path "$path"
	done
}

main() {
	local expected

	test_path_boundaries

	# Проверяем настоящую фильтрацию очередей для локализованного вывода и принтера за роутером.
	expected='removed:Panasonic_KX_MB1500RU
removed:Shared_Panasonic
removed:Router'
	assert_eq "$expected" "$(panasonic_remove_queues)" 'only Panasonic queues must be removed'

	# Очистка забывает только наши и MFS receipts, сохраняя свой текущий компонент и чужие пакеты.
	expected='forgot:com.panasonic.panasonicMfs.panasonicMfsScanner5.pkg
forgot:com.panasonic.panasonicMfs.ghostscript.pkg
forgot:ru.haikiri.panasonic-kx-mb1500
forgot:ru.haikiri.panasonic-kx-mb1500.print
forgot:ru.haikiri.panasonic-kx-mb1500.scanner
forgot:ru.haikiri.panasonic-kx-mb1500.mfs
forgot:ru.haikiri.panasonic-kx-mb1500.repair'
	assert_eq "$expected" "$(panasonic_forget_packages)" 'only driver package receipts must be forgotten'
	printf 'panasonic_uninstaller tests passed\n'
}

main "$@"
