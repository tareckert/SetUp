# autologin – nach dem Einschalten ohne Passwort direkt ins Menü
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Autologin"
DESC="Automatische Anmeldung auf tty1, ohne Ubuntu-Begrüßungstext"
DEFAULT=1
NEEDS="oberflaeche"
PACKAGES=""

feature_install() {
    sys_file autologin.conf /etc/systemd/system/getty@tty1.service.d/ki-autologin.conf
    $SUDO systemctl daemon-reload
    ok "Autologin für $USER_NAME auf tty1 (wirkt nach Neustart)"
    if [ ! -e "$HOME/.hushlogin" ]; then
        : > "$HOME/.hushlogin"; m_add ufile .hushlogin - 0644
    fi
    ok "Begrüßungstext beim Login aus (~/.hushlogin)"
}
