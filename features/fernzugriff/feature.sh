# fernzugriff – SSH-Server für Zugriff vom Zweitrechner (Terminal, Jupyter-Tunnel)
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Fernzugriff (SSH)"
DESC="SSH-Server: vom Zweitrechner arbeiten, Jupyter per Tunnel – für die Einrichtung nicht nötig"
DEFAULT=0
NEEDS="basis"
PACKAGES="openssh-server"

feature_install() {
    apt_install $PACKAGES
    ok "SSH bereit: ssh $USER_NAME@$(hostname -I 2>/dev/null | awk '{print $1}')"
    note "Tipp: Anmeldung per Schlüssel statt Passwort (ssh-copy-id vom Zweitrechner)"
}
