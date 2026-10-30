#!/usr/bin/env bash
# tests/run.sh – Prüfungen ohne Root, ohne echten Bildschirm, ohne Internet:
#   1. statisch: Syntax, shellcheck, i3-Konfiguration, Python
#   2. Setup-Kreislauf in einem Schein-System: alle Funktionen installieren, benutzen,
#      wieder entfernen – danach muss alles exakt wie vorher sein (keine Dateileichen)
#   3. Kerker mit echtem bubblewrap: Umgebung, Isolation, Jobs, Vorlagen, clone/import,
#      zwei PyCharm-Fenster (Schein-PyCharm), Restarter (B8), Fenster-Logik
#   4. echte Oberfläche auf virtuellem Bildschirm (Xvfb): Menü, Fenster nebeneinander, einzeln
#      schließen, zurück zum Menü – falls Xvfb, i3 und urxvt installiert sind
#   5. alles entfernen und mit dem Ausgangszustand vergleichen
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KI="$REPO/features/basis/bin/ki"
FAIL=0
pass()   { printf '  ok     %s\n' "$*"; }
nok()    { printf '  FEHLER %s\n' "$*"; FAIL=1; }
check()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else nok "$d"; fi; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else nok "$1: erwartet '$3', bekommen '$2'"; fi; }

cd "$REPO" || exit 1
echo "1. Statische Prüfungen"
BASH_FILES=(setup core/lib.sh core/ui.sh features/*/feature.sh features/basis/bin/ki features/menue/bin/ki-menu
            features/menue/bin/ki-einstellungen features/dateien/bin/ki-usb features/pycharm/bin/ki-pycharm
            features/oberflaeche/bin/ki-fenster tests/run.sh tests/stub)
SH_FILES=(features/basis/login.sh features/oberflaeche/start.sh features/oberflaeche/xinitrc
          features/oberflaeche/bin/ki-start features/oberflaeche/bin/ki-anzeige features/oberflaeche/bin/ki-statusbar
          features/dateien/bin/ki-dateien features/monitor/bin/ki-top features/menue/ki-power
          features/oberflaeche/bin/ki-menuschleife)
for f in "${BASH_FILES[@]}"; do check "bash -n $f" bash -n "$f"; done
for f in "${SH_FILES[@]}"; do check "sh -n $f" sh -n "$f"; done
if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck (bash)" env LC_ALL=C.UTF-8 shellcheck -x -s bash "${BASH_FILES[@]}"
    check "shellcheck (sh)" env LC_ALL=C.UTF-8 shellcheck -s sh "${SH_FILES[@]}"
else echo "  –      shellcheck nicht installiert"; fi
check "Python (ki-mount, Vorlagen)" python3 -c 'import ast, sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]' \
    features/dateien/ki-mount features/basis/templates/*/*.py
if command -v i3 >/dev/null 2>&1; then
    check "i3-Konfiguration gültig" env HOME=/nonexistent i3 -C -c features/oberflaeche/i3.conf
fi
mapfile -t order < <(sed -n 's/^ORDER=(\(.*\))$/\1/p' setup | tr ' ' '\n')
dirs=$(for d in features/*/; do d=${d%/}; echo "${d##*/}"; done | sort | paste -sd' ')
expect "jede Funktion steht in ORDER" "$(printf '%s\n' "${order[@]}" | sort | paste -sd' ')" "$dirs"
for f in features/*/feature.sh; do
    if ! grep -q '^feature_install()' "$f" || ! grep -q '^TITLE=' "$f" || ! grep -q '^DESC=' "$f"; then
        nok "$f: TITLE/DESC/feature_install fehlt"
    fi
done

if ! bwrap --unshare-user --uid "$(id -u)" --gid "$(id -g)" --ro-bind / / true 2>/dev/null; then
    echo "  –      bwrap nicht nutzbar – dynamische Tests übersprungen"; exit $FAIL
fi

echo "2. Setup-Kreislauf im Schein-System"
T=$(mktemp -d -p /var/tmp)   # nicht /tmp: das ersetzt der Kerker durch ein tmpfs
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home" KI_ROOT="$T/root" SUDO="" STUB_STATE="$T/stub" YES=1 XDG_RUNTIME_DIR="$T/run"
export STUB_PYCHARM="$T/fake-pycharm" KI_TEST_IDE_SLEEP=3
unset DISPLAY XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME SSH_AUTH_SOCK KI_PROJECT KI_USE_UV
mkdir -p "$T/bin" "$STUB_STATE" "$HOME" "$XDG_RUNTIME_DIR"
for c in apt-get apt-mark apt-cache dpkg-query systemctl swapon swapoff nvidia-smi lspci visudo sysctl \
         apparmor_parser mkswap ubuntu-drivers gpg timedatectl curl i3-msg i3status urxvt; do
    ln -s "$REPO/tests/stub" "$T/bin/$c"
done
ORIG_PATH=$PATH
export PATH="$T/bin:$PATH"
# Schein-System: wie ein frisches Ubuntu Server minimized
R=$KI_ROOT
mkdir -p "$R"/etc/{cloud,default,sudoers.d,sysctl.d,apt/preferences.d,apt/sources.list.d,systemd/system} "$R"/opt "$R"/media
printf '# gai.conf\n#precedence ::ffff:0:0/96  100\n' > "$R/etc/gai.conf"
printf 'UUID=abc / ext4 defaults 0 1\n/swap.img none swap sw 0 0\n' > "$R/etc/fstab"
head -c 1048576 /dev/zero > "$R/swap.img"; chmod 600 "$R/swap.img"
cp /etc/os-release "$R/etc/os-release"
cp /etc/skel/.profile /etc/skel/.bashrc "$HOME/" 2>/dev/null || printf '# profile\n' > "$HOME/.profile"
[ -f "$HOME/.bashrc" ] || printf '# bashrc\n' > "$HOME/.bashrc"
printf 'ubuntu-minimal\nopenssh-client\n' > "$STUB_STATE/manual"
printf 'multipathd.service\napt-daily.timer\nunattended-upgrades.service\n' > "$STUB_STATE/enabled"
echo /swap.img > "$STUB_STATE/swaps"
cat > "$STUB_PYCHARM" <<'SH'
#!/bin/sh
env > "$HOME/ide-env.txt"
touch "$HOME/.config/JetBrains/marker-$KI_PROJECT"
cp /bin/sleep "$HOME/restarter"
"$HOME/restarter" "${KI_TEST_IDE_SLEEP:-3}" &
exit 0
SH
chmod +x "$STUB_PYCHARM"

snapshot() {   # alles außer den Arbeitsordnern (projects, shared_data) und ~/.ki selbst
    (cd "$T" && find root home -mindepth 1 \( -path home/projects -o -path home/shared_data -o -path home/.ki \) -prune \
        -o -printf '%p %y %m\n' | sort)
    (cd "$T" && find root home \( -path home/projects -o -path home/shared_data -o -path home/.ki \) -prune \
        -o -type f -print0 | sort -z | xargs -0 md5sum)
    for f in manual installed enabled swaps; do echo "== $f"; sort "$STUB_STATE/$f" 2>/dev/null; done
}
before=$(snapshot)

ALL=(basis netz schlank speicher nvidia cuda uv oberflaeche autologin menue pycharm dateien monitor node fernzugriff)
check "setup install (alle außer igpu)" ./setup install "${ALL[@]}"
for f in "${ALL[@]}"; do [ -f "$HOME/.ki/$f/.installed" ] || nok "$f nicht als installiert markiert"; done
check "gai.conf: IPv4 zuerst" grep -q '^precedence ::ffff:0:0/96  100  # ki:netz$' "$R/etc/gai.conf"
check "fstab: Swap auskommentiert" grep -q '^#ki:speicher# /swap.img' "$R/etc/fstab"
check "SSD-Swapdatei entfernt" test ! -e "$R/swap.img"
check "sudo-Regeln" test -f "$R/etc/sudoers.d/ki-menue" -a -f "$R/etc/sudoers.d/ki-dateien"
check "uv in /opt/ki/uv" test -x "$R/opt/ki/uv/bin/uv"
check "PyCharm in /opt/ki/pycharm" test -x "$R/opt/ki/pycharm/current/bin/pycharm"
check "Root-Helfer in /opt/ki" test -x "$R/opt/ki/menue/ki-power" -a -x "$R/opt/ki/dateien/ki-mount"
check "Autologin-Drop-in" test -f "$R/etc/systemd/system/getty@tty1.service.d/ki-autologin.conf"
check "~/.profile-Zeile" grep -q '# ki:basis$' "$HOME/.profile"
check "Dienste abgeschaltet" bash -c "! grep -q multipathd '$STUB_STATE/enabled'"
check "mc-Lesezeichen in ~/.ki/dateien" test -f "$HOME/.ki/dateien/.config/mc/hotlist"
check "setup list zeigt Status" bash -c "./setup list | grep -q 'speicher.*installiert'"
check "setup files nennt /etc/fstab" bash -c "./setup files speicher | grep -q /etc/fstab"
check "inotify-Wert gehört zu pycharm" bash -c "grep -q max_user_watches '$R/etc/sysctl.d/90-ki-pycharm.conf' && ! grep -q inotify '$R/etc/sysctl.d/90-ki-speicher.conf'"
check "Git-Einstellungen in ~/.ki/basis/git (mit Zugangsdaten-Speicher)" bash -c "grep -q 'helper = store' '$HOME/.ki/basis/git/config' && test -f '$HOME/.ki/basis/git/credentials' && [ \"\$(stat -c %a '$HOME/.ki/basis/git/credentials')\" = 600 ] && ! test -e '$HOME/.gitconfig'"
expect "login.sh: Git-Einstellungen und UTF-8" "$(env -u LANG -u LC_ALL -u LC_CTYPE KI_REPO="$REPO" sh -c '. features/basis/login.sh; echo "$GIT_CONFIG_GLOBAL $LANG"')" "$HOME/.ki/basis/git/config C.UTF-8"
m1=$(cat "$HOME"/.ki/*/.manifest | wc -l)
check "erneut anwenden (idempotent)" ./setup install basis netz speicher
expect "keine doppelten Einträge" "$(cat "$HOME"/.ki/*/.manifest | wc -l)" "$m1"
expect "gai.conf-Zeile nur einmal" "$(grep -c 'ki:netz' "$R/etc/gai.conf")" "1"
check "igpu scheitert ohne Monitor" bash -c "! ./setup install igpu"
check "halbe Installation entfernbar" ./setup remove igpu
check "Abhängige werden mit entfernt" bash -c "./setup remove oberflaeche && test ! -e '$HOME/.ki/pycharm' && test ! -e '$HOME/.ki/autologin'"
check "und wieder installiert" ./setup install pycharm autologin

echo "3. Kerker mit bubblewrap"
P="$HOME/projects"
echo "KI_PYCHARM=\"$R/opt/ki/pycharm/current\"" >> "$HOME/.ki/basis/ki.conf"
check "ki new demo (Vorlage ml)" "$KI" new demo --vorlage ml
check ".venv angelegt (offline, python3 -m venv)" test -x "$P/demo/code/.venv/bin/python"
check "Vorlage kopiert" test -f "$P/demo/code/gpu_check.py" -a -f "$P/demo/code/.gitignore"
expect "Profil" "$(cat "$P/demo/.ki/profile")" "ml"
out=$("$KI" shell demo -- sh -c 'echo "$HOME|$PWD|$VIRTUAL_ENV|$XDG_CACHE_HOME|$(command -v python)|$KI_PROJECT|$HF_HOME"')
expect "Umgebung im Kerker" "$out" \
    "$HOME|$HOME/code|$HOME/code/.venv|$HOME/.system_cache|$HOME/code/.venv/bin/python|demo|$HOME/.system_cache/huggingface"
check "Host nur lesbar" bash -c "! '$KI' shell demo -- touch /usr/ki-test"
"$KI" shell demo -- sh -c 'touch ~/im-projekt' >/dev/null 2>&1
check "Schreiben landet im Projekt" test -f "$P/demo/im-projekt"
check "andere Projekte unsichtbar, ~/.ki ist das des Projekts" "$KI" shell demo -- sh -c '! ls ~/projects && test -f ~/.ki/profile && ! test -e ~/.ki/basis'
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
expect "Status nach Stopp" "$("$KI" jobs --porcelain demo | head -n1 | cut -f3)" "gestoppt"
sleep 1
"$KI" run demo --sh 'echo hallo; exit 3' >/dev/null
sleep 2
expect "Exit-Code gemeldet" "$("$KI" jobs --porcelain demo | head -n1 | cut -f3)" "fehler (3)"
check "Statusleiste meldet Job-Ende" bash -c "'$KI' statusbar | grep -q '✗ demo Fehler'"
check "Statusleiste meldet Stopp" bash -c "'$KI' statusbar | grep -q '■ demo gestoppt'"
sleep 1
"$KI" run demo -- python -c 'import cv2' >/dev/null
sleep 3
check "Tipp im Log: fehlendes Paket" grep -q 'ki pakete demo opencv-python' "$P/demo/.ki/jobs/$("$KI" jobs --porcelain demo | head -n1 | cut -f2).log"
expect "Job-Befehl neu startbar gemerkt" "$("$KI" _lastcmd demo)" 'python -c import\ cv2'
"$KI" new leer2 --vorlage py >/dev/null 2>&1
printf '# nur ein Kommentar\n' > "$P/leer2/code/requirements.txt"
check "ki pakete (requirements.txt, offline leer)" "$KI" pakete leer2
check "ki pakete ohne Pakete und requirements.txt scheitert verständlich" bash -c "rm '$P/leer2/code/requirements.txt'; '$KI' pakete leer2 2>&1 | grep -q 'Welche Pakete'"
expect "Job-Vorschlag ohne bisherige Jobs" "$("$KI" _lastcmd leer2)" "python main.py"
"$KI" rm leer2 --yes >/dev/null
mkdir -p "$P/demo/.system_cache/pip/x" && echo 1 > "$P/demo/.system_cache/pip/x/f"
check "ki clean" "$KI" clean demo pip
check "Cache leer, Ordner bleibt" test -d "$P/demo/.system_cache/pip" -a ! -e "$P/demo/.system_cache/pip/x"

# Fenster: Terminal und Dateien nebeneinander, jedes einzeln schließbar
calls() { cat "$STUB_STATE/calls.log" 2>/dev/null; }
check "ki terminal ohne Oberfläche läuft hier" bash -c "echo 'echo hallo-\$KI_PROJECT' | '$KI' terminal demo | grep -qx hallo-demo"
: > "$STUB_STATE/calls.log"
DISPLAY=:99 "$KI" terminal demo; sleep 1
check "Terminal-Fenster vom Menü aus → Fläche Extra" grep -qx 'i3-msg -q workspace 3:Extra' <(calls)
check "Terminal-Fenster startet ki shell demo" grep -q '^urxvt -title Terminal demo -e .*ki-fenster _innen .*/ki shell demo$' <(calls)
echo '[{"name":"2:IDE","focused":true}]' > "$STUB_STATE/i3_workspaces"; : > "$STUB_STATE/calls.log"
DISPLAY=:99 "$KI" dateien --fenster; sleep 1
check "Dateien von IDE aus → bleibt daneben auf derselben Fläche" bash -c "! grep -q 'i3-msg -q workspace' '$STUB_STATE/calls.log'"
check "Dateien-Fenster startet mc-Aufruf" grep -q '^urxvt -title Dateien -e .*ki-fenster _innen .*/ki-dateien$' <(calls)
rm -f "$STUB_STATE/i3_workspaces"
F="$REPO/features/oberflaeche/bin/ki-fenster"
echo '{"nodes":[{"type":"workspace","name":"3:Extra","nodes":[{"window":42,"focused":true}]}]}' > "$STUB_STATE/i3_tree"
: > "$STUB_STATE/calls.log"; DISPLAY=:99 WINDOWID=42 "$F" _innen true
check "letztes Fenster zu → zurück zum Menü" grep -qx 'i3-msg -q workspace 1:Menü' <(calls)
echo '{"nodes":[{"type":"workspace","name":"3:Extra","nodes":[{"window":42,"focused":true},{"window":43}]}]}' > "$STUB_STATE/i3_tree"
: > "$STUB_STATE/calls.log"; DISPLAY=:99 WINDOWID=42 "$F" _innen true
check "anderes Fenster bleibt offen → kein Sprung" bash -c "! grep -q 'i3-msg -q workspace' '$STUB_STATE/calls.log'"
rm -f "$STUB_STATE/i3_tree"

# Eigene Vorlage
mkdir -p "$HOME/.ki/basis/vorlagen/meine" && echo "# Meine Vorlage" > "$HOME/.ki/basis/vorlagen/meine/README.md"
echo ml > "$HOME/.ki/basis/vorlagen/meine/profil"; echo 'print(1)' > "$HOME/.ki/basis/vorlagen/meine/start.py"
echo "Meine eigene Vorlage" > "$HOME/.ki/basis/vorlagen/meine/beschreibung"
check "eigene Vorlage gelistet (mit Beschreibung)" bash -c "'$KI' new --vorlagen | grep -q '^meine.Meine eigene Vorlage$'"
expect "Vorlagen: ml zuerst, alle beschrieben" "$("$KI" new --vorlagen | head -n4 | cut -f1 | paste -sd' ')" "ml llm py node"
check "jede eingebaute Vorlage hat eine Beschreibung" bash -c "! '$KI' new --vorlagen | grep -qP '\t\$'"
check "ki new mit eigener Vorlage" "$KI" new eigen --vorlage meine
check "eigene Vorlage kopiert, Profil übernommen" bash -c "test -f '$P/eigen/code/start.py' && ! test -e '$P/eigen/code/profil' && ! test -e '$P/eigen/code/beschreibung' && grep -qx ml '$P/eigen/.ki/profile'"
check "ki new llm (Sprachmodell-Vorlage, Profil ml)" bash -c "'$KI' new sprach --vorlage llm >/dev/null && test -f '$P/sprach/code/chat.py' && grep -qx ml '$P/sprach/.ki/profile' && '$KI' rm sprach --yes >/dev/null"

# Git: gemeinsame Einstellungen und Zugangsdaten für Host, alle Projekte und PyCharm
check "ki git name" "$KI" git name "Test Nutzer" test@example.org
expect "Git-Name im Kerker" "$("$KI" shell demo -- git config --global user.name)" "Test Nutzer"
"$KI" shell demo -- sh -c 'printf "protocol=https\nhost=example.org\nusername=u\npassword=geheim\n" | git credential approve' >/dev/null 2>&1
check "Zugangsdaten aus dem Kerker auf dem Host gespeichert" grep -q 'u:geheim@example.org' "$HOME/.ki/basis/git/credentials"
expect "und in einem anderen Projekt nutzbar" "$("$KI" shell eigen -- sh -c 'printf "protocol=https\nhost=example.org\n\n" | git credential fill' 2>/dev/null | sed -n 's/^password=//p')" "geheim"
check "ki git vergessen" bash -c "'$KI' git vergessen && ! test -s '$HOME/.ki/basis/git/credentials'"

# clone und import (lokal, ohne Netz)
src="$T/quelle"; mkdir -p "$src/.venv" "$src/.idea"; echo 'torch' > "$src/requirements.txt"; echo x > "$src/main.py"
git -C "$src" init -q && git -C "$src" add requirements.txt main.py && git -C "$src" -c user.name=t -c user.email=t@t commit -qm init
check "ki clone" "$KI" clone "$src" geklont
check "geklont: Code + ML-Profil" bash -c "test -f '$P/geklont/code/main.py' && grep -qx ml '$P/geklont/.ki/profile'"
check "ki import" "$KI" import "$src" importiert
check "importiert ohne .venv/.idea" bash -c "test -f '$P/importiert/code/main.py' && ! test -e '$P/importiert/code/.idea' && test -x '$P/importiert/code/.venv/bin/python'"

# Zwei PyCharm-Fenster gleichzeitig (Schein-PyCharm), Kopie der Einstellungen, Restarter (B8)
vmo="$HOME/.ki/pycharm/config/PyCharm2099.1/pycharm64.vmoptions"
mkdir -p "${vmo%/*}" && printf -- '-Xmx3000m\n-Dide.no.platform.update=false\n' > "$vmo"   # eigene Werte
expect "Hinweis zum ersten PyCharm-Start" "$("$KI" _state | sed -n 's/^pycharm_neu=//p')" "1"
check "ki open demo (Fenster 1)" env DISPLAY=:99 "$KI" open demo
sleep 1
check "ki open eigen (Fenster 2)" env DISPLAY=:99 "$KI" open eigen
sleep 1
expect "beide Fenster sichtbar" "$("$KI" _state | sed -n 's/^ide=//p')" "demo,eigen"
check "selbes Projekt nicht doppelt" bash -c "DISPLAY=:99 '$KI' open demo | grep -q 'schon'"
check "Fenster 2 nutzt Kopie der Einstellungen" test -f "$HOME/.ki/pycharm/fenster-2/config/marker-demo"
check "Fenster 1 schreibt in die echten Einstellungen" test -f "$HOME/.ki/pycharm/config/marker-demo"
check "vmoptions ergänzt (keine Rückfragen beim Start)" grep -qx -- '-Djb.consents.confirmation.enabled=false' "$vmo"
check "eigene vmoptions-Werte bleiben" bash -c "grep -qx -- -Xmx3000m '$vmo' && ! grep -q -- -Xmx2048m '$vmo' && ! grep -qx -- -Dide.no.platform.update=true '$vmo'"
expect "Erststart-Hinweis danach aus" "$("$KI" _state | sed -n 's/^pycharm_neu=//p')" "0"
for _ in $(seq 20); do [ -z "$("$KI" _state | sed -n 's/^ide=//p')" ] && break; sleep 1; done
expect "Fenster nach Restarter-Ende zu (B8)" "$("$KI" _state | sed -n 's/^ide=//p')" ""
check "IDE-Log" grep -q '^# Ende' "$P/demo/.ki/ide.log"
check "ki mv" "$KI" mv eigen eigen2
check "ki rm" "$KI" rm eigen2 --yes
check "ki doctor läuft durch" bash -c "'$KI' doctor >/dev/null 2>&1; [ \$? -le 1 ]"
check "Funktionsbefehl erreichbar (ki pycharm versionen)" bash -c "'$KI' pycharm versionen | grep -q 2099.1"

echo "4. Echte Oberfläche: i3 + urxvt auf virtuellem Bildschirm"
if command -v Xvfb >/dev/null && command -v i3 >/dev/null && command -v urxvt >/dev/null && command -v xset >/dev/null; then
    (
        export PATH="$REPO/features/basis/bin:$ORIG_PATH" DISPLAY=:97
        Xvfb :97 -screen 0 1920x1080x24 >/dev/null 2>&1 & xv=$!
        for _ in $(seq 20); do xset q >/dev/null 2>&1 && break; sleep 0.25; done
        i3 -c "$REPO/features/oberflaeche/i3.conf" >"$T/i3.log" 2>&1 & i3p=$!
        # shellcheck disable=SC2317  # win/shown laufen über waitfor (eval)
        win() {   # "fläche|titel|x|breite" je Fenster
            i3-msg -t get_tree 2>/dev/null | python3 -c '
import json, sys
def walk(n, ws=None):
    if n.get("type") == "workspace": ws = n["name"]
    if n.get("window") and ws != "__i3_scratch" and ws: print("%s|%s|%s|%s" % (ws, n.get("name"), n["rect"]["x"], n["rect"]["width"]))
    for k in n.get("nodes", []) + n.get("floating_nodes", []): walk(k, ws)
walk(json.load(sys.stdin))'; }
        # shellcheck disable=SC2317
        shown() { i3-msg -t get_workspaces | python3 -c 'import json,sys; print(next(w["name"] for w in json.load(sys.stdin) if w["focused"]))'; }
        # shellcheck disable=SC2317  # wird über check aufgerufen
        waitfor() { for _ in $(seq 40); do eval "$1" >/dev/null 2>&1 && return 0; sleep 0.25; done; return 1; }
        check "Menü-Fenster erscheint auf der Fläche Menü" waitfor 'win | grep -q "^1:Menü|"'
        ki fenster --titel FensterA -- sleep 60
        check "Fenster vom Menü aus → Fläche Extra, Vollbild" waitfor 'win | grep -q "^3:Extra|FensterA|0|1920$"'
        ki fenster --titel FensterB -- sleep 60
        check "zweites Fenster teilt den Bildschirm (je 960 px)" waitfor 'win | grep -q "^3:Extra|FensterA|0|960$" && win | grep -q "^3:Extra|FensterB|960|960$"'
        i3-msg -q '[title="FensterA"] kill'
        check "einzeln geschlossen – das andere füllt den Bildschirm" waitfor 'win | grep -q "^3:Extra|FensterB|0|1920$" && ! win | grep -q FensterA'
        i3-msg -q '[title="FensterB"] kill'
        ki fenster --titel FensterC -- sleep 1
        check "nach dem letzten Fenster zurück zum Menü" waitfor '[ "$(shown)" = "1:Menü" ] && ! win | grep -q FensterC'
        check "Statusleiste und Menü ohne Fehler gestartet" bash -c "! grep -qi 'syntax error' '$T/i3.log'"
        i3-msg -q exit >/dev/null 2>&1; kill "$i3p" "$xv" 2>/dev/null; wait 2>/dev/null
        exit "$FAIL"
    ) || FAIL=1
else
    echo "  –      Xvfb/i3/urxvt/xset nicht installiert – übersprungen"
fi

echo "5. Alles entfernen – keine Dateileichen"
check "setup remove-all" ./setup remove-all
for f in "${ALL[@]}"; do [ -e "$HOME/.ki/$f" ] && nok "~/.ki/$f ist noch da"; done
check "/opt/ki weg" test ! -e "$R/opt/ki"
after=$(snapshot)
if [ "$before" = "$after" ]; then pass "System exakt wie vorher (Dateien, Rechte, Inhalte, Pakete, Dienste)"
else nok "Unterschiede nach dem Entfernen:"; diff <(echo "$before") <(echo "$after") | head -20; fi
check "Projekte bleiben erhalten" test -d "$P/demo/code"

echo
if [ $FAIL = 0 ]; then echo "Alle Tests bestanden."; else echo "Es gibt Fehler."; fi
exit $FAIL
