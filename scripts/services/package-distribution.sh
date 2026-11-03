#!/usr/bin/env bash

write_package_distribution() {
	local distribution_path="$1"
	local version="$2"

	# Нативная печать устанавливается всегда, сканер пользователь выбирает отдельно.
	cat > "$distribution_path" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Panasonic KX-MB1500</title>
    <options customize="always" require-scripts="true" rootVolumeOnly="true" hostArchitectures="x86_64,arm64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <choices-outline>
        <line choice="print"/>
        <line choice="scanner"/>
    </choices-outline>
    <choice id="scanner" title="Сканер (Rosetta)" description="" start_selected="false" enabled="true">
        <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.scanner"/>
    </choice>
    <choice id="print" title="Печать" description="" start_selected="true" selected="true" enabled="false">
        <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.print"/>
    </choice>
    <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.scanner" version="$version" auth="Root">scanner.pkg</pkg-ref>
    <pkg-ref id="ru.haikiri.panasonic-kx-mb1500.print" version="$version" auth="Root">print.pkg</pkg-ref>
</installer-gui-script>
XML
}
