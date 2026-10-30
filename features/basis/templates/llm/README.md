# @NAME@

Sprachmodell lokal auf der KI-Workstation (RTX 2060, 6 GB VRAM).

| Datei | Zweck |
|---|---|
| `chat.py` | Chat im Terminal mit einem kleinen Sprachmodell (Standard: Qwen2.5-0.5B-Instruct) |
| `requirements.txt` | Pakete des Projekts – installieren: Menü → Projekte verwalten → Pakete, oder `ki pakete @NAME@` |

Starten: in PyCharm `chat.py` öffnen und mit dem grünen ▶ starten (Eingabe unten im Run-Fenster)
oder im Projekt-Terminal `python chat.py`. Der erste Start lädt das Modell (ca. 1 GB) in den
Projekt-Cache, danach geht es ohne Internet. Strg+C bricht eine Antwort ab, `exit` beendet.

Modelle, die in 6 GB passen (fp16):

| Modell | VRAM | |
|---|---|---|
| `Qwen/Qwen2.5-0.5B-Instruct` | ~1,5 GB | Standard, schnell |
| `Qwen/Qwen2.5-1.5B-Instruct` | ~3,5 GB | deutlich besser, `--modell Qwen/Qwen2.5-1.5B-Instruct` |
| `HuggingFaceTB/SmolLM2-1.7B-Instruct` | ~4 GB | Englisch |

Größere Modelle (3B, 7B) brauchen 4-Bit-Quantisierung (`bitsandbytes`) – siehe docs/KI-PRAXIS.md.
Ein Modell für mehrere Projekte: Ordner nach `~/shared_data/models/` legen und mit
`--modell ~/shared_data/models/<ordner>` laden (im Kerker nur lesbar).
