#!/usr/bin/env bash
# Install Usage Bar into DankMaterialShell (user scope; nothing touches /usr,
# so it works on immutable Fedora Atomic / Bazzite without rpm-ostree).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd -P)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell"
DEST="$CFG/plugins/UsageBar"
ID="usageBar"

command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
mkdir -p "$CFG/plugins"

if [ "$(realpath -m "$DEST")" = "$SRC" ]; then
  # Cloned straight into the plugins folder (or already linked here).
  echo "Plugin is at $DEST"
elif [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "$DEST exists and is not a symlink; remove it first." >&2; exit 1
else
  # Cloned elsewhere (e.g. a dev checkout): link it into the plugins folder.
  ln -sfn "$SRC" "$DEST"
  echo "Linked $DEST -> $SRC"
fi

if [ "${1:-}" = "--no-bar" ]; then exit 0; fi

stamp=$(date +%Y%m%d-%H%M%S)
ps="$CFG/plugin_settings.json"
[ -f "$ps" ] || echo '{}' > "$ps"
cp "$ps" "$ps.before-usage-bar-$stamp"
tmp=$(mktemp)
jq --arg id "$ID" '.[$id] = ((.[$id] // {}) + {enabled: true})' "$ps" > "$tmp" && mv "$tmp" "$ps"

s="$CFG/settings.json"
if [ -f "$s" ] && ! jq -e --arg id "$ID" '[.barConfigs[]?.rightWidgets[]?] | index($id)' "$s" >/dev/null; then
  cp "$s" "$s.before-usage-bar-$stamp"
  jq --arg id "$ID" '.barConfigs[0].rightWidgets = ([$id] + (.barConfigs[0].rightWidgets // []))' "$s" > "$tmp" && mv "$tmp" "$s"
  echo "Added $ID to the first bar's right section (backup: $s.before-usage-bar-$stamp)"
fi
echo "Done. If the widget doesn't appear, run: dms restart"
