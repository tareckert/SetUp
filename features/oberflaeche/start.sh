# oberflaeche/start.sh – startet X auf tty1 (aus basis/login.sh). POSIX-sh; die Tastenabfrage nur unter bash.
# shellcheck disable=SC1090,SC3045
_ki_conf="$HOME/.ki/oberflaeche/einstellungen.conf"
AUTOSTART=ja
[ -f "$_ki_conf" ] && . "$_ki_conf"
if [ "$AUTOSTART" = ja ] && [ -n "${BASH_VERSION:-}" ]; then
    printf '\n  KI-Workstation startet … (Taste drücken = Konsole statt Oberfläche)\n'
    if read -r -s -n 1 -t 2 _ki_key; then
        printf '  Konsole. Oberfläche starten mit: ki start\n\n'
    else
        "$KI_REPO/features/oberflaeche/bin/ki-start"
    fi
fi
unset _ki_conf _ki_key
