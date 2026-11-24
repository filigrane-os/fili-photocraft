#!/bin/sh
# Screenshot of the window of an application with niri (the window must be on screen, the session unlocked): scripts/niri-shot.sh APP_ID NAME -> ~/Screenshots/NAME.png
# usage: shot.sh APP_ID NAME  -> ~/Screenshots/NAME.png
id=$(niri msg --json windows | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if w['app_id']=='$1'))")
cd ~/Screenshots && niri msg action screenshot-window --id "$id" -d true && sleep 3 && f=$(command ls -t | head -1) && mv "$f" "$2.png" && echo "$HOME/Screenshots/$2.png"
