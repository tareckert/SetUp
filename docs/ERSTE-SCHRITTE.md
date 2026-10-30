# Erste Schritte

Alles geht über das Menü: **Pfeile + Enter** wählen, **Esc** geht zurück. Das Menü liegt immer
auf **Win+1** (Win = Windows-Taste). Nichts davon musst du dir merken – die wichtigsten Tasten
stehen unter dem Menükopf.

## 1. Ein Projekt anlegen

Menü → **Neues Projekt** → *Aus einer Vorlage* → Name eingeben → Vorlage wählen:

- **ml** – KI-Training mit PyTorch (GPU-Check und Trainingsvorlage). „PyTorch gleich installieren?“
  mit *Ja* beantworten (einmalig ca. 3 GB, dauert ein paar Minuten).
- **llm** – ein Sprachmodell lokal laufen lassen (Chat).
- **py** – normales Python. **node** – JavaScript.

Jedes Projekt ist ein Ordner unter `~/projects/<name>`. Dein Code liegt in `code/`, die
Python-Umgebung in `code/.venv` – du musst sie nicht anfassen.

Vorhandenen Code holst du mit *Aus einem Git-Repo klonen* oder *Vorhandenen Ordner übernehmen*
(z. B. vom USB-Stick).

## 2. Programmieren

**In PyCharm öffnen** – PyCharm erscheint auf der Arbeitsfläche **Win+2**, das Menü bleibt auf
**Win+1**. Beim allerersten Start fragt PyCharm einmalig nach Nutzungsbedingungen, Lizenz
(kostenlos weiter oder aktivieren) und „Trust Project“ (→ *Trust Project*). Die Python-Umgebung
erkennt es selbst. Ein Skript startest du mit dem grünen ▶ neben `if __name__ == …`.

Ohne PyCharm (spart 1,5–2 GB RAM): **Terminal im Projekt** (Win+T). Dort:

    python gpu_check.py          Skript starten
    uv pip install pandas        Paket installieren
    git status                   Git wie gewohnt

Kopieren/Einfügen im Terminal: **Strg+Shift+C / Strg+Shift+V**. `exit` schließt es.

**Pakete installieren** geht auch ohne Befehl: Menü → *Projekte verwalten* → Projekt →
*Pakete installieren* (leer lassen = alles aus `requirements.txt`).

## 3. Trainieren

Menü → **Training & Jobs** → *Job starten* → Projekt wählen. Der Befehl ist schon vorgeschlagen
(z. B. `python train_example.py`) – Enter startet ihn **im Hintergrund**: Er läuft weiter, auch
wenn du PyCharm schließt oder das Menü verlässt. Die Leiste unten zeigt laufende Jobs und meldet
das Ende (✓ fertig, ■ gestoppt, ✗ Fehler).

- *Jobs ansehen* → Job wählen → *Log live ansehen* oder *Stoppen*.
- Stoppen wirkt wie Strg+C: das Training speichert seinen Stand. *Gleichen Befehl neu starten*
  setzt beim letzten Checkpoint fort.
- Bricht ein Job mit Fehler ab, steht am Ende des Logs oft schon der nächste Schritt
  (z. B. welches Paket fehlt).
- GPU-Auslastung live: **Win+G**.

## 4. KI ausführen

Projekt mit der Vorlage **llm** anlegen, in PyCharm `chat.py` starten (oder im Terminal
`python chat.py`). Der erste Start lädt das Modell (~1 GB), danach läuft es ohne Internet.

Eigene trainierte Modelle lädst du genauso: `python chat.py --modell ~/code/runs/mein-modell`.

## 5. Daten und Modelle

- Datensätze und Modelle für mehrere Projekte: `~/shared_data/datasets` und
  `~/shared_data/models`. Projekte sehen sie unter `~/shared_data` (nur lesen – nichts geht
  aus Versehen kaputt).
- USB-Stick: Menü → *Dateien & USB* → *USB-Stick einbinden*. Dateimanager: **Win+D**
  (F5 kopieren, F6 verschieben, F10 schließen).

## 6. Git und GitHub

Name und E-Mail für Commits fragt das Menü beim ersten Projekt einmal ab (später: Einstellungen →
Git). Beim ersten Push fragt Git nach Benutzername und Passwort – bei GitHub ist das ein
**Token** (github.com → Settings → Developer settings → Personal access tokens). Git merkt sich
die Zugangsdaten für alle Projekte.

## 7. Mehrere Dinge gleichzeitig

Jedes Terminal, jeder Dateimanager und jedes Log öffnet sich als eigenes Fenster neben dem
aktuellen – zwei Fenster teilen sich den Bildschirm. Jedes schließt einzeln (`exit`, F10 oder
**Win+Shift+Q**). **Win+Pfeil** wechselt zwischen ihnen, **Win+E** stellt nebeneinander ↔
untereinander um. Ein zweites Projekt in PyCharm öffnet ein zweites PyCharm-Fenster.

## Wenn etwas hakt

Menü → *System* → **Diagnose** prüft alles und sagt, was zu tun ist. Alle Befehle und Tasten:
Menü → *Hilfe* → *Tasten und Befehle*.
