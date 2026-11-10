pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One poller shared by every bar instance (multi-monitor safe).
Singleton {
    id: root

    readonly property var providerIds: ["claude", "codex"]
    readonly property var providerMeta: ({
        claude: {name: "Claude", icon: "auto_awesome", logo: "icons/claude.svg"},
        codex: {name: "Codex", icon: "terminal", logo: "icons/openai-%1.svg"}
    })

    // Per provider: {ok, plan, windows, extra, error, errorKind, updatedAt, stale}
    property var providers: ({})
    property bool loading: false
    property int lastFetch: 0
    property int refreshMinutes: 5
    property int widgetCount: 0
    property real now: Date.now() / 1000

    readonly property string scriptPath: Qt.resolvedUrl("usage-fetch.py").toString().replace("file://", "")

    property var widgets: []

    function attachWidget(widget) {
        widgets = widgets.concat([widget])
        widgetCount++
        if (widgetCount === 1) refresh()
    }

    function detachWidget(widget) {
        widgets = widgets.filter(w => w !== widget)
        widgetCount = Math.max(0, widgetCount - 1)
    }

    // `dms ipc call usageBar toggle|refresh` (bindable from niri)
    IpcHandler {
        target: "usageBar"
        function toggle(): string {
            const w = root.widgets[0]
            if (!w) return "NO_WIDGET"
            w.triggerPopout()
            return "OK"
        }
        function refresh(): string {
            root.refresh()
            return "OK"
        }
    }

    function refresh() {
        if (fetcher.running) return
        loading = true
        fetcher.output = ""
        fetcher.running = true
    }

    // Refresh on popout open if the data is older than a minute.
    function refreshIfStale() {
        if (now - lastFetch > 60) refresh()
    }

    function ingest(text) {
        let packet
        try { packet = JSON.parse(text) } catch (e) {
            markAllFailed("Usage fetcher returned invalid output")
            return
        }
        const next = Object.assign({}, providers)
        for (const id of providerIds) {
            const r = (packet.providers || {})[id]
            if (!r) continue
            const prev = providers[id]
            if (r.ok) {
                next[id] = Object.assign({}, r, {updatedAt: packet.fetchedAt, stale: false})
            } else if (prev && prev.windows && prev.windows.length) {
                // Keep the last good numbers visible, flagged as stale.
                next[id] = Object.assign({}, prev, {error: r.error, errorKind: r.errorKind, stale: true})
            } else {
                next[id] = r
            }
        }
        providers = next
        lastFetch = packet.fetchedAt || Math.floor(Date.now() / 1000)
    }

    function markAllFailed(message) {
        const next = Object.assign({}, providers)
        for (const id of providerIds) {
            const prev = providers[id] || {}
            next[id] = Object.assign({}, prev, {error: message, errorKind: "error", stale: !!prev.windows})
        }
        providers = next
    }

    // ── helpers used by bar + popout ──

    function primaryWindows(id) {
        const p = providers[id]
        return p && p.windows ? p.windows.filter(w => !w.secondary) : []
    }

    // mode: "max" (most constrained), "session" (shortest window), "weekly"
    function metric(id, mode) {
        const all = providers[id] && providers[id].windows ? providers[id].windows : []
        const main = all.filter(w => !w.secondary)
        if (!all.length) return null
        if (mode === "session") {
            const s = main.slice().sort((a, b) => (a.windowSeconds || 0) - (b.windowSeconds || 0))[0]
            if (s) return s
        } else if (mode === "weekly") {
            const w = main.find(x => x.windowSeconds === 604800)
            if (w) return w
        }
        return all.reduce((a, b) => (b.percent > a.percent ? b : a))
    }

    function formatReset(epoch) {
        if (!epoch) return ""
        let s = Math.max(0, Math.round(epoch - now))
        if (s < 60) return "Resets now"
        const d = Math.floor(s / 86400); s -= d * 86400
        const h = Math.floor(s / 3600); s -= h * 3600
        const m = Math.floor(s / 60)
        if (d > 0) return "Resets in " + d + "d " + h + "h"
        if (h > 0) return "Resets in " + h + "h " + m + "m"
        return "Resets in " + m + "m"
    }

    function formatAgo(epoch) {
        if (!epoch) return "never"
        const s = Math.max(0, Math.round(now - epoch))
        if (s < 60) return "just now"
        if (s < 3600) return Math.floor(s / 60) + "m ago"
        return Math.floor(s / 3600) + "h ago"
    }

    Timer {
        interval: Math.max(1, root.refreshMinutes) * 60 * 1000
        running: root.widgetCount > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30 * 1000
        running: root.widgetCount > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now() / 1000
    }

    Process {
        id: fetcher
        property string output: ""
        command: ["python3", root.scriptPath]
        stdout: SplitParser { onRead: data => fetcher.output += data }
        onExited: (code) => {
            root.loading = false
            root.now = Date.now() / 1000
            if (fetcher.output.length) root.ingest(fetcher.output)
            else root.markAllFailed(code === 0 ? "No output from usage fetcher" : "Usage fetcher failed (python3 missing?)")
        }
    }
}
