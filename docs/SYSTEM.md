# KI-Workstation – Systemdokumentation v2

Stand: 28.10.2026 · ersetzt v1 · Änderungen und Begründungen: [REVIEW.md](REVIEW.md)

## 1. Ziel und Philosophie

Eine schlanke Entwicklungs- und KI-Workstation, deren Host-System dauerhaft sauber bleibt: Jedes Projekt
lebt in einem eigenen Ordner, alles, was beim Arbeiten entsteht, landet dort. Ordner löschen = Projekt
spurlos weg.

Die vier Kernziele, in dieser Rangfolge (unverändert):

1. **Zero-Garbage** – Caches, Pakete, Modelle, Compilate und IDE-Indizes landen im Projektordner.
2. **Stabilität** – Start ohne Eingriff ins Menü, kein Absturz lässt einen unbedienbaren Zustand zurück.
3. **Performance** – minimaler Grundverbrauch; RAM, CPU und die ganze GPU gehören dem Training.
4. **Bedienkomfort** – dunkles Textmenü, neue Projekte ohne Handarbeit, alles auch per SSH.

**Bedrohungsmodell:** Der Code im Kerker gilt als vertrauenswürdig. bwrap dient der Ordner- und
Cache-Isolation, nicht als Sicherheits-Sandbox. Der Host ist komplett lesbar eingebunden; geschützt
wird nur gegen ungewolltes Schreiben.

**Nicht-Ziele:** Schutz vor Schadcode, Mehrbenutzerbetrieb, Docker/Container-Orchestrierung,
Maussteuerung im Menü, Compositor-Effekte.

## 2. Hardware und Basis

| Komponente | Wert | Hinweis |
|---|---|---|
| Mainboard | ASRock Z270 Extreme4, UEFI P2.30, CSM aus, AHCI | BIOS-Update prüfen |
| CPU | Intel Core i7-7700K, 4 Kerne / 8 Threads, **mit HD 630 (iGPU)** | iGPU kann den Bildschirm übernehmen (Abschnitt 4.7) |
| RAM | 16 GB (2 von 4 Slots) | zram erweitert effektiv (Abschnitt 4.6) |
| GPU | RTX 2060, 6 GB, Turing (Compute Capability 7.5) | fp16-Tensor-Cores, kein bf16 in Hardware |
| Treiber | 595.91.07, CUDA bis 13.2 | |
| SSD | NVMe, Dual-Boot mit Windows, Ubuntu-Partition ~970 GB ext4 | |
| OS | Ubuntu Server 26.04 LTS minimized, Kernel 7.0 | Secure Boot aus → kein MOK-Schritt |
| Benutzer | `tb@tserv`, Tastatur `de` | |
| IDE | PyCharm (vereinheitlicht, ohne Abo kostenlos) unter `/opt/pycharm` | Symlink auf die aktuelle Version |

## 3. Architektur

```
Boot ─► getty tty1 (Autologin) ─► ~/.bash_profile ─► startx ─► ~/.xinitrc (xrdb) ─► i3
                                   2 s „Taste = Konsole“                               │
     ┌─────────────────────────────────────────────────────────────────────────────────┘
     │  Arbeitsfläche 1: urxvt „ki-menu“ (gum)   ← kommt immer wieder, auch nach Absturz
     │  Arbeitsfläche 2: PyCharm                 ← läuft im Hintergrund, Menü bleibt frei
     │  Arbeitsfläche 3: Jupyter, GPU-Monitor, Terminals
     │  Leiste: Jobs · GPU-Last/VRAM/Temperatur · CPU · RAM · SSD · Uhr
     ▼
  ki (CLI) ─► bwrap-Kerker ─► PyCharm | bash | Job | JupyterLab
```

**Der Kerker** (eine Instanz pro IDE, Terminal oder Job):

```
/                  Host, nur lesbar (Treiber, CUDA, Python, /opt/pycharm, uv)
/tmp, /run/user/…  tmpfs im RAM, beim Schließen weg
/dev               minimal + /dev/nvidia*, /dev/dri
~                  = ~/projects/<name>/       (Home-Swap, beschreibbar)
  ├── code/        = PyCharm-Projektwurzel, dein Code
  │   └── .venv/   Python-Umgebung – Pfad ~/code/.venv in jedem Projekt gleich
  ├── .system_cache/  pip, uv, huggingface, torch, triton, torchinductor, nv, JetBrains-Index
  ├── .ki/         profile, env, ide.log, jobs/<id>.{cmd,log,pid,exit}
  ├── .bashrc      von ki erzeugt (Prompt, Hinweise); eigenes in .bashrc.local
  └── shared_data  = ~/shared_data des Hosts, nur lesbar
~/.config/JetBrains, ~/.local/share/JetBrains, ~/.java   (nur bei PyCharm) global geteilt
~/.gitconfig, ~/.ssh/config, ~/.ssh/known_hosts          nur lesbar; SSH-Agent-Socket
```

Andere Projekte und der Rest des Host-Homes sind im Kerker unsichtbar.

## 4. Komponenten

### 4.1 Repository

```
bootstrap.sh          Systemeinrichtung (sudo), Schritte einzeln wiederholbar
install.sh            Benutzer-Dateien einspielen, mit Sicherung
bin/ki                CLI: Projekte, Kerker, Jobs, Jupyter, Diagnose, Updates
bin/ki-menu           gum-Menü (reine Oberfläche über ki)
bin/ki-status         Statuszeile für i3bar
bin/run-project.sh    Kompatibilität mit v1 (= ki open)
dotfiles/             .bash_profile, .xinitrc, .Xresources, i3, i3status, Bash-Ergänzung, ki.conf
system/               Vorlagen für /etc und /usr/local/sbin (von bootstrap.sh verwendet)
templates/            Projektvorlagen: common, ml, py, node
tests/run.sh          shellcheck + Rauchtest mit echtem bubblewrap
```

### 4.2 bootstrap.sh

Läuft als normaler Benutzer, fragt sudo bei Bedarf. Jeder Schritt prüft zuerst, ob er schon erledigt
ist. `./bootstrap.sh --list` zeigt alle, `--only a,b` wählt aus, `--yes` nimmt die Vorgaben.
Log: `~/.local/state/ki/bootstrap-*.log`.

| Schritt | Was passiert | Warum |
|---|---|---|
| netz | `precedence ::ffff:0:0/96 100` in `/etc/gai.conf` | B10: IPv4 zuerst für alle Programme, IPv6 bleibt als Ausweich |
| ballast | cloud-init deaktivieren (nicht purgen: netplan.io), snapd entfernen + Pin, nach Rückfrage multipathd, iscsid, ModemManager, udisks2, motd-news, apport, ua-timer, esm-cache abschalten | kein Hintergrund-RAM/-I/O |
| upgrade | `apt update` + `full-upgrade` | aktuelle Basis |
| pakete | build-essential, git, curl, wget, gnupg, nano, less, htop, nvtop, xorg, xinit, i3, i3status, rxvt-unicode, fonts-dejavu-core, bubblewrap, python3-venv/-pip/-dev, PyCharm-Bibliotheken | B9 behoben |
| gum | Charm-APT-Repo + gum | Menü |
| uv | aktuelles uv-Release von GitHub, Prüfsumme geprüft, nach `/usr/local/bin` | schnell, Hardlinks statt Doppelkopien, im Kerker sichtbar |
| nvidia | `ubuntu-drivers install`, falls `nvidia-smi` nicht antwortet; `ki-gpu.service` (Persistence Mode) | schneller CUDA-Start |
| cuda | optional (Vorgabe nein): Repo aus `/etc/os-release` (B5), sonst Ubuntu-Paket | nur für eigenes nvcc nötig |
| bwrap | AppArmor-Profil nur, falls bwrap keinen User-Namespace bekommt | Ubuntu sperrt unprivilegierte Namespaces |
| speicher | zram (zstd, 50 %, Prio 100), SSD-Swap nach Rückfrage aus, alte swappiness auskommentiert, `90-ki.conf` (swappiness 100, page-cluster 0, inotify 524288), earlyoom, Journal 200 MB | Abschnitt 4.6 |
| igpu | optional: Xorg auf die Intel-iGPU, nur wenn dort ein Monitor erkannt wird | Abschnitt 4.7 |
| autologin | getty-Drop-in für tty1 | Autostart |
| sudoers | `/usr/local/sbin/ki-power`, `systemctl poweroff/reboot` ohne Passwort, mit `visudo -c` geprüft | Menü |
| node | optional: nodejs + npm | Profil Node/JS |

### 4.3 install.sh

Spielt `bin/` nach `~/bin`, die Dotfiles, Vorlagen nach `~/.local/share/ki/templates` und legt
`~/projects`, `~/shared_data`, die JetBrains-Ordner und `~/.config/ki/ki.conf` an. Schreibt nur
geänderte Dateien, sichert vorher alle überschriebenen nach
`~/.local/state/ki/backup/ki-backup-<zeit>.tgz` und lädt eine laufende Oberfläche neu (`xrdb`,
`i3-msg restart` – Fenster bleiben offen). `--dry-run` zeigt nur an. Rückweg:
`tar -xzf <sicherung> -C ~`.

### 4.4 Autostart

1. `getty@tty1` loggt `tb` automatisch ein (`/etc/systemd/system/getty@tty1.service.d/autologin.conf`).
2. `~/.bash_profile` lädt `~/.profile` (PATH mit `~/bin`), startet auf tty1 ohne X nach 2 Sekunden
   `startx`. Taste in den 2 Sekunden = Konsole; `touch ~/.ki-no-x` schaltet den Autostart dauerhaft ab.
   SSH startet nie X. Endet X, bleibt die Konsole mit Hinweis auf `~/.local/state/ki/xsession.log`.
3. `~/.xinitrc` lädt `~/.Xresources` **vor** i3 (B2) und startet i3.
4. i3 startet das Menü in einer Schleife; bricht es ab, bleibt eine Shell im Fenster.

### 4.5 ki und das Menü

`ki` ist die eine Quelle aller Aktionen, `ki-menu` nur die Oberfläche darüber. Übersicht: `ki help`.

| Menü | CLI | Funktion |
|---|---|---|
| ▶ Weiter mit … | `ki open <p>` | zuletzt genutztes Projekt in PyCharm (bzw. „Zu PyCharm“, wenn offen) |
| Projekt öffnen | `ki open <p>` | PyCharm im Kerker auf Arbeitsfläche 2; nur eine IDE gleichzeitig |
| Neues Projekt | `ki new <p> --profile ml\|py\|node [--torch] [--python 3.12]` | Ordner, Vorlage, `git init`, `.venv`; ML optional mit PyTorch |
| Terminal im Projekt | `ki shell <p> [befehl]` | Shell im Kerker ohne IDE; `exit` = zurück |
| Training & Jobs | `ki run <p> -- cmd`, `ki jobs`, `ki logs`, `ki stop` | Hintergrund-Jobs mit Log; Stopp = Strg+C, nach 30 s hart |
| | `ki jupyter <p> [port]` | JupyterLab auf 127.0.0.1, Zugriff vom Zweitrechner per SSH-Tunnel |
| | `ki top`, `ki power …` | nvtop; CPU-Modus Leistung/ausgewogen |
| Projekte verwalten | `ki list --size`, `ki clean`, `ki mv`, `ki rm`, `ki migrate` | Größe, Cache je Ordner leeren, Umbenennen, Löschen, v1-Projekte umstellen, Dateibrowser |
| System | `ki status`, `ki doctor`, `ki update`, `ki pycharm-update` | Status, Diagnose, apt-Update, Setup-Update, PyCharm-Update, Host-Terminal, Neustart |
| Hilfe & Tasten | `ki help` | Spickzettel |

**Profile** (gespeichert in `.ki/profile`): `ml` setzt `HF_HOME`, `TORCH_HOME`,
`TORCHINDUCTOR_CACHE_DIR`, `TRITON_CACHE_DIR`, `CUDA_CACHE_PATH` (alle in `.system_cache`) und
`PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`; `node` setzt `NPM_CONFIG_CACHE` und
`NPM_CONFIG_PREFIX=~/.local`; `py` nur die Grundumgebung. Eigene Variablen pro Projekt:
`~/projects/<p>/.ki/env` mit Zeilen `KEY=Wert` (z. B. `WANDB_MODE=offline`, `CUDA_VISIBLE_DEVICES=0`).

**Grundumgebung im Kerker:** `HOME`, `XDG_RUNTIME_DIR`, `XDG_CACHE_HOME=~/.system_cache`,
`PIP_CACHE_DIR`, `UV_CACHE_DIR`, `VIRTUAL_ENV=~/code/.venv`, `PATH` mit `.venv/bin`, `~/.local/bin`
und `/usr/local/cuda/bin` (falls vorhanden), `KI_PROJECT`. Entfernt: `DBUS_SESSION_BUS_ADDRESS`,
`PYTHONPATH`, `PYTHONHOME`.

**`.venv`:** wird bei jedem Start geprüft. Fehlt es, legt `ki` es an (uv, offline-Fallback
`python3 -m venv`). Zeigt es nach einem Python-Update ins Leere, wird es neu angelegt – Pakete danach
mit `uv pip install -r requirements.txt` neu installieren.

**PyCharm:** `bin/pycharm` (sonst `pycharm.sh`) startet im Kerker mit `~/code` als Projekt. Beim
ersten Start legt `ki` `pycharm64.vmoptions` mit `-Xmx2048m` an (Version aus `product-info.json`);
später ändert man das in PyCharm unter *Help → Change Memory Settings*. Ausgabe:
`~/projects/<p>/.ki/ide.log`. Neustarts aus PyCharm heraus funktionieren (B8). Weil `~/code` in jedem
Kerker derselbe Pfad ist, gilt „Trust Project“ einmal für alle Projekte.

### 4.6 Speicher: zram + earlyoom

- **zram** legt komprimierten Swap in den RAM (zstd, typisch 3:1). Ruhende Seiten (IDE, Dienste)
  wandern dorthin und machen echten RAM für Training und Datensätze frei – ohne SSD-Zugriff.
  `swappiness=100` ist für zram richtig (für SSD-Swap war 10 richtig, v1).
- **SSD-Swap** wird nach Rückfrage abgeschaltet: Mit großem SSD-Swap greift kein OOM-Wächter, bevor
  das System im Thrashing hängt.
- **earlyoom** beendet bei <5 % freiem RAM *und* <10 % freiem Swap den größten Prozess (meist das
  Training) und verschont Xorg, i3, urxvt, Menü, SSH. Danach im Job-Log nachsehen und Batchgröße
  oder `num_workers` reduzieren.

### 4.7 Bildschirm über die iGPU (optional, empfohlen)

Mit dem Monitor am Mainboard zeichnet die HD 630 die Oberfläche; die RTX 2060 rechnet nur noch.
Ablauf:

1. BIOS: *Advanced → Chipset Configuration* → **IGPU Multi-Monitor = Enabled**, **Primary Graphics
   Adapter = Onboard** (sonst erscheinen BIOS, GRUB und Konsole weiter an der Grafikkarte).
   DVMT Pre-Allocated 64 MB reicht.
2. Monitor an den Ausgang des Mainboards stecken, booten.
3. `./bootstrap.sh --only igpu` – erkennt die iGPU und den angeschlossenen Monitor, schreibt
   `/etc/X11/xorg.conf.d/10-ki-igpu.conf`, danach Neustart.
4. Prüfen: `ki doctor` meldet „RTX ist frei von Grafikausgabe“, `nvidia-smi` zeigt keinen
   Xorg-Prozess mehr.

Notfall (schwarzer Bildschirm): Strg+Alt+F2, einloggen,
`sudo rm /etc/X11/xorg.conf.d/10-ki-igpu.conf`, Monitor zurück an die RTX, `sudo reboot`.

**Windows-Hinweis:** Windows zeigt dann ebenfalls über die iGPU an. Programme können die RTX trotzdem
nutzen (Einstellungen → Grafik → Hohe Leistung); wer unter Windows viel spielt, steckt besser um.

## 5. Bewusste Entscheidungen

Die Liste aus v1 gilt weiter (u. a. kein Docker, kein Compositor, kein C-Menü, kein `xhost`, kein
pauschaler 32-GB-Swap, kein Mod+Shift+E, keine festen Download-Links, `.venv` bleibt indiziert,
bwraps eigenes `/dev/shm`). Neu:

| Vorschlag | Entscheidung | Begründung |
|---|---|---|
| i3-Mod Alt | ersetzt durch Win | Alt+Enter, Alt+1 u. a. gehören PyCharm |
| Menü per Scratchpad verstecken | ersetzt | Arbeitsflächen 1/2: Menü bleibt bedienbar, B1 entfällt |
| `.idea`/SDK-Einträge selbst erzeugen | verworfen | bricht mit PyCharm-Versionen (B3/B4); PyCharm erkennt `.venv` selbst |
| Projekt als zwei Mounts `home/` + `code/` (Phase 2, v1) | ersetzt | ein Mount + Unterordner `code/`: gleiche Übersicht, aber uv-Hardlinks funktionieren nur innerhalb eines Mounts |
| Gemeinsamer Paket-Cache für alle Projekte | verworfen | widerspricht Zero-Garbage, und Hardlinks gehen nicht über Bind-Mounts |
| SSD-Swap + swappiness 10 | ersetzt | zram + earlyoom: schneller, kein Einfrieren |
| Ollama/llama.cpp als Systemdienst | verworfen | dauerhafter Dienst, Modelle außerhalb der Projekte; stattdessen im Kerker bei Bedarf ([KI-PRAXIS.md](KI-PRAXIS.md)) |
| `systemd-run --user` für Jobs | verworfen | braucht D-Bus-Benutzersitzung; `setsid` + PID-Datei reicht und überlebt SSH-Abmeldung |
| `mitigations=off` | nicht automatisiert | Leistungsgewinn bei GPU-Training klein, Sicherheitsfolgen groß; bei Bedarf selbst entscheiden |
| `set-local-rtc 1` für Dual-Boot (B11) | ersetzt | Windows auf UTC stellen (Abschnitt 8) |
| unattended-upgrades abschalten | verworfen | Sicherheitsupdates bleiben; das Menü erinnert nach 14 Tagen an ein volles Update |

## 6. Grenzen

- **Keine Sicherheits-Sandbox.** Schadcode aus pip-Paketen kann Host-Dateien lesen und senden.
- **Kein `sudo` im Kerker** (bwrap setzt *no_new_privs*) – Systempakete über Menü → System → Host-Terminal.
- **Eine IDE gleichzeitig.** Mehrere PyCharm-Instanzen mit derselben Konfiguration vertragen sich nicht;
  Terminals, Jobs und Jupyter laufen parallel beliebig viele.
- **Keine Maus im Menü, keine Emojis** (DejaVu Sans Mono).
- **PyCharm-Lizenzdialog** einmal „ohne Abo fortfahren“; der Zustand liegt in den globalen Ordnern.
- **Interpreter:** PyCharm erkennt `~/code/.venv` normalerweise selbst. Steht unten rechts doch
  „No interpreter“: einmal *Add Interpreter → Existing → ~/code/.venv/bin/python*. Da der Pfad in jedem
  Projekt gleich ist, reicht das einmal.
- **Docker ist nicht vorgesehen** (dauerhafter Daemon).
- **Strg+C in `ki shell <p> <befehl>`** erreicht nur das Programm; bwrap selbst reagiert nicht darauf –
  hängt ein Programm wirklich, das Terminal-Fenster schließen.

## 7. Stand der bekannten Bugs (v1)

| ID | Problem | Stand in v2 |
|---|---|---|
| B1 | Menü nach PyCharm-Ende unsichtbar | **entfällt** – kein Scratchpad, Menü auf eigener Arbeitsfläche |
| B2 | Menü nach dem Boot weiß | **behoben** – `.xinitrc` mit `xrdb`; `ki doctor` prüft |
| B3 | Projektwurzel `/home` | **entfällt** – keine `.iml`-Erzeugung, PyCharm öffnet `~/code` |
| B4 | Interpreter nicht gesetzt | **entfällt** – `.venv` in der Projektwurzel, kein `jdk.table.xml`-Eingriff |
| B5 | CUDA-Repo 24.04 | **behoben** – aus `/etc/os-release`, Toolkit optional |
| B6 | Projektordner überladen | **behoben** – PyCharm sieht nur `code/` |
| B7 | User Agreement je Projekt | **behoben** – `~/.java` eingebunden (aus v1 übernommen, mit echtem PyCharm prüfen) |
| B8 | Neustart aus PyCharm | **behoben** – Kerker wartet auf den Restarter (mit Schein-Restarter getestet) |
| B9 | nano/less fehlen | **behoben** – in der Paketliste |
| B10 | GnuTLS-Fehler (IPv6) | **behoben** – `gai.conf`, Schritt `netz` |
| B11 | Uhr nach Windows falsch | **Anleitung** – Abschnitt 8 |
| B12 | CUDA-PATH mehrfach in `.bashrc` | **entfällt** – keine `.bashrc`-Änderung durch bootstrap |
| B13 | Esc bei Profilwahl beendet Start | **entfällt** – kein `set -e`, Esc = zurück |

## 8. Einspielen, Wartung, Dual-Boot

**Von v1 auf v2** (Rückweg jeweils über die Sicherung von `install.sh`):

1. Repo holen: `git clone https://github.com/tareckert/SetUp ~/SetUp` (oder per USB-Stick nach `~/SetUp`).
2. `cd ~/SetUp && ./tests/run.sh` (optional, prüft die Skripte auf diesem Rechner).
3. `./bootstrap.sh` – erledigte Schritte werden übersprungen; neu sind netz, uv, speicher, ballast,
   sudoers, ki-gpu. igpu erst, wenn der Monitor umgesteckt ist.
4. `./install.sh` – sichert die alten Skripte und Dotfiles.
5. `ki migrate --all` – Code der v1-Projekte wandert nach `code/`, `.venv` wird mitgenommen und
   angepasst, die alte `.idea` landet in `.ki/idea-alt`.
6. `sudo reboot`, dann Testcheckliste (Abschnitt 9).

**Neuinstallation:** Ubuntu Server minimized wie in v1 (Rufus DD-Modus, manuelle Partitionierung,
OpenSSH), dann `sudo apt install git`, Schritte 1–4, `ki pycharm-update`, Neustart.
Bei Installer-Abbrüchen in `curtin extract` erst RAM per Memtest prüfen und den Stick an einen
hinteren USB-2.0-Port stecken (v1).

**Wartung:**

- Setup: Menü → System → Setup aktualisieren (= `ki update`: `git pull` + `install.sh`)
- System: Menü → System → System aktualisieren; nach Kernel-Updates prüft der Menükopf auf nötige Neustarts
- PyCharm: `ki pycharm-update` lädt die aktuelle Version (Prüfsumme), entpackt nach `/opt`, setzt den
  Symlink; die alte Version bleibt bis zum Test liegen. Alternativ mit Link oder Datei:
  `ki pycharm-update <url|tarball>`
- Python-Upgrade: `.venv` wird automatisch neu angelegt, danach Pakete neu installieren
- Eigene Einstellungen: `~/.config/ki/ki.conf` (Projektordner, PyCharm-Pfad, Heap, uv an/aus, Jupyter-Port)

**Uhrzeit bei Dual-Boot (B11):** Windows führt die Hardware-Uhr sonst in Ortszeit. Einmal in Windows
als Administrator:
`reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f`
und dort den Schnellstart abschalten. Linux bleibt bei UTC.

## 9. Fehlersuche und Tests

**Erst `ki doctor`.** Es prüft Treiber, Persistence Mode, ob X an der RTX hängt, bwrap, uv, PyCharm,
gum, Autologin, `.bash_profile`, `.xinitrc`, Farbschema, Menüfenster, zram, earlyoom, SSD-Platz,
Host-Cache (Ausbrüche aus dem Kerker), Netz und alte Projekte – jeweils mit der Lösung.

**Testcheckliste nach jeder Änderung**

- [ ] Neustart: Autologin, dunkles Menü im Vollbild ohne Eingabe, Leiste mit GPU-Werten
- [ ] Menüfenster mit Win+Shift+Q schließen: kommt nach einer Sekunde wieder
- [ ] Neues Projekt `zz-test` (KI/ML, ohne PyTorch), in PyCharm öffnen: kein EULA-Dialog, Interpreter
      unten rechts gesetzt, Projektbaum zeigt nur `code`-Inhalt, `.venv` ausgeschlossen
- [ ] Win+1 während PyCharm läuft: Menü bedienbar, Kopf zeigt „PyCharm: zz-test“
- [ ] PyCharm-Terminal: `nvidia-smi` zeigt die GPU, `echo $XDG_CACHE_HOME` → `/home/tb/.system_cache`
- [ ] `uv pip install numpy`, Autocomplete für `numpy.` funktioniert
- [ ] PyCharm normal schließen und hart beenden (Win+Shift+Q): Menü kommt jedes Mal zurück
- [ ] Plugin installieren mit Neustart: PyCharm startet neu (B8)
- [ ] Job starten (`python -c "import time; time.sleep(600)"`), Jobs ansehen, stoppen: Status „fertig“
- [ ] Cache leeren: Unterordner von `.system_cache` bleiben als leere Ordner
- [ ] Projekt über das Menü löschen: Ordner weg, `pgrep -a bwrap` zeigt nichts
- [ ] Alt+Enter in PyCharm öffnet Quick-Fixes (nicht mehr ein Terminal)

**Diagnose nach Ebene** (von unten nach oben)

| Ebene | Prüfbefehl | Erwartet | Wenn nicht |
|---|---|---|---|
| GPU-Treiber | `nvidia-smi` | Tabelle mit RTX 2060 | `sudo ubuntu-drivers install`, Neustart; nach Kernel-Update `dkms status` |
| bwrap | `bwrap --unshare-user --uid $(id -u) --gid $(id -g) --ro-bind / / echo ok` | `ok` | `./bootstrap.sh --only bwrap` |
| Autologin | `tty` direkt nach Boot | `/dev/tty1` | `./bootstrap.sh --only autologin` |
| Autostart X | `cat ~/.local/state/ki/xsession.log` | keine Fehler | `./install.sh`; bei iGPU-Problemen Abschnitt 4.7 |
| Farben | `xrdb -query \| grep background` | `#2B2B2B` | `./install.sh` (B2) |
| Menü | Win+1 | Menü | `i3-msg restart`; im Fenster Shell → `ki-menu` |
| PyCharm | `less ~/projects/<p>/.ki/ide.log` | keine `Read-only file system` | Pfad fehlt im Kerker → in `kerker_build` beschreibbar machen |
| Job | `ki logs <p>` | Programmausgabe | Exit-Code steht am Ende des Logs |
| Speicher | `ki status`, `journalctl -u earlyoom` | — | earlyoom hat beendet → Batchgröße/`num_workers` senken |
| Netz | `curl -I https://download.jetbrains.com` | HTTP 200/30x | `./bootstrap.sh --only netz`, `timedatectl` |

**Neue Fallstricke finden:** `grep -ri "read-only" ~/projects/*/.ki/ide.log` (Schreibversuche auf den
Host); `ki doctor` warnt, wenn `~/.cache` des Hosts wächst; `./tests/run.sh` nach jeder Skriptänderung.

## 10. Spickzettel

| Aufgabe | Taste / Befehl |
|---|---|
| Menü / PyCharm / Extra | Win+1 / Win+2 / Win+3, Win+Tab = zuletzt |
| Terminal (Host) | Win+Enter |
| Fenster schließen / Vollbild | Win+Shift+Q / Win+F |
| GPU-Monitor | Win+G oder `ki top` |
| i3 neu laden | Win+Shift+R |
| Schriftgröße im Terminal | Strg+Bild↑/↓ oder Strg+Plus/Minus, Strg+0 |
| Kopieren/Einfügen im Terminal | Strg+Shift+C / Strg+Shift+V |
| Projekt ohne Menü öffnen | `ki open <p>` (alt: `run-project.sh <p>`) |
| Training im Hintergrund | `ki run <p> -- python train.py`, dann `ki logs <p>` |
| Jupyter vom Zweitrechner | `ki jupyter <p>`, dort `ssh -N -L 8888:127.0.0.1:8888 tb@<IP>` |
| Speicher pro Projekt | `ki list --size` |
| Alles prüfen | `ki doctor` |
| Konsole statt Oberfläche | beim Boot Taste drücken oder `touch ~/.ki-no-x` |
| Datei vom Zweitrechner | `scp datei tb@<IP>:~/projects/<p>/code/` |
| USB-Stick | `lsblk`, `sudo mount /dev/sdX1 /mnt`, `sudo umount /mnt` |
