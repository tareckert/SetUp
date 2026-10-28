# schlank – Ballast und Hintergrund-Traffic abschalten
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Schlank"
DESC="cloud-init, snapd, unnötige Dienste und automatische Updates aus – kein Hintergrund-Traffic"
DEFAULT=1
NEEDS="basis"
PACKAGES=""

# Dienste, die auf einer Einzelplatz-Workstation mit einer NVMe nichts tun
SERVICES="multipathd.service multipathd.socket ModemManager.service iscsid.socket iscsid.service
          open-iscsi.service udisks2.service apport.service motd-news.timer ua-timer.timer
          esm-cache.service fwupd-refresh.timer man-db.timer"
# Automatische Updates: laden und installieren täglich zu zufälligen Zeiten im Hintergrund
UPDATES="apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service"

feature_install() {
    local s
    if [ -d "$KI_ROOT/etc/cloud" ]; then
        # deaktivieren statt deinstallieren – ein Purge reißt netplan.io mit
        sys_text /etc/cloud/cloud-init.disabled "# ki:schlank – cloud-init aus"
        ok "cloud-init deaktiviert"
    fi
    if [ "$(dpkg-query -W -f='${Status}' snapd 2>/dev/null)" = "install ok installed" ]; then
        ask "snapd entfernen? (Ubuntu-Server bringt es mit; wird hier nicht gebraucht)" j &&
            must $SUDO env DEBIAN_FRONTEND=noninteractive apt-get purge -y snapd
    fi
    sys_text /etc/apt/preferences.d/ki-no-snapd "Package: snapd
Pin: release a=*
Pin-Priority: -10"
    ok "snapd gesperrt"
    for s in $SERVICES; do svc_disable "$s"; done
    ok "überflüssige Dienste aus"
    if ask "Automatische Updates abschalten? (Updates dann übers Menü; es erinnert nach 14 Tagen)" j; then
        for s in $UPDATES; do svc_disable "$s"; done
        ok "keine automatischen Downloads mehr"
    fi
}
