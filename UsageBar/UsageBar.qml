import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "." as UB

PluginComponent {
    id: root
    layerNamespacePlugin: "usage-bar"
    popoutWidth: 360

    readonly property var backend: UB.UsageBackend
    readonly property string mainProvider: pluginData.mainProvider || "claude"
    readonly property string barMetric: pluginData.barMetric || "max"
    readonly property bool showBoth: (pluginData.barShows || "main") === "both"
    readonly property var shownProviders: showBoth
        ? [mainProvider].concat(backend.providerIds.filter(id => id !== mainProvider))
        : [mainProvider]

    onPluginDataChanged: backend.refreshMinutes = parseInt(pluginData.refreshMinutes || "5") || 5
    Component.onCompleted: {
        backend.refreshMinutes = parseInt(pluginData.refreshMinutes || "5") || 5
        backend.attachWidget(root)
    }
    Component.onDestruction: backend.detachWidget(root)

    function setMainProvider(id) {
        if (pluginService) pluginService.savePluginData(pluginId, "mainProvider", id)
    }

    function levelColor(percent, fallback) {
        if (percent === null || percent === undefined) return fallback
        if (percent >= 90) return Theme.error
        if (percent >= 75) return Theme.warning
        return fallback
    }

    function pillText(id) {
        const m = backend.metric(id, barMetric)
        return m ? Math.round(m.percent) + "%" : (backend.loading ? "…" : "—")
    }

    function pillColor(id) {
        const p = backend.providers[id]
        const m = backend.metric(id, barMetric)
        if (!m) return p && p.error ? Theme.error : Theme.surfaceTextMedium
        return levelColor(m.percent, Theme.surfaceText)
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            Repeater {
                model: root.shownProviders
                Row {
                    required property string modelData
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.backend.providerMeta[modelData].icon
                        size: root.iconSize
                        color: root.pillColor(modelData)
                        filled: modelData === root.mainProvider
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pillText(modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: root.pillColor(modelData)
                        opacity: root.backend.providers[modelData] && root.backend.providers[modelData].stale ? 0.6 : 1
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2
            Repeater {
                model: root.shownProviders
                Column {
                    required property string modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    DankIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: root.backend.providerMeta[modelData].icon
                        size: root.iconSize
                        color: root.pillColor(modelData)
                        filled: modelData === root.mainProvider
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.pillText(modelData).replace("%", "")
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: root.pillColor(modelData)
                    }
                }
            }
        }
    }

    popoutContent: Component {
        UsagePanel { widget: root; backend: root.backend }
    }
}
