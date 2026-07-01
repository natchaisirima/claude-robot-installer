🤖  Claude Robot — Mac menubar + iPhone widget
================================================

Shows your live Claude "current session" and "weekly" usage on your Mac
menubar AND as an iPhone home-screen widget.

BEFORE YOU START
----------------
1. Be logged into Claude Code on this Mac (install: https://claude.com/claude-code,
   then run `claude` once and log in). The robot reads YOUR usage from this login.
2. For the iPhone widget you need your OWN free Firebase project:
   - Go to https://console.firebase.google.com  → Add project
   - Name it something like "claude-robot" → create it (free, no billing needed).
   - Use a NEW/empty project (the installer publishes a tiny file to it).

HOW TO INSTALL
--------------
1. Double-click:  "Install Claude Robot (Mac + iPhone).command"
   (If macOS blocks it: right-click → Open → Open. Or in Terminal:
    bash ~/Desktop/"Claude Robot Installer"/"Install Claude Robot (Mac + iPhone).command")
2. Follow the prompts. It will:
   - install the menubar robot,
   - open a browser to log into Firebase,
   - ask you to paste your Firebase Project ID,
   - publish your usage and print a 3-line code for your phone.
3. On your iPhone: install "Scriptable" (App Store, free), make a new script,
   paste the 3 lines the installer printed, name it "Claude Robot", tap ▶,
   then add it as a Medium widget on your home screen.

NOTES
-----
- Menubar updates about every 60 seconds.
- The iPhone widget refreshes on Apple's schedule (about every 15-30 min) —
  that's an iOS limit on ALL widgets, not something the script controls.
- Your data stays on your Mac + your own Firebase. Your Claude login token
  never leaves your Mac.
