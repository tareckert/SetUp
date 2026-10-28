# uv – schneller Python-Paketmanager nach /opt/ki/uv (auch im Kerker sichtbar)
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="uv"
DESC="uv: Pakete ein Vielfaches schneller installieren, keine Doppelkopien (Hardlinks)"
DEFAULT=1
NEEDS="basis"
PACKAGES=""

feature_install() {
    local arch dir tmp base f
    case $(uname -m) in
        x86_64)  arch=x86_64-unknown-linux-gnu ;;
        aarch64) arch=aarch64-unknown-linux-gnu ;;
        *) fail "Architektur $(uname -m) nicht vorgesehen" ;;
    esac
    dir=$(opt_dir)
    if [ -x "$KI_ROOT$dir/bin/uv" ]; then
        ok "uv $("$KI_ROOT$dir/bin/uv" --version | cut -d' ' -f2) vorhanden (neueste Version: ki setup reinstall uv)"
        return 0
    fi
    tmp=$(mktemp -d); base=https://github.com/astral-sh/uv/releases/latest/download; f="uv-$arch.tar.gz"
    if ! curl -fsSL -o "$tmp/$f" "$base/$f" || ! curl -fsSL -o "$tmp/$f.sha256" "$base/$f.sha256"; then
        rm -rf "$tmp"; fail "Download fehlgeschlagen"
    fi
    (cd "$tmp" && sha256sum -c "$f.sha256" >/dev/null) || { rm -rf "$tmp"; fail "Prüfsumme stimmt nicht"; }
    tar -xzf "$tmp/$f" -C "$tmp" || { rm -rf "$tmp"; fail "Archiv defekt"; }
    must $SUDO install -D -m 0755 "$tmp/uv-$arch/uv" "$KI_ROOT$dir/bin/uv"
    must $SUDO install -D -m 0755 "$tmp/uv-$arch/uvx" "$KI_ROOT$dir/bin/uvx"
    rm -rf "$tmp"
    ok "uv $("$KI_ROOT$dir/bin/uv" --version | cut -d' ' -f2) in $dir"
}
