#!/usr/bin/env bash
# install.sh – spielt Skripte und Konfiguration der KI-Workstation ins Home-Verzeichnis ein.
#
# Idempotent: schreibt nur, was sich geändert hat, und sichert vorher jede Datei, die es
# überschreibt, nach ~/.local/state/ki/backup/. Braucht kein sudo.
#
#   ./install.sh            einspielen
#   ./install.sh --dry-run  nur anzeigen, was sich ändern würde
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DRY=0
[ "${1:-}" = --dry-run ] && DRY=1
STATE="$HOME/.local/state/ki"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$STATE/backup/ki-backup-$STAMP.tgz"

# Quelle (im Repo) → Ziel (relativ zu ~) → Modus
FILES=(
    "bin/ki                   bin/ki                        0755"
    "bin/ki-menu              bin/ki-menu                   0755"
    "bin/ki-status            bin/ki-status                 0755"
    "bin/run-project.sh       bin/run-project.sh            0755"
    "dotfiles/bash_profile    .bash_profile                 0644"
    "dotfiles/xinitrc         .xinitrc                      0755"
    "dotfiles/Xresources      .Xresources                   0644"
    "dotfiles/i3/config       .config/i3/config             0644"
    "dotfiles/i3status/config .config/i3status/config       0644"
    "dotfiles/ki-bashrc       .config/ki/bashrc             0644"
)
# Dateien aus v1, die ersetzt werden (werden gesichert und entfernt)
OBSOLETE=(bin/ki-menu.sh)

if [ -t 1 ]; then A=$'\e[38;5;173m' G=$'\e[38;5;107m' D=$'\e[2m' N=$'\e[0m'; else A='' G='' D='' N=''; fi

changed=() new=() backup=()
for entry in "${FILES[@]}"; do
    read -r src dst _ <<< "$entry"
    if [ ! -e "$HOME/$dst" ]; then new+=("$dst")
    elif ! cmp -s "$REPO/$src" "$HOME/$dst"; then changed+=("$dst"); backup+=("$dst")
    fi
done
for f in "${OBSOLETE[@]}"; do [ -e "$HOME/$f" ] && backup+=("$f"); done
grep -qs 'config/ki/bashrc' "$HOME/.bashrc" || { [ -e "$HOME/.bashrc" ] && backup+=(.bashrc); changed+=(".bashrc (+1 Zeile)"); }

printf '%sKI-Workstation – Einspielen%s aus %s\n' "$A" "$N" "$REPO"
[ ${#new[@]} -gt 0 ]     && printf '  %sneu:%s       %s\n' "$G" "$N" "${new[*]}"
[ ${#changed[@]} -gt 0 ] && printf '  %sgeändert:%s  %s\n' "$A" "$N" "${changed[*]}"
for f in "${OBSOLETE[@]}"; do [ -e "$HOME/$f" ] && printf '  %sentfernt:%s  %s (ersetzt durch ki-menu)\n' "$A" "$N" "$f"; done
if [ ${#new[@]} -eq 0 ] && [ ${#changed[@]} -eq 0 ]; then printf '  alles aktuell\n'; fi
[ $DRY = 1 ] && exit 0

mkdir -p "$STATE/backup" "$HOME/bin" "$HOME/projects" "$HOME/shared_data" \
         "$HOME/.config/JetBrains" "$HOME/.local/share/JetBrains" "$HOME/.java" \
         "$HOME/.config/ki" "$HOME/.local/share/ki"

# 1. Sicherung aller Dateien, die gleich überschrieben werden
if [ ${#backup[@]} -gt 0 ]; then
    tar -czf "$BACKUP" -C "$HOME" "${backup[@]}"
    printf '  %sSicherung:%s %s\n' "$D" "$N" "$BACKUP"
fi

# 2. Dateien einspielen
for entry in "${FILES[@]}"; do
    read -r src dst mode <<< "$entry"
    cmp -s "$REPO/$src" "$HOME/$dst" 2>/dev/null || install -D -m "$mode" "$REPO/$src" "$HOME/$dst"
done
for f in "${OBSOLETE[@]}"; do rm -f "$HOME/$f"; done
rm -rf "$HOME/.local/share/ki/templates"
cp -r "$REPO/templates" "$HOME/.local/share/ki/templates"
[ -f "$HOME/.config/ki/ki.conf" ] || cp "$REPO/dotfiles/ki.conf.example" "$HOME/.config/ki/ki.conf"
printf '%s\n' "$REPO" > "$HOME/.config/ki/repo"
if ! grep -qs 'config/ki/bashrc' "$HOME/.bashrc"; then
    printf '\n# KI-Workstation: PATH, CUDA, Tab-Vervollständigung für ki\n[ -f "$HOME/.config/ki/bashrc" ] && . "$HOME/.config/ki/bashrc"\n' >> "$HOME/.bashrc"
fi

# 3. Laufende Oberfläche neu laden (Fenster bleiben offen)
if [ -n "${DISPLAY:-}" ]; then
    xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
    if command -v i3-msg >/dev/null 2>&1; then i3-msg -q restart 2>/dev/null || true; fi
fi

printf '%s›%s Fertig.' "$A" "$N"
[ ${#backup[@]} -gt 0 ] && printf ' Rückweg: tar -xzf %s -C ~' "$BACKUP"
printf '\n'
if ls -d "$HOME"/projects/*/ >/dev/null 2>&1; then
    for d in "$HOME"/projects/*/; do
        [ -d "$d/code" ] && continue
        printf '%s›%s Projekte aus v1 gefunden – einmalig umstellen: ki migrate --all\n' "$A" "$N"
        break
    done
fi
