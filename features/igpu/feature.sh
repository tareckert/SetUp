# igpu – Bildschirm über die Intel-iGPU, die RTX rechnet nur noch
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="Bildschirm über iGPU"
DESC="Oberfläche über die Intel-Grafik (Monitor am Mainboard) – volles VRAM für CUDA"
DEFAULT=0
NEEDS="oberflaeche"
PACKAGES=""

feature_install() {
    local slot b d f conn c drv connected=0
    slot=$(lspci -D -n -d 8086::0300 2>/dev/null | awk 'NR==1 {print $1}')
    if [ -z "$slot" ]; then
        note "Keine Intel-iGPU sichtbar. Im BIOS (ASRock: Advanced → Chipset Configuration):"
        note "IGPU Multi-Monitor = Enabled, Primary Graphics Adapter = Onboard. Danach erneut installieren."
        fail "iGPU nicht aktiv"
    fi
    IFS=':.' read -r _ b d f <<< "$slot"
    BUSID="PCI:$((16#$b)):$((16#$d)):$((16#$f))"      # 0000:00:02.0 → PCI:0:2:0
    for conn in /sys/class/drm/card*-*/status; do
        [ "$(cat "$conn" 2>/dev/null)" = connected ] || continue
        c=${conn%/status}; c=${c##*/}; c=${c%%-*}
        drv=$(basename "$(readlink -f "/sys/class/drm/$c/device/driver" 2>/dev/null)")
        case $drv in i915|xe) connected=1 ;; esac
    done
    if [ $connected = 0 ]; then
        note "Am Mainboard ist kein Monitor angeschlossen – sonst bliebe der Bildschirm nach dem Neustart schwarz."
        fail "erst Monitor ans Mainboard stecken, dann erneut installieren"
    fi
    sys_file xorg-igpu.conf /etc/X11/xorg.conf.d/10-ki-igpu.conf
    touch "$KI_DIR/.neustart"
    ok "Xorg nutzt die iGPU ($BUSID) – wirkt nach dem Neustart"
    note "Notfall bei schwarzem Bild: Strg+Alt+F2, einloggen, ki setup remove igpu"
}
