# dateien – Dateimanager und USB-Sticks; läuft nur, solange er geöffnet ist
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Dateien & USB"
DESC="Dateimanager Midnight Commander und USB-Sticks einbinden – kein Hintergrunddienst"
DEFAULT=1
NEEDS="basis"
PACKAGES="mc"

feature_install() {
    local dir hot="$FDIR/.config/mc/hotlist"
    apt_install $PACKAGES
    # mc legt dank MC_PROFILE_ROOT alles unter ~/.ki/dateien ab; Lesezeichen mit Strg+\
    if [ ! -f "$hot" ]; then
        mkdir -p "${hot%/*}"
        printf 'ENTRY "Projekte" URL "%s/projects"\nENTRY "Datensätze und Modelle" URL "%s/shared_data"\nENTRY "USB-Sticks" URL "/media/ki"\n' \
            "$HOME" "$HOME" > "$hot"
    fi
    ok "Dateimanager: ki dateien (oder Win+D) – Einstellungen in ~/.ki/dateien"

    # USB ohne udisks-Dienst: ein kleiner Root-Helfer, nur für Wechseldatenträger
    dir=$(opt_dir)
    must $SUDO install -m 0755 "$FSRC/ki-mount" "$KI_ROOT$dir/ki-mount"
    sys_sudoers sudoers ki-dateien
    sys_mkdir /media/ki
    ok "USB-Sticks: ki usb – eingebunden unter /media/ki/<name>"
}
