# basis/login.sh – aus ~/.profile geladen (Login auf der Konsole oder per SSH). POSIX-sh.
# Erwartet KI_REPO (setzt die Zeile in ~/.profile).

# Nur "ki" kommt in den PATH – alle anderen Werkzeuge laufen als "ki <befehl>"
case ":$PATH:" in *":$KI_REPO/features/basis/bin:"*) ;; *) PATH="$KI_REPO/features/basis/bin:$PATH" ;; esac
for _ki_d in /opt/ki/*/bin /usr/local/cuda/bin; do
    [ -d "$_ki_d" ] || continue
    case ":$PATH:" in *":$_ki_d:"*) ;; *) PATH="$PATH:$_ki_d" ;; esac
done
unset _ki_d
export PATH KI_REPO
export LESSHISTFILE=-          # less legt keine ~/.lesshst an
# Menü, Rahmen und Umlaute brauchen UTF-8; ohne eingestellte Sprache gilt das immer vorhandene C.UTF-8
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *.UTF-8|*.utf8|*.utf-8|*.UTF8) ;; *) export LANG=C.UTF-8 ;; esac
export GIT_CONFIG_GLOBAL="$HOME/.ki/basis/git/config"   # dieselben Git-Einstellungen wie in den Projekten

# Oberfläche auf tty1 starten (Funktion "oberflaeche")
if [ -f "$HOME/.ki/oberflaeche/.installed" ] && [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
    . "$KI_REPO/features/oberflaeche/start.sh"
fi
