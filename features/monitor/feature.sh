# monitor – GPU-/CPU-Monitor; läuft nur, solange er geöffnet ist
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Monitor"
DESC="nvtop (GPU) und htop (CPU/RAM) – Einstellungen in ~/.ki/monitor"
DEFAULT=1
NEEDS="basis"
PACKAGES="htop nvtop"

feature_install() {
    apt_install $PACKAGES
    mkdir -p "$FDIR"
    ok "ki top (oder Win+G): nvtop, mit ki top cpu: htop"
}
