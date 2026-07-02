#!/usr/bin/env python3
# Claude Robot - Windows system-tray robot + Firebase publisher (single process).
# Mirrors the macOS publisher, but reads the token from the Windows creds FILE
# (macOS uses the Keychain), and renders a tray icon instead of a menubar item.
#
# Runs forever: every few minutes it fetches your Claude usage and (if configured)
# deploys it to YOUR Firebase for the iPhone widget; every ~20s it refreshes the
# tray icon + tooltip from the local usage.json.
import os, sys, json, time, shutil, tempfile, threading, subprocess, webbrowser, traceback
import urllib.request, urllib.error
from datetime import datetime, timezone

ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
BASE_INTERVAL = 300      # seconds between usage fetches
MAX_BACKOFF = 1800       # cap on error backoff
DEPLOY_INTERVAL = 600    # min seconds between Firebase deploys
TICK = 20                # main loop tick (icon refresh) seconds

HOME = os.path.expanduser("~")
ROOT = os.path.join(HOME, ".claude-robot")
STATE = os.path.join(ROOT, "usage.json")
CFG = os.path.join(ROOT, "config.json")
LOG = os.path.join(ROOT, "robot.err.log")
# Windows/Linux: Claude Code stores creds in ~/.claude/.credentials.json
# (macOS stores them in the Keychain instead). CLAUDE_CONFIG_DIR overrides ~/.claude.
_CFGDIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
CREDS = os.path.join(_CFGDIR, ".credentials.json")
FB_DIR = os.path.join(ROOT, "fb")
FB_PUBLIC = os.path.join(FB_DIR, "public", "usage.json")
WIDGET_SRC = os.path.join(ROOT, "robot.js")

force = threading.Event()   # set by "Refresh now" menu item
icon = None                 # pystray Icon, set in main()


def log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"{datetime.now().isoformat(timespec='seconds')} {msg}\n")
    except Exception:
        pass


def cfg():
    try:
        with open(CFG, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def firebase_cmd():
    # shutil.which resolves firebase.cmd on Windows (via PATHEXT)
    return shutil.which("firebase") or shutil.which("firebase.cmd") or "firebase"


def token():
    with open(CREDS, "r", encoding="utf-8") as f:
        d = json.load(f)
    return d["claudeAiOauth"]["accessToken"]


def fetch():
    req = urllib.request.Request(ENDPOINT, headers={
        "Authorization": f"Bearer {token()}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-robot/2-win"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())


def wa(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f)
    os.replace(tmp, path)


def load():
    try:
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def deploy_fb(state, now):
    c = cfg(); proj = c.get("fb_project")
    if not proj or not os.path.isdir(FB_DIR) or "session_pct" not in state:
        return state
    if now < state.get("fb_next_epoch", 0):
        return state
    cur = [state.get("session_pct"), state.get("weekly_pct"), state.get("opus_pct"),
           [m.get("pct") for m in state.get("models") or []], state.get("stale")]
    if cur == state.get("fb_last") and state.get("fb_deployed_once"):
        state["fb_next_epoch"] = now + 120
        return state
    try:
        shutil.copyfile(STATE, FB_PUBLIC)
        if os.path.exists(WIDGET_SRC):
            shutil.copyfile(WIDGET_SRC, os.path.join(FB_DIR, "public", "robot.js"))
        r = subprocess.run([firebase_cmd(), "deploy", "--only", "hosting", "--project", proj],
                           cwd=FB_DIR, capture_output=True, text=True, timeout=180)
        if r.returncode == 0:
            state["fb_last"] = cur
            state["fb_deployed_once"] = True
            state["fb_next_epoch"] = now + DEPLOY_INTERVAL
            state.pop("fb_error", None)
        else:
            state["fb_error"] = (r.stderr or r.stdout or "")[-160:]
            state["fb_next_epoch"] = now + 300
            log("firebase deploy failed: " + state["fb_error"])
    except Exception as e:
        state["fb_error"] = str(e)[:160]
        state["fb_next_epoch"] = now + 300
        log("deploy exception: " + repr(e))
    return state


def update(state):
    now = int(time.time())
    if state.get("next_fetch_epoch", 0) > now:
        state = deploy_fb(state, now); wa(STATE, state); return state
    try:
        d = fetch()
        L = {x.get("kind"): x for x in d.get("limits", [])}
        s = L.get("session") or {}; w = L.get("weekly_all") or {}; o = d.get("seven_day_opus")
        # Per-model weekly limits (e.g. "Fable") arrive as weekly_scoped entries.
        models = [{
            "name": (((x.get("scope") or {}).get("model") or {}).get("display_name") or "Scoped"),
            "pct": int(x.get("percent") or 0),
            "sev": x.get("severity"),
            "reset_iso": x.get("resets_at"),
        } for x in d.get("limits", []) if x.get("kind") == "weekly_scoped"]
        state = {
            "ok": True, "stale": False,
            "session_pct": int(s.get("percent", round(d.get("five_hour", {}).get("utilization", 0)))),
            "weekly_pct": int(w.get("percent", round(d.get("seven_day", {}).get("utilization", 0)))),
            "session_sev": s.get("severity"), "weekly_sev": w.get("severity"),
            "opus_pct": int(round(o["utilization"])) if o and o.get("utilization") is not None else None,
            "models": models,
            "session_reset_iso": s.get("resets_at") or d.get("five_hour", {}).get("resets_at"),
            "weekly_reset_iso": w.get("resets_at") or d.get("seven_day", {}).get("resets_at"),
            "fetched_epoch": now, "updated_epoch": now, "error": None,
            "backoff_level": 0, "next_fetch_epoch": now + BASE_INTERVAL}
    except Exception as e:
        code = getattr(e, "code", None)
        lvl = min(state.get("backoff_level", 0) + 1, 6)
        state = dict(state); state["stale"] = True
        state["error"] = "reauth" if code == 401 else (f"http_{code}" if code else str(e)[:80])
        state["updated_epoch"] = now; state["backoff_level"] = lvl
        state["next_fetch_epoch"] = now + min(BASE_INTERVAL * (2 ** (lvl - 1)), MAX_BACKOFF)
        state.setdefault("ok", False)
        if "session_pct" not in state:
            state["ok"] = False
        log("fetch failed: " + state["error"])
    state = deploy_fb(state, now); wa(STATE, state); return state


# ---------- tray rendering ----------

def color_for(p, sev=None):
    if p >= 90 or sev in ("critical", "high"):
        return (255, 85, 85)
    if p >= 75 or (sev not in ("normal", None)):
        return (255, 159, 67)
    return (201, 138, 91)


def rel(iso):
    if not iso:
        return "?"
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        sec = int((dt - datetime.now(timezone.utc)).total_seconds())
        if sec <= 0:
            return "now"
        mins = sec // 60
        h, m = divmod(mins, 60)
        d, h = divmod(h, 24)
        return f"{d}d {h}h" if d else (f"{h}h {m}m" if h else f"{m}m")
    except Exception:
        return "?"


def make_icon(state):
    from PIL import Image, ImageDraw, ImageFont
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if not state.get("ok") or "session_pct" not in state:
        col, txt = (136, 136, 136), "…"
    else:
        p = state["session_pct"]
        col = color_for(p, state.get("session_sev"))
        txt = str(p)
    d.rounded_rectangle([2, 2, size - 3, size - 3], radius=14, fill=col)
    font = None
    fpath = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", "segoeui.ttf")
    try:
        font = ImageFont.truetype(fpath, 30 if len(txt) < 3 else 24)
    except Exception:
        try:
            font = ImageFont.truetype("segoeui.ttf", 30 if len(txt) < 3 else 24)
        except Exception:
            font = ImageFont.load_default()
    tb = d.textbbox((0, 0), txt, font=font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    d.text(((size - tw) / 2 - tb[0], (size - th) / 2 - tb[1]), txt, font=font, fill=(255, 255, 255))
    return img


def tooltip(state):
    # Windows tray tooltips are ~127 chars; keep it tight.
    if not state.get("ok") or "session_pct" not in state:
        if state.get("error") == "reauth":
            return "Claude Robot\nRun 'claude' once to refresh login."
        return "Claude Robot\nWaiting for first sync..."
    lines = [
        f"Claude  Session {state['session_pct']}% (resets {rel(state.get('session_reset_iso'))})",
        f"Weekly {state['weekly_pct']}% (resets {rel(state.get('weekly_reset_iso'))})",
    ]
    rows = state.get("models") or ([{"name": "Opus", "pct": state["opus_pct"]}]
                                   if state.get("opus_pct") is not None else [])
    for m in rows:
        lines.append(f"{m.get('name', '?')} wk {m.get('pct', 0)}%")
    if state.get("stale"):
        lines.append("(last update, retrying)")
    return "\n".join(lines)


def refresh_tray(state):
    if icon is None:
        return
    try:
        icon.icon = make_icon(state)
        icon.title = tooltip(state)
    except Exception as e:
        log("tray refresh error: " + repr(e))


# ---------- menu actions ----------

def on_refresh(_icon, _item):
    force.set()


def on_usage(_icon, _item):
    webbrowser.open("https://claude.ai/settings/usage")


def on_quit(_icon, _item):
    _icon.stop()


def loop():
    state = load()
    while True:
        try:
            if force.is_set():
                state["next_fetch_epoch"] = 0
                state["fb_next_epoch"] = 0
                force.clear()
            state = update(state)
            refresh_tray(state)
        except Exception as e:
            log("loop error: " + repr(e) + "\n" + traceback.format_exc())
        # wake early if a manual refresh was requested
        force.wait(timeout=TICK)


def main():
    global icon
    import pystray
    state = load()
    menu = pystray.Menu(
        pystray.MenuItem("Refresh now", on_refresh),
        pystray.MenuItem("Open Usage settings", on_usage),
        pystray.MenuItem("Quit", on_quit),
    )
    icon = pystray.Icon("claude-robot", make_icon(state), tooltip(state), menu)
    threading.Thread(target=loop, daemon=True).start()
    icon.run()


if __name__ == "__main__":
    try:
        if "--once" in sys.argv:
            # one-shot fetch+deploy, used by the installer for the first publish
            update(load())
        else:
            main()
    except Exception as e:
        log("fatal: " + repr(e) + "\n" + traceback.format_exc())
        raise
