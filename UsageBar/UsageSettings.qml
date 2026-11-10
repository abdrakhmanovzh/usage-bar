import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "usageBar"

    StyledText {
        width: parent.width
        text: "Usage Bar"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Reads the sign-in your Claude Code and Codex CLIs already use (~/.claude/.credentials.json, ~/.codex/auth.json). Tokens are never modified or sent anywhere except the providers' own usage endpoints."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "mainProvider"
        label: "Main subscription"
        description: "Shown in the bar. You can also pick it with the star in the popout."
        options: [{label: "Claude", value: "claude"}, {label: "Codex", value: "codex"}]
        defaultValue: "claude"
    }

    SelectionSetting {
        settingKey: "barMetric"
        label: "Bar percentage"
        description: "Which limit the bar percentage tracks"
        options: [
            {label: "Most constrained limit", value: "max"},
            {label: "Session (shortest window)", value: "session"},
            {label: "Weekly", value: "weekly"}
        ]
        defaultValue: "max"
    }

    SelectionSetting {
        settingKey: "barShows"
        label: "Bar shows"
        options: [{label: "Main subscription only", value: "main"}, {label: "Both subscriptions", value: "both"}]
        defaultValue: "main"
    }

    SelectionSetting {
        settingKey: "refreshMinutes"
        label: "Refresh interval"
        description: "The usage endpoints rate-limit aggressive polling; 5 minutes is a safe default."
        options: [
            {label: "1 minute", value: "1"},
            {label: "2 minutes", value: "2"},
            {label: "5 minutes", value: "5"},
            {label: "10 minutes", value: "10"},
            {label: "15 minutes", value: "15"}
        ]
        defaultValue: "5"
    }
}
