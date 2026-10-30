# @NAME@

KI/ML-Projekt auf der KI-Workstation (RTX 2060, 6 GB VRAM, Turing).

| Datei | Zweck |
|---|---|
| `gpu_check.py` | Prüft PyTorch, CUDA, VRAM und misst fp32 gegen fp16 |
| `train_example.py` | Trainingsvorlage: Mixed Precision (fp16), Checkpoints, sauberes Stoppen |
| `requirements.txt` | Pakete des Projekts – installieren: Menü → Projekte verwalten → Pakete, oder `ki pakete @NAME@` |

Ausprobieren: in PyCharm `gpu_check.py` öffnen und mit dem grünen ▶ starten – oder im Terminal
`python gpu_check.py`.

Training im Hintergrund (läuft weiter, auch ohne PyCharm und nach dem Abmelden) – Menü →
Training & Jobs → Job starten, oder:

    ki run @NAME@ -- python train_example.py
    ki logs @NAME@          # mitlesen
    ki stop @NAME@          # wie Strg+C: Checkpoint wird gespeichert, neu starten setzt fort

Weitere Pakete: `ki pakete @NAME@ <paket>` oder im Projekt-Terminal `uv pip install <paket>` –
und in `requirements.txt` eintragen, damit das Projekt reproduzierbar bleibt.
Notebooks (`.ipynb`) öffnet PyCharm direkt; beim ersten Mal bietet es an, Jupyter zu installieren.

Turing-Hinweise: fp16 statt bf16 (bf16 hat erst Ampere in Hardware), Batchgröße an 6 GB
anpassen, für große Modelle Gradient Accumulation und QLoRA (4 Bit) nutzen.
