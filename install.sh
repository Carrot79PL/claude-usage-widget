#!/bin/zsh
# Instaluje zbieranie danych dla widgetu „Zużycie Claude”:
# kopiuje skrypt do ~/.claude-usage-widget i uruchamia go co minutę (LaunchAgent).
# Odinstalowanie: ./install.sh --uninstall
set -e
DIR="${0:A:h}"
DEST="$HOME/.claude-usage-widget"
LABEL="pl.claudeusage.collector"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [[ "$1" == "--uninstall" ]]; then
  rm -f "$PLIST"
  rm -rf "$DEST"
  echo "Odinstalowano."
  exit 0
fi

PY="$(command -v python3)"
PY="$("$PY" -c 'import sys; print(sys.executable)')"

mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
cp "$DIR/collector/claude_usage.py" "$DEST/claude_usage.py"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$PY</string><string>-I</string><string>$DEST/claude_usage.py</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>StandardErrorPath</key><string>$DEST/collector.log</string>
</dict></plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 3
if [[ -f "$DEST/usage.json" ]]; then
  echo "Gotowe. Dane: $DEST/usage.json (odświeżane co minutę)."
else
  echo "LaunchAgent zainstalowany, ale brak usage.json — sprawdź $DEST/collector.log"
fi
