#!/bin/bash
# 🤖 Claude Robot — full installer (Mac menubar + iPhone widget)
# Sets up: SwiftBar menubar robot, a background publisher, and publishing to
# YOUR OWN Firebase so an iPhone widget can show your live Claude usage.

set -u
BOLD=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; RST=$'\033[0m'
say(){ printf "%s\n" "$*"; }
ok(){ printf "${GRN}✅ %s${RST}\n" "$*"; }
warn(){ printf "${YEL}⚠️  %s${RST}\n" "$*"; }
err(){ printf "${RED}❌ %s${RST}\n" "$*"; }
pause(){ printf "\n"; read -r -p "Press Return to close…" _ || true; }

clear
say "${BOLD}🤖  Claude Robot — Mac menubar + iPhone widget${RST}"
say "${DIM}Shows your live Claude session + weekly usage.${RST}"; say ""

[ "$(uname)" = "Darwin" ] || { err "macOS only."; pause; exit 1; }

# --- 1. Claude Code must be logged in (token lives in Keychain) --------------
say "→ Checking your Claude Code login…"
if ! /usr/bin/security find-generic-password -s "Claude Code-credentials" -w >/dev/null 2>&1; then
  err "Claude Code isn't logged in on this Mac yet."
  say "  1. Install: ${BOLD}https://claude.com/claude-code${RST}"
  say "  2. Run ${BOLD}claude${RST} once and log in."
  say "  3. Re-run this installer."
  pause; exit 1
fi
ok "Claude Code login found."

# --- 2. Homebrew ------------------------------------------------------------
BREW=""; [ -x /opt/homebrew/bin/brew ] && BREW=/opt/homebrew/bin/brew
[ -z "$BREW" ] && [ -x /usr/local/bin/brew ] && BREW=/usr/local/bin/brew
if [ -z "$BREW" ]; then
  warn "Installing Homebrew (may ask for your Mac password)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || { err "Homebrew install failed."; pause; exit 1; }
  [ -x /opt/homebrew/bin/brew ] && BREW=/opt/homebrew/bin/brew || BREW=/usr/local/bin/brew
fi
eval "$("$BREW" shellenv)"; ok "Homebrew ready."

# --- 3. Apps + tools --------------------------------------------------------
say "→ Installing SwiftBar, Ice, Node (for Firebase)…"
"$BREW" install --cask swiftbar >/dev/null 2>&1 || "$BREW" install --cask swiftbar
"$BREW" install --cask jordanbaird-ice >/dev/null 2>&1 || true
command -v node >/dev/null 2>&1 || "$BREW" install node
if ! command -v firebase >/dev/null 2>&1; then
  say "→ Installing Firebase CLI…"; npm install -g firebase-tools || { err "firebase-tools install failed."; pause; exit 1; }
fi
FIREBASE="$(command -v firebase)"
PY="$(command -v python3 || echo /usr/bin/python3)"
ok "Tools installed."

mkdir -p "$HOME/.claude-robot"

# --- 4. Publisher (config-driven; single API caller) ------------------------
cat > "$HOME/.claude-robot/publish-usage.py" <<'PYEOF'
#!/usr/bin/env python3
import os, json, time, shutil, subprocess, urllib.request, urllib.error, tempfile
from datetime import datetime, timezone
ENDPOINT="https://api.anthropic.com/api/oauth/usage"
BASE_INTERVAL=300; MAX_BACKOFF=1800; DEPLOY_INTERVAL=600
HOME=os.path.expanduser("~")
STATE=os.path.join(HOME,".claude-robot","usage.json")
CFG=os.path.join(HOME,".claude-robot","config.json")
FB_DIR=os.path.join(HOME,".claude-robot","fb")
FB_PUBLIC=os.path.join(FB_DIR,"public","usage.json")
WIDGET_SRC=os.path.join(HOME,".claude-robot","Claude Robot.js")
FIREBASE=shutil.which("firebase") or "/opt/homebrew/bin/firebase"

def cfg():
    try:
        with open(CFG) as f: return json.load(f)
    except Exception: return {}

def token():
    out=subprocess.check_output(["/usr/bin/security","find-generic-password","-s","Claude Code-credentials","-w"],stderr=subprocess.DEVNULL)
    return json.loads(out)["claudeAiOauth"]["accessToken"]

def fetch():
    req=urllib.request.Request(ENDPOINT,headers={"Authorization":f"Bearer {token()}","anthropic-beta":"oauth-2025-04-20","User-Agent":"claude-robot/2"})
    with urllib.request.urlopen(req,timeout=10) as r: return json.loads(r.read())

def wa(path,payload):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),suffix=".tmp")
    with os.fdopen(fd,"w") as f: json.dump(payload,f)
    os.replace(tmp,path)

def load():
    try:
        with open(STATE) as f: return json.load(f)
    except Exception: return {}

def deploy_fb(state,now):
    c=cfg(); proj=c.get("fb_project")
    if not proj or not os.path.isdir(FB_DIR) or "session_pct" not in state: return state
    if now < state.get("fb_next_epoch",0): return state
    cur=[state.get("session_pct"),state.get("weekly_pct"),state.get("opus_pct"),[m.get("pct") for m in state.get("models") or []],state.get("stale")]
    if cur==state.get("fb_last") and state.get("fb_deployed_once"):
        state["fb_next_epoch"]=now+120; return state
    try:
        shutil.copyfile(STATE,FB_PUBLIC)
        if os.path.exists(WIDGET_SRC): shutil.copyfile(WIDGET_SRC,os.path.join(FB_DIR,"public","robot.js"))
        env=dict(os.environ); env["PATH"]="/opt/homebrew/bin:/usr/local/bin:"+env.get("PATH","")
        r=subprocess.run([FIREBASE,"deploy","--only","hosting","--project",proj],cwd=FB_DIR,env=env,capture_output=True,text=True,timeout=180)
        if r.returncode==0:
            state["fb_last"]=cur; state["fb_deployed_once"]=True; state["fb_next_epoch"]=now+DEPLOY_INTERVAL; state.pop("fb_error",None)
        else:
            state["fb_error"]=(r.stderr or r.stdout or "")[-160:]; state["fb_next_epoch"]=now+300
    except Exception as e:
        state["fb_error"]=str(e)[:160]; state["fb_next_epoch"]=now+300
    return state

def main():
    now=int(time.time()); state=load()
    if state.get("next_fetch_epoch",0)>now:
        wa(STATE,state); state=deploy_fb(state,now); wa(STATE,state); return
    try:
        d=fetch(); L={x.get("kind"):x for x in d.get("limits",[])}
        s=L.get("session") or {}; w=L.get("weekly_all") or {}; o=d.get("seven_day_opus")
        models=[{"name":(((x.get("scope") or {}).get("model") or {}).get("display_name") or "Scoped"),
                 "pct":int(x.get("percent") or 0),"sev":x.get("severity"),"reset_iso":x.get("resets_at")}
                for x in d.get("limits",[]) if x.get("kind")=="weekly_scoped"]
        state={"ok":True,"stale":False,
            "session_pct":int(s.get("percent",round(d.get("five_hour",{}).get("utilization",0)))),
            "weekly_pct":int(w.get("percent",round(d.get("seven_day",{}).get("utilization",0)))),
            "session_sev":s.get("severity"),"weekly_sev":w.get("severity"),
            "opus_pct":int(round(o["utilization"])) if o and o.get("utilization") is not None else None,
            "models":models,
            "session_reset_iso":s.get("resets_at") or d.get("five_hour",{}).get("resets_at"),
            "weekly_reset_iso":w.get("resets_at") or d.get("seven_day",{}).get("resets_at"),
            "fetched_epoch":now,"updated_epoch":now,"error":None,"backoff_level":0,"next_fetch_epoch":now+BASE_INTERVAL}
    except Exception as e:
        code=getattr(e,"code",None); lvl=min(state.get("backoff_level",0)+1,6)
        state=dict(state); state["stale"]=True
        state["error"]="reauth" if code==401 else (f"http_{code}" if code else str(e)[:80])
        state["updated_epoch"]=now; state["backoff_level"]=lvl
        state["next_fetch_epoch"]=now+min(BASE_INTERVAL*(2**(lvl-1)),MAX_BACKOFF)
        state.setdefault("ok",False)
        if "session_pct" not in state: state["ok"]=False
    wa(STATE,state); state=deploy_fb(state,now); wa(STATE,state)

if __name__=="__main__": main()
PYEOF

# --- 5. Menubar plugin (reads local file) -----------------------------------
PLUGDIR="$HOME/Library/Application Support/SwiftBar/Plugins"; mkdir -p "$PLUGDIR"
cat > "$PLUGDIR/claude-usage.60s.py" <<'PYEOF'
#!/usr/bin/env python3
import os, json
from datetime import datetime
LOCAL=datetime.now().astimezone().tzinfo
STATE=os.path.expanduser("~/.claude-robot/usage.json")
CLAUDE=os.path.expanduser("~/.local/bin/claude")
def bar(p,w=10):
    f=max(0,min(w,round(p/100*w))); return "█"*f+"░"*(w-f)
def col(p,s):
    if p>=90 or s in("critical","high"): return "#ff5555"
    if p>=75 or s not in("normal",None): return "#ff9f43"
    return "#c98a5b"
def face(p):
    if p>=100: return "×","×","▬"
    if p>=90: return "◉","◉","o"
    if p>=75: return "•","•","~"
    if p>=50: return "◕","◕","▿"
    return "◕","◕","◡"
def fmt(iso):
    try:
        dt=datetime.fromisoformat(iso.replace("Z","+00:00")).astimezone(LOCAL)
        sec=int((dt-datetime.now(LOCAL)).total_seconds())
        if sec<=0: rel="now"
        else:
            h,m=divmod(sec//60,60); d,h=divmod(h,24)
            rel=f"{d}d {h}h" if d else (f"{h}h {m}m" if h else f"{m}m")
        return dt.strftime("%a %-I:%M %p"),rel,dt.strftime("%-I:%M %p")
    except Exception: return iso,"?","?"
def wait(msg):
    print("🤖 …"); print("---"); print("Claude Usage Robot")
    print(f"{msg} | color=#888888")
    print(f"Open Claude to refresh login | bash={CLAUDE} terminal=true")
    print("Open Usage settings | href=https://claude.ai/settings/usage"); print("Refresh | refresh=true")
def main():
    try:
        with open(STATE) as f: d=json.load(f)
    except Exception: wait("Starting up… background job hasn't published yet."); return
    if not d.get("ok") or "session_pct" not in d:
        wait("Token expired — run Claude Code once." if d.get("error")=="reauth" else "Waiting for first sync…"); return
    s,w=d["session_pct"],d["weekly_pct"]; ss,ws=d.get("session_sev"),d.get("weekly_sev"); worst=max(s,w)
    sf,sr,sc=fmt(d.get("session_reset_iso","")); wf,wr,_=fmt(d.get("weekly_reset_iso",""))
    title=f"🤖 {s}% ⏰ {sc} 📅 {w}%"
    print(f"{title} | color=#ff5555" if worst>=90 else title)
    print("---"); le,re,mo=face(worst); mono="font=Menlo size=14"
    print(f"  ╭───────╮   | {mono}"); print(f"  │ {le}   {re} │   Claude | {mono}")
    print(f"  │   {mo}   │   is watching | {mono}"); print(f"  ╰──┬─┬──╯   your limits | {mono}"); print("---")
    print(f"Current session   {s}% used | color={col(s,ss)} {mono}")
    print(f"  {bar(s)}  | color={col(s,ss)} {mono}"); print(f"  resets in {sr}  ·  {sf} | color=#888888 size=12"); print("---")
    print(f"Weekly · all models   {w}% used | color={col(w,ws)} {mono}")
    print(f"  {bar(w)}  | color={col(w,ws)} {mono}"); print(f"  resets in {wr}  ·  {wf} | color=#888888 size=12")
    rows=d.get("models") or ([{"name":"Opus","pct":d["opus_pct"],"sev":None}] if d.get("opus_pct") is not None else [])
    for m in rows:
        p,sv=int(m.get("pct",0)),m.get("sev")
        print("---"); print(f"Weekly · {m.get('name','?')}   {p}% used | color={col(p,sv)} {mono}"); print(f"  {bar(p)}  | color={col(p,sv)} {mono}")
    print("---")
    if d.get("stale"): print(f"⏳ showing last update (retrying) | color=#ff9f43 size=11")
    print("Open Usage settings | href=https://claude.ai/settings/usage"); print("Refresh now | refresh=true")
if __name__=="__main__": main()
PYEOF
chmod +x "$PLUGDIR/claude-usage.60s.py"
defaults write com.ambar.SwiftBar PluginDirectory "$PLUGDIR" >/dev/null 2>&1 || true
ok "Menubar robot installed."

# --- 6. Firebase (YOUR project) for the iPhone widget -----------------------
say ""; say "${BOLD}=== iPhone widget setup (your own Firebase) ===${RST}"
say "You need a ${BOLD}dedicated, empty${RST} Firebase project (free)."
say "If you don't have one: open ${BOLD}https://console.firebase.google.com${RST} →"
say "Add project → name it e.g. 'claude-robot' → create. Then come back here."
say ""
say "→ Logging in to Firebase (a browser window will open)…"
"$FIREBASE" login 2>&1 | tail -3
say ""; say "Your Firebase projects:"; "$FIREBASE" projects:list 2>/dev/null | grep -iE "Project ID|[a-z0-9-]{6,}" | head -20
say ""
read -r -p "${BOLD}Type your DEDICATED Firebase Project ID and press Return: ${RST}" PROJECT
PROJECT="$(echo "$PROJECT" | tr -d '[:space:]')"
[ -n "$PROJECT" ] || { err "No project entered. Menubar is installed; re-run to add the phone widget."; pause; exit 1; }

DATA_URL="https://${PROJECT}.web.app"
printf '{ "fb_project": "%s", "fb_site": "%s" }\n' "$PROJECT" "$PROJECT" > "$HOME/.claude-robot/config.json"

# widget code (URL baked in)
cat > "$HOME/.claude-robot/Claude Robot.js" <<'JSEOF'
// Variables used by Scriptable. Do not edit.
// icon-color: deep-orange; icon-glyph: robot;
const CLAY=new Color("#d97757"),BG_TOP=new Color("#1c1a19"),BG_BOT=new Color("#0e0d0c"),DIM=new Color("#8a8580"),TRACK=new Color("#3a3633");
const DATA_URL="__DATA_URL__/usage.json";
function colorFor(p){if(p>=90)return new Color("#ff5555");if(p>=75)return new Color("#ff9f43");return CLAY;}
function faceFor(p){if(p>=100)return "×_×";if(p>=90)return "◉_◉";if(p>=75)return "•~•";if(p>=50)return "◕‿◕";return "◕ᴗ◕";}
function resetsIn(iso){if(!iso)return "";const s=Math.floor((new Date(iso).getTime()-Date.now())/1000);if(s<=0)return "now";const m=Math.floor(s/60)%60,h=Math.floor(s/3600)%24,d=Math.floor(s/86400);if(d)return `${d}d ${h}h`;if(h)return `${h}h ${m}m`;return `${m}m`;}
function clockOf(iso){if(!iso)return "";const d=new Date(iso);let h=d.getHours(),a=h>=12?"PM":"AM";h=h%12||12;const m=d.getMinutes().toString().padStart(2,"0");return `${h}:${m} ${a}`;}
function barImage(p,c,w=260,h=16){const x=new DrawContext();x.size=new Size(w,h);x.opaque=false;x.respectScreenScale=true;const r=h/2;const t=new Path();t.addRoundedRect(new Rect(0,0,w,h),r,r);x.addPath(t);x.setFillColor(TRACK);x.fillPath();const fw=Math.max(h,(Math.min(100,Math.max(0,p))/100)*w);const f=new Path();f.addRoundedRect(new Rect(0,0,fw,h),r,r);x.addPath(f);x.setFillColor(c);x.fillPath();return x.getImage();}
async function loadData(){try{const r=new Request(DATA_URL+"?t="+Date.now());r.timeoutInterval=8;return await r.loadJSON();}catch(e){return null;}}
function row(st,em,lb,p,sub){const c=colorFor(p);const rw=st.addStack();rw.layoutVertically();const tp=rw.addStack();tp.centerAlignContent();const e=tp.addText(em+" ");e.font=Font.systemFont(13);const l=tp.addText(lb);l.font=Font.mediumSystemFont(13);l.textColor=Color.white();tp.addSpacer();const pc=tp.addText(p+"%");pc.font=Font.boldSystemFont(15);pc.textColor=c;rw.addSpacer(4);const im=rw.addImage(barImage(p,c));im.imageSize=new Size(260,8);if(sub){rw.addSpacer(3);const s=rw.addText(sub);s.font=Font.systemFont(10);s.textColor=DIM;}}
async function build(){const data=await loadData();const w=new ListWidget();const g=new LinearGradient();g.colors=[BG_TOP,BG_BOT];g.locations=[0,1];w.backgroundGradient=g;w.setPadding(14,15,14,15);
if(!data||!data.ok){const t=w.addText("🤖 Claude");t.font=Font.boldSystemFont(15);t.textColor=Color.white();w.addSpacer(6);const m=w.addText(!data?"Can't reach usage right now…":(data.error==="reauth"?"Run Claude Code once to refresh.":"Can't reach usage right now."));m.font=Font.systemFont(11);m.textColor=DIM;w.refreshAfterDate=new Date(Date.now()+300000);return w;}
const s=data.session_pct,wk=data.weekly_pct;const hd=w.addStack();hd.centerAlignContent();const ti=hd.addText("🤖  Claude");ti.font=Font.boldSystemFont(15);ti.textColor=Color.white();hd.addSpacer();const fa=hd.addText(faceFor(Math.max(s,wk)));fa.font=Font.systemFont(13);fa.textColor=colorFor(Math.max(s,wk));
w.addSpacer(10);row(w,"🤖","Session",s,`⏰ resets in ${resetsIn(data.session_reset_iso)} · ${clockOf(data.session_reset_iso)}`);
w.addSpacer(9);row(w,"📅","Weekly",wk,`resets in ${resetsIn(data.weekly_reset_iso)}`);
const ms=(data.models&&data.models.length)?data.models:(data.opus_pct!=null?[{name:"Opus",pct:data.opus_pct}]:[]);for(const m of ms){w.addSpacer(9);row(w,"🧠",`Weekly · ${m.name}`,m.pct,null);}
w.addSpacer();const st=(data.fetched_epoch||data.updated_epoch)*1000;const ft=w.addText("updated "+clockOf(new Date(st).toISOString())+(data.stale?" · syncing…":""));ft.font=Font.systemFont(9);ft.textColor=DIM;
w.refreshAfterDate=new Date(Date.now()+60000);return w;}
const widget=await build();if(config.runsInWidget){Script.setWidget(widget);}else{await widget.presentMedium();}Script.complete();
JSEOF
/usr/bin/sed -i '' "s|__DATA_URL__|$DATA_URL|g" "$HOME/.claude-robot/Claude Robot.js"

# isolated deploy dir
FB="$HOME/.claude-robot/fb"; mkdir -p "$FB/public"
printf '{ "projects": { "default": "%s" } }\n' "$PROJECT" > "$FB/.firebaserc"
cat > "$FB/firebase.json" <<EOF
{ "hosting": { "site": "$PROJECT", "public": "public", "ignore": ["firebase.json","**/.*"],
  "headers": [ { "source": "*.json", "headers": [{ "key": "Cache-Control", "value": "no-store, max-age=0" }] },
               { "source": "*.js",   "headers": [{ "key": "Cache-Control", "value": "no-store, max-age=0" }] } ] } }
EOF
cp "$HOME/.claude-robot/Claude Robot.js" "$FB/public/robot.js"
echo '{"ok":false,"note":"starting"}' > "$FB/public/usage.json"

say "→ Publishing to your Firebase (first fetch + deploy)…"
"$PY" "$HOME/.claude-robot/publish-usage.py"
( cd "$FB" && "$FIREBASE" deploy --only hosting --project "$PROJECT" 2>&1 | tail -4 )

# --- 7. launchd background job ----------------------------------------------
PLIST="$HOME/Library/LaunchAgents/com.chain.clauderobot.publish.plist"; mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.chain.clauderobot.publish</string>
<key>ProgramArguments</key><array><string>$PY</string><string>$HOME/.claude-robot/publish-usage.py</string></array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
<key>StartInterval</key><integer>60</integer><key>RunAtLoad</key><true/>
<key>StandardErrorPath</key><string>$HOME/.claude-robot/publish.err.log</string>
</dict></plist>
EOF
launchctl unload "$PLIST" 2>/dev/null; launchctl load "$PLIST"
open -a SwiftBar 2>/dev/null || true; open -a Ice 2>/dev/null || true

# --- 8. Done + personalized phone code --------------------------------------
say ""; ok "${BOLD}Mac side done!${RST}  Menubar robot is live (top-right)."
say ""; say "${BOLD}=== Finish on your iPhone ===${RST}"
say "1. Install ${BOLD}Scriptable${RST} (App Store, free)."
say "2. Open Scriptable → tap ${BOLD}➕${RST} (new script) → delete placeholder → paste EXACTLY this:"
say ""
say "${BOLD}------------------------------------------------------------${RST}"
say "const src = await new Request(\"${DATA_URL}/robot.js\").loadString();"
say "await eval(\`(async()=>{\${src}})()\`);"
say "${BOLD}------------------------------------------------------------${RST}"
say ""
say "3. Rename the script ${BOLD}Claude Robot${RST} → tap ▶ to test (should show your %)."
say "4. Home screen → long-press → ➕ → Scriptable → Medium → Add →"
say "   long-press it → Edit Widget → Script → ${BOLD}Claude Robot${RST}."
say ""
say "${DIM}Your data lives only on your Mac + your own Firebase: ${DATA_URL}${RST}"
pause
