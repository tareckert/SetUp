# core/lib.sh – Werkzeuge für features/<name>/feature.sh (wird von ./setup geladen)
#
# Grundregel: Ein Feature legt seine eigenen Dateien nur in ~/.ki/<feature>/ ab (Programme, die
# nicht aus apt kommen, in /opt/ki/<feature>/). Alles, was es darüber hinaus anfassen MUSS
# (Dateien in /etc, Zeilen in ~/.profile, Dienste, apt-Pakete), läuft über diese Funktionen.
# Sie notieren jede Änderung im Manifest ~/.ki/<feature>/.manifest – "setup remove" macht sie
# daraus exakt rückgängig, auch gesicherte Originaldateien werden zurückgelegt.
#
# Manifest: eine Zeile pro Änderung, Felder durch Tabulator getrennt
#   file  <pfad> <sicherung|-> <modus>   Systemdatei angelegt/ersetzt
#   ufile <pfad> <sicherung|-> <modus>   Datei im Home angelegt/ersetzt (Pfad relativ zu ~)
#   mkdir <pfad>  / umkdir <pfad>        neu angelegter Ordner (wird entfernt, wenn leer)
#   line  <datei> <neu|alt>  / uline     Zeile mit Marke "# ki:<feature>" angehängt
#   comment <datei>                      Zeilen mit "#ki:<feature># " auskommentiert
#   enable <unit> / disable <unit>       Dienst ein-/ausgeschaltet
#   dir <pfad>                           Programmordner unter /opt/ki
#   upath <pfad>                         Datei/Ordner, den ein Programm im Home anlegt (relativ zu ~)
#   pkg <paket>                          apt-Paket, das dieses Feature neu installiert hat

# shellcheck disable=SC2086,SC2034  # $SUDO absichtlich ungequotet (leer in Tests); CHANGED lesen die Features
KI_ROOT=${KI_ROOT:-}          # Präfix für alle Systempfade – nur für Tests
SUDO=${SUDO-sudo}
KI_DIR=${KI_DIR:-$HOME/.ki}
USER_NAME=${USER_NAME:-$(id -un)}
YES=${YES:-0}

if [ -t 1 ]; then
    C_A=$'\e[38;5;173m' C_G=$'\e[38;5;107m' C_R=$'\e[38;5;210m' C_D=$'\e[2m' C_B=$'\e[1m' C_0=$'\e[0m'
    export C_B      # von ./setup genutzt
else
    C_A='' C_G='' C_R='' C_D='' C_B='' C_0=''
fi
say()  { printf '%s>%s %s\n' "$C_A" "$C_0" "$*"; }
ok()   { printf '  %s[ok]%s %s\n' "$C_G" "$C_0" "$*"; }
skip() { printf '  %s[--]%s %s\n' "$C_D" "$C_0" "$*"; }
note() { printf '  %s%s%s\n' "$C_D" "$*" "$C_0"; }
err()  { printf '  %s[!!]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
fail() { err "$*"; exit 1; }                   # beendet die Installation des Features (Subshell)
must() { "$@" || fail "fehlgeschlagen: $*"; }

ask() {   # ask "Frage" j|n → 0 = ja. Liest vom Terminal, damit es auch in Pipes funktioniert.
    local q=$1 def=${2:-j} a hint
    if [ "$def" = j ]; then hint="[J/n]"; else hint="[j/N]"; fi
    if [ "$YES" = 1 ] || ! { : </dev/tty; } 2>/dev/null; then [ "$def" = j ]; return; fi
    printf '  ? %s %s ' "$q" "$hint" >/dev/tty
    read -r a </dev/tty || a=""
    a=${a:-$def}
    [[ $a =~ ^[jJyY] ]]
}

# ------------------------------------------------------------------ Manifest
m_add() {
    local line
    line=$(printf '%s\t' "$@"); line=${line%$'\t'}
    grep -qxF -- "$line" "$MANIFEST" 2>/dev/null || printf '%s\n' "$line" >> "$MANIFEST"
}
m_has() {   # m_has <typ> <pfad>
    awk -F'\t' -v t="$1" -v p="$2" '$1 == t && $2 == p {f = 1} END {exit !f}' "$MANIFEST" 2>/dev/null
}

# Platzhalter in Vorlagen: @USER@ @HOME@ @KI_DIR@ @REPO@ @BUSID@
render() {
    sed -e "s|@USER@|$USER_NAME|g" -e "s|@HOME@|$HOME|g" -e "s|@KI_DIR@|$KI_DIR|g" \
        -e "s|@REPO@|$REPO|g" -e "s|@BUSID@|${BUSID:-}|g" "$1"
}

# Ersten noch fehlenden Ordner eines Pfads merken, damit er beim Entfernen wieder verschwindet
_track_mkdir() {   # _track_mkdir <typ mkdir|umkdir> <echter pfad> <manifest-pfad>
    local real=$2 rec=$3 top="" toprec=""
    while [ ! -e "$real" ] && [ "$real" != / ] && [ -n "$real" ]; do
        top=$real toprec=$rec
        real=${real%/*} rec=${rec%/*}
    done
    [ -n "$top" ] && m_add "$1" "$toprec"
    return 0
}

# sys_put <inhaltsdatei> <zielpfad> [modus] – legt eine Systemdatei ab (sichert ein vorhandenes Original)
CHANGED=0
sys_put() {
    local src=$1 dst=$2 mode=${3:-0644} real=$KI_ROOT$2 bak=- omode=0644
    CHANGED=0
    if ! m_has file "$dst"; then
        if [ -e "$real" ]; then
            bak="$FDIR/.orig$dst"; mkdir -p "${bak%/*}"
            $SUDO cat "$real" > "$bak" || fail "kann $dst nicht sichern"
            omode=$($SUDO stat -c %a "$real")
        else
            _track_mkdir mkdir "${real%/*}" "${dst%/*}"
        fi
        m_add file "$dst" "$bak" "$omode"
    fi
    if ! $SUDO cmp -s "$src" "$real" 2>/dev/null; then
        $SUDO install -D -m "$mode" "$src" "$real" || fail "kann $dst nicht schreiben"
        CHANGED=1
    fi
}
sys_file() {   # sys_file <vorlage im Feature-Ordner> <zielpfad> [modus]
    local tmp; tmp=$(mktemp)
    render "$FSRC/$1" > "$tmp"
    sys_put "$tmp" "$2" "${3:-0644}"
    rm -f "$tmp"
}
sys_text() {   # sys_text <zielpfad> <inhalt> [modus]
    local tmp; tmp=$(mktemp)
    printf '%s\n' "$2" > "$tmp"
    sys_put "$tmp" "$1" "${3:-0644}"
    rm -f "$tmp"
}

sys_sudoers() {   # sys_sudoers <vorlage> <name> – sudo-Regel, vorher mit visudo geprüft
    local tmp; tmp=$(mktemp)
    render "$FSRC/$1" > "$tmp"
    if ! visudo -cf "$tmp" >/dev/null 2>&1 && ! $SUDO visudo -cf "$tmp" >/dev/null; then
        rm -f "$tmp"; fail "sudo-Regel $1 ist ungültig – nichts geändert"
    fi
    sys_put "$tmp" "/etc/sudoers.d/$2" 0440
    rm -f "$tmp"
}

user_file() {   # user_file <vorlage> <pfad relativ zu ~> [modus]
    local dst=$2 mode=${3:-0644} real=$HOME/$2 bak=- omode=0644 tmp
    CHANGED=0
    if ! m_has ufile "$dst"; then
        if [ -e "$real" ]; then
            bak="$FDIR/.orig/home/$dst"; mkdir -p "${bak%/*}"; cp -p "$real" "$bak"
            omode=$(stat -c %a "$real")
        else
            _track_mkdir umkdir "${real%/*}" "${dst%/*}"
        fi
        m_add ufile "$dst" "$bak" "$omode"
    fi
    tmp=$(mktemp); render "$FSRC/$1" > "$tmp"
    if ! cmp -s "$tmp" "$real" 2>/dev/null; then install -D -m "$mode" "$tmp" "$real"; CHANGED=1; fi
    rm -f "$tmp"
}

sys_line() {   # sys_line <datei> <zeile> – Zeile mit Marke anhängen
    local f=$KI_ROOT$1 mark="# ki:$FEATURE" state=alt
    [ -e "$f" ] || state=neu
    if ! $SUDO grep -qF -- "$2  $mark" "$f" 2>/dev/null; then
        printf '%s  %s\n' "$2" "$mark" | $SUDO tee -a "$f" >/dev/null || fail "kann $1 nicht ändern"
    fi
    m_has line "$1" || m_add line "$1" "$state"
}
user_line() {   # user_line <datei relativ zu ~> <zeile>
    local f=$HOME/$1 mark="# ki:$FEATURE" state=alt
    [ -e "$f" ] || state=neu
    grep -qF -- "$2  $mark" "$f" 2>/dev/null || printf '%s  %s\n' "$2" "$mark" >> "$f"
    m_has uline "$1" || m_add uline "$1" "$state"
}
sys_comment() {   # sys_comment <datei> <ERE> – passende, aktive Zeilen auskommentieren
    local f=$KI_ROOT$1
    $SUDO sed -i -E "/^#/! { \\%$2% s|^|#ki:$FEATURE# | }" "$f" || fail "kann $1 nicht ändern"
    m_add comment "$1"
}

svc_enable() {   # Dienst einschalten (beim Entfernen wieder aus)
    if ! systemctl is-enabled --quiet "$1" 2>/dev/null; then m_add enable "$1"; fi
    $SUDO systemctl enable --now "$1" >/dev/null 2>&1 || fail "Dienst $1 startet nicht"
}
svc_disable() {   # Dienst abschalten (beim Entfernen wieder ein)
    local st
    st=$(systemctl is-enabled "$1" 2>/dev/null) || true
    case $st in enabled|enabled-runtime) ;; *) return 0 ;; esac
    m_add disable "$1"
    $SUDO systemctl disable --now "$1" >/dev/null 2>&1 || err "konnte $1 nicht abschalten"
}

opt_dir() {   # opt_dir – Programmordner /opt/ki/<feature> anlegen und merken, gibt den Pfad aus
    local d="/opt/ki/$FEATURE"
    m_add mkdir /opt/ki                  # jedes Feature merkt sich /opt/ki: wer zuletzt geht, räumt es weg
    m_add dir "$d"
    $SUDO mkdir -p "$KI_ROOT$d" || fail "kann $d nicht anlegen"
    printf '%s\n' "$d"
}
sys_mkdir() {   # sys_mkdir <pfad> – Systemordner anlegen (wird beim Entfernen gelöscht, wenn leer)
    _track_mkdir mkdir "$KI_ROOT$1" "$1"
    $SUDO mkdir -p "$KI_ROOT$1" || fail "kann $1 nicht anlegen"
}
user_path() {   # user_path <pfad relativ zu ~> – Pfad, den ein Programm selbst im Home anlegt
    _track_mkdir umkdir "$HOME/${1%/*}" "${1%/*}"
    m_add upath "$1"
}

apt_install() {   # nur die genannten Pakete, ohne "Empfehlungen" – hält das System schlank
    local missing=() p
    for p in "$@"; do
        [ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" = "install ok installed" ] || missing+=("$p")
    done
    [ ${#missing[@]} -eq 0 ] && return 0
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" ||
        fail "apt-get install ${missing[*]}"
}
apt_install_optional() {   # einzeln, unbekannte Paketnamen werden übersprungen
    local p
    for p in "$@"; do
        apt-cache show "$p" >/dev/null 2>&1 || { note "Paket $p gibt es hier nicht – übersprungen"; continue; }
        apt_install "$p"
    done
}

# ------------------------------------------------------------------ Rückgängig machen
# undo_manifest <manifest> <feature>: alles rückwärts zurückdrehen; gibt die Pakete in UNDO_PKGS zurück
UNDO_PKGS=()
undo_manifest() {
    local man=$1 feat=$2 t a b c
    UNDO_PKGS=()
    [ -f "$man" ] || return 0
    while IFS=$'\t' read -r t a b c; do
        case $t in
            file)    if [ "$b" != - ] && [ -f "$b" ]; then $SUDO install -D -m "${c:-0644}" "$b" "$KI_ROOT$a"
                     else $SUDO rm -f "$KI_ROOT$a"; fi ;;
            ufile)   if [ "$b" != - ] && [ -f "$b" ]; then install -D -m "${c:-0644}" "$b" "$HOME/$a"
                     else rm -f "$HOME/$a"; fi ;;
            mkdir)   [ -d "$KI_ROOT$a" ] && $SUDO find "$KI_ROOT$a" -depth -type d -empty -delete 2>/dev/null ;;
            umkdir)  [ -d "$HOME/$a" ] && find "$HOME/$a" -depth -type d -empty -delete 2>/dev/null ;;
            line)    $SUDO sed -i "/  # ki:$feat\$/d" "$KI_ROOT$a" 2>/dev/null
                     if [ "$b" = neu ] && [ ! -s "$KI_ROOT$a" ]; then $SUDO rm -f "$KI_ROOT$a"; fi ;;
            uline)   sed -i "/  # ki:$feat\$/d" "$HOME/$a" 2>/dev/null
                     if [ "$b" = neu ] && [ ! -s "$HOME/$a" ]; then rm -f "$HOME/$a"; fi ;;
            comment) $SUDO sed -i "s|^#ki:$feat# ||" "$KI_ROOT$a" 2>/dev/null ;;
            enable)  $SUDO systemctl disable --now "$a" >/dev/null 2>&1 ;;
            disable) $SUDO systemctl enable --now "$a" >/dev/null 2>&1 ;;
            dir)     case $a in /opt/ki/?*) $SUDO rm -rf "$KI_ROOT$a" ;; esac ;;
            upath)   case $a in ""|/*|*..*) ;; *) rm -rf "${HOME:?}/$a" ;; esac ;;
            pkg)     UNDO_PKGS+=("$a") ;;
        esac
    done < <(tac "$man")
}
