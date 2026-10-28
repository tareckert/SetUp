# cuda – CUDA-Toolkit (nvcc). PyTorch braucht es NICHT – seine Wheels bringen CUDA mit.
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="CUDA-Toolkit"
DESC="nvcc zum Selbstkompilieren (llama.cpp, eigene Kernels) – für PyTorch nicht nötig, ~5 GB"
DEFAULT=0
NEEDS="nvidia"
PACKAGES=""

feature_install() {
    local id repo keyring tmp
    # B5: Repo aus der tatsächlichen Ubuntu-Version ableiten
    # shellcheck source=/dev/null
    id=$(. "$KI_ROOT/etc/os-release"; echo "${VERSION_ID//./}")
    repo="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$id/x86_64"
    keyring=$(curl -fsS --max-time 20 "$repo/" 2>/dev/null | grep -o 'cuda-keyring_[0-9.]*-[0-9]*_all\.deb' | sort -V | tail -n1)
    if [ -n "$keyring" ]; then
        tmp=$(mktemp -d)
        must curl -fsSL -o "$tmp/$keyring" "$repo/$keyring"
        must $SUDO dpkg -i "$tmp/$keyring"
        rm -rf "$tmp"
        must $SUDO apt-get update -qq
        apt_install cuda-toolkit
        ok "CUDA-Toolkit aus dem NVIDIA-Repo ubuntu$id (/usr/local/cuda/bin kommt automatisch in den PATH)"
    else
        note "NVIDIA hat (noch) kein Repo für ubuntu$id – nehme das Ubuntu-Paket"
        apt_install nvidia-cuda-toolkit
        ok "nvidia-cuda-toolkit installiert"
    fi
}
