# menue – das gum-Menü (Arbeitsfläche 1, auch per SSH oder auf der Konsole)
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Menü"
DESC="Textmenü mit Einstellungen, Ausschalten/Neustart und CPU-Modus ohne Passwort"
DEFAULT=1
NEEDS="basis"
PACKAGES="gum"

feature_install() {
    local tmp dir
    if ! grep -q 'Candidate: [0-9]' <<< "$(apt-cache policy gum 2>/dev/null)"; then
        tmp=$(mktemp)
        curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor > "$tmp" || { rm -f "$tmp"; fail "Charm-Schlüssel nicht geladen"; }
        sys_put "$tmp" /etc/apt/keyrings/ki-charm.gpg 0644; rm -f "$tmp"
        sys_text /etc/apt/sources.list.d/ki-charm.list \
            "deb [signed-by=/etc/apt/keyrings/ki-charm.gpg] https://repo.charm.sh/apt/ * *"
        must $SUDO apt-get update -qq
    fi
    apt_install $PACKAGES
    ok "gum $(gum --version 2>/dev/null | awk '{print $NF}')"

    # Root-Helfer gehören root (sonst könnte jeder Prozess sie umschreiben und per sudo ausführen)
    dir=$(opt_dir)
    must $SUDO install -m 0755 "$FSRC/ki-power" "$KI_ROOT$dir/ki-power"
    sys_sudoers sudoers ki-menue
    ok "ohne Passwort: Ausschalten, Neustart, CPU-Modus (geprüft mit visudo)"
}

feature_post_remove() {
    # Paketlisten des Charm-Repos aufräumen
    $SUDO apt-get update -qq >/dev/null 2>&1
    return 0
}
