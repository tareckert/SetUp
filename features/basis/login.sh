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

# Oberfläche auf tty1 starten (Funktion "oberflaeche")
if [ -f "$HOME/.ki/oberflaeche/.installed" ] && [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
    . "$KI_REPO/features/oberflaeche/start.sh"
fi
