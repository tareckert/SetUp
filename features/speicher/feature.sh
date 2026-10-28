# speicher – zram statt SSD-Swap, earlyoom gegen Einfrieren, Journal-Limit
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Speicher-Schutz"
DESC="zram (komprimierter RAM-Swap), earlyoom gegen Einfrieren, Journal max. 200 MB"
DEFAULT=1
NEEDS="basis"
PACKAGES="zram-tools earlyoom"

feature_install() {
    local swaps dev size
    apt_install $PACKAGES
    sys_file zramswap /etc/default/zramswap
    must $SUDO systemctl restart zramswap.service
    ok "zram: zstd, 50 % des RAM, Priorität 100"

    # SSD-Swap: mit großem SSD-Swap greift earlyoom erst, wenn das System schon im Thrashing hängt
    swaps=$(swapon --show=NAME,TYPE --noheadings 2>/dev/null | grep -v zram | awk '{print $1}' | paste -sd' ' -)
    if [ -n "$swaps" ] && ask "SSD-Swap ($swaps) abschalten? zram ersetzt ihn" j; then
        for dev in $swaps; do
            $SUDO swapoff "$dev" || continue
            if [ -f "$KI_ROOT$dev" ]; then
                size=$(stat -c %s "$KI_ROOT$dev")
                printf '%s %s\n' "$dev" "$size" >> "$FDIR/swapdateien"   # zum Wiederherstellen
                $SUDO rm -f "$KI_ROOT$dev"
            fi
        done
        sys_comment /etc/fstab '[[:space:]]swap[[:space:]]'
        ok "SSD-Swap aus"
    fi

    sys_file sysctl.conf /etc/sysctl.d/90-ki-speicher.conf
    [ "$CHANGED" = 1 ] && $SUDO sysctl -q --system
    ok "sysctl: swappiness 100 (zram), page-cluster 0, inotify 524288"

    sys_file earlyoom /etc/default/earlyoom
    [ "$CHANGED" = 1 ] && $SUDO systemctl restart earlyoom
    svc_enable earlyoom.service
    ok "earlyoom aktiv (schont Oberfläche, Menü, SSH)"

    sys_file journald.conf /etc/systemd/journald.conf.d/90-ki.conf
    [ "$CHANGED" = 1 ] && $SUDO systemctl restart systemd-journald
    ok "Systemlog max. 200 MB"
}

feature_post_remove() {
    local dev size
    # SSD-Swap wiederherstellen, wie er vorher war
    if [ -f "$FDIR/swapdateien" ]; then
        while read -r dev size; do
            $SUDO fallocate -l "$size" "$KI_ROOT$dev" && $SUDO chmod 600 "$KI_ROOT$dev" && $SUDO mkswap -q "$KI_ROOT$dev"
        done < "$FDIR/swapdateien"
    fi
    $SUDO swapon -a 2>/dev/null
    $SUDO sysctl -q --system 2>/dev/null
    $SUDO systemctl restart systemd-journald 2>/dev/null
    return 0
}
