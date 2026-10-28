#!/usr/bin/env bash
# tests/run.sh – statische Prüfungen und Rauchtest von ki mit echtem bubblewrap.
# Läuft ohne Root, ohne X und ohne PyCharm (ein Schein-PyCharm prüft den GUI-Pfad).
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KI="$REPO/bin/ki"
FAIL=0
pass()   { printf '  ok    %s\n' "$*"; }
nok()    { printf '  FEHLER %s\n' "$*"; FAIL=1; }
check()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else nok "$d"; fi; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else nok "$1: erwartet '$3', bekommen '$2'"; fi; }

echo "Statische Prüfungen"
SH=(bin/ki bin/ki-menu bin/ki-status bin/run-project.sh bootstrap.sh install.sh system/ki-power
    dotfiles/bash_profile dotfiles/xinitrc dotfiles/ki-bashrc tests/run.sh)
for f in "${SH[@]}"; do check "bash -n $f" bash -n "$REPO/$f"; done
if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck" env LC_ALL=C.UTF-8 shellcheck -x -s bash "${SH[@]/#/$REPO/}"
else echo "  –     shellcheck nicht installiert"; fi
check "Python-Vorlagen" python3 -c 'import ast, sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]' \
    "$REPO"/templates/*/*.py

echo "Rauchtest mit bubblewrap"
if ! bwrap --unshare-user --uid "$(id -u)" --gid "$(id -g)" --ro-bind / / true 2>/dev/null; then
    echo "  –     bwrap nicht nutzbar – Rauchtest übersprungen"; exit $FAIL
fi
T=$(mktemp -d -p /var/tmp)   # nicht /tmp: das ersetzt der Kerker durch ein tmpfs
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run"
unset DISPLAY XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME SSH_AUTH_SOCK KI_PROJECT
mkdir -p "$HOME/.config/ki" "$XDG_RUNTIME_DIR"
P="$HOME/projects"

# Ohne uv: klassisches venv + pip
echo "KI_USE_UV=0" > "$HOME/.config/ki/ki.conf"
check "ki new ohne uv" "$KI" new nouv
check "pip im .venv" "$KI" shell nouv -- pip --version
rm -f "$HOME/.config/ki/ki.conf"

check "ki new demo" "$KI" new demo --profile ml
check ".venv angelegt" test -x "$P/demo/code/.venv/bin/python"
check "Vorlagen kopiert" test -f "$P/demo/code/gpu_check.py" -a -f "$P/demo/code/.gitignore"
expect "Profil" "$(cat "$P/demo/.ki/profile")" "ml"
out=$("$KI" shell demo -- sh -c 'echo "$HOME|$PWD|$VIRTUAL_ENV|$XDG_CACHE_HOME|$(command -v python)|$KI_PROJECT|$HF_HOME"')
expect "Umgebung im Kerker" "$out" \
    "$HOME|$HOME/code|$HOME/code/.venv|$HOME/.system_cache|$HOME/code/.venv/bin/python|demo|$HOME/.system_cache/huggingface"
check "Host nur lesbar" bash -c "! '$KI' shell demo -- touch /usr/ki-test"
"$KI" shell demo -- sh -c 'touch ~/im-projekt' >/dev/null 2>&1
check "Schreiben landet im Projekt" test -f "$P/demo/im-projekt"
check "andere Projekte unsichtbar" "$KI" shell demo -- sh -c '! ls ~/projects'
check "Python im Kerker läuft" "$KI" shell demo -- python -c 'import sys; assert sys.prefix.endswith("/code/.venv")'

# Jobs: Stopp per Strg+C erreicht nur das Programm, es kann aufräumen
cat > "$P/demo/code/job.py" <<'PY'
import time
print("start", flush=True)
try:
    while True:
        time.sleep(0.1)
except KeyboardInterrupt:
    print("sauber beendet", flush=True)
PY
check "ki run" "$KI" run demo -- python job.py
sleep 2
expect "Job läuft" "$("$KI" jobs --porcelain demo | head -n1 | cut -f3)" "läuft"
check "ki stop" "$KI" stop demo
sleep 1
id=$("$KI" jobs --porcelain demo | head -n1 | cut -f2)
check "Job hat aufgeräumt (KeyboardInterrupt)" grep -q "sauber beendet" "$P/demo/.ki/jobs/$id.log"
expect "Job-Status nach Stopp" "$("$KI" jobs --porcelain demo | head -n1 | cut -f3)" "fertig"
sleep 1
"$KI" run demo --sh 'echo hallo; exit 3' >/dev/null
sleep 2
expect "Exit-Code wird gemeldet" "$("$KI" jobs --porcelain demo | head -n1 | cut -f3)" "fehler (3)"
expect "letzter Befehl" "$("$KI" _lastcmd demo)" "echo hallo; exit 3"

# Cache leeren: Inhalt weg, Ordner bleiben
mkdir -p "$P/demo/.system_cache/pip/x" && echo 1 > "$P/demo/.system_cache/pip/x/f"
check "ki clean" "$KI" clean demo
check "Cache leer, Ordner bleibt" test -d "$P/demo/.system_cache/pip" -a ! -e "$P/demo/.system_cache/pip/x"

# Umbenennen bricht nichts: im Kerker ist jedes Projekt ~
check "ki mv" "$KI" mv demo demo2
check "nach Umbenennen läuft Python" "$KI" shell demo2 -- python -c 'print(1)'

# Schein-PyCharm: prüft GUI-Kerker, IDE-Sperre und das Warten auf den Restarter (B8)
mkdir -p "$T/pycharm/bin"
cat > "$T/pycharm/bin/pycharm" <<'SH'
#!/bin/sh
env > "$HOME/ide-env.txt"
touch "$HOME/.config/JetBrains/marker"
cp /bin/sleep "$HOME/restarter"
"$HOME/restarter" 3 &
exit 0
SH
chmod +x "$T/pycharm/bin/pycharm"
echo "{\"dataDirectoryName\": \"PyCharm2099.1\", \"version\": \"2099.1\"}" > "$T/pycharm/product-info.json"
echo "KI_PYCHARM=\"$T/pycharm\"" > "$HOME/.config/ki/ki.conf"
start=$(date +%s)
DISPLAY=:99 KI_FOREGROUND=1 "$KI" open demo2 >/dev/null 2>&1 &
sleep 1
check "IDE-Sperre sichtbar" grep -q '^ide=demo2$' <("$KI" _state)
check "zweite IDE wird abgelehnt" bash -c "! DISPLAY=:99 '$KI' open demo2x 2>/dev/null"
wait
dur=$(( $(date +%s) - start ))
check "Kerker wartet auf Restarter (B8)" test "$dur" -ge 3
check "JetBrains-Einstellungen global" test -f "$HOME/.config/JetBrains/marker"
check "vmoptions angelegt" grep -q -- '-Xmx2048m' "$HOME/.config/JetBrains/PyCharm2099.1/pycharm64.vmoptions"
check "IDE-Log geschrieben" grep -q '^# Ende' "$P/demo2/.ki/ide.log"
check "IDE-Sperre frei" grep -q '^ide=$' <("$KI" _state)

# Migration eines v1-Projekts (Code und .venv direkt im Projektordner)
mkdir -p "$P/alt/.system_cache/pycharm" "$P/alt/.idea" "$P/alt/.git" "$P/alt/src"
echo 'print("alt")' > "$P/alt/main.py"; echo "KI/ML" > "$P/alt/.system_cache/.profile"
bwrap --unshare-user --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --bind "$P/alt" "$HOME" \
    python3 -m venv "$HOME/.venv" >/dev/null 2>&1
check "altes Layout erkannt" bash -c "! '$KI' shell alt -- true 2>/dev/null"
check "ki migrate" "$KI" migrate alt
check "Code nach code/" test -f "$P/alt/code/main.py" -a -d "$P/alt/code/.git" -a -d "$P/alt/code/src"
check "alte .idea gesichert" test -d "$P/alt/.ki/idea-alt"
expect "Profil übernommen" "$(cat "$P/alt/.ki/profile")" "ml"
check "verschobenes .venv funktioniert" "$KI" shell alt -- sh -c 'python -c "import sys; assert sys.prefix.endswith(\"/code/.venv\")" && pip --version'

check "ki rm" "$KI" rm demo2 --yes
check "Projekt weg" test ! -e "$P/demo2"
check "ki doctor läuft durch" bash -c "'$KI' doctor >/dev/null 2>&1; [ \$? -le 1 ]"

echo
if [ $FAIL = 0 ]; then echo "Alle Tests bestanden."; else echo "Es gibt Fehler."; fi
exit $FAIL
