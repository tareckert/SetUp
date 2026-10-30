# KI auf der RTX 2060 (6 GB, Turing) – Praxisblatt

Was auf dieser Hardware gut geht, was nicht, und wie man die 6 GB VRAM und 16 GB RAM ausreizt.

**PyTorch:** `torch` von PyPI (getestet: 2.15 mit CUDA 13.2) bringt alle CUDA-Bibliotheken selbst mit
und ist für Turing (sm_75) gebaut – kein CUDA-Toolkit nötig. Es braucht einen NVIDIA-Treiber ab
Version 580; `ki doctor` warnt, wenn er älter ist. Die Installation lädt rund 3 GB und belegt im
Projekt etwa 5 GB – dank uv-Hardlinks nur einmal, obwohl Cache und `.venv` die Dateien enthalten.

## Grundregeln

| Thema | Empfehlung | Warum |
|---|---|---|
| Präzision | **fp16** mit `torch.autocast(..., dtype=torch.float16)` + `torch.amp.GradScaler` | Turing hat Tensor Cores für fp16, nicht für bf16 (bf16 wird nur langsam emuliert) |
| Attention | `torch.nn.functional.scaled_dot_product_attention` | FlashAttention-2 braucht Ampere; PyTorch wählt auf Turing automatisch den speichersparenden Kernel |
| VRAM-Fragmentierung | im ML-Profil gesetzt: `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` | weniger „CUDA out of memory“ trotz freiem Speicher |
| Batchgröße | so groß, wie es passt; darüber **Gradient Accumulation** | effektive Batchgröße ohne mehr VRAM |
| Große Modelle | **Gradient Checkpointing**, **LoRA/QLoRA** (4 Bit, bitsandbytes) | Fine-Tuning von 1–3B-Modellen wird auf 6 GB machbar |
| DataLoader | `num_workers=2…4`, `pin_memory=True`, `persistent_workers=True` | 4 Kerne – mehr Worker kosten nur RAM |
| Datensätze | in `~/shared_data` ablegen (im Kerker nur lesbar), Ergebnisse in `~/code/runs/` | einmal speichern, in allen Projekten nutzen |
| Kompilieren | `torch.compile` lohnt sich bei langen Läufen; Cache bleibt im Projekt (`TORCHINDUCTOR_CACHE_DIR`) | erster Lauf kompiliert, spätere nicht mehr |
| Messen | `python gpu_check.py` (ML-Vorlage), `ki top`, Leiste unten | fp16 sollte ein Vielfaches von fp32 schaffen |

## Workflow

Im Menü: *Neues Projekt* → Vorlage `ml` → PyTorch installieren *Ja* → *Training & Jobs* →
*Job starten* (der Befehl ist vorgeschlagen). Dasselbe als Befehle:

```bash
ki new bilder --vorlage ml --torch     # Projekt mit PyTorch (CUDA-Bibliotheken kommen mit, kein Toolkit nötig)
ki shell bilder                        # Terminal im Kerker
python gpu_check.py                    # GPU, VRAM, fp16-Leistung
exit
ki pakete bilder pandas                # weiteres Paket (oder: requirements.txt ergänzen, dann ki pakete bilder)
ki run bilder -- python train_example.py   # Training im Hintergrund, PyCharm darf zu sein
ki logs bilder                         # mitlesen (q schließt, F = live weiter)
ki stop bilder                         # wie Strg+C – die Vorlage speichert und setzt beim nächsten Start fort
```

Beim Training PyCharm schließen spart 1,5–2 GB RAM. Die Leiste unten meldet das Ende des Jobs
(„✓ bilder fertig“, „■ bilder gestoppt“ oder „✗ bilder Fehler“). Bei einem Fehler steht am Ende des
Logs oft schon der nächste Schritt – etwa welches Paket fehlt oder dass der VRAM voll war.

Notebooks (`.ipynb`) öffnet PyCharm direkt; beim ersten Mal bietet es an, Jupyter ins Projekt zu
installieren. JupyterLab im Browser gibt es mit `ki jupyter` für den Zweitrechner (SSH-Tunnel,
Funktion `fernzugriff`).

## Sprachmodelle laufen lassen (Inferenz)

| Modellgröße | Format | Passt in 6 GB? |
|---|---|---|
| 1–3B | fp16 | ja |
| 7–8B | 4 Bit (GGUF Q4_K_M, AWQ/GPTQ) | knapp, mit kurzem Kontext |
| 13B+ | 4 Bit | nur teilweise auf der GPU (Rest CPU/RAM, langsam) |

Am schnellsten: Projekt mit der Vorlage **`llm`** – `python chat.py` lädt beim ersten Start
`Qwen/Qwen2.5-0.5B-Instruct` (~1 GB) in den Projekt-Cache und chattet danach offline auf der GPU
(fp16). Anderes Modell: `--modell Qwen/Qwen2.5-1.5B-Instruct` oder ein Ordner, z. B. ein selbst
trainiertes Modell aus `~/code/runs/…`. Strg+C bricht nur die laufende Antwort ab.

Ohne Systemdienst und ohne Modelle außerhalb der Projekte geht außerdem:

- **llama.cpp über Python:** `uv pip install llama-cpp-python` (CUDA-Build laut dessen Doku; braucht
  die Funktion `cuda`), Modell als GGUF nach `~/shared_data/models/` legen und per Pfad laden.
- **Ollama im Kerker:** Linux-Archiv in ein Projekt entpacken, `OLLAMA_MODELS` in `.ki/env` auf einen
  Ordner im Projekt setzen, `ollama serve` per `ki run` starten – läuft nur, solange der Job läuft.
- **Hugging Face Transformers:** `device_map="auto"` und `load_in_4bit` (bitsandbytes) für 7B-Modelle.

Modelle, die mehrere Projekte brauchen, einmal nach `~/shared_data/models/` legen (z. B. per USB-Stick
über `ki usb` und den Dateimanager) statt in jedes Projekt-`HF_HOME`. Offline laden mit
`HF_HUB_OFFLINE=1` in `~/projects/<p>/.ki/env`.

## Wenn es eng wird

- **CUDA out of memory:** Batchgröße halbieren, Accumulation verdoppeln; `torch.cuda.empty_cache()` hilft
  selten. VRAM-Spitze mit `torch.cuda.max_memory_allocated()` messen (die Vorlage zeigt sie an).
  Läuft nebenbei ein zweiter Job oder ein Chat-Modell? Beide teilen sich die 6 GB.
- **`torch.cuda.is_available()` ist False:** `ki doctor` – meist Treiber zu alt (< 580) oder nach einem
  Kernel-Update noch nicht neu gestartet.
- **Prozess plötzlich weg, Log endet abrupt:** earlyoom hat bei RAM-Mangel eingegriffen
  (`journalctl -u earlyoom`). `num_workers` senken, Datensätze streamen statt komplett laden.
- **GUI ruckelt beim Training:** Bildschirm auf die iGPU legen (`ki setup install igpu`, SYSTEM.md Abschnitt 6).
- **Jeder CUDA-Start dauert Sekunden:** Persistence Mode prüfen (`ki doctor`).
- **Langer Lauf, CPU als Flaschenhals** (Datenvorbereitung): `ki power performance`, danach `balanced`.
