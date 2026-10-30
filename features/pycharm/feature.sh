# pycharm – die IDE, im Kerker gestartet; Programm in /opt/ki/pycharm, Einstellungen in ~/.ki/pycharm
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="PyCharm"
DESC="PyCharm (aktuelle Version) – Programm in /opt/ki/pycharm, Einstellungen in ~/.ki/pycharm"
DEFAULT=1
NEEDS="oberflaeche"
PACKAGES="libxi6 libxrender1 libxtst6 libxext6 libfontconfig1 libfreetype6"
# Für den eingebetteten Browser (Markdown-Vorschau, Hilfe-Seiten); fehlt einer, läuft PyCharm trotzdem
OPTIONAL="libnss3 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libxkbcommon0 libasound2t64"

feature_install() {
    local src=""
    apt_install $PACKAGES
    apt_install_optional $OPTIONAL
    opt_dir >/dev/null
    mkdir -p "$FDIR/config" "$FDIR/data" "$FDIR/java"
    sys_file sysctl.conf /etc/sysctl.d/90-ki-pycharm.conf
    [ "$CHANGED" = 1 ] && $SUDO sysctl -q --system
    ok "inotify: 524288 Watches – PyCharm bemerkt Dateiänderungen sofort"
    if [ -e "$KI_ROOT/opt/ki/pycharm/current" ]; then
        ok "PyCharm vorhanden – neue Version: ki pycharm update"
        return 0
    fi
    if [ "$YES" != 1 ] && { : </dev/tty; } 2>/dev/null; then
        printf '  ? PyCharm-Archiv (Datei oder Link) – Enter = aktuelle Version laden: ' >/dev/tty
        read -r src </dev/tty || src=""
    fi
    "$FSRC/bin/ki-pycharm" install ${src:+"$src"} || fail "PyCharm nicht installiert"
    ok "Einstellungen, Plugins und Lizenzstatus: ~/.ki/pycharm (für alle Projekte gemeinsam)"
}
