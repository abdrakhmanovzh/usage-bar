#!/usr/bin/env python3
"""Fetch Claude and Codex subscription usage and print one JSON object.

Stdlib only (Bazzite ships python3 in the base image; nothing to layer).
Read-only: credentials are read from the CLIs' own files and are never
refreshed, rewritten or printed. If a token has expired, using the CLI
once (`claude` / `codex`) refreshes it.

Sources (same ones CodexBar uses):
  Claude: GET https://api.anthropic.com/api/oauth/usage
          token: ~/.claude/.credentials.json (claudeAiOauth.accessToken)
  Codex:  GET https://chatgpt.com/backend-api/wham/usage
          token: ~/.codex/auth.json (tokens.access_token + account_id)
"""

import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

TIMEOUT = 12
HOME = os.path.expanduser("~")


class FetchError(Exception):
    def __init__(self, message, kind="error"):
        super().__init__(message)
        self.kind = kind


def http_json(url, headers):
    req = urllib.request.Request(url, headers={"Accept": "application/json", **headers})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise FetchError("auth", "auth")
        if e.code == 429:
            raise FetchError("Rate limited by the server, retrying later", "ratelimit")
        raise FetchError(f"HTTP {e.code} from usage endpoint")
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise FetchError("Network unavailable", "offline") from e
    except json.JSONDecodeError:
        raise FetchError("Unexpected response from usage endpoint")


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError):
        raise FetchError(f"Could not read {path}")


def iso_to_epoch(value):
    if not value:
        return None
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def pct(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return max(0.0, min(100.0, float(value)))


def window_label(seconds):
    if not seconds:
        return "Limit"
    if seconds == 5 * 3600:
        return "Session (5h)"
    if seconds == 7 * 86400:
        return "Weekly"
    if 28 * 86400 <= seconds <= 31 * 86400:
        return "Monthly"
    if seconds % 86400 == 0:
        return f"{seconds // 86400}-day"
    if seconds % 3600 == 0:
        return f"{seconds // 3600}h window"
    return f"{round(seconds / 3600, 1)}h window"


# ── Claude ────────────────────────────────────────────────────────────────

def fetch_claude():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
    creds = read_json(os.path.join(base, ".credentials.json"))
    oauth = (creds or {}).get("claudeAiOauth") or {}
    token = oauth.get("accessToken")
    if not token:
        raise FetchError("Not signed in. Run `claude` and log in with your subscription.", "auth")
    if "user:profile" not in (oauth.get("scopes") or ["user:profile"]):
        raise FetchError("Token lacks usage scope. Run `claude /login`.", "auth")

    plan = (oauth.get("subscriptionType") or "").capitalize()
    tier = oauth.get("rateLimitTier") or ""
    m = re.search(r"max_(\d+x)", tier)
    if m:
        plan = f"{plan} · Max {m.group(1)}" if plan and plan.lower() != "max" else f"Max {m.group(1)}"

    expires = oauth.get("expiresAt")
    if isinstance(expires, (int, float)) and expires / 1000 < time.time():
        raise FetchError("Sign-in token expired. Use Claude Code once to refresh it.", "expired")

    try:
        data = http_json(
            "https://api.anthropic.com/api/oauth/usage",
            {
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2.1.0 (usage-bar)",
            },
        )
    except FetchError as e:
        if e.kind == "auth":
            raise FetchError("Sign-in rejected. Use Claude Code once (or `claude /login`).", "auth")
        raise

    windows = []

    def add(wid, label, block, seconds):
        if isinstance(block, dict) and pct(block.get("utilization")) is not None:
            windows.append({
                "id": wid, "label": label, "percent": pct(block["utilization"]),
                "resetsAt": iso_to_epoch(block.get("resets_at")), "windowSeconds": seconds,
            })

    add("session", "Session (5h)", data.get("five_hour"), 5 * 3600)
    add("weekly", "Weekly", data.get("seven_day") or data.get("seven_day_oauth_apps"), 7 * 86400)

    scoped = [l for l in (data.get("limits") or []) if isinstance(l, dict) and l.get("kind") == "weekly_scoped"]
    for i, lim in enumerate(scoped):
        model = (((lim.get("scope") or {}).get("model")) or {}).get("display_name") or "Model"
        if pct(lim.get("percent")) is None:
            continue
        windows.append({
            "id": f"weekly-{model.lower()}-{i}", "label": f"Weekly · {model}", "percent": pct(lim["percent"]),
            "resetsAt": iso_to_epoch(lim.get("resets_at")), "windowSeconds": 7 * 86400, "secondary": True,
        })
    if not scoped:
        add("weekly-opus", "Weekly · Opus", data.get("seven_day_opus"), 7 * 86400)
        add("weekly-sonnet", "Weekly · Sonnet", data.get("seven_day_sonnet"), 7 * 86400)
        for w in windows[2:]:
            w["secondary"] = True

    extra = None
    spend = data.get("spend") or {}
    try:
        limit = spend["limit"]["amount_minor"] / 10 ** spend["limit"]["exponent"]
        used = spend["used"]["amount_minor"] / 10 ** spend["used"]["exponent"]
        if spend.get("enabled") and limit > 0:
            extra = {"label": "Extra usage", "used": used, "limit": limit,
                     "currency": spend["limit"].get("currency", "USD"), "percent": pct(spend.get("percent"))}
    except (KeyError, TypeError, ZeroDivisionError):
        pass

    return {"plan": plan, "windows": windows, "extra": extra,
            "dashboardUrl": "https://claude.ai/settings/usage"}


# ── Codex ─────────────────────────────────────────────────────────────────

def jwt_exp(token):
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload)).get("exp")
    except (IndexError, ValueError):
        return None


def codex_base_url(home):
    try:
        with open(os.path.join(home, "config.toml"), encoding="utf-8") as f:
            for line in f:
                m = re.match(r'\s*chatgpt_base_url\s*=\s*"([^"]+)"', line)
                if m:
                    return m.group(1).rstrip("/")
    except OSError:
        pass
    return "https://chatgpt.com/backend-api"


def fetch_codex():
    home = os.environ.get("CODEX_HOME") or os.path.join(HOME, ".codex")
    auth = read_json(os.path.join(home, "auth.json"))
    tokens = (auth or {}).get("tokens") or {}
    token = tokens.get("access_token")
    if not token:
        raise FetchError("Not signed in with ChatGPT. Run `codex login`.", "auth")
    exp = jwt_exp(token)
    if exp and exp < time.time():
        raise FetchError("Sign-in token expired. Use Codex once to refresh it.", "expired")

    headers = {"Authorization": f"Bearer {token}", "User-Agent": "codex_cli_rs"}
    if tokens.get("account_id"):
        headers["ChatGPT-Account-Id"] = tokens["account_id"]
    base = codex_base_url(home)
    path = "/wham/usage" if "/backend-api" in base else "/api/codex/usage"
    try:
        data = http_json(base + path, headers)
    except FetchError as e:
        if e.kind == "auth":
            raise FetchError("Sign-in rejected. Use Codex once (or `codex login`).", "auth")
        raise

    windows = []

    def add_rate_limit(rl, prefix="", secondary=False):
        if not isinstance(rl, dict):
            return
        for key in ("primary_window", "secondary_window"):
            w = rl.get(key)
            if not isinstance(w, dict) or pct(w.get("used_percent")) is None:
                continue
            secs = w.get("limit_window_seconds")
            reset = w.get("reset_at")
            if not reset and w.get("reset_after_seconds") is not None:
                reset = int(time.time() + w["reset_after_seconds"])
            label = window_label(secs)
            windows.append({
                "id": (prefix or "main") + "-" + key, "label": f"{label} · {prefix}" if prefix else label,
                "percent": pct(w["used_percent"]), "resetsAt": reset, "windowSeconds": secs,
                "secondary": secondary,
            })

    add_rate_limit(data.get("rate_limit"))
    windows.sort(key=lambda w: w.get("windowSeconds") or 0)
    add_rate_limit(data.get("code_review_rate_limit"), "Code review", True)
    extra_limits = data.get("additional_rate_limits")
    if isinstance(extra_limits, list):
        for item in extra_limits:
            if isinstance(item, dict):
                name = item.get("limit_name") or item.get("metered_feature") or "Extra"
                add_rate_limit(item.get("rate_limit"), str(name), True)

    plan_raw = data.get("plan_type") or ""
    plan = {"prolite": "Pro Lite", "plus": "Plus", "pro": "Pro", "team": "Team", "business": "Business",
            "enterprise": "Enterprise", "edu": "Edu", "free": "Free"}.get(plan_raw, plan_raw.capitalize())

    extra = None
    credits = data.get("credits") or {}
    if credits.get("unlimited"):
        extra = {"label": "Credits", "text": "Unlimited"}
    elif credits.get("has_credits"):
        try:
            extra = {"label": "Credits", "text": f"{float(credits.get('balance') or 0):g} remaining"}
        except ValueError:
            pass

    return {"plan": plan, "windows": windows, "extra": extra,
            "limitReached": bool((data.get("rate_limit") or {}).get("limit_reached")),
            "dashboardUrl": "https://chatgpt.com/codex/cloud/settings/analytics#usage"}


PROVIDERS = {"claude": fetch_claude, "codex": fetch_codex}


def run(name):
    try:
        return name, {"ok": True, **PROVIDERS[name]()}
    except FetchError as e:
        return name, {"ok": False, "error": str(e), "errorKind": e.kind}
    except Exception as e:  # never let one provider break the other
        return name, {"ok": False, "error": f"Unexpected error: {type(e).__name__}", "errorKind": "error"}


def main():
    names = [a for a in sys.argv[1:] if a in PROVIDERS] or list(PROVIDERS)
    with ThreadPoolExecutor(max_workers=len(names)) as pool:
        results = dict(pool.map(run, names))
    print(json.dumps({"fetchedAt": int(time.time()), "providers": results}), flush=True)


if __name__ == "__main__":
    main()
