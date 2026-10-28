#!/usr/bin/env bash
# bootstrap.sh – einmalige Systemeinrichtung der KI-Workstation (Ubuntu Server 26.04 minimized)
#
# Läuft als normaler Benutzer und holt sich Rechte per sudo. Jeder Schritt prüft zuerst,
# ob er schon erledigt ist – das Skript darf also jederzeit erneut laufen.
#
#   ./bootstrap.sh                 alle Schritte, fragt bei optionalen nach
#   ./bootstrap.sh --yes           alle Fragen mit der Vorgabe beantworten
#   ./bootstrap.sh --only uv,igpu  nur bestimmte Schritte
#   ./bootstrap.sh --list          Schritte anzeigen
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
USER_NAME=$(id -un)
YES=0
ONLY=""
REBOOT=0
FAILED=()

STEPS=(netz ballast upgrade pakete gum uv nvidia cuda bwrap speicher igpu autologin sudoers node)
declare -A DESC=(
    [netz]="IPv4 bevorzugen (B10: halbes IPv6 im Heimnetz)"
    [ballast]="cloud-init, snapd und unnötige Hintergrunddienste abschalten"
    [upgrade]="apt update + full-upgrade"
    [pakete]="Grundpakete: X, i3, urxvt, bubblewrap, Python, Werkzeuge"
    [gum]="gum (Menü) aus dem Charm-Repo"
    [uv]="uv: schnelle Python-Pakete, keine Doppelkopien (/usr/local/bin)"
    [nvidia]="NVIDIA-Treiber + Persistence Mode"
    [cuda]="CUDA-Toolkit (optional – PyTorch braucht es nicht)"
    [bwrap]="AppArmor-Freigabe für bubblewrap, falls nötig"
    [speicher]="zram-Swap, earlyoom, sysctl, Journal-Limit"
    [igpu]="Bildschirm über die Intel-iGPU – RTX bleibt frei (optional)"
    [autologin]="Autologin auf tty1"
    [sudoers]="ki-power, poweroff, reboot ohne Passwort"
    [node]="Node.js + npm (optional)"
)

if [ -t 1 ]; then A=$'\e[38;5;173m' G=$'\e[38;5;107m' R=$'\e[38;5;210m' D=$'\e[2m' B=$'\e[1m' N=$'\e[0m'
else A='' G='' R='' D='' B='' N=''; fi
say()  { printf '%s›%s %s\n' "$A" "$N" "$*"; }
ok()   { printf '  %s✔%s %s\n' "$G" "$N" "$*"; }
skip() { printf '  %s–%s %s\n' "$D" "$N" "$*"; }
err()  { printf '  %s✘%s %s\n' "$R" "$N" "$*" >&2; }
ask() {   # ask "Frage" j|n  → 0 = ja
    local q=$1 def=${2:-j} a hint
    [ "$def" = j ] && hint="[J/n]" || hint="[j/N]"
    if [ $YES = 1 ] || [ ! -t 0 ]; then [ "$def" = j ]; return; fi
    read -r -p "  ? $q $hint " a
    a=${a:-$def}
    [[ $a =~ ^[jJyY] ]]
}
apt_install() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed'; }
put() {   # put <vorlage> <ziel> [modus] – Platzhalter ersetzen, nur bei Änderung schreiben
    local src="$REPO/system/$1" dst=$2 mode=${3:-0644} tmp
    tmp=$(mktemp)
    sed -e "s|@USER@|$USER_NAME|g" -e "s|@BUSID@|${BUSID:-}|g" "$src" > "$tmp"
    if sudo cmp -s "$tmp" "$dst" 2>/dev/null; then rm -f "$tmp"; return 1; fi
    sudo install -D -m "$mode" "$tmp" "$dst"; rm -f "$tmp"
    return 0
}

# ------------------------------------------------------------------ Schritte
step_netz() {
    if grep -qE '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' /etc/gai.conf 2>/dev/null; then
        ok "IPv4 wird bereits bevorzugt"; return
    fi
    ask "IPv4 vor IPv6 bevorzugen? Hilft gegen abbrechende Downloads (wget/curl/pip/apt) bei halbem IPv6" j ||
        { skip "unverändert"; return; }
    if grep -qE '^#[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' /etc/gai.conf 2>/dev/null; then
        sudo sed -i -E 's|^#[[:space:]]*(precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100)|\1|' /etc/gai.conf
    else
        echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf >/dev/null
    fi
    ok "/etc/gai.conf: IPv4 zuerst (IPv6 bleibt als Ausweich)"
}

step_ballast() {
    local s list=() active
    if [ -d /etc/cloud ] && [ ! -e /etc/cloud/cloud-init.disabled ]; then
        sudo touch /etc/cloud/cloud-init.disabled && ok "cloud-init deaktiviert (nicht deinstalliert – ein Purge reißt netplan.io mit)"
    else skip "cloud-init bereits aus"; fi
    if pkg_installed snapd; then
        sudo apt-get purge -y snapd && ok "snapd entfernt"
    else skip "snapd nicht installiert"; fi
    if [ ! -f /etc/apt/preferences.d/no-snapd ]; then
        printf 'Package: snapd\nPin: release a=*\nPin-Priority: -10\n' | sudo tee /etc/apt/preferences.d/no-snapd >/dev/null
        ok "snapd per APT-Pin gesperrt"
    fi
    # Dienste, die auf einer Einzelplatz-Workstation mit einer NVMe nichts tun
    for s in multipathd.service multipathd.socket ModemManager.service iscsid.socket iscsid.service \
             open-iscsi.service udisks2.service motd-news.timer apport.service ua-timer.timer esm-cache.service; do
        active=$(systemctl is-enabled "$s" 2>/dev/null) || true
        case $active in enabled|enabled-runtime|static) [ "$active" = static ] || list+=("$s") ;; esac
    done
    if [ ${#list[@]} -eq 0 ]; then skip "keine überflüssigen Dienste aktiv"; return; fi
    printf '  %sAktiv:%s %s\n' "$D" "$N" "${list[*]}"
    if ask "Diese Dienste abschalten? (spart RAM und Hintergrund-I/O; rückgängig mit systemctl enable)" j; then
        sudo systemctl disable --now "${list[@]}" >/dev/null 2>&1
        ok "abgeschaltet: ${list[*]}"
    fi
}

step_upgrade() {
    sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y || return 1
    ok "System aktuell"
    [ -e /var/run/reboot-required ] && REBOOT=1
    return 0
}

step_pakete() {
    local pkgs=(
        build-essential git curl wget ca-certificates gnupg nano less htop pciutils unzip
        xorg xinit x11-xserver-utils i3 i3status rxvt-unicode fonts-dejavu-core
        bubblewrap python3-venv python3-pip python3-dev
        libxi6 libxrender1 libxtst6 libfontconfig1 libgtk-3-bin mesa-utils
        nvtop
    )
    apt_install "${pkgs[@]}" || return 1
    ok "Grundpakete installiert (nano/less: B9)"
}

step_gum() {
    if command -v gum >/dev/null 2>&1; then ok "gum $(gum --version | awk '{print $NF}')"; return; fi
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg || return 1
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" |
        sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
    sudo apt-get update && apt_install gum || return 1
    ok "gum installiert"
}

step_uv() {
    local arch tmp base f
    if [ -x /usr/local/bin/uv ]; then
        ok "uv $(/usr/local/bin/uv --version | cut -d' ' -f2) – neu laden mit: sudo rm /usr/local/bin/uv{,x} && ./bootstrap.sh --only uv"
        return
    fi
    ask "uv installieren? (10–100× schnellere Paketinstallation; Pakete liegen nicht doppelt in Cache und .venv)" j ||
        { skip "ohne uv – ki nutzt pip"; return; }
    case $(uname -m) in
        x86_64)  arch=x86_64-unknown-linux-gnu ;;
        aarch64) arch=aarch64-unknown-linux-gnu ;;
        *) err "Architektur $(uname -m) nicht vorgesehen"; return 1 ;;
    esac
    tmp=$(mktemp -d); base=https://github.com/astral-sh/uv/releases/latest/download; f="uv-$arch.tar.gz"
    if ! curl -fsSL -o "$tmp/$f" "$base/$f" || ! curl -fsSL -o "$tmp/$f.sha256" "$base/$f.sha256"; then
        rm -rf "$tmp"; return 1
    fi
    if ! (cd "$tmp" && sha256sum -c "$f.sha256" >/dev/null); then
        err "Prüfsumme falsch"; rm -rf "$tmp"; return 1
    fi
    tar -xzf "$tmp/$f" -C "$tmp" && sudo install -m 0755 "$tmp/uv-$arch/uv" "$tmp/uv-$arch/uvx" /usr/local/bin/
    rm -rf "$tmp"
    ok "uv $(/usr/local/bin/uv --version | cut -d' ' -f2) nach /usr/local/bin (auch im Kerker sichtbar)"
}

step_nvidia() {
    if nvidia-smi -L >/dev/null 2>&1; then
        ok "Treiber läuft: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader)"
    else
        pkg_installed ubuntu-drivers-common || apt_install ubuntu-drivers-common || return 1
        say "Installiere den empfohlenen NVIDIA-Treiber …"
        sudo ubuntu-drivers install || return 1
        REBOOT=1
        ok "Treiber installiert – wirkt nach dem Neustart"
    fi
    if put ki-gpu.service /etc/systemd/system/ki-gpu.service; then sudo systemctl daemon-reload; fi
    sudo systemctl enable ki-gpu.service >/dev/null 2>&1
    nvidia-smi -L >/dev/null 2>&1 && sudo systemctl start ki-gpu.service
    ok "Persistence Mode beim Booten (ki-gpu.service)"
}

step_cuda() {
    local id repo keyring tmp
    if [ -x /usr/local/cuda/bin/nvcc ] || command -v nvcc >/dev/null 2>&1; then
        ok "CUDA-Toolkit vorhanden: $( (nvcc --version 2>/dev/null || /usr/local/cuda/bin/nvcc --version) | tail -n1)"; return
    fi
    printf '  %sPyTorch-Wheels bringen ihre CUDA-Bibliotheken selbst mit. Das Toolkit (~5 GB) brauchst du nur,\n  um selbst CUDA zu kompilieren (nvcc, z. B. llama.cpp mit CUDA, eigene Kernels).%s\n' "$D" "$N"
    ask "CUDA-Toolkit installieren?" n || { skip "ohne Toolkit"; return; }
    # B5: Repo aus der tatsächlichen Version ableiten statt fest ubuntu2404
    # shellcheck source=/dev/null
    id=$(. /etc/os-release; echo "${VERSION_ID//./}")
    repo="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$id/x86_64"
    keyring=$(curl -fsS "$repo/" 2>/dev/null | grep -o 'cuda-keyring_[0-9.]*-[0-9]*_all\.deb' | sort -V | tail -n1)
    if [ -n "$keyring" ]; then
        tmp=$(mktemp -d)
        if ! curl -fsSL -o "$tmp/$keyring" "$repo/$keyring" || ! sudo dpkg -i "$tmp/$keyring"; then
            rm -rf "$tmp"; return 1
        fi
        rm -rf "$tmp"
        sudo apt-get update && apt_install cuda-toolkit || return 1
        ok "CUDA-Toolkit aus dem NVIDIA-Repo ubuntu$id (PATH setzt ~/.config/ki/bashrc und der Kerker)"
    else
        say "NVIDIA hat (noch) kein Repo für ubuntu$id – nehme das Ubuntu-Paket nvidia-cuda-toolkit (multiverse)"
        apt_install nvidia-cuda-toolkit || return 1
        ok "nvidia-cuda-toolkit installiert"
    fi
}

bwrap_test() { bwrap --unshare-user --uid "$(id -u)" --gid "$(id -g)" --ro-bind / / true 2>/dev/null; }
step_bwrap() {
    command -v bwrap >/dev/null 2>&1 || apt_install bubblewrap || return 1
    if bwrap_test; then ok "bwrap darf User-Namespaces anlegen"; return; fi
    [ -d /etc/apparmor.d ] || { err "bwrap scheitert, AppArmor nicht vorhanden – Kernel-Einstellung prüfen"; return 1; }
    put apparmor-bwrap /etc/apparmor.d/bwrap
    sudo apparmor_parser -r /etc/apparmor.d/bwrap || return 1
    if bwrap_test; then ok "AppArmor-Profil /etc/apparmor.d/bwrap geladen"; else err "bwrap scheitert weiterhin"; return 1; fi
}

step_speicher() {
    local swaps dev changed=0 f
    # 1. zram – komprimierter Swap im RAM
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        ok "zram-Swap aktiv"
    elif pkg_installed systemd-zram-generator; then
        ok "systemd-zram-generator verwaltet zram (Ubuntu-Standard)"
    else
        apt_install zram-tools || return 1
        put zramswap /etc/default/zramswap || true
        sudo systemctl restart zramswap.service && ok "zram-Swap: zstd, 50 % RAM, Priorität 100"
    fi
    # 2. Swap auf der SSD: ersetzt durch zram, sonst sieht earlyoom zu spät, dass es eng wird
    swaps=$(swapon --show=NAME,TYPE --noheadings 2>/dev/null | grep -v zram)
    if [ -n "$swaps" ]; then
        printf '  %sSwap auf der SSD:%s %s\n' "$D" "$N" "$(awk '{print $1}' <<< "$swaps" | tr '\n' ' ')"
        if ask "SSD-Swap abschalten? zram ist ~100× schneller, und Swap-Thrashing friert das System ein" j; then
            while read -r dev _; do
                sudo swapoff "$dev" && sudo sed -i.ki-bak -E "s|^([^#]*[[:space:]]swap[[:space:]].*)$|# \1  # ki: durch zram ersetzt|" /etc/fstab
                if [ "$dev" = /swap.img ] && ask "Datei /swap.img löschen (gibt Platz frei)?" j; then sudo rm -f /swap.img; fi
            done <<< "$swaps"
            ok "SSD-Swap aus (Sicherung: /etc/fstab.ki-bak)"
        fi
    fi
    # 3. Alte swappiness aus v1 (10) würde unsere Einstellung überschreiben
    for f in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
        [ "$f" = /etc/sysctl.d/90-ki.conf ] && continue
        if grep -qE '^[[:space:]]*vm\.swappiness' "$f" 2>/dev/null; then
            sudo sed -i.ki-bak -E 's|^([[:space:]]*vm\.swappiness.*)$|# \1  # ki: siehe 90-ki.conf|' "$f"
            ok "alte swappiness in $f auskommentiert"
        fi
    done
    put sysctl-ki.conf /etc/sysctl.d/90-ki.conf && changed=1
    [ $changed = 1 ] && sudo sysctl -q --system
    ok "sysctl: swappiness 100 (zram), page-cluster 0, inotify 524288"
    # 4. earlyoom – lieber ein Prozess weg als Minuten Einfrieren
    pkg_installed earlyoom || apt_install earlyoom || return 1
    if put earlyoom /etc/default/earlyoom; then sudo systemctl restart earlyoom; fi
    sudo systemctl enable --now earlyoom >/dev/null 2>&1
    ok "earlyoom aktiv (schont Xorg, i3, Menü, SSH)"
    # 5. Journal begrenzen
    if put journald-ki.conf /etc/systemd/journald.conf.d/90-ki.conf; then sudo systemctl restart systemd-journald; fi
    ok "Systemlog auf 200 MB begrenzt"
}

step_igpu() {
    local slot conn c drv intel_connected=0
    slot=$(lspci -D -n -d 8086::0300 2>/dev/null | awk 'NR==1 {print $1}')
    if [ -z "$slot" ]; then
        skip "keine Intel-iGPU sichtbar. Zum Aktivieren im BIOS (ASRock): Advanced → Chipset Configuration →"
        skip "Primary Graphics Adapter = Onboard, IGPU Multi-Monitor = Enabled; dann erneut: ./bootstrap.sh --only igpu"
        return
    fi
    # 0000:00:02.0 → PCI:0:2:0 (Xorg will dezimal)
    IFS=':.' read -r _ b d f <<< "$slot"
    BUSID="PCI:$((16#$b)):$((16#$d)):$((16#$f))"
    for conn in /sys/class/drm/card*-*/status; do
        [ "$(cat "$conn" 2>/dev/null)" = connected ] || continue
        c=${conn%/status}; c=${c##*/}; c=${c%%-*}
        drv=$(basename "$(readlink -f "/sys/class/drm/$c/device/driver")" 2>/dev/null)
        case $drv in i915|xe) intel_connected=1 ;; esac
    done
    if [ -f /etc/X11/xorg.conf.d/10-ki-igpu.conf ]; then ok "Bildschirm läuft schon über die iGPU ($BUSID)"; return; fi
    printf '  %sMit dem Monitor am Mainboard-Ausgang zeichnet die Intel-GPU die Oberfläche. Die RTX 2060\n' "$D"
    printf '  bleibt komplett für CUDA: ~150–400 MB mehr VRAM, keine Ruckler während des Trainings.%s\n' "$N"
    if [ $intel_connected = 0 ]; then
        skip "Am Mainboard ist gerade kein Monitor angeschlossen. Erst umstecken, dann: ./bootstrap.sh --only igpu"
        return
    fi
    ask "Monitor hängt am Mainboard – Oberfläche auf die iGPU legen?" j || { skip "unverändert"; return; }
    put xorg-igpu.conf /etc/X11/xorg.conf.d/10-ki-igpu.conf
    ok "Xorg nutzt die iGPU ($BUSID) – wirkt nach Neustart. Notfall: Strg+Alt+F2, einloggen,"
    ok "sudo rm /etc/X11/xorg.conf.d/10-ki-igpu.conf"
    REBOOT=1
}

step_autologin() {
    if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ] &&
       grep -q -- "--autologin $USER_NAME" /etc/systemd/system/getty@tty1.service.d/autologin.conf; then
        ok "Autologin für $USER_NAME auf tty1"; return
    fi
    ask "Autologin für $USER_NAME auf tty1 (Start direkt ins Menü)?" j || { skip "ohne Autologin"; return; }
    put getty-autologin.conf /etc/systemd/system/getty@tty1.service.d/autologin.conf
    sudo systemctl daemon-reload
    ok "Autologin eingerichtet"
}

step_sudoers() {
    local tmp
    put ki-power /usr/local/sbin/ki-power 0755 || true
    tmp=$(mktemp)
    sed "s|@USER@|$USER_NAME|g" "$REPO/system/sudoers-ki" > "$tmp"
    if ! sudo visudo -cf "$tmp" >/dev/null; then err "sudoers-Regel ungültig – nichts geändert"; rm -f "$tmp"; return 1; fi
    sudo install -m 0440 "$tmp" /etc/sudoers.d/ki-workstation; rm -f "$tmp"
    [ -f /etc/sudoers.d/ki-workstation-poweroff ] && sudo rm -f /etc/sudoers.d/ki-workstation-poweroff
    ok "ohne Passwort: ki-power, systemctl poweroff/reboot (geprüft mit visudo)"
}

step_node() {
    if command -v node >/dev/null 2>&1; then ok "Node.js $(node --version)"; return; fi
    ask "Node.js + npm installieren (für Projekte mit Profil Node/JS)?" n || { skip "ohne Node.js"; return; }
    apt_install nodejs npm && ok "Node.js $(node --version)"
}

# ------------------------------------------------------------------ Ablauf
while [ $# -gt 0 ]; do
    case $1 in
        --yes|-y) YES=1 ;;
        --only)   ONLY=${2:-}; shift ;;
        --list)   for s in "${STEPS[@]}"; do printf '  %-10s %s\n' "$s" "${DESC[$s]}"; done; exit 0 ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ "$(id -u)" -eq 0 ] && { echo "Bitte als normaler Benutzer starten (sudo wird bei Bedarf gefragt)." >&2; exit 1; }
sudo -v || exit 1

LOG_DIR="$HOME/.local/state/ki"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# shellcheck source=/dev/null
printf '%sKI-Workstation – Systemeinrichtung%s (%s, Benutzer %s)\n' "$B" "$N" "$(. /etc/os-release; echo "$PRETTY_NAME")" "$USER_NAME"
for s in "${STEPS[@]}"; do
    if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$s,"* ]]; then continue; fi
    printf '\n%s[%s]%s %s\n' "$B" "$s" "$N" "${DESC[$s]}"
    "step_$s" || { err "Schritt $s fehlgeschlagen – später erneut: ./bootstrap.sh --only $s"; FAILED+=("$s"); }
done

printf '\n'
if [ ${#FAILED[@]} -gt 0 ]; then err "Fehlgeschlagen: ${FAILED[*]}  (Log: $LOG)"; else say "Alle Schritte erledigt. Log: $LOG"; fi
[ -z "$ONLY" ] && say "Weiter mit: ./install.sh   danach PyCharm: ki pycharm-update"
[ $REBOOT = 1 ] && say "Neustart nötig: sudo reboot"
[ ${#FAILED[@]} -eq 0 ]
