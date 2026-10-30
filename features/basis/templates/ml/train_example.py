"""Trainingsvorlage für 6 GB VRAM: Mixed Precision (fp16), Checkpoints, sauberes Stoppen.

Starten:   ki run <projekt> -- python train_example.py
Stoppen:   ki stop <projekt>   (oder Strg+C) – der letzte Stand wird gespeichert
Fortsetzen: einfach erneut starten, es geht beim letzten Checkpoint weiter.
"""
from pathlib import Path

import torch
from torch import nn

CHECKPOINT = Path("runs/example/checkpoint.pt")
EPOCHS, STEPS, BATCH = 20, 200, 256


def make_batch(device: torch.device) -> tuple[torch.Tensor, torch.Tensor]:
    """Synthetische Daten – hier eigenen DataLoader einsetzen (num_workers ≤ 4 bei 4 Kernen)."""
    x = torch.randn(BATCH, 512, device=device)
    y = (x[:, :8].sum(dim=1) > 0).long()
    return x, y


def main() -> None:
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = nn.Sequential(nn.Linear(512, 1024), nn.GELU(), nn.Linear(1024, 2)).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-3)
    # Turing hat Tensor Cores für fp16, nicht für bf16 – der GradScaler verhindert Unterlauf
    scaler = torch.amp.GradScaler(device.type, enabled=device.type == "cuda")
    start_epoch = 0

    if CHECKPOINT.exists():
        state = torch.load(CHECKPOINT, map_location=device)
        model.load_state_dict(state["model"])
        optimizer.load_state_dict(state["optimizer"])
        scaler.load_state_dict(state["scaler"])
        start_epoch = state["epoch"] + 1
        print(f"Fortsetzen ab Epoche {start_epoch + 1} (Checkpoint {CHECKPOINT})")

    def save(epoch: int) -> None:
        CHECKPOINT.parent.mkdir(parents=True, exist_ok=True)
        state = {"model": model.state_dict(), "optimizer": optimizer.state_dict(),
                 "scaler": scaler.state_dict(), "epoch": epoch}
        torch.save(state, CHECKPOINT)

    print(f"Training auf {torch.cuda.get_device_name(0) if device.type == 'cuda' else 'CPU (keine GPU gefunden)'}")
    try:
        for epoch in range(start_epoch, EPOCHS):
            total = 0.0
            for _ in range(STEPS):
                x, y = make_batch(device)
                with torch.autocast(device.type, dtype=torch.float16, enabled=device.type == "cuda"):
                    loss = nn.functional.cross_entropy(model(x), y)
                optimizer.zero_grad(set_to_none=True)
                scaler.scale(loss).backward()
                scaler.step(optimizer)
                scaler.update()
                total += loss.item()
            save(epoch)
            vram = f" · VRAM-Spitze {torch.cuda.max_memory_allocated() / 2**20:.0f} MiB" if device.type == "cuda" else ""
            print(f"Epoche {epoch + 1}/{EPOCHS} · Loss {total / STEPS:.4f}{vram}")
    except KeyboardInterrupt:
        print("Gestoppt – letzter vollständiger Checkpoint bleibt erhalten.")
        return
    print("Fertig.")


if __name__ == "__main__":
    main()
