# 🤖 Claude Robot

**Live Claude usage on your Mac menubar _and_ your iPhone home screen.**

Claude Robot shows your Claude **current-session** and **weekly** usage as a Mac
menubar item and as an iPhone home-screen widget. It's a single double-click
installer — no build tools, no coding.

Your Claude login token never leaves your Mac. Usage data lives on your Mac and
your own free Firebase project; nothing is sent anywhere else.

---

## What you need first

1. **Claude Code, logged in on this Mac.**
   Install from <https://claude.com/claude-code>, then run `claude` once and log
   in. The robot reads *your* usage from this login.
2. **Your own free Firebase project** (only needed for the iPhone widget).
   - Go to <https://console.firebase.google.com> → **Add project**
   - Name it something like `claude-robot` → create it (free, no billing needed)
   - Use a **new/empty** project — the installer publishes one tiny file to it.

## Install

1. Double-click **`Install Claude Robot (Mac + iPhone).command`**.
   > If macOS blocks it: right-click → **Open** → **Open**. Or in Terminal:
   > ```bash
   > bash ~/Documents/Codex/08-ClaudeRobot/"Install Claude Robot (Mac + iPhone).command"
   > ```
2. Follow the prompts. The installer will:
   - install the menubar robot,
   - open a browser to log into Firebase,
   - ask you to paste your **Firebase Project ID**,
   - publish your usage and print a **3-line code** for your phone.
3. On your **iPhone**:
   - Install **Scriptable** (App Store, free)
   - New script → paste the 3 lines the installer printed → name it **Claude Robot** → tap ▶
   - Add it to your home screen as a **Medium** widget.

## Notes

- The **menubar** updates about every **60 seconds**.
- The **iPhone widget** refreshes on Apple's schedule (~15–30 min). That's an iOS
  limit on *all* widgets, not something this script controls.
- Your data stays on your Mac + your own Firebase. Your Claude login token never
  leaves your Mac.

## What's in this repo

| File | Purpose |
| --- | --- |
| `Install Claude Robot (Mac + iPhone).command` | The double-click installer (Mac menubar + iPhone widget). |
| `README - Read Me First.txt` | Plain-text quick-start (same content as this README). |
| `windows/robot.py` | Windows variant: system-tray robot + Firebase publisher in one process (reads the token from the Windows creds file instead of the macOS Keychain). |
| `windows/robot.js` | Scriptable iPhone-widget script template (the installer fills in `__DATA_URL__`). |
| `LICENSE` | MIT. |
