#!/usr/bin/env bash

write_package_distribution() {
	local distribution_path="$1"
	local version="$2"

	# Установка драйверов и очистка не должны выполняться одновременно.
	cat > "$distribution_path" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Panasonic KX-MB1500</title>
    <options customize="always" require-scripts="true" rootVolumeOnly="true" hostArchitectures="x86_64,arm64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <choices-outline>
        <line choice="scanner"/>
        <line choice="print"/>
        <line choice="cleanup"/>
    </choices-outline>
    <choice id="scanner" title="Сканер (Rosetta)" description="" start_selected="false"
        selected="scannerSelection()"
        enabled="!choices.cleanup.selected">
        <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.scanner"/>
    </choice>
    <choice id="print" title="Печать" description="" start_selected="true"
        selected="!choices.cleanup.selected" enabled="false">
        <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.print"/>
    </choice>
    <choice id="cleanup" title="Delete Drivers: Panasonic MFS" description="" start_selected="false">
        <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.cleanup"/>
    </choice>
    <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.scanner" version="$version" auth="Root"
        active="!choices.cleanup.selected">scanner.pkg</pkg-ref>
    <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.print" version="$version" auth="Root"
        active="!choices.cleanup.selected">print.pkg</pkg-ref>
    <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.cleanup" version="$version" auth="Root">cleanup.pkg</pkg-ref>
    <script><![CDATA[
        var scannerBeforeCleanup = false;
        var cleanupWasSelected = false;

        function scannerSelection() {
            var cleanupSelected = choices.cleanup.selected;
            var scannerSelected = choices.scanner.selected;

            // Сохраняем выбор только при переходе в режим очистки.
            if (cleanupSelected) {
                if (!cleanupWasSelected) {
                    scannerBeforeCleanup = scannerSelected;
                }
                cleanupWasSelected = true;
                return false;
            }

            // Возвращаем галочку после отключения очистки.
            if (cleanupWasSelected) {
                cleanupWasSelected = false;
                return scannerBeforeCleanup;
            }

            return scannerSelected;
        }
    ]]></script>
</installer-gui-script>
XML
}
