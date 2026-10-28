# KI-Workstation – Systemdokumentation v3

Stand: 28.10.2026 · Neuaufbau mit Funktionen zum Ein- und Ausschalten · Vorgeschichte: [REVIEW.md](REVIEW.md)

## 1. Ziel und Regeln

Eine schlanke Entwicklungs- und KI-Workstation, deren Host-System dauerhaft sauber bleibt.

Die vier Kernziele, in dieser Rangfolge:

1. **Zero-Garbage** – Projekte, Caches, Modelle und IDE-Indizes liegen im Projektordner; jede
   Systemfunktion in ihrem eigenen Ordner. Nichts sammelt sich unbemerkt an.
2. **Stabilität** – Start ohne Eingriff ins Menü; kein Absturz hinterlässt einen unbedienbaren Zustand.
3. **Performance** – kein Desktop, kein Hintergrunddienst, kein Hintergrund-Traffic. Werkzeuge laufen
   nur, solange sie offen sind. RAM, CPU und die ganze GPU gehören dem Training.
4. **Bedienkomfort** – dunkles Textmenü, Einstellungen als Dialog, alles auch als `ki …`-Befehl.

Dazu drei Bauregeln:

- **Jede Funktion hat ihren Ordner** (`features/<name>/` im Repo, `~/.ki/<name>/` für Daten,
  `/opt/ki/<name>/` für Programme) und lässt sich einzeln installieren und restlos entfernen.
- **Offline-fähig:** Nur Installationen brauchen Internet. Arbeiten, Trainieren, Menü, Dateien,
  USB-Sticks, Hilfe und Doku gehen ohne Netz.
- **Ohne SSH einrichtbar:** Alles läuft auf der Konsole des PCs. SSH ist eine optionale Funktion.

**Bedrohungsmodell:** Code im Kerker gilt als vertrauenswürdig. bwrap trennt Ordner und Caches, ist
aber keine Sicherheits-Sandbox. Der Host ist lesbar eingebunden; geschützt wird nur vor ungewolltem
Schreiben.

## 2. Hardware

| Komponente | Wert | Hinweis |
|---|---|---|
| Mainboard | ASRock Z270 Extreme4, UEFI, CSM aus, AHCI, Secure Boot aus | Boot-Menü: F11 |
| CPU | i7-7700K, 4 Kerne / 8 Threads, **mit Intel HD 630** | iGPU kann den Bildschirm übernehmen |
| RAM | 16 GB | zram erweitert effektiv |
| GPU | RTX 2060, 6 GB, Turing (CC 7.5) | fp16-Tensor-Cores, kein bf16 in Hardware |
| SSD | NVMe, Dual-Boot mit Windows | |
| OS | Ubuntu Server 26.04 LTS minimized | Benutzer `tb`, Rechner `tserv` |

## 3. Architektur

```
Einschalten ─► getty tty1 (Funktion autologin) ─► ~/.profile ─► basis/login.sh
                                                     PATH: nur "ki" (+ /opt/ki/*/bin)
                       oberflaeche/start.sh ◄────────┘  2 s „Taste = Konsole“
                       ki start ─► startx oberflaeche/xinitrc
                                    xrdb · ki anzeige anwenden (Bildschirm, DPI, Tastatur) · i3
  Arbeitsfläche Menü   urxvt „ki-menu“ ─► ki menu (gum)   ← kommt immer wieder
  Arbeitsfläche IDE    PyCharm-Fenster (eins oder mehrere, nebeneinander/Reiter/zweiter Monitor)
  Arbeitsfläche Extra  Jupyter, Dateimanager, GPU-Monitor
  Leiste               Jobs (✓/✗ beim Ende) · GPU · CPU · RAM · SSD · Uhr   (alle 10 s)

  ki (Kern) ─► bwrap-Kerker ─► PyCharm | bash | Job | JupyterLab
```

**Der Kerker** (eine Instanz pro IDE-Fenster, Terminal oder Job):

```
/                    Host, nur lesbar (Treiber, Python, /opt/ki/…)
/tmp, /run/user/…    tmpfs im RAM, beim Schließen weg
/dev                 minimal + /dev/nvidia*, /dev/dri
~                    = ~/projects/<name>/        beschreibbar
  ├── code/          PyCharm-Projektwurzel, dein Code
  │   └── .venv/     Python-Umgebung – Pfad ~/code/.venv in jedem Projekt gleich
  ├── .system_cache/ pip, uv, huggingface, torch, triton, torchinductor, nv, JetBrains-Index
  ├── .ki/           profile, env, ide.log, jobs/<id>.{cmd,log,pid,exit}
  ├── .bashrc        von ki erzeugt (eigenes: .bashrc.local)
  └── shared_data    = ~/shared_data, nur lesbar
~/.config/JetBrains, ~/.local/share/JetBrains, ~/.java   (nur PyCharm) aus ~/.ki/pycharm/
~/.gitconfig, ~/.ssh/config, ~/.ssh/known_hosts         nur lesbar; SSH-Agent-Socket
```

Andere Projekte, `~/.ki` und der Rest des Host-Homes sind im Kerker unsichtbar.

## 4. Ordner und Buchführung

```
~/projects/<name>/        Projekte – gehören dir, bleiben auch bei "setup remove-all"
~/shared_data/            datasets/, models/ – gehören dir
~/.ki/system/             das Setup (Git-Repo), hier zu Hause
~/.ki/<funktion>/         Daten der Funktion; .manifest, .installed, .orig/ (gesicherte Originale)
/opt/ki/<funktion>/       Programme außerhalb von apt (root gehört, im Kerker sichtbar)
```

**Manifest:** Was eine Funktion außerhalb ihres Ordners tun *muss*, geht über `core/lib.sh` und wird
in `~/.ki/<funktion>/.manifest` notiert: Systemdateien (mit Sicherung eines vorhandenen Originals),
neu angelegte Ordner, Zeilen mit Marke `# ki:<funktion>` in fremden Dateien, auskommentierte Zeilen,
ein-/ausgeschaltete Dienste, Programmordner, Laufzeitpfade und **neu installierte apt-Pakete**
(Vergleich von `apt-mark showmanual` vorher/nachher). `ki setup files <funktion>` zeigt das lesbar.

**Entfernen** (`ki setup remove <funktion>`) liest das Manifest rückwärts: Originale zurück, eigene
Dateien und leere Ordner weg, Zeilen raus, Dienste zurück, Pakete auf „automatisch“ gesetzt und per
`apt-get autoremove --purge` entfernt – aber nur, wenn keine andere installierte Funktion sie braucht.
Danach verschwindet `~/.ki/<funktion>/` (mit `--keep-data` bleiben Einstellungen liegen).
Funktionen, die davon abhängen, werden nach Rückfrage mit entfernt.

Der Test `tests/run.sh` installiert alle Funktionen in einem Schein-System, benutzt sie, entfernt
alles und vergleicht: Dateien, Rechte, Inhalte, Paketliste und Dienste müssen exakt wie vorher sein.

### Was jede Funktion wo ablegt

| Funktion | Pakete (apt) | Außerhalb ihres Ordners | Daten in `~/.ki/<funktion>/` |
|---|---|---|---|
| basis | git, curl, nano, less, bubblewrap, rsync, Python, build-essential … | je 1 Zeile in `~/.profile`, `~/.bashrc`; `/etc/apparmor.d/ki-bwrap` nur falls nötig | `ki.conf`, `vorlagen/`, `logs/` |
| netz | – | 1 Zeile in `/etc/gai.conf` | – |
| schlank | – (snapd wird entfernt) | `/etc/cloud/cloud-init.disabled`, `/etc/apt/preferences.d/ki-no-snapd`; Dienste aus | – |
| speicher | zram-tools, earlyoom | `/etc/default/{zramswap,earlyoom}`, `/etc/sysctl.d/90-ki-speicher.conf`, `/etc/systemd/journald.conf.d/90-ki.conf`; Swap-Zeile in `/etc/fstab` auskommentiert | `swapdateien` (zum Wiederherstellen) |
| nvidia | ubuntu-drivers-common, Treiber | `/etc/systemd/system/ki-gpu.service` | – |
| igpu | – | `/etc/X11/xorg.conf.d/10-ki-igpu.conf` | – |
| cuda | cuda-toolkit oder nvidia-cuda-toolkit | (über das Paket) | – |
| uv | – | `/opt/ki/uv/bin/{uv,uvx}` | – |
| oberflaeche | xserver-xorg, xinit, i3, urxvt, Schriften … | Xorg-Log `~/.local/share/xorg` (wird beim Entfernen gelöscht) | `einstellungen.conf`, `eigene.conf`, `eigene.Xresources`, `xsession.log` |
| autologin | – | `/etc/systemd/system/getty@tty1.service.d/ki-autologin.conf`, `~/.hushlogin` | – |
| menue | gum | `/etc/apt/keyrings/ki-charm.gpg`, `/etc/apt/sources.list.d/ki-charm.list`, `/etc/sudoers.d/ki-menue`, `/opt/ki/menue/ki-power` | – |
| pycharm | X- und Browser-Bibliotheken | `/opt/ki/pycharm/<version>`, `/opt/ki/pycharm/current` | `config/`, `data/` (Plugins), `java/`, `fenster-N/` |
| dateien | mc | `/etc/sudoers.d/ki-dateien`, `/opt/ki/dateien/ki-mount`, `/media/ki` | mc-Einstellungen, Lesezeichen |
| monitor | htop, nvtop | – | htop/nvtop-Einstellungen |
| node | nodejs, npm | – | – |
| fernzugriff | openssh-server | – | – |

Helfer, die per sudo ohne Passwort laufen (`ki-power`, `ki-mount`), liegen bewusst in `/opt/ki`
und gehören root: Läge so ein Skript im Home, könnte jedes Programm es umschreiben und damit Root werden.

## 5. Bedienung

### 5.1 `ki` – ein Befehl für alles

`ki` liegt im Kern; Befehle anderer Funktionen stecken in `features/<name>/bin/ki-<befehl>` und
werden von `ki` weitergereicht, wenn die Funktion installiert ist (Tab-Vervollständigung inklusive).

| Bereich | Befehle |
|---|---|
| Projekte | `ki new <p> [--vorlage …] [--torch] [--python 3.12]`, `ki clone <url>`, `ki import <ordner>`, `ki open <p>`, `ki shell <p>`, `ki terminal [p]`, `ki list`, `ki clean`, `ki mv`, `ki rm` |
| Training | `ki run <p> -- cmd`, `ki jobs`, `ki logs`, `ki stop`, `ki jupyter <p>`, `ki power` |
| Funktionen | `ki setup`, `ki setup list/install/remove/reinstall/files/update/remove-all` |
| System | `ki status`, `ki doctor`, `ki update`, `ki menu`, `ki start`, `ki fenster [befehl]`, `ki einstellungen` |
| Werkzeuge | `ki dateien`, `ki usb`, `ki top`, `ki pycharm update/versionen/aufraeumen/speicher` |

### 5.2 Menü

```
▶ Weiter mit <letztes Projekt>  |  ▶ Zu PyCharm (…)  |  ▶ Terminal in … (ohne Oberfläche)
Projekt öffnen                    (nur mit Oberfläche und PyCharm)
Neues Projekt                     Vorlage · Git-Repo klonen · vorhandenen Ordner übernehmen
Terminal im Projekt
Training & Jobs                   Job starten/ansehen/stoppen · JupyterLab · GPU-Monitor · CPU-Modus
Projekte verwalten                Größe · Dateimanager · Logs · Cache je Ordner · Umbenennen · Löschen
Dateien & USB                     Dateimanager · USB einbinden/auswerfen
Einstellungen                     siehe 5.4
System                            Status · Diagnose · apt-Update · Setup-Update · PyCharm-Update ·
                                  Host-Terminal · Handbuch (offline) · Neustart
Hilfe & Tasten · Ausschalten
```

Ohne Oberfläche (Konsole, SSH) blendet das Menü alles aus, was einen Bildschirm braucht. Ohne gum
läuft ein nummerierter Notfallmodus.

### 5.3 Vorlagen

Eingebaut: `ml` (PyTorch-Check, Trainingsvorlage mit fp16 und Checkpoints), `py`, `node`.
Eigene: einen Ordner nach `~/.ki/basis/vorlagen/<name>/` legen – sein Inhalt wird nach `code/`
kopiert. Optional darin eine Datei `profil` mit `ml`, `py` oder `node` (Umgebungsvariablen im
Kerker) und eine `README.md`, deren erste Zeile im Menü als Beschreibung erscheint.

### 5.4 Einstellungen

Gespeichert in `~/.ki/oberflaeche/einstellungen.conf`, angewendet beim Start der Oberfläche und
direkt nach jeder Änderung (`ki anzeige anwenden`) – nie im Hintergrund.

| Einstellung | Wirkung |
|---|---|
| Bildschirm | Auflösung oder Anordnung eines zweiten Monitors (rechts, links, darüber, gespiegelt, aus). Wird ausprobiert und ohne Bestätigung nach 15 s zurückgenommen. |
| Skalierung | 100–200 % (Xft.dpi) für Terminal, Menü und PyCharm |
| Schriftgröße | Terminal-Schrift (das Menü-Fenster ändert sich sofort) |
| Bildschirm aus nach | 5–60 Minuten oder nie |
| Tastatur | Layout (de, ch, at, us) und Tastenwiederholung |
| Oberfläche automatisch starten | sonst bleibt tty1 eine Konsole (`ki start`) |
| Zeitzone | `timedatectl` |
| PyCharm-Speicher | Heap 1–4 GB (`ki pycharm speicher`) |
| CPU-Modus | ausgewogen / Leistung |
| Funktionen verwalten | Häkchenliste: an = installieren, aus = restlos entfernen |

### 5.5 Fenster nebeneinander, zweiter Monitor

Terminals (`ki terminal`, Win+T), der Dateimanager (Win+D), ein Host-Terminal (Win+Enter), der
GPU-Monitor (Win+G) und JupyterLab öffnen sich über `ki fenster` als **eigene Fenster neben dem
aktuellen**. i3 teilt den Bildschirm dabei selbst: zwei Fenster = je eine Hälfte, drei = Drittel.

- **Einzeln schließen:** `exit` im Terminal, F10 im Dateimanager oder Win+Shift+Q auf dem Fenster.
  Das übrige Fenster füllt danach den Platz.
- **Menü bleibt frei:** Wer von der Menü-Fläche aus ein Fenster öffnet, landet auf „Extra“. Ist
  dort das letzte Fenster geschlossen, springt die Anzeige zurück zum Menü.
- **Anordnen:** Win+Pfeil wechselt das Fenster, Win+Shift+Pfeil tauscht die Plätze, Win+E schaltet
  nebeneinander ↔ untereinander, Win+W macht Reiter daraus, Win+R ändert die Größe (Pfeile, Enter).
- **Zweiter Monitor:** Win+Shift+O schiebt das Fenster hinüber, Win+O die ganze Arbeitsfläche.
- **Neben PyCharm:** Win+2 (IDE), dann Win+T – das Terminal öffnet sich rechts neben PyCharm.

**Zweites PyCharm-Fenster (experimentell):** Ein zweites `ki open` startet eine weitere PyCharm-
Instanz, bis zu drei (`KI_IDE_MAX`), mit einer frischen Kopie der Einstellungen
(`~/.ki/pycharm/fenster-N/config`), weil zwei Instanzen nicht in denselben Einstellungsordner
schreiben dürfen. Mit echtem PyCharm ist das nicht getestet – klappt es nicht, für das zweite
Projekt ein Terminal (Win+T) und den Dateimanager nehmen. Jede Instanz kostet 1,5–2 GB RAM.

### 5.6 Dateien und USB-Sticks

`ki dateien` (Win+D) öffnet Midnight Commander mit zwei Spalten (Projekte | Datensätze), dunklem
Skin und Lesezeichen (Strg+\\). Alle seine Dateien liegen in `~/.ki/dateien`. `ki usb` listet
USB-/Wechseldatenträger, hängt sie unter `/media/ki/<name>` ein (nosuid, nodev; bei FAT/exFAT/NTFS
gehören die Dateien dir) und wirft sie sicher aus. Kein udisks-Dienst – der kleine Root-Helfer
`/opt/ki/dateien/ki-mount` akzeptiert nur Wechseldatenträger und nur Ziele unter `/media/ki`.

### 5.7 Jobs, Jupyter, Monitor

- `ki run` startet einen Befehl im Kerker als eigene Sitzung: läuft weiter ohne Menü und ohne
  PyCharm, Log pro Job. Die Leiste zeigt laufende Jobs und 15 Minuten lang „✓ fertig“ oder „✗ Fehler“.
- `ki stop` schickt Strg+C nur an das Programm (Python kann seinen Checkpoint speichern), nach 30 s hart.
- `ki jupyter` startet JupyterLab auf 127.0.0.1 – Browser hier nicht vorhanden, also vom Zweitrechner
  per SSH-Tunnel (Funktion `fernzugriff`).
- `ki top` zeigt nvtop, `ki top cpu` htop.

## 6. Speicher und GPU

- **zram** legt komprimierten Swap in den RAM (zstd, 50 %, typisch 3:1). SSD-Swap wird nach
  Rückfrage abgeschaltet und beim Entfernen der Funktion wiederhergestellt. `swappiness=100` ist für
  zram richtig.
- **earlyoom** beendet bei <5 % freiem RAM *und* <10 % freiem Swap den größten Prozess und verschont
  Xorg, i3, urxvt, Menü, SSH. Danach im Job-Log nachsehen, Batchgröße oder `num_workers` senken.
- **Persistence Mode** (`ki-gpu.service`) hält den Treiber initialisiert: CUDA startet sofort.
- **iGPU** (Funktion `igpu`): Monitor ans Mainboard, im BIOS *Advanced → Chipset Configuration*
  **IGPU Multi-Monitor = Enabled** und **Primary Graphics Adapter = Onboard**. Die Funktion erkennt
  iGPU und angeschlossenen Monitor selbst und weigert sich ohne Monitor (sonst bliebe das Bild
  schwarz). Notfall: Strg+Alt+F2, anmelden, `ki setup remove igpu`. Windows zeigt dann ebenfalls über
  die iGPU an; Programme können die RTX trotzdem nutzen.

## 7. Bewusste Entscheidungen

| Vorschlag | Entscheidung | Begründung |
|---|---|---|
| Docker, Compositor/Transparenz, Maus im Menü, Menü in C | verworfen | dauerhafte Dienste oder Aufwand ohne messbaren Nutzen |
| GUI-Dateimanager (pcmanfm, thunar) | verworfen | ziehen gvfs-Hintergrunddienste nach; mc läuft nur, solange er offen ist |
| udisks2 für USB | verworfen | Dienst im Hintergrund; ein geprüfter Root-Helfer reicht |
| Benachrichtigungsdienst (dunst) | verworfen | die Leiste zeigt Job-Enden ohne zusätzlichen Prozess |
| i3-Mod Alt | Win | Alt+Enter, Alt+1 u. a. gehören PyCharm |
| `.idea`/SDK-Einträge erzeugen | verworfen | bricht mit PyCharm-Versionen; PyCharm erkennt `code/.venv` selbst |
| gemeinsamer Paket-Cache aller Projekte | verworfen | widerspricht Zero-Garbage; Hardlinks gehen nicht über Bind-Mounts |
| `uv venv` für neue Projekte | ersetzt | `python3 -m venv` geht offline; uv nur für andere Python-Versionen und schnelle Installationen |
| gum als GitHub-Binary statt Charm-apt-Repo | verworfen | das Repo ist der dokumentierte Weg und bekommt Updates über „System aktualisieren“ |
| Automatische Updates | aus (Rückfrage) | kein Hintergrund-Traffic; das Menü erinnert nach 14 Tagen |
| GRUB anpassen | verworfen | dein Wunsch; Windows über das Firmware-Boot-Menü (F11) |
| `mitigations=off` | nicht automatisiert | kleiner Gewinn bei GPU-Training, große Sicherheitsfolgen |

## 8. Grenzen

- **Keine Sicherheits-Sandbox.** Schadcode aus pip-Paketen kann Host-Dateien lesen und senden.
- **Kein sudo im Kerker** (bwrap setzt *no_new_privs*) – Systempakete über Menü → System → Host-Terminal.
- **Weitere PyCharm-Fenster** speichern Einstellungsänderungen nicht dauerhaft (siehe 5.5).
- **Kein Browser auf der Workstation** – JupyterLab und Doku-Links vom Zweitrechner.
- **Interpreter:** PyCharm erkennt `~/code/.venv` normalerweise selbst. Sonst einmal *Add Interpreter
  → Existing → ~/code/.venv/bin/python* – der Pfad ist in jedem Projekt gleich.
- **Lizenzdialog** einmal „ohne Abo fortfahren“; der Zustand liegt in `~/.ki/pycharm`.
- **Strg+C in `ki shell <p> <befehl>`** erreicht nur das Programm; hängt es wirklich, das Fenster schließen.

## 9. Stand der bekannten Bugs (aus v1)

| ID | Problem | Stand |
|---|---|---|
| B1 | Menü nach PyCharm-Ende unsichtbar | entfällt – Menü auf eigener Arbeitsfläche, kein Scratchpad |
| B2 | Menü nach dem Boot weiß | behoben – xinitrc lädt Farben vor i3 |
| B3/B4 | Projektwurzel/Interpreter | entfällt – PyCharm öffnet `~/code`, `.venv` liegt dort |
| B5 | CUDA-Repo 24.04 | behoben – aus `/etc/os-release`, Toolkit optional |
| B6 | Projektordner überladen | behoben – PyCharm sieht nur `code/` |
| B7 | User Agreement je Projekt | behoben – `~/.ki/pycharm/java` eingebunden |
| B8 | Neustart aus PyCharm | behoben – Kerker wartet auf den Restarter (getestet mit Schein-PyCharm) |
| B9 | nano/less fehlen | behoben – Funktion basis |
| B10 | GnuTLS-Fehler (IPv6) | behoben – Funktion netz |
| B11 | Uhr nach Windows falsch | Anleitung: in Windows `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f`, Schnellstart aus |
| B12 | CUDA-PATH mehrfach | entfällt – `login.sh` setzt PATH, keine `.bashrc`-Bearbeitung |
| B13 | Esc beendet Start | entfällt – kein `set -e`, Esc = zurück |
| N1 | Menüfenster erschien nicht (v2) | behoben – i3 wandelt `\"` in seiner Konfiguration um; die Menü-Schleife ist jetzt ein eigenes Skript und endet mit der Oberfläche (im Test mit echtem i3 geprüft) |

## 10. Wartung

- **Setup:** Menü → System → Setup aktualisieren (`ki update`): zeigt die neuen Commits, holt sie,
  wendet alle installierten Funktionen neu an (nur Änderungen werden geschrieben).
- **System:** Menü → System → System aktualisieren (apt). Der Menükopf erinnert nach 14 Tagen und
  meldet nötige Neustarts.
- **PyCharm:** `ki pycharm update` (Prüfsumme wird geprüft) oder offline mit Archiv vom USB-Stick:
  `ki pycharm update /media/ki/STICK/pycharm-….tar.gz`. Alte Versionen: `ki pycharm aufraeumen`.
- **uv:** `ki setup reinstall uv` holt die neueste Version.
- **Python-Update:** `.venv` wird automatisch neu angelegt, danach Pakete neu installieren.
- **Eigene Ergänzungen:** i3 → `~/.ki/oberflaeche/eigene.conf`, Farben/Schrift →
  `~/.ki/oberflaeche/eigene.Xresources`, Kerker-Shell → `~/projects/<p>/.bashrc.local`,
  Umgebungsvariablen → `~/projects/<p>/.ki/env`, ki → `~/.ki/basis/ki.conf`.

## 11. Fehlersuche

**Erst `ki doctor`.** Es prüft je nach installierten Funktionen Kerker, uv, GPU-Treiber, Persistence
Mode, ob der Bildschirm an der RTX hängt, PyCharm, Farbschema, Menüfenster, zram, earlyoom, freien
Platz und Netz – und sucht **Dateileichen**: Einträge im Home, die nicht zum System gehören, und
Programmdaten in `~/.config` oder `~/.local/share`.

| Ebene | Prüfung | Wenn nicht |
|---|---|---|
| Funktionen | `ki setup list` | „unvollständig“ → `ki setup install <f>` oder `ki setup remove <f>` |
| GPU | `nvidia-smi` | Neustart; nach Kernel-Update `dkms status`; `ki setup reinstall nvidia` |
| Kerker | `ki shell <p> -- true` | `ki setup reinstall basis` (AppArmor-Freigabe) |
| Oberfläche | `cat ~/.ki/oberflaeche/xsession.log` | bei iGPU: Strg+Alt+F2, `ki setup remove igpu` |
| Menü | Win+1 | Win+Shift+R; im Fenster steht sonst eine Shell → `ki menu` |
| PyCharm | `less ~/projects/<p>/.ki/ide.log` | „Read-only file system“ → Pfad fehlt im Kerker |
| Job | `ki logs <p>` | Exit-Code am Ende; plötzlich weg → `journalctl -u earlyoom` |
| Netz (nur Installation) | `curl -I https://pypi.org` | `ki setup install netz`; Uhrzeit prüfen |

**Testcheckliste nach Änderungen**

- [ ] Neustart: Autologin, dunkles Menü, Leiste mit GPU-Werten, Arbeitsflächen „Menü IDE Extra“
- [ ] Neues Projekt `zz-test` (Vorlage ml), in PyCharm öffnen: Interpreter gesetzt, nur `code`-Inhalt sichtbar
- [ ] Win+T (Projekt wählen) und Win+D: Terminal und Dateien je eine Bildschirmhälfte, einzeln schließbar
- [ ] Letztes Fenster auf „Extra“ schließen: Anzeige springt zurück zum Menü
- [ ] Win+1 während PyCharm läuft: Menü bedienbar, Kopf zeigt beide Projekte
- [ ] Job starten, Leiste zeigt „Jobs 1“, nach dem Ende „✓ zz-test fertig“
- [ ] USB-Stick einbinden, im Dateimanager öffnen, auswerfen
- [ ] Einstellungen → Skalierung 125 %: neues Terminal größer; zurück auf 100 %
- [ ] Alt+Enter in PyCharm öffnet Quick-Fixes
- [ ] `ki setup remove monitor` und wieder `install`: `ki doctor` ohne Leichen
- [ ] Netzwerkkabel ziehen: Projekt öffnen, Job starten, Dateien – alles geht weiter

## 12. Spickzettel

| Aufgabe | Taste / Befehl |
|---|---|
| Menü / IDE / Extra | Win+1 / Win+2 / Win+3, Win+Tab = zuletzt |
| Terminal im Projekt / Host-Terminal / Dateien / GPU-Monitor | Win+T / Win+Enter / Win+D / Win+G |
| Fenster schließen / Vollbild | Win+Shift+Q / Win+F |
| Fenster wechseln / tauschen / schließen | Win+Pfeil / Win+Shift+Pfeil / Win+Shift+Q |
| Anordnung: nebeneinander↔untereinander / Reiter / Größe | Win+E / Win+W / Win+R (Pfeile, Enter) |
| Zweiter Monitor | Win+O (Arbeitsfläche), Win+Shift+O (Fenster) |
| i3 neu laden | Win+Shift+R |
| Schriftgröße im Terminal | Strg+Bild↑/↓ |
| Kopieren/Einfügen im Terminal | Strg+Shift+C / Strg+Shift+V |
| Konsole statt Oberfläche | beim Booten Taste drücken; Oberfläche später: `ki start` |
| Was liegt wo? | `ki setup files <funktion>` |
| Alles prüfen | `ki doctor` |
