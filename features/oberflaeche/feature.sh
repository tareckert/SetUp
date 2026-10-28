# oberflaeche – Xorg, i3, urxvt, Statusleiste; Autostart auf tty1
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Oberfläche"
DESC="Xorg + i3 + urxvt im Darcula-Look, Statusleiste mit GPU/Jobs, Start auf tty1"
DEFAULT=1
NEEDS="basis"
PACKAGES="xserver-xorg libgl1-mesa-dri xinit xauth x11-xserver-utils i3-wm i3status rxvt-unicode fonts-dejavu-core fonts-jetbrains-mono"

feature_install() {
    apt_install $PACKAGES
    mkdir -p "$FDIR"
    [ -f "$FDIR/einstellungen.conf" ] || cp "$FSRC/einstellungen.conf" "$FDIR/einstellungen.conf"
    # Xorg schreibt sein Log fest nach ~/.local/share/xorg – beim Entfernen räumen wir es weg
    user_path .local/share/xorg
    ok "Konfiguration liest direkt aus $FSRC; deine Ergänzungen: ~/.ki/oberflaeche/eigene.conf (i3), eigene.Xresources"
    ok "Start: nach dem Login auf tty1 automatisch, sonst mit: ki start"
}
