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
