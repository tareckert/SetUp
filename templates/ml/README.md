# @NAME@

KI/ML-Projekt auf der KI-Workstation (RTX 2060, 6 GB VRAM, Turing).

| Datei | Zweck |
|---|---|
| `gpu_check.py` | Prüft PyTorch, CUDA, VRAM und misst fp32 gegen fp16 |
| `train_example.py` | Trainingsvorlage: Mixed Precision (fp16), Checkpoints, sauberes Stoppen |
| `requirements.txt` | Pakete – `uv pip install -r requirements.txt` |

Training im Hintergrund (läuft weiter, auch ohne PyCharm und nach SSH-Abmeldung):

    ki run @NAME@ -- python train_example.py
    ki logs @NAME@          # mitlesen
    ki stop @NAME@          # wie Strg+C: Checkpoint wird gespeichert

Turing-Hinweise: fp16 statt bf16 (bf16 hat erst Ampere in Hardware), Batchgröße an 6 GB
anpassen, für große Modelle Gradient Accumulation und QLoRA (4 Bit) nutzen.
