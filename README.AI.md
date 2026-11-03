# Panasonic KX-MB1500 series driver

Нативный CUPS-драйвер печати и установочные скрипты для Panasonic KX-MB1500 series на macOS.

## Текущий статус

- Скрипты поддерживают `KX-MB1500`, `KX-MB1500RU` и региональные варианты серии `KX-MB1500*`, включая суффиксы вроде `CX`, `HK`, `UC`.
- Серийные номера и локальные USB URI не хранятся в репозитории.
- Docker не используется во время печати или сканирования.
- Dockerfile оставлен только как build/research окружение.
- Нативный CUPS-фильтр `panasonic-kx-mb1500-gdi` реализован как universal Mach-O `arm64+x86_64`.
- Печать не требует Rosetta: системная очередь вызывает arm64 slice фильтра на Apple Silicon.
- Официальный macOS GDI-фильтр Panasonic непригоден для современных macOS ARM: он содержит только `i386/ppc`.
- Для «Захвата изображений» добавлен repair script: он чинит падение официального Panasonic ICA backend на новых macOS через локальный `CarbonShim.dylib`.

## Структура

- `printer/ppd/Panasonic_KX-MB1500-haikiri.ppd` - публичный PPD без локальных идентификаторов.
- `printer/filter/src/panasonic_kx_mb1500_gdi.c` - CUPS raster -> Panasonic GDI/JBIG фильтр.
- `scripts/build-filter.sh` - сборка universal фильтра `arm64+x86_64`.
- `scripts/install-driver.sh` - установка PPD, фильтра, создание CUPS-очереди и best-effort repair scanner backend.
- `scripts/verify-print.sh` - проверка очереди и отправка тестовой страницы в реальный USB-принтер.
- `scripts/repair-scanner-ica.sh` - ремонт установленного `Panasonic MFS Scanner.app` для Image Capture.
- `scripts/build-pkg.sh` - сборка product `.pkg` (печать, вложенный Panasonic `Install.pkg` из DMG, repair ICA; `productbuild` + экран «Настроить»).
- `printer/docker/Dockerfile` - build/research окружение, не runtime печати.
- `artifacts/` - локальные архивы/исходники Panasonic; содержимое не коммитится.

## Требования

- macOS с CUPS.
- Подключённый по USB Panasonic `KX-MB1500`, `KX-MB1500RU` или другой вариант серии `KX-MB1500*`.
- Command Line Tools (`clang`, `install_name_tool`) для сборки фильтра и ремонта старого Image Capture backend.
- Нативный фильтр устанавливается сюда:

```text
/Library/Printers/Panasonic/Filter/panasonic-kx-mb1500-gdi
```

Фильтр принимает `application/vnd.cups-raster` и отдаёт Panasonic GDI/PJL поток.

## Сборка фильтра

```bash
./scripts/build-filter.sh
```

Результат:

```text
printer/filter/bin/panasonic-kx-mb1500-gdi
```

Проверка архитектур:

```bash
file printer/filter/bin/panasonic-kx-mb1500-gdi
```

Ожидаемо: `arm64` и `x86_64`.

## Установка из репозитория

```bash
./scripts/install-driver.sh
```

Опционально: `./scripts/install-driver.sh --ppd-only` ставит только PPD и фильтр (без очереди и без repair); сочетание `./scripts/install-driver.sh --without-scanner-repair` отключает repair при создании очереди.

Команда по умолчанию установит PPD:

```text
/Library/Printers/PPDs/Contents/Resources/Panasonic_KX-MB1500-haikiri.ppd
```

Фильтр:

```text
/Library/Printers/Panasonic/Filter/panasonic-kx-mb1500-gdi
```

И создаст CUPS-очередь по точному имени подключённой модели, например:

```text
Panasonic_KX_MB1500
Panasonic_KX_MB1500RU
Panasonic_KX_MB1500CX
```

Скрипт сам найдёт локальный USB URI через `lpinfo -v`; серийник не записывается в файлы проекта.

Дополнительно полный запуск `./scripts/install-driver.sh` (без `--ppd-only` и без `--without-scanner-repair`) пытается выполнить `repair-scanner-ica.sh` внутри основного install flow:

- если `Panasonic MFS Scanner.app` уже установлен, install flow попробует сразу починить ICA backend для `Image Capture`;
- если scanner app ещё не установлен, этот шаг будет просто пропущен;
- если repair scanner backend завершится ошибкой, установка печати всё равно не упадёт.

## Проверка печати после установки

После установки или переподключения USB-принтера стоит сразу прогнать отдельную проверку тракта печати:

```bash
./scripts/verify-print.sh
```

Скрипт делает только профильную проверку печати:

- убеждается, что очередь для реально подключённой модели серии `KX-MB1500*` существует;
- убеждается, что очередь привязана к точному локальному `usb://Panasonic/KX-MB1500...` URI;
- отправляет короткую тестовую страницу;
- ждёт, пока CUPS переведёт задание в `completed`;
- дополнительно сверяет успешное завершение по `error_log` CUPS.

Ожидаемый результат:

```text
Verified print path for Panasonic_KX_MB1500RU via job Panasonic_KX_MB1500RU-<id>
```

Для моделей без суффикса или с другим суффиксом имя очереди в выводе будет соответствовать точной модели, например `Panasonic_KX_MB1500` или `Panasonic_KX_MB1500CX`.

Это означает, что со стороны macOS/CUPS цепочка `text -> PDF -> CUPS raster -> panasonic-kx-mb1500-gdi -> usb backend` отработала без ошибки.

## Если очередь есть, но печать не идёт

Если в системном UI принтер виден, но задания зависают или появляется сообщение `Не удается отправить данные на принтер`, лучше не гадать, а пройти короткую проверку:

1. Убедиться, что очередь и USB URI живы:

```bash
lpstat -t
```

2. Включить подробный лог CUPS и повторить тест:

```bash
cupsctl --debug-logging
./scripts/verify-print.sh
```

3. Проверить, что в `error_log` для конкретного job есть нормальная последовательность:

```text
Started filter /Library/Printers/Panasonic/Filter/panasonic-kx-mb1500-gdi
Started backend /usr/libexec/cups/backend/usb
Job completed.
```

Если эта последовательность есть, то macOS успешно открыла USB-соединение, прогнала raster через наш нативный фильтр и отправила поток данных в принтер без backend-ошибки.

## Очистка старого Docker-runtime моста

Если ранее ставилась экспериментальная socket/Docker схема, её можно удалить:

```bash
./scripts/remove-legacy-runtime.sh
```

Этот скрипт удаляет старую очередь, LaunchAgent, старый `haikiri` log и системный фильтр `panasonic-mb1500-docker-filter`.

## Сборка pkg

```bash
./scripts/build-pkg.sh 0.1.0
```

Результат:

```text
dist/Panasonic-KX-MB1500-haikiri-0.1.0.pkg
```

Установка пакета:

```bash
sudo installer -pkg dist/Panasonic-KX-MB1500-haikiri-0.1.0.pkg -target /
```

Компонент **печати** внутри продукта ставит PPD, нативный фильтр и helper-скрипты; если принтер подключён по USB во время установки, создаётся CUPS-очередь. Подготовка сканера выполняется при сборке, а не при установке.

Скрипт `./scripts/build-pkg.sh` монтирует `artifacts/Mac_1.15.2.dmg`, извлекает только `Panasonic MFS Scanner.app` из `panasonicMfsScanner.pkg` и подготавливает его существующим repair-скриптом. Сборка `productbuild` включает `scanner.pkg`, `print.pkg` и `cleanup.pkg`. Вложенного `Install.pkg` и вызова `installer` из postinstall нет.

В готовом `.pkg` пользователь выбирает компоненты:

- **Сканер (Rosetta)**: выключен по умолчанию, доступен для включения.
- **Печать**: выбрана всегда, кроме режима очистки; ручное отключение запрещено.
- **Delete Drivers: Panasonic MFS**: выключен по умолчанию; при включении сканер и печать сняты и заблокированы.

После снятия очистки возвращается прежний выбор сканера и обязательная печать.
Взаимное исключение использует `enabled` у choice и `active` у pkg-ref, как в Sasquatch.
Переменные JavaScript текущего сеанса Installer сохраняют галочку сканера на время очистки;
при закрытии установщика этот выбор не сохраняется на диск.

Компонент очистки не имеет payload: `components/cleanup/scripts/postinstall` вызывает соседний
`panasonic-uninstaller.sh`, который сборщик помещает в Scripts. Удаляются только проверенные пути MFS,
очереди Panasonic, профильные настройки пользователей и receipt драйверов.
Документы, сканы, репозитории и другие приложения Panasonic не удаляются.
Общие Ghostscript и libjpeg удаляются только при наличии receipt соответствующего пакета Panasonic.
Receipt самого `cleanup.pkg` остаётся как запись выполненной операции, драйверов он не содержит.

Отдельного пункта Rosetta нет. На Intel scanner backend работает напрямую, на Apple Silicon через Rosetta.

`scripts/services/package-payload.sh` готовит содержимое, `package-builder.sh` собирает компоненты,
`package-distribution.sh` задаёт выбор в Installer. Скрипты установки находятся в `components/`.
В scanner payload входит только приложение с двумя shim; MFS GUI, TWAIN datasource, факс,
pushserver и launch daemon не включаются. Все внешние зависимости scanner app системные.
Пустой component plist фиксирует установку scanner app в `/Library/Image Capture/Devices/`.
На целевом Mac не нужны Command Line Tools.

При запуске из репозитория `./scripts/install-driver.sh` без флагов по-прежнему выполняет best-effort repair, если установлен `Panasonic MFS Scanner.app`. Флаги: `--ppd-only` (только PPD и фильтр), `--without-scanner-repair` (очередь/полная установка без repair).

## Архитектуры

Печатный runtime собирается как universal binary для `arm64` и `x86_64` (`amd64`).

Закрытый Linux-фильтр Panasonic можно использовать только как внешний build-time reference/oracle. Он не участвует в runtime, не ставится в систему и не вызывается CUPS.

## Сканер

### Что важно понимать заранее

Сканирование через стандартное приложение macOS `Image Capture` (`Захват изображений`) для `KX-MB1500` не работает “само по себе”.

Причина в том, что `Image Capture` является только системным UI и ожидает установленный ICA backend производителя. Для этой серии Panasonic таким backend является `Panasonic MFS Scanner.app`, который ставится из официального macOS-пакета `Multi-Function Station`.

Официальная страница Panasonic для Mac:

- [Panasonic Global: Mac driver page for KX-MB1500 series](https://docs.connect.panasonic.com/pcc/support/fax/common/table/macdriver.html)

Официальный прямой файл установщика, который сейчас доступен:

- [Mac_1.15.2.dmg](https://www.psn-web.net/cs/support/fax/common/file/Mac_Installer/Mac_1.15.2.dmg)

Panasonic на этой странице прямо указывает:

- `KX-MB1500 series` поддерживается этим `Mac_1.15.2.dmg`;
- официальная поддержка заявлена для `Mac OS X 10.5 - 10.11`;
- `macOS 10.15 or later is not supported`;
- на `10.12 - 10.14` часть функций может работать не полностью.

То есть на новых macOS это не “официально поддерживаемая” установка, а рабочий compatibility-path через старый Panasonic backend и наш repair-script.

### Полная настройка сканера с нуля

Используется собранный продуктовый `.pkg`, в котором приложение сканера уже подготовлено.

Ниже шаги с чистой системы, чтобы завести сканирование через `Image Capture`.

1. Подключить `Panasonic KX-MB1500*` по USB и включить устройство.

2. Открыть собранный `.pkg`. Установщик работает нативно на Intel и Apple Silicon; печать не требует Rosetta.
3. Печать устанавливается всегда. При необходимости включить «Сканер (Rosetta)» и завершить установку. На Apple Silicon preinstall выбранного сканера устанавливает Rosetta штатным softwareupdate, если Intel-код ещё не запускается. На Intel этот шаг пропускается. Проверок, запрещающих выбор сканера по версии macOS, нет; для работы backend необходима фактическая возможность запуска x86_64.
4. Проверить, что в системе действительно появился ICA backend Panasonic:

```bash
ls -la "/Library/Image Capture/Devices/Panasonic MFS Scanner.app"
```

Если этого `.app` нет, то дальше `Image Capture` не заработает, потому что системе не с чем разговаривать со сканером.

5. Открыть системное приложение `Image Capture`:

```bash
open -a "Image Capture"
```

6. В списке устройств выбрать `Panasonic KX-MB1500*`, задать папку назначения, формат и выполнить тестовый скан.

### Что делает repair-script

`Panasonic MFS Scanner.app` содержит matching для `04da:0f0b`, но на новых macOS падает при запуске из-за перенесённых ICA symbols:

```text
Symbol not found: _kICANotificationImageHeightKey
Expected in: /System/Library/Frameworks/Carbon.framework/Versions/A/Carbon
```

`./scripts/repair-scanner-ica.sh` делает ровно следующее:

- собирает x86_64 `CarbonShim.dylib`;
- реэкспортирует через него системные `Carbon` и `ICADevices`;
- перепривязывает Panasonic binary с `Carbon.framework` на shim;
- добавляет `ObjCMsgFixupShim.dylib` для старого Objective-C ABI и перепривязывает `libobjc`;
- применяет существующее исправление USB handshake;
- переподписывает `.app` ad-hoc;
- в ручном режиме перезапускает `icdd`, чтобы `Image Capture` увидел исправленный backend.

Режим `--prepare-app /путь/к/копии.app` выполняет те же исправления при сборке без root
и перезапуска служб. Системное приложение в этом режиме изменять нельзя.

### Проверка результата

После установки собранного пакета в системе должен существовать такой backend:

```bash
ls -la "/Library/Image Capture/Devices/Panasonic MFS Scanner.app"
```

А `Image Capture` должен показывать устройство без падения Panasonic backend при обращении к сканеру.

### Ограничения

- Без официального `Panasonic MFS Scanner.app` сканирование через `Image Capture` не заработает: одного принтера, PPD и CUPS-недостаточно.
- Официальный Panasonic macOS scanner backend остаётся `x86_64`, поэтому на Apple Silicon он зависит от Rosetta.
- Когда Apple окончательно уберёт Rosetta, для сканера понадобится либо нативный `arm64` backend, либо собственная реализация USB-протокола сканера без Panasonic software.
