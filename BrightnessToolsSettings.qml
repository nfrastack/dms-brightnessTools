import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "icons.js" as Icons

PluginSettings {
    id: root
    pluginId: "brightnessPills"

    // PluginSettings does NOT inherit pluginData from PluginComponent — mirror it manually.
    property var pluginData: ({})
    function _reloadPluginData() {
        try {
            if (pluginService && pluginId)
                pluginData = SettingsData.getPluginSettingsForPlugin(pluginId);
        } catch (e) {
            console.warn("brightnessPills settings: pluginData reload failed:", e);
        }
    }
    Connections {
        target: pluginService
        enabled: pluginService !== null
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId) root._reloadPluginData();
        }
    }
    // Don't override PluginSettings's built-in Component.onCompleted (which calls loadVariants())
    // or its onPluginServiceChanged. A self-firing Timer is the safe way to schedule a one-shot
    // init without touching parent handlers.
    Connections {
        target: root
        function onPluginServiceChanged() { root._reloadPluginData(); }
    }
    Timer {
        running: true
        interval: 0
        onTriggered: root._reloadPluginData()
    }

    property var iconNames: Icons.names

    property int selectedIndex: 0
    property var selectedVariant: variants.length > 0 && selectedIndex >= 0 && selectedIndex < variants.length
        ? variants[selectedIndex] : null

    property bool _syncing: false
    onSelectedVariantChanged: {
        if (!selectedVariant) return;
        _syncing = true;
        nameField.text = selectedVariant.name ?? "";
        deviceDropdownLoader.active = false;
        deviceDropdownLoader.active = true;
        iconDropdownLoader.active = false;
        iconDropdownLoader.active = true;
        showInBarToggle.checked = selectedVariant.showInBar !== false;
        showInCCToggle.checked = selectedVariant.showInControlCenter === true;
        useOSDToggle.checked = selectedVariant.useOSD !== false;
        minPctSlider.value = selectedVariant.minPercent ?? 1;
        stepSlider.value = selectedVariant.step ?? 5;
        _syncing = false;
    }

    onVariantsChanged: {
        if (selectedIndex >= variants.length) {
            selectedIndex = Math.max(0, variants.length - 1);
        }
    }

    property int widgetCounter: 0
    function nextWidgetName() {
        widgetCounter++;
        return "Slider " + widgetCounter;
    }

    function saveFieldFor(variantId, key, value) {
        if (!variantId) return;
        let config = {};
        config[key] = value;
        updateVariant(variantId, config);
    }

    function saveField(key, value) {
        if (!selectedVariant) return;
        saveFieldFor(selectedVariant.id, key, value);
    }

    property string _pendingKey: ""
    property string _pendingValue: ""
    property string _pendingVariantId: ""
    Timer {
        id: saveDebounce
        interval: 500
        onTriggered: {
            if (root._pendingKey !== "" && root._pendingVariantId !== "")
                root.saveFieldFor(root._pendingVariantId, root._pendingKey, root._pendingValue);
        }
    }
    function debounceSave(key, value, field) {
        if (_syncing) return;
        if (field && !field.getActiveFocus()) return;
        _pendingKey = key;
        _pendingValue = value;
        _pendingVariantId = selectedVariant ? selectedVariant.id : "";
        saveDebounce.restart();
    }
    function flushPendingSave() {
        if (saveDebounce.running) {
            saveDebounce.stop();
            if (_pendingKey !== "" && _pendingVariantId !== "")
                saveFieldFor(_pendingVariantId, _pendingKey, _pendingValue);
            _pendingKey = "";
            _pendingVariantId = "";
        }
    }

    // -- Device discovery ----------------------------------------------------

    property var deviceList: pluginData.deviceList ?? []
    property bool refreshing: false
    property string refreshError: ""

    Process {
        id: refreshProc
        command: ["dms", "brightness", "list"]
        running: false

        property string buffer: ""

        stdout: SplitParser {
            onRead: data => { refreshProc.buffer += data + "\n"; }
        }

        onRunningChanged: {
            if (running) {
                buffer = "";
                root.refreshing = true;
                root.refreshError = "";
                return;
            }
            root.refreshing = false;
            const parsed = parseBrightnessList(buffer);
            if (parsed.length === 0) {
                // Fall back to sysfs scan
                sysfsScan.running = true;
            } else {
                pluginService.savePluginData("brightnessPills", "deviceList", parsed);
                root.deviceList = parsed;
                deviceDropdownLoader.active = false;
                deviceDropdownLoader.active = true;
            }
        }
    }

    Process {
        id: sysfsScan
        command: ["sh", "-c",
                 "for d in /sys/class/backlight/*; do [ -d \"$d\" ] && echo \"backlight:$(basename $d)\"; done; " +
                 "for d in /sys/class/leds/*; do [ -d \"$d\" ] && echo \"leds:$(basename $d)\"; done"]
        running: false

        property string buffer: ""

        stdout: SplitParser {
            onRead: data => { sysfsScan.buffer += data + "\n"; }
        }

        onRunningChanged: {
            if (running) { buffer = ""; return; }
            const lines = buffer.split("\n").map(l => l.trim()).filter(l => l.length > 0);
            const parsed = lines.map(l => ({ id: l, name: l }));
            if (parsed.length === 0) {
                root.refreshError = "No devices found via dms brightness list or sysfs.";
                return;
            }
            pluginService.savePluginData("brightnessPills", "deviceList", parsed);
            root.deviceList = parsed;
            deviceDropdownLoader.active = false;
            deviceDropdownLoader.active = true;
        }
    }

    function parseBrightnessList(text) {
        const out = [];
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!line || line.length === 0) continue;
            // Skip header and rule lines
            if (line.indexOf("Device") === 0) continue;
            if (line.indexOf("─") >= 0 || line.indexOf("---") === 0) continue;
            // First whitespace-separated token is the device id
            const m = line.match(/^(\S+)\s+(\S+)\s+(\S.*?)\s+(\S+)\s*$/);
            if (m) {
                out.push({ id: m[1], name: m[1] + "  (" + m[2] + ")" });
            } else {
                const tok = line.trim().split(/\s+/)[0];
                if (tok && tok.indexOf(":") > 0) out.push({ id: tok, name: tok });
            }
        }
        return out;
    }

    Component.onCompleted: {
        if (!pluginData.deviceList || pluginData.deviceList.length === 0) {
            refreshProc.running = true;
        }
    }

    function deviceIds() {
        return (root.deviceList || []).map(d => d.id);
    }

    // -- Page content --------------------------------------------------------

    StyledText {
        width: parent.width
        text: "Brightness Pills"
        font.pixelSize: Appearance.fontSize.large
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Add a slider per device. Each variant becomes its own bar pill and/or control-center entry."
        font.pixelSize: Appearance.fontSize.small
        color: Theme.surfaceVariantText
    }

    Row {
        spacing: Theme.spacingS

        DankButton {
            text: root.refreshing ? "Refreshing..." : "Refresh devices"
            iconName: "refresh"
            buttonHeight: 28
            horizontalPadding: Theme.spacingS
            iconSize: 16
            enabled: !root.refreshing
            onClicked: refreshProc.running = true
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.deviceList.length > 0
                ? root.deviceList.length + " device(s) detected"
                : (root.refreshError || "No devices yet")
            font.pixelSize: Appearance.fontSize.small
            color: root.refreshError ? Theme.error : Theme.surfaceVariantText
        }
    }

    // -- Empty state --

    Item { width: 1; height: Appearance.spacing.small; visible: root.variants.length === 0 }

    DankButton {
        visible: root.variants.length === 0
        text: "Add Slider"
        iconName: "add"
        buttonHeight: 28
        horizontalPadding: Theme.spacingS
        iconSize: 16
        onClicked: {
            const firstDevice = root.deviceList.length > 0 ? root.deviceList[0].id : "";
            createVariant(root.nextWidgetName(), {
                device: firstDevice,
                icon: "brightness_6",
                showInBar: true,
                showInControlCenter: false,
                useOSD: true,
                minPercent: 1,
                step: 5
            });
            loadVariants();
            root.selectedIndex = 0;
        }
    }

    // -- Variants list --

    Column {
        visible: root.variants.length > 0
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: "Sliders"
            font.pixelSize: Appearance.fontSize.normal
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        Column {
            id: variantList
            width: parent.width
            spacing: Theme.spacingXS

            Repeater {
                model: root.variantsModel

                delegate: Rectangle {
                    id: variantRow
                    required property int index
                    required property var model
                    width: variantList.width
                    height: rowContent.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: "transparent"
                    border.width: 1
                    border.color: index === root.selectedIndex
                        ? Theme.primary
                        : (rowMouseArea.containsMouse ? Theme.outline : Theme.outlineMedium)

                    Row {
                        id: rowContent
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        DankIcon {
                            name: variantRow.model.icon || "brightness_6"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: rowContent.width - rowContent.spacing * 2 - deleteBtn.width - Theme.iconSizeSmall

                            StyledText {
                                text: variantRow.model.name || "Unnamed"
                                font.pixelSize: Appearance.fontSize.small
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            StyledText {
                                text: variantRow.model.device || "(no device)"
                                font.pixelSize: Appearance.fontSize.small
                                color: Theme.surfaceVariantText
                                elide: Text.ElideMiddle
                                width: parent.width
                            }
                        }

                        Rectangle {
                            id: deleteBtn
                            width: 28
                            height: 28
                            radius: 14
                            color: deleteArea.containsMouse ? Theme.errorHover : "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            DankIcon {
                                anchors.centerIn: parent
                                name: "delete"
                                size: 16
                                color: deleteArea.containsMouse ? Theme.error : Theme.surfaceVariantText
                            }

                            MouseArea {
                                id: deleteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: removeVariant(variantRow.model.id)
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.flushPendingSave();
                            root.selectedIndex = variantRow.index;
                        }
                        z: -1
                    }
                }
            }
        }

        Item { width: 1; height: Appearance.spacing.small }

        DankButton {
            text: "Add Another Slider"
            iconName: "add"
            buttonHeight: 28
            horizontalPadding: Theme.spacingS
            iconSize: 16
            onClicked: {
                const firstDevice = root.deviceList.length > 0 ? root.deviceList[0].id : "";
                createVariant(root.nextWidgetName(), {
                    device: firstDevice,
                    icon: "brightness_6",
                    showInBar: true,
                    showInControlCenter: false,
                    useOSD: true,
                    minPercent: 1,
                    step: 5
                });
                loadVariants();
                root.selectedIndex = root.variants.length - 1;
            }
        }
    }

    // -- Per-variant form --

    Column {
        visible: root.selectedVariant !== null
        width: parent.width
        spacing: Theme.spacingM

        Column {
            width: parent.width
            spacing: Theme.spacingXS

            StyledText {
                text: "Name"
                font.pixelSize: Appearance.fontSize.normal
                color: Theme.surfaceText
            }

            DankTextField {
                id: nameField
                width: parent.width
                text: root.selectedVariant?.name ?? ""
                placeholderText: "Slider name"
                onTextEdited: root.debounceSave("name", text, nameField)
                onEditingFinished: root.flushPendingSave()
            }
        }

        Loader {
            id: deviceDropdownLoader
            width: parent.width
            active: true
            sourceComponent: DankDropdown {
                id: deviceDropdown
                text: "Device"
                description: "Select a backlight or LED device"
                enableFuzzySearch: true
                dropdownWidth: 320
                options: root.deviceIds()
                currentValue: root.selectedVariant?.device ?? ""
                onValueChanged: value => {
                    if (root.selectedVariant) root.selectedVariant.device = value;
                    root.saveField("device", value);
                }
            }
        }

        Loader {
            id: iconDropdownLoader
            width: parent.width
            active: true
            sourceComponent: DankDropdown {
                id: iconDropdown
                text: "Icon"
                description: "Material Design icon"
                enableFuzzySearch: true
                dropdownWidth: 280
                options: root.iconNames
                optionIcons: root.iconNames
                currentValue: root.selectedVariant?.icon ?? "brightness_6"
                onValueChanged: value => {
                    if (root.selectedVariant) root.selectedVariant.icon = value;
                    root.saveField("icon", value);
                    if (typeof iconDropdown.resetSearch === "function") {
                        iconDropdown.resetSearch();
                    } else {
                        iconReloadTimer.restart();
                    }
                }
            }
        }

        Timer {
            id: iconReloadTimer
            interval: 100
            onTriggered: {
                iconDropdownLoader.active = false;
                iconDropdownLoader.active = true;
            }
        }

        DankToggle {
            id: showInBarToggle
            width: parent.width
            text: "Show as bar pill"
            description: "Render this slider as a pill in the DankBar"
            checked: root.selectedVariant?.showInBar !== false
            onToggled: isChecked => {
                checked = isChecked;
                root.saveField("showInBar", isChecked);
            }
        }

        DankToggle {
            id: showInCCToggle
            width: parent.width
            text: "Include in control center"
            description: "Add this slider to the single 'Brightness' panel in the control center (DMS only allows one CC entry per plugin, so all flagged sliders share that panel)"
            checked: root.selectedVariant?.showInControlCenter === true
            onToggled: isChecked => {
                checked = isChecked;
                root.saveField("showInControlCenter", isChecked);
            }
        }

        DankToggle {
            id: useOSDToggle
            width: parent.width
            text: "Show OSD when adjusting"
            description: "Use dms ipc (with OSD overlay) instead of silent brightnessctl"
            checked: root.selectedVariant?.useOSD !== false
            onToggled: isChecked => {
                checked = isChecked;
                root.saveField("useOSD", isChecked);
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingXS

            StyledText {
                text: "Minimum Percent"
                font.pixelSize: Appearance.fontSize.normal
                color: Theme.surfaceText
            }
            StyledText {
                text: "Floor for the slider — some LEDs feel broken at 0"
                font.pixelSize: Appearance.fontSize.small
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }
            DankSlider {
                id: minPctSlider
                width: parent.width
                value: root.selectedVariant?.minPercent ?? 1
                minimum: 0
                maximum: 100
                unit: "%"
                leftIcon: "vertical_align_bottom"
                onSliderDragFinished: finalValue => root.saveField("minPercent", finalValue)
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingXS

            StyledText {
                text: "Step"
                font.pixelSize: Appearance.fontSize.normal
                color: Theme.surfaceText
            }
            StyledText {
                text: "Wheel/keyboard increment in percent"
                font.pixelSize: Appearance.fontSize.small
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }
            DankSlider {
                id: stepSlider
                width: parent.width
                value: root.selectedVariant?.step ?? 5
                minimum: 1
                maximum: 25
                unit: "%"
                leftIcon: "tune"
                onSliderDragFinished: finalValue => root.saveField("step", finalValue)
            }
        }
    }
}
