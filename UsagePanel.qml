import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PopoutComponent {
    id: panel
    required property var widget
    required property var backend
    readonly property bool shown: parentPopout ? parentPopout.shouldBeVisible : visible

    headerText: ""
    showCloseButton: false
    spacing: Theme.spacingM

    onShownChanged: if (shown) backend.refreshIfStale()
    Component.onCompleted: backend.refreshIfStale()

    // ── header ──
    Item {
        width: parent.width
        height: 36
        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            text: "AI usage"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.backend.loading ? "Updating…" : "Updated " + panel.backend.formatAgo(panel.backend.lastFetch)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextMedium
            }
            DankActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "refresh"
                buttonSize: 30
                enabled: !panel.backend.loading
                opacity: enabled ? 1 : 0.4
                tooltipText: "Refresh now"
                onClicked: panel.backend.refresh()
            }
        }
    }

    Repeater {
        model: [panel.widget.mainProvider].concat(panel.backend.providerIds.filter(id => id !== panel.widget.mainProvider))

        Rectangle {
            id: card
            required property string modelData
            readonly property var info: panel.backend.providers[modelData] || ({})
            readonly property var meta: panel.backend.providerMeta[modelData]
            readonly property bool isMain: modelData === panel.widget.mainProvider
            readonly property var windows: info.windows || []

            width: panel.width
            height: cardColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: cardColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                // provider header
                Item {
                    width: parent.width
                    height: 28
                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            sourceSize: Qt.size(40, 40)
                            smooth: true
                            source: Qt.resolvedUrl(card.meta.logo.replace("%1", Theme.isLightMode ? "light" : "dark"))
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.meta.name
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
                        Rectangle {
                            visible: !!card.info.plan
                            anchors.verticalCenter: parent.verticalCenter
                            width: planText.implicitWidth + Theme.spacingS * 2
                            height: 20
                            radius: 10
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                            StyledText {
                                id: planText
                                anchors.centerIn: parent
                                text: card.info.plan || ""
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.primary
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        DankActionButton {
                            iconName: "open_in_new"
                            buttonSize: 28
                            iconSize: 16
                            visible: !!card.info.dashboardUrl
                            tooltipText: "Open usage page"
                            onClicked: Qt.openUrlExternally(card.info.dashboardUrl)
                        }
                        // DankActionButton can't fill its icon, so build the same thing with a filled star.
                        StyledRect {
                            width: 28
                            height: 28
                            radius: Theme.cornerRadius
                            color: "transparent"
                            DankIcon {
                                anchors.centerIn: parent
                                name: "star"
                                size: 18
                                filled: card.isMain
                                color: card.isMain ? Theme.primary : Theme.surfaceTextMedium
                            }
                            StateLayer {
                                stateColor: Theme.primary
                                cornerRadius: parent.radius
                                tooltipText: card.isMain ? "Shown in bar" : "Show in bar"
                                onClicked: panel.widget.setMainProvider(card.modelData)
                            }
                        }
                    }
                }

                // windows
                Repeater {
                    model: card.windows
                    Column {
                        required property var modelData
                        width: cardColumn.width
                        spacing: 4
                        opacity: card.info.stale ? 0.6 : 1

                        Item {
                            width: parent.width
                            height: labelText.implicitHeight
                            StyledText {
                                id: labelText
                                anchors.left: parent.left
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: modelData.secondary ? Font.Normal : Font.Medium
                                color: modelData.secondary ? Theme.surfaceTextMedium : Theme.surfaceText
                            }
                            StyledText {
                                anchors.right: parent.right
                                text: Math.round(modelData.percent) + "% used"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: panel.widget.levelColor(modelData.percent, Theme.surfaceText)
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: modelData.secondary ? 4 : 6
                            radius: height / 2
                            color: Theme.surfaceContainerHighest
                            Rectangle {
                                width: parent.width * Math.min(100, modelData.percent) / 100
                                height: parent.height
                                radius: parent.radius
                                color: panel.widget.levelColor(modelData.percent, Theme.primary)
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                        }
                        StyledText {
                            visible: text.length > 0
                            text: panel.backend.formatReset(modelData.resetsAt)
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceTextMedium
                        }
                    }
                }

                // extra usage / credits
                Item {
                    visible: !!card.info.extra
                    width: parent.width
                    height: extraLabel.implicitHeight
                    StyledText {
                        id: extraLabel
                        text: card.info.extra ? card.info.extra.label : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                    StyledText {
                        anchors.right: parent.right
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        text: {
                            const e = card.info.extra
                            if (!e) return ""
                            if (e.text) return e.text
                            return "$" + e.used.toFixed(2) + " / $" + e.limit.toFixed(2)
                        }
                    }
                }

                // empty / error state
                StyledText {
                    visible: !card.windows.length && !card.info.error
                    text: panel.backend.loading ? "Loading…" : "No usage data"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextMedium
                }
                Row {
                    visible: !!card.info.error
                    width: parent.width
                    spacing: Theme.spacingXS
                    DankIcon {
                        id: errIcon
                        name: card.info.errorKind === "offline" ? "cloud_off" : card.info.errorKind === "ratelimit" ? "schedule" : "error"
                        size: 16
                        color: card.info.errorKind === "ratelimit" || card.info.errorKind === "offline" ? Theme.surfaceTextMedium : Theme.error
                    }
                    StyledText {
                        width: parent.width - errIcon.width - Theme.spacingXS
                        text: (card.info.stale ? "Showing last data (" + panel.backend.formatAgo(card.info.updatedAt) + "). " : "") + (card.info.error || "")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceTextMedium
                    }
                }
            }
        }
    }
}
