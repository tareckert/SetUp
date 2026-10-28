# KI-Workstation

Schlankes Programmier- und KI-System für einen PC mit schwacher Hardware (i7-7700K, 16 GB RAM,
RTX 2060 6 GB): Ubuntu Server ohne Desktop, i3 mit dunklem Textmenü, PyCharm und alle Werkzeuge im
bubblewrap-„Kerker“. Jedes Projekt ist ein Ordner, jede Funktion des Systems hat ihren eigenen Ordner,
und alles lässt sich einzeln installieren und **restlos** wieder entfernen.

- **Leistung fürs Rechnen:** kein Desktop, keine Hintergrunddienste, kein Hintergrund-Traffic.
  Zusätzliche Werkzeuge (Dateimanager, Monitor, Einstellungen) laufen nur, solange sie offen sind.
- **Ordnung:** Projekte in `~/projects`, das System in `~/.ki`, Programme in `/opt/ki`.
  Jede Funktion notiert, was sie außerhalb ihres Ordners anlegt, und räumt es beim Entfernen weg.
- **Offline:** Arbeiten, Trainieren, Menü, Dateien und USB-Sticks gehen ohne Internet. Netz brauchst
  du nur zum Installieren. Für die Einrichtung ist kein SSH nötig.

```
╭──────────────────────────────────────────────────╮
│      KI-Workstation · tserv · Mi 28.10. 14:03     │
│   RAM 3.1/16 G   GPU 0.0/6 G 34°C   SSD 812G frei │
│        PyCharm: bilder, notizen   Jobs aktiv: 1   │
╰──────────────────────────────────────────────────╯
               › ▶ Zu PyCharm (bilder, notizen)
                 Projekt öffnen
                 Neues Projekt
                 Terminal im Projekt
                 Training & Jobs
                 Projekte verwalten
                 Dateien & USB
                 Einstellungen
                 System
                 Hilfe & Tasten
                 Ausschalten
```

## Neu aufsetzen – Schritt für Schritt, ohne SSH

**Vorher:** Alles, was du behalten willst (z. B. die `code`-Ordner alter Projekte, ohne `.venv`), auf
einen USB-Stick kopieren. Beim Installieren wird die Ubuntu-Partition formatiert.

1. **Ubuntu Server 26.04 installieren** (USB-Stick, z. B. mit Rufus im DD-Modus):
   - Sprache Deutsch, Tastatur Deutsch, Variante **Ubuntu Server (minimized)**
   - Netzwerk: Kabel mit DHCP reicht
   - Speicher: *Benutzerdefiniert* → die bisherige Ubuntu-Partition als **ext4** formatieren, Einhängepunkt `/`.
     Die EFI-Partition als `/boot/efi` nutzen, **nicht** formatieren. Windows-Partitionen nicht anfassen.
   - Rechnername `tserv`, Benutzer `tb`; **OpenSSH nicht nötig**; keine Snaps
2. **Nach dem Neustart** auf der Konsole anmelden und das Setup holen:
   ```bash
   sudo apt update && sudo apt install -y git
   git clone https://github.com/tareckert/SetUp ~/.ki/system
   ```
   (Privates Repo: als Passwort ein GitHub-Token eingeben. Ohne Netz: Repo per USB-Stick nach
   `~/.ki/system` kopieren – `sudo mount /dev/sdb1 /mnt && cp -r /mnt/SetUp ~/.ki/system && sudo umount /mnt`.)
3. **Funktionen wählen und installieren:**
   ```bash
   ~/.ki/system/setup
   ```
   Die Liste zeigt alle Funktionen mit sinnvoller Vorauswahl. Nummern eintippen schaltet sie um, Enter
   installiert. Dauert je nach Leitung 15–30 Minuten; ein paar Fragen kommen unterwegs.
4. `sudo reboot` – danach startet der PC direkt ins Menü.
5. Alte Projekte zurückholen: Menü → *Dateien & USB* → USB-Stick einbinden, dann
   *Neues Projekt* → *Vorhandenen Ordner übernehmen*.

Windows startest du über das Boot-Menü der Firmware (ASRock: **F11** beim Einschalten), falls es im
GRUB-Menü fehlt – am Bootloader ändert dieses Setup nichts.

## Funktionen

| Funktion | Vorauswahl | Was sie tut |
|---|---|---|
| `basis` | immer | `ki`-Befehl, Kerker (bubblewrap), Python, Projektvorlagen |
| `netz` | ja | IPv4 vor IPv6 – gegen abbrechende Downloads bei halbem IPv6 |
| `schlank` | ja | cloud-init, snapd, unnötige Dienste und automatische Updates aus |
| `speicher` | ja | zram (komprimierter RAM-Swap), earlyoom gegen Einfrieren, Journal-Limit |
| `nvidia` | ja | NVIDIA-Treiber + Persistence Mode |
| `uv` | ja | schnelle Python-Paketinstallation ohne Doppelkopien |
| `oberflaeche` | ja | Xorg + i3 + urxvt, Statusleiste mit GPU und Jobs |
| `autologin` | ja | ohne Passwort direkt ins Menü |
| `menue` | ja | Textmenü mit Einstellungen; Ausschalten und CPU-Modus ohne Passwort |
| `pycharm` | ja | PyCharm, im Kerker gestartet |
| `dateien` | ja | Dateimanager (Midnight Commander) und USB-Sticks |
| `monitor` | ja | nvtop (GPU) und htop (CPU/RAM) |
| `igpu` | nein | Bildschirm über die Intel-Grafik – volles VRAM für CUDA (Monitor ans Mainboard) |
| `cuda` | nein | CUDA-Toolkit (nvcc) – für PyTorch nicht nötig |
| `node` | nein | Node.js + npm |
| `fernzugriff` | nein | SSH-Server für den Zweitrechner |

Später ändern: Menü → *Einstellungen* → *Funktionen verwalten*, oder `ki setup` (gleiche Liste wie
bei der Installation). Einzeln: `ki setup install igpu`, `ki setup remove node`.
Was eine Funktion angelegt hat: `ki setup files <name>`. Alles entfernen: `ki setup remove-all`.

## Ordnung

```
~/projects/<name>/          deine Projekte – Code in code/, Python in code/.venv, Caches, Jobs
~/shared_data/              datasets/, models/ – für alle Projekte, im Kerker nur lesbar
~/.ki/system/               dieses Setup (Git)
~/.ki/<funktion>/           alles, was eine Funktion ablegt (Einstellungen, Daten, Logs)
/opt/ki/<funktion>/         Programme, die nicht aus apt kommen (uv, PyCharm, zwei kleine Helfer)
/etc/…                      wenige Systemdateien mit "ki" im Namen – jede im Manifest ihrer Funktion
```

`ki doctor` prüft das System und sucht dabei auch nach Dateien, die nicht hierher passen.

## Alltag

| Was | Menü | Befehl |
|---|---|---|
| Projekt anlegen | Neues Projekt | `ki new bilder --vorlage ml --torch` |
| Git-Repo als Projekt | Neues Projekt → Git | `ki clone https://github.com/… --install` |
| In PyCharm arbeiten | ▶ Weiter / Projekt öffnen | `ki open bilder` |
| Terminal ohne IDE | Terminal im Projekt | `ki terminal bilder` (Win+T) |
| Zwei Terminals / Terminal + Dateien nebeneinander | einfach nacheinander öffnen | Win+T, Win+D, Win+Enter |
| Training im Hintergrund | Training & Jobs | `ki run bilder -- python train.py`, `ki logs bilder`, `ki stop bilder` |
| Notebook | Training & Jobs → JupyterLab | `ki jupyter bilder` |
| Dateien, USB-Stick | Dateien & USB | `ki dateien` (Win+D), `ki usb` |
| Bildschirm, Skalierung, Tastatur | Einstellungen | – |
| Platz freimachen | Projekte verwalten | `ki list --size`, `ki clean bilder` |
| Etwas stimmt nicht | System → Diagnose | `ki doctor` |
| Setup aktualisieren | System → Setup aktualisieren | `ki update` |

**Fenster nebeneinander:** Terminal, Dateien, GPU-Monitor und Jupyter öffnen sich als eigene Fenster
neben dem aktuellen – i3 teilt den Bildschirm von selbst (zwei Fenster = je eine Hälfte). Jedes
schließt einzeln (`exit`, F10 im Dateimanager oder Win+Shift+Q), das andere füllt dann den Platz.
Von der Menü-Fläche aus landen neue Fenster auf „Extra“, damit das Menü frei bleibt; ist dort das
letzte Fenster zu, geht es zurück zum Menü.

Tasten: **Win+1** Menü · **Win+2** IDE · **Win+3** Extra · **Win+T** Terminal im Projekt ·
**Win+Enter** Terminal (Host) · **Win+D** Dateien · **Win+G** GPU-Monitor · **Win+Pfeil** Fenster
wechseln · **Win+Shift+Q** Fenster schließen · **Win+E** nebeneinander ↔ untereinander · **Win+W**
als Reiter · **Win+R** Größe · **Win+O** auf den zweiten Monitor. Alles Weitere: `ki help`.

## Dokumentation

- [docs/SYSTEM.md](docs/SYSTEM.md) – wie alles funktioniert: Funktionen, Ordner, Kerker, Einstellungen,
  Entscheidungen, Grenzen, Fehlersuche, Spickzettel
- [docs/KI-PRAXIS.md](docs/KI-PRAXIS.md) – Training und Inferenz mit 6 GB VRAM
- [docs/REVIEW.md](docs/REVIEW.md) – Design-Review der ersten Fassung und was daraus wurde

## Aufbau des Repos

```
setup              Funktionen installieren / entfernen / aktualisieren
core/lib.sh        Buchführung: jede Änderung außerhalb von ~/.ki/<funktion> landet im Manifest
core/ui.sh         Menü-Bausteine (gum, mit Notfallmodus)
features/<name>/   je Funktion: feature.sh, ihre Vorlagen und Befehle (bin/ki-…)
tests/run.sh       117 Prüfungen: Lint, Installieren→Entfernen ohne Rückstände, Kerker mit bubblewrap,
                   echte Oberfläche (i3 + urxvt auf virtuellem Bildschirm)
```
