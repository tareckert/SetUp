# basis – Kern der KI-Workstation (immer installiert)
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Kern"
DESC="ki-Befehl, Kerker (bubblewrap), Python, Projektvorlagen – immer dabei"
CORE=1
DEFAULT=1
NEEDS=""
PACKAGES="git curl ca-certificates nano less procps bubblewrap rsync unzip build-essential python3 python3-venv python3-pip python3-dev"

bwrap_ok() { bwrap --unshare-user --uid "$(id -u)" --gid "$(id -g)" --ro-bind / / true 2>/dev/null; }

feature_install() {
    apt_install $PACKAGES
    # Ubuntu sperrt unprivilegierte User-Namespaces; nur falls bwrap scheitert, eine Freigabe
    if ! bwrap_ok; then
        sys_file apparmor-bwrap /etc/apparmor.d/ki-bwrap
        must $SUDO apparmor_parser -r "$KI_ROOT/etc/apparmor.d/ki-bwrap"
        bwrap_ok || fail "bwrap darf weiterhin keine User-Namespaces anlegen"
    fi
    ok "Kerker (bubblewrap) einsatzbereit"

    # Je eine Zeile in ~/.profile (PATH, Autostart) und ~/.bashrc (Vervollständigung)
    user_line .profile "KI_REPO='$REPO'; [ -f \"\$KI_REPO/features/basis/login.sh\" ] && . \"\$KI_REPO/features/basis/login.sh\""
    user_line .bashrc "[ -f '$REPO/features/basis/bashrc.sh' ] && . '$REPO/features/basis/bashrc.sh'"
    ok "Anmeldung: je eine Zeile in ~/.profile und ~/.bashrc"

    # Arbeitsordner – gehören dir und bleiben auch beim Entfernen erhalten
    mkdir -p "$HOME/projects" "$HOME/shared_data/datasets" "$HOME/shared_data/models" "$FDIR/vorlagen"
    [ -f "$FDIR/ki.conf" ] || cp "$FSRC/ki.conf.example" "$FDIR/ki.conf"
    ok "~/projects, ~/shared_data/{datasets,models}, Einstellungen in ~/.ki/basis/ki.conf"
}

feature_pre_remove() {
    if [ -f "$KI_ROOT/etc/apparmor.d/ki-bwrap" ]; then
        $SUDO apparmor_parser -R "$KI_ROOT/etc/apparmor.d/ki-bwrap" 2>/dev/null
    fi
    return 0
}
