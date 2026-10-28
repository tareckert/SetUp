# Design-Review der KI-Workstation (v1 → v2)

Grundlage: „KI-Workstation – Systemdokumentation“ vom 28.10.2026 (22 Seiten, Stand v1).
Ziel des Reviews: mehr RAM, CPU und GPU fürs Rechnen, ein stabileres und bequemeres System –
ohne die vier Kernziele in ihrer Rangfolge (Zero-Garbage, Stabilität, Performance, Bedienkomfort)
und ohne die bewusst verworfenen Vorschläge (Abschnitt 5 der v1-Doku) aufzuweichen.

## Fazit in drei Sätzen

Die Architektur ist gut und bleibt: kein Display-Manager, kein Desktop, i3 + urxvt + gum, und der
bwrap-Kerker mit Home-Swap ist eine elegante Lösung für „Projekt löschen = alles weg“. Die größten
ungenutzten Reserven liegen woanders: Die RTX 2060 zeichnet den Bildschirm, obwohl der i7-7700K eine
eigene Grafikeinheit hat; der Speicher hat weder schnellen Swap noch OOM-Schutz; und Training ist an
PyCharm oder ein offenes Terminal gebunden. v2 behebt das, macht alle 13 bekannten Bugs gegenstandslos
und ersetzt Heredoc-Kopieren durch ein Repo mit Installer, Diagnose und einem CLI, das auch per SSH geht.

## Was bleibt (bewährt)

- Autostart-Kette ohne Display-Manager, i3 + urxvt, Darcula-Farben, gum statt dialog
- Kerker: `--ro-bind / /`, Home-Swap, minimales `/dev` + GPU-Geräte, tmpfs für `/tmp` und Laufzeitordner,
  nur `config`/`known_hosts` + Agent-Socket aus `~/.ssh`, globale JetBrains-Ordner
- Bedrohungsmodell: Kerker = Ordner-Isolation, keine Sicherheits-Sandbox
- Alle „Nicht-Ziele“ und verworfenen Vorschläge: kein Docker, kein Compositor, kein C-Menü, keine
  Maus im Menü, kein pauschaler 32-GB-Swap, kein `xhost`, kein `Mod+Shift+E`, keine festen Download-Links

## Befunde und Änderungen

Sortiert nach Wirkung. „Gewinn“ sind Richtwerte; nachmessen mit `ki status` vorher/nachher.

### Ressourcen (Performance)

| # | Befund | Änderung in v2 | Gewinn |
|---|---|---|---|
| R1 | **Der Bildschirm hängt an der RTX 2060.** Xorg belegt dort VRAM (mit PyCharm typisch 100–300 MB von 6 GB), Oberfläche und Training teilen sich die Karte – die GUI ruckelt bei Volllast. Die v1-Aussage „GUI rendert per CPU“ stimmt nicht: Xorg nutzt den NVIDIA-Treiber. Der i7-7700K hat eine eigene HD 630. | Optional: Monitor ans Mainboard, Xorg per `10-ki-igpu.conf` fest auf die iGPU (`./bootstrap.sh --only igpu`, erkennt den angeschlossenen Ausgang selbst). | ganze RTX + volles VRAM für CUDA, flüssige GUI beim Training |
| R2 | **Kein Schutz vor Speicher-Einfrieren.** SSD-Swap mit `swappiness=10` heißt: wenn RAM knapp wird, kommt Thrashing – Minuten ohne Reaktion. Ohne OOM-Wächter sieht der Kernel lange keinen Grund einzugreifen. | zram (zstd, 50 % RAM) ersetzt den SSD-Swap, `earlyoom` beendet bei echtem Mangel den größten Prozess und verschont Xorg/i3/Menü/SSH. | ~4–8 GB zusätzlicher Puffer für ruhende Seiten; kein Einfrieren |
| R3 | **Training hängt an PyCharm oder einem offenen Terminal.** Für reine Trainingsläufe bleiben 1,5–2 GB IDE-RAM belegt; über SSH bricht ein Lauf beim Abmelden ab. | `ki run` startet Jobs im Kerker als eigene Sitzung (überlebt SSH-Abmeldung), Logs pro Job, `ki stop` = Strg+C. Dazu `ki shell` (Phase 4 aus v1) und `ki jupyter` per SSH-Tunnel für den Zweitrechner. | 1,5–2 GB RAM pro Lauf ohne IDE |
| R4 | **Pakete liegen doppelt.** Der pip-Cache im Projekt hält jede Wheel-Datei zusätzlich zum `.venv` – bei PyTorch mit CUDA-Bibliotheken rund 3 GB extra pro Projekt. | `uv` (nach `/usr/local/bin`, auch im Kerker sichtbar) mit Projekt-Cache und Hardlinks: Cache und `.venv` teilen sich die Dateien. Installation ein Vielfaches schneller. pip bleibt im `.venv` für PyCharm. | ~3 GB SSD pro ML-Projekt, Minuten pro Installation |
| R5 | **Hintergrundballast** auf Ubuntu Server: multipathd, iscsid, ModemManager, motd-news, apport, ua-timer; Journal unbegrenzt. | `bootstrap.sh` zeigt die aktiven Dienste und schaltet sie nach Rückfrage ab; Journal auf 200 MB begrenzt. | einige 10 MB RAM, weniger Hintergrund-I/O |
| R6 | **CUDA startet langsam**, wenn kein Bildschirm an der Karte hängt (Treiber wird jedes Mal neu initialisiert). | `ki-gpu.service`: Persistence Mode beim Booten. | ~1–2 s pro CUDA-Start |
| R7 | Kleine PyTorch-Hebel fehlen. | ML-Profil setzt `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` (weniger Fragmentierung auf 6 GB), Triton/Inductor/CUDA-JIT-Caches bleiben im Projekt erhalten (kein Neukompilieren je Start). Vorlage zeigt fp16-Mixed-Precision – Turing hat keine bf16-Tensor-Cores. | schnellere Trainings, weniger OOM |
| R8 | CPU-Governor nur dauerhaft umstellbar (v1: systemd-Dienst). | `ki power performance/balanced` als Schalter im Menü; Standard bleibt sparsam. | nach Bedarf |

### Stabilität

| # | Befund | Änderung in v2 |
|---|---|---|
| S1 | **B1 (kritisch): Menü bleibt nach PyCharm-Fehlercode unsichtbar.** Ursache ist die Scratchpad-Konstruktion an sich: das Menü wartet blockierend auf PyCharm und muss danach zurückgeholt werden. | Kein Scratchpad mehr. PyCharm startet im Hintergrund auf Arbeitsfläche 2, das Menü bleibt auf Arbeitsfläche 1 immer bedienbar. Nach dem Schließen springt i3 zurück. Eine Sperre verhindert eine zweite IDE (spart RAM, und zwei PyCharm-Instanzen mit derselben Konfiguration vertragen sich ohnehin nicht). |
| S2 | **B8 ist falsch zugeordnet.** Nicht `--die-with-parent` beendet den Neustart, sondern das Ende des PID-Namespace: Sobald PyCharm (der Hauptprozess im Kerker) endet, tötet der Kernel alle übrigen Prozesse – auch den Restarter. | Ein kleiner Wrapper im Kerker wartet, solange `restarter`, `pycharm` oder `java` laufen. Plugin-Installationen und IDE-Updates mit Neustart funktionieren. (Mit Schein-Restarter getestet, mit echtem PyCharm noch nicht.) |
| S3 | **Strg+C tötet Trainings hart.** Strg+C trifft die ganze Prozessgruppe, also auch bwrap. bwrap stirbt, und `--die-with-parent` beendet den Kerker sofort mit SIGKILL – das Programm kann keinen Checkpoint mehr schreiben. | ki und bwrap ignorieren SIGINT, im Kerker wird es für das Programm wieder scharf geschaltet. Strg+C und `ki stop` lösen in Python ein sauberes `KeyboardInterrupt` aus (getestet). |
| S4 | **`exec startx` ohne Notausgang.** Startet X nicht (z. B. nach Treiber-Update), loggt sich tty1 in einer Schleife ein und aus. | 2 Sekunden „Taste = Konsole“, `startx` ohne `exec`: stürzt X ab, bleibt eine Konsole mit Log-Pfad. Dauerhaft abschalten: `touch ~/.ki-no-x`. |
| S5 | **`~/.bash_profile` verhindert `~/.profile`.** Damit fehlt `~/bin` im PATH der Sitzung, und die CUDA-Zeile aus `~/.bashrc` erreicht weder X noch den Kerker (der Kerker hat ein eigenes `~/.bashrc`). | `.bash_profile` lädt `~/.profile`; der Kerker setzt PATH selbst (inkl. `/usr/local/cuda/bin`, aktiviertes `.venv`). |
| S6 | **Kerker braucht `/run/user/<uid>`** – ohne Login-Sitzung (su, cron) fehlt der Ordner und bwrap bricht ab. | Fallback auf `/tmp/run-<uid>` im Kerker. |
| S7 | **Menü stürzt ab → Fenster blinkt im Sekundentakt.** | Bricht `ki-menu` ab, bleibt eine Shell im Fenster (exit = Menü neu). Ohne gum läuft ein nummerierter Notfallmodus. |
| S8 | **B13/`set -e`:** jede leere Eingabe beendete Skripte. | Kein `set -e` in ki/ki-menu, Esc heißt überall „zurück“. |

### Bedienkomfort

| # | Befund | Änderung in v2 |
|---|---|---|
| U1 | **i3-Mod-Taste Alt blockiert PyCharm.** Alt+Enter (Quick-Fix, die wichtigste PyCharm-Taste!) öffnete ein Terminal, Alt+1 (Projektfenster) wechselte die Arbeitsfläche. | Mod = Win-Taste. Win+1/2/3 Arbeitsflächen, Win+Enter Terminal, Win+G GPU-Monitor. |
| U2 | **Interpreter- und Projektwurzel-Automatik ist fragil** (B3, B4): `.iml`, `misc.xml` und `jdk.table.xml` von Hand erzeugen bricht mit jeder PyCharm-Version. | Nichts mehr erzeugen. Das `.venv` liegt in der Projektwurzel (`~/code/.venv`, in jedem Projekt derselbe Pfad); PyCharm erkennt und schließt es selbst aus. |
| U3 | **Projektordner überladen (B6).** | PyCharm öffnet `~/code`; Caches, `.venv`-Cache, JetBrains-Mountpunkte und Dotfiles liegen eine Ebene höher und sind in der IDE unsichtbar. Anders als Phase 2 aus v1 mit nur einem Bind-Mount – zwei getrennte Mounts hätten uv-Hardlinks unmöglich gemacht (EXDEV). |
| U4 | **Wartung per Heredoc und USB-Stick**, keine automatische Sicherung, Diagnose von Hand (Abschnitt 10). | Git-Repo + `install.sh` (sichert jede überschriebene Datei), `ki update`, `ki doctor` prüft alle Ebenen und nennt die Lösung, `ki pycharm-update` lädt die aktuelle Version mit Prüfsumme. |
| U5 | Menü: kein Überblick über RAM/GPU/Jobs, kein „weiter mit letztem Projekt“, Projektliste ohne Größe/Datum (Phase 5 aus v1). | Kopf mit RAM, VRAM, Temperatur, SSD, offener IDE, laufenden Jobs, fälligen Updates. Erster Eintrag „▶ Weiter mit …“. Projekte nach letzter Nutzung, mit Größe; Cache pro Ordner leeren; Umbenennen; Logs. |
| U6 | Alles nur über das Menü. | Jede Aktion auch als `ki …` – mit Tab-Vervollständigung, auch per SSH vom Zweitrechner. |
| U7 | Uhrzeit-Fix B11 (`set-local-rtc 1`) wird von systemd nicht empfohlen. | Doku: Windows auf UTC umstellen (ein Registry-Eintrag), Linux bleibt bei UTC. |
| U8 | IPv6-Workaround pro Werkzeug (apt, wget). | Einmal zentral in `/etc/gai.conf`: IPv4 zuerst, IPv6 bleibt als Ausweich. Gilt für apt, wget, curl, pip, uv, git. |

### Bootstrap

| v1 | v2 |
|---|---|
| CUDA-Repo fest `ubuntu2404` (B5), Toolkit Pflicht | Repo aus `/etc/os-release`, Fallback Ubuntu-Paket; Toolkit optional (PyTorch bringt CUDA selbst mit, spart ~5 GB) |
| PATH-Zeile ohne Prüfung an `.bashrc` (B12) | keine `.bashrc`-Änderung durch bootstrap; `install.sh` fügt genau eine geprüfte Zeile ein |
| nano/less fehlen (B9), mokutil unnötig (Secure Boot aus) | nano, less, htop, nvtop dabei; mokutil raus |
| Schritte nicht einzeln wiederholbar | jeder Schritt prüft „schon erledigt?“; `--only`, `--list`, `--yes`, Log-Datei |

## Was ich nicht testen konnte

Getestet wurde in einem Linux-Container mit echtem bubblewrap (siehe `tests/run.sh`, 51 Prüfungen,
als root und als normaler Benutzer): Kerker-Umgebung und Isolation, Jobs inkl. sauberem Stopp,
Migration eines v1-Projekts mit `.venv`, Cache, Umbenennen, Löschen, IDE-Sperre und das Warten auf
den Restarter (mit Schein-PyCharm), Menüabläufe mit gum 0.17 in einem Pseudo-Terminal.

Nicht testbar ohne deine Hardware: echtes PyCharm im Kerker, i3/urxvt/Xorg, die iGPU-Konfiguration,
NVIDIA-Treiber/Persistence Mode, zram/earlyoom unter Last. Deshalb: Phasen einzeln einspielen und
jeweils die Testcheckliste aus `docs/SYSTEM.md` abarbeiten.
