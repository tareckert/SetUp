# KI-Workstation

Schlankes Programmier- und KI-Setup für einen PC mit schwacher Hardware (i7-7700K, 16 GB RAM,
RTX 2060 6 GB): Ubuntu Server ohne Desktop, i3 mit dunklem Textmenü, PyCharm und alle Werkzeuge im
bubblewrap-„Kerker“ – jedes Projekt ist ein Ordner, und alles, was beim Arbeiten entsteht, bleibt darin.
Möglichst viel RAM, CPU und die ganze GPU gehören dem Rechnen.

```
╭──────────────────────────────────────────────────╮
│      KI-Workstation · tserv · Mi 28.10. 14:03     │
│   RAM 3.1/16 G   GPU 0.0/6 G 34°C   SSD 812G frei │
│            PyCharm: bilder   Jobs aktiv: 1        │
╰──────────────────────────────────────────────────╯
                 › ▶ Zu PyCharm (bilder)
                   Projekt öffnen
                   Neues Projekt
                   Terminal im Projekt
                   Training & Jobs
                   Projekte verwalten
                   System
                   Hilfe & Tasten
                   Ausschalten
```

## Schnellstart

**Neuinstallation** (Ubuntu Server 26.04 minimized mit OpenSSH ist installiert):

```bash
sudo apt install -y git
git clone https://github.com/tareckert/SetUp ~/SetUp && cd ~/SetUp
./bootstrap.sh          # System: Pakete, Treiber, uv, zram/earlyoom, Autologin … (fragt bei Optionalem)
./install.sh            # Skripte und Konfiguration ins Home (mit Sicherung)
ki pycharm-update       # aktuelles PyCharm nach /opt
sudo reboot             # startet direkt ins Menü
```

**Umstieg von v1** (das System aus der alten Dokumentation läuft schon):

```bash
git clone https://github.com/tareckert/SetUp ~/SetUp && cd ~/SetUp
./bootstrap.sh          # überspringt Erledigtes, bietet die neuen Schritte an
./install.sh            # sichert die alten Skripte nach ~/.local/state/ki/backup/
ki migrate --all        # Projekte: Code nach code/, .venv wird mitgenommen
sudo reboot
ki doctor               # prüft alles und nennt bei Problemen die Lösung
```

Optional, aber der größte Einzelgewinn: Monitor an den Mainboard-Ausgang und
`./bootstrap.sh --only igpu` – dann zeichnet die Intel-iGPU den Bildschirm, und die RTX 2060 rechnet
nur noch (Anleitung: [docs/SYSTEM.md](docs/SYSTEM.md#47-bildschirm-über-die-igpu-optional-empfohlen)).

## Alltag

| Was | Menü | Befehl (auch per SSH) |
|---|---|---|
| Projekt anlegen | Neues Projekt | `ki new bilder --profile ml --torch` |
| In PyCharm arbeiten | ▶ Weiter mit … / Projekt öffnen | `ki open bilder` |
| Terminal ohne IDE | Terminal im Projekt | `ki shell bilder` |
| Training im Hintergrund | Training & Jobs | `ki run bilder -- python train.py`, `ki logs bilder`, `ki stop bilder` |
| Notebook im Browser des Zweitrechners | Training & Jobs → JupyterLab | `ki jupyter bilder` |
| Platz freimachen | Projekte verwalten | `ki list --size`, `ki clean bilder` |
| Etwas stimmt nicht | System → Diagnose | `ki doctor` |
| Setup aktualisieren | System → Setup aktualisieren | `ki update` |

Tasten: **Win+1** Menü · **Win+2** PyCharm · **Win+3** Extra · **Win+Enter** Terminal ·
**Win+G** GPU-Monitor · **Win+Shift+Q** Fenster schließen. Die Win-Taste lässt Alt für PyCharm frei
(Alt+Enter!). Alles Weitere: `ki help`.

## Was v2 gegenüber v1 verbessert

- **Mehr Ressourcen fürs Rechnen:** Bildschirm optional über die iGPU (volles VRAM, keine GUI-Ruckler),
  zram statt SSD-Swap, earlyoom gegen Einfrieren, Training ohne IDE als Hintergrund-Job,
  uv statt doppelter pip-Caches (~3 GB pro ML-Projekt), Persistence Mode, abgeschaltete Hintergrunddienste.
- **Stabiler:** Menü auf eigener Arbeitsfläche statt Scratchpad (B1 entfällt), PyCharm-Neustarts
  funktionieren (B8), Strg+C lässt Trainings sauber enden, Notausgang beim Booten, alle 13 v1-Bugs
  behoben oder gegenstandslos.
- **Bequemer:** Menükopf mit RAM/GPU/Jobs, „Weiter mit letztem Projekt“, Projekte mit Größe und
  Datum, Cache je Ordner leeren, Umbenennen, `ki doctor`, `ki update`, `ki pycharm-update`,
  Tab-Vervollständigung – und jede Aktion auch per SSH.

Begründungen im Detail: [docs/REVIEW.md](docs/REVIEW.md).

## Dokumentation

- [docs/REVIEW.md](docs/REVIEW.md) – Design-Review: Befunde, Änderungen, Begründungen
- [docs/SYSTEM.md](docs/SYSTEM.md) – Systemdokumentation v2: Architektur, Komponenten, Entscheidungen,
  Grenzen, Bug-Stand, Tests, Spickzettel
- [docs/KI-PRAXIS.md](docs/KI-PRAXIS.md) – Training und Inferenz mit 6 GB VRAM auf Turing

## Aufbau

```
bootstrap.sh   install.sh          Einrichtung System / Benutzer
bin/           ki, ki-menu, ki-status, run-project.sh
dotfiles/      .bash_profile, .xinitrc, .Xresources, i3, i3status, Bash-Ergänzung, ki.conf
system/        Vorlagen für /etc und /usr/local/sbin
templates/     Projektvorlagen (ml, py, node)
tests/run.sh   shellcheck + Rauchtest mit echtem bubblewrap
```
