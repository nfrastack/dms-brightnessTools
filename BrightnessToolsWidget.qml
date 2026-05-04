import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var variantId: null
    property var variantData: null

    readonly property string devKey: variantData?.device ?? ""
    readonly property string devClass: devKey.indexOf(":") >= 0 ? devKey.substring(0, devKey.indexOf(":")) : ""
    readonly property string devName: devKey.indexOf(":") >= 0 ? devKey.substring(devKey.indexOf(":") + 1) : ""
    readonly property string iconName: variantData?.icon ?? "brightness_6"
    readonly property string label: variantData?.name ?? "Brightness"
    readonly property bool useOSD: variantData?.useOSD ?? true
    readonly property bool showInBar: variantData?.showInBar ?? true
    readonly property bool showInControlCenter: variantData?.showInControlCenter ?? false
    readonly property int minPct: variantData?.minPercent ?? 1
    readonly property int stepPct: variantData?.step ?? 5

    property int curRaw: 0
    property int curMax: 1
    readonly property int curPct: curMax > 0 ? Math.round(100 * curRaw / curMax) : 0

    Connections {
        target: pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId && root.variantId) {
                root.variantData = pluginService.getPluginVariantData(root.pluginId, root.variantId);
            }
        }
    }

    FileView {
        id: brightnessFile
        path: root.devClass && root.devName ? `/sys/class/${root.devClass}/${root.devName}/brightness` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text());
            if (!isNaN(v)) root.curRaw = v;
        }
    }

    FileView {
        id: maxFile
        path: root.devClass && root.devName ? `/sys/class/${root.devClass}/${root.devName}/max_brightness` : ""
        onLoaded: {
            const v = parseInt(text());
            if (!isNaN(v) && v > 0) root.curMax = v;
        }
    }

    function setPct(pct) {
        if (!root.devKey) return;
        pct = Math.max(root.minPct, Math.min(100, Math.round(pct)));
        if (root.useOSD) {
            Quickshell.execDetached(["dms", "ipc", "call", "brightness", "set", String(pct), root.devKey]);
        } else {
            Quickshell.execDetached(["brightnessctl", "-d", root.devName, "set", pct + "%"]);
        }
    }

    function bumpPct(delta) { setPct(curPct + delta); }

    horizontalBarPill: showInBar ? horizontalPillComponent : null
    verticalBarPill: showInBar ? verticalPillComponent : null

    Component {
        id: horizontalPillComponent
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.iconName
                size: root.iconSize
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.curPct + "%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Component {
        id: verticalPillComponent
        Column {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.iconName
                size: root.iconSize
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.curPct + "%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 320
    popoutHeight: 140

    popoutContent: Component {
        PopoutComponent {
            headerText: root.label
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    text: root.devKey || "No device configured"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideMiddle
                    width: parent.width
                }

                DankSlider {
                    width: parent.width
                    minimum: 0
                    maximum: 100
                    value: root.curPct
                    unit: "%"
                    leftIcon: root.iconName
                    onSliderValueChanged: v => root.setPct(v)
                    onSliderDragFinished: v => root.setPct(v)
                }
            }
        }
    }

    // CC discovery probes the component with no variantData injected and only
    // registers ONE entry per plugin (not per variant). So advertise CC capability
    // unconditionally; the detail panel below renders all variants flagged for CC.
    ccWidgetIcon: "brightness_6"
    ccWidgetPrimaryText: "Brightness"
    ccWidgetSecondaryText: variantData ? (root.curPct + "%") : ""
    ccWidgetIsToggle: false
    ccDetailHeight: 280

    readonly property var ccVariants: {
        const all = pluginData.variants ?? [];
        return all.filter(v => v && v.showInControlCenter === true);
    }

    ccDetailContent: Component {
        Rectangle {
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                StyledText {
                    text: "Brightness"
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                    font.weight: Font.Medium
                }

                StyledText {
                    visible: root.ccVariants.length === 0
                    text: "No sliders flagged for control center. Enable \"Show in control center\" on a slider in plugin settings."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }

                Repeater {
                    model: root.ccVariants
                    delegate: Column {
                        required property var modelData
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: modelData.name || modelData.device || "Slider"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        DankSlider {
                            width: parent.width
                            minimum: 0
                            maximum: 100
                            value: root.percentForVariant(modelData)
                            unit: "%"
                            leftIcon: modelData.icon || "brightness_6"
                            onSliderValueChanged: v => root.setPctForVariant(modelData, v)
                            onSliderDragFinished: v => root.setPctForVariant(modelData, v)
                        }
                    }
                }
            }
        }
    }

    function variantDevName(v) {
        if (!v || !v.device) return "";
        const i = v.device.indexOf(":");
        return i >= 0 ? v.device.substring(i + 1) : v.device;
    }

    function setPctForVariant(v, pct) {
        if (!v || !v.device) return;
        pct = Math.max(v.minPercent ?? 1, Math.min(100, Math.round(pct)));
        const useO = v.useOSD !== false;
        if (useO) {
            Quickshell.execDetached(["dms", "ipc", "call", "brightness", "set", String(pct), v.device]);
        } else {
            Quickshell.execDetached(["brightnessctl", "-d", variantDevName(v), "set", pct + "%"]);
        }
    }

    function percentForVariant(v) {
        // Best-effort: read sysfs synchronously is messy, just default to 50 for the slider initial position.
        // The slider acts as input rather than display in CC mode.
        return 50;
    }
}
