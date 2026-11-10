# Usage Bar

DankMaterialShell bar widget showing Claude and Codex subscription usage.

- **Bar:** icon and percentage for your main subscription (or both). Turns amber at 75% and red at 90%.
- **Popout:** a card per provider with plan, the session/weekly windows (plus model-scoped limits like
  `Weekly · Fable`), reset countdowns, extra usage/credits, a refresh button and a link to the usage page.
  The ★ on a card makes it the main subscription.
- **IPC:** `dms ipc call usageBar toggle` / `dms ipc call usageBar refresh`. For example, in niri:
  `Mod+U { spawn "dms" "ipc" "call" "usageBar" "toggle"; }`

## Install

```sh
git clone https://github.com/abdrakhmanovzh/usage-bar ~/.config/DankMaterialShell/plugins/UsageBar
~/.config/DankMaterialShell/plugins/UsageBar/install.sh   # enable it and add it to the bar
```

Then run `dms restart` if it doesn't show up. To update, run `git pull` in that folder.

`install.sh --no-bar` skips enabling and the bar edit; turn it on yourself in Settings → Plugins and add it to DankBar.
If you cloned somewhere else (e.g. `~/code/usage-bar` for development), `install.sh` symlinks that checkout into
the plugins folder instead.

Everything lives in `$HOME`. Nothing is layered with rpm-ostree and there are no pip packages: the fetcher is
stdlib Python, and `python3` is part of the base image. The `claude` and `codex` CLIs don't need to be on
the shell's `PATH`; only their credential files are read.

## How the data is fetched

`usage-fetch.py` prints one JSON object. It is the same approach
[CodexBar](https://github.com/steipete/CodexBar) uses in its OAuth paths:

| | Claude | Codex |
|---|---|---|
| Credentials | `~/.claude/.credentials.json` → `claudeAiOauth.accessToken` (`$CLAUDE_CONFIG_DIR` respected) | `~/.codex/auth.json` → `tokens.access_token`, `tokens.account_id` (`$CODEX_HOME` respected) |
| Endpoint | `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20` | `GET https://chatgpt.com/backend-api/wham/usage` with `ChatGPT-Account-Id` (`chatgpt_base_url` in `config.toml` respected) |
| Fields | `five_hour`, `seven_day` (`utilization`, `resets_at`), `limits[]` `weekly_scoped`, `spend` | `rate_limit.primary_window` / `secondary_window` (`used_percent`, `limit_window_seconds`, `reset_at`), `credits`, `plan_type` |

Codex windows are labelled by `limit_window_seconds`, not by primary/secondary position. Some plans (for
example Pro Lite) return only a weekly window, in `primary_window`.

**Tokens are read-only.** The fetcher never refreshes or rewrites credentials, because rotating an OAuth refresh
token behind the CLI's back would log the CLI out. If a token expires (Claude's last about 8 hours), the card keeps the last
numbers dimmed and asks you to use the CLI once, which refreshes the token.

Test the fetcher directly:

```sh
python3 usage-fetch.py | jq
```
