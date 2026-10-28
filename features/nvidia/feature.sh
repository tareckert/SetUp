# nvidia – NVIDIA-Treiber und Persistence Mode
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="NVIDIA"
DESC="NVIDIA-Treiber (empfohlene Version) + Persistence Mode für schnellen CUDA-Start"
DEFAULT=1
NEEDS="basis"
PACKAGES="ubuntu-drivers-common"

feature_install() {
    apt_install $PACKAGES
    if nvidia-smi -L >/dev/null 2>&1; then
        ok "Treiber läuft: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null)"
    else
        say "Installiere den empfohlenen NVIDIA-Treiber …"
        must $SUDO ubuntu-drivers install
        touch "$KI_DIR/.neustart"
        ok "Treiber installiert – wirkt nach dem Neustart"
    fi
    sys_file ki-gpu.service /etc/systemd/system/ki-gpu.service
    $SUDO systemctl daemon-reload
    if nvidia-smi -L >/dev/null 2>&1; then svc_enable ki-gpu.service
    else m_add enable ki-gpu.service; $SUDO systemctl enable ki-gpu.service >/dev/null 2>&1; fi
    ok "Persistence Mode beim Booten (ki-gpu.service)"
}
