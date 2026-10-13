#!/bin/bash
# Install (or upgrade) Herdboard for the current user.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID="io.github.fatihaydost.herdboard"

if ! command -v kpackagetool6 >/dev/null; then
    echo "kpackagetool6 not found: Herdboard needs KDE Plasma 6." >&2
    exit 1
fi

missing=()
command -v herdr >/dev/null 2>&1 || [[ -x $HOME/.local/bin/herdr ]] || missing+=(herdr)
for c in jq ss qdbus6 journalctl; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
command -v konsole >/dev/null 2>&1 || command -v xdg-terminal-exec >/dev/null 2>&1 || missing+=("konsole (or xdg-terminal-exec)")
if (( ${#missing[@]} )); then
    echo "Warning: not found: ${missing[*]}" >&2
    echo "Herdboard needs herdr and jq; ss is used to kill a server, qdbus6 + journalctl to find" >&2
    echo "the window showing a session, and konsole to open one." >&2
fi

upgraded=0
if kpackagetool6 --type Plasma/Applet --show "$ID" >/dev/null 2>&1; then
    echo "Upgrading $ID ..."
    kpackagetool6 --type Plasma/Applet --upgrade "$ROOT/package"
    upgraded=1
else
    echo "Installing $ID ..."
    kpackagetool6 --type Plasma/Applet --install "$ROOT/package"
fi

echo
echo "Done. Herdboard shows up in the system tray. If it does not:"
echo "  right-click the tray arrow -> Configure System Tray... -> Entries -> Herdboard -> Always shown"
echo

# Plasma loads an applet's QML once and keeps it for the life of the shell, so
# a widget already in the tray goes on running the old code until Plasma
# restarts. herdr servers are not Plasma's and keep running through it.
if [[ "${1:-}" == "--reload" ]]; then
    echo "Restarting Plasma so the tray picks up the new code ..."
    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service
    else
        kquitapp6 plasmashell 2>/dev/null || true
        sleep 1
        setsid plasmashell >/dev/null 2>&1 < /dev/null &
    fi
    echo "Done."
elif (( upgraded )); then
    echo "A Herdboard already in your tray is still running the old code."
    echo "Restart Plasma to pick this up  ->  ./install.sh --reload"
    echo "                              or  ->  systemctl --user restart plasma-plasmashell.service"
fi
