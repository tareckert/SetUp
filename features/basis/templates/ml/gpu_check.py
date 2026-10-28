"""GPU-Check: Ist PyTorch mit CUDA einsatzbereit, und was kann die Karte?"""
import time

import torch


def bench(dtype: torch.dtype, n: int = 4096, reps: int = 20) -> float:
    """Matrixmultiplikation n×n, gibt TFLOPS zurück."""
    a = torch.randn(n, n, device="cuda", dtype=dtype)
    b = torch.randn(n, n, device="cuda", dtype=dtype)
    for _ in range(3):
        a @ b
    torch.cuda.synchronize()
    start = time.perf_counter()
    for _ in range(reps):
        a @ b
    torch.cuda.synchronize()
    return 2 * n**3 * reps / (time.perf_counter() - start) / 1e12


def main() -> None:
    print(f"PyTorch {torch.__version__} · CUDA-Laufzeit {torch.version.cuda}")
    if not torch.cuda.is_available():
        print("CUDA nicht verfügbar – auf dem Host prüfen: nvidia-smi (ki doctor)")
        return
    props = torch.cuda.get_device_properties(0)
    free, total = torch.cuda.mem_get_info()
    print(f"GPU {props.name} · Compute Capability {props.major}.{props.minor} · {props.multi_processor_count} SMs")
    print(f"VRAM {free / 2**30:.2f} GiB frei von {total / 2**30:.2f} GiB")
    if props.major < 8:
        print("bf16 nicht in Hardware → Mixed Precision mit fp16 + GradScaler (siehe train_example.py)")
    fp32, fp16 = bench(torch.float32), bench(torch.float16)
    print(f"Matmul fp32 {fp32:.1f} TFLOPS · fp16 {fp16:.1f} TFLOPS (Tensor Cores: ×{fp16 / fp32:.1f})")


if __name__ == "__main__":
    main()
