# node – Node.js für Projekte mit dem Profil "node"
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Node.js"
DESC="Node.js + npm für JavaScript-Projekte (Pakete landen im Projekt)"
DEFAULT=0
NEEDS="basis"
PACKAGES="nodejs npm"

feature_install() {
    apt_install $PACKAGES
    ok "Node.js $(node --version 2>/dev/null)"
}
