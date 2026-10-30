"""Chat mit einem Sprachmodell – läuft lokal auf der RTX 2060 (fp16, 1–3 GB VRAM).

Starten:        python chat.py          (oder in PyCharm mit dem grünen ▶ – Eingabe unten in "Run")
Anderes Modell: python chat.py --modell Qwen/Qwen2.5-1.5B-Instruct
Eigenes Modell: python chat.py --modell ~/shared_data/models/mein-modell   (ein Ordner)

Beim ersten Start wird das Modell aus dem Internet (Hugging Face) in den Projekt-Cache geladen,
danach läuft alles ohne Internet.
"""
import argparse
import os
from threading import Thread

import torch
from transformers import (AutoModelForCausalLM, AutoTokenizer, StoppingCriteria,
                          StoppingCriteriaList, TextIteratorStreamer)

STANDARD = "Qwen/Qwen2.5-0.5B-Instruct"   # klein und schnell; die 1.5B-Variante passt auch in 6 GB


class Abbruch(StoppingCriteria):
    """Strg+C während der Antwort stoppt nur die Antwort, nicht den Chat."""

    def __init__(self) -> None:
        self.an = False

    def __call__(self, input_ids, scores, **kwargs) -> bool:
        return self.an


def laden(name: str, gpu: bool):
    """Erst aus dem Cache (geht offline), sonst einmalig herunterladen."""
    dtype = torch.float16 if gpu else torch.float32   # Turing: fp16 statt bf16
    for nur_lokal in (True, False):
        try:
            tok = AutoTokenizer.from_pretrained(name, local_files_only=nur_lokal)
            model = AutoModelForCausalLM.from_pretrained(name, dtype=dtype, local_files_only=nur_lokal)
            return tok, model.to("cuda" if gpu else "cpu").eval()
        except OSError:
            if not nur_lokal:
                raise SystemExit(f"Modell '{name}' nicht gefunden – beim ersten Mal braucht es Internet.")
            print(f"Lade {name} herunter (einmalig, danach offline) …")


def main() -> None:
    p = argparse.ArgumentParser(description="Lokaler Chat mit einem Sprachmodell")
    p.add_argument("--modell", default=STANDARD, help=f"Hugging-Face-Name oder Ordner (Standard: {STANDARD})")
    p.add_argument("--system", default="Du bist ein hilfreicher Assistent. Antworte auf Deutsch.")
    p.add_argument("--max-tokens", type=int, default=512, help="höchstens so viele Tokens pro Antwort")
    p.add_argument("--kontext", type=int, default=4096, help="Verlauf kürzen, wenn er länger wird")
    args = p.parse_args()

    gpu = torch.cuda.is_available()
    name = os.path.expanduser(args.modell)
    tok, model = laden(name, gpu)
    ort = f"GPU, {torch.cuda.memory_allocated() / 2**30:.1f} GiB VRAM" if gpu else "CPU – langsam"
    print(f"{name} geladen ({ort}).")
    print("Nachricht eingeben, Enter schickt ab · /neu = Verlauf löschen · exit oder Strg+D = Ende")

    verlauf = [{"role": "system", "content": args.system}]
    abbruch = Abbruch()
    while True:
        try:
            text = input("\nDu: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if text in ("exit", "quit", "/exit"):
            break
        if text == "/neu":
            verlauf = verlauf[:1]
            print("(Verlauf gelöscht)")
            continue
        if not text:
            continue

        verlauf.append({"role": "user", "content": text})
        while True:   # ältesten Wortwechsel streichen, bis der Verlauf in den Kontext passt
            eingabe = tok.apply_chat_template(verlauf, add_generation_prompt=True, return_tensors="pt",
                                              return_dict=True)
            if eingabe["input_ids"].shape[1] <= args.kontext or len(verlauf) <= 2:
                break
            del verlauf[1:3]

        streamer = TextIteratorStreamer(tok, skip_prompt=True, skip_special_tokens=True)
        abbruch.an = False
        arbeit = Thread(target=model.generate, kwargs=dict(
            **eingabe.to(model.device), streamer=streamer, max_new_tokens=args.max_tokens,
            do_sample=True, temperature=0.7, top_p=0.9, pad_token_id=tok.pad_token_id or tok.eos_token_id,
            stopping_criteria=StoppingCriteriaList([abbruch])))
        arbeit.start()
        print("KI: ", end="", flush=True)
        antwort = ""
        try:
            for stueck in streamer:
                print(stueck, end="", flush=True)
                antwort += stueck
        except KeyboardInterrupt:
            abbruch.an = True
            print(" (abgebrochen)", end="")
        arbeit.join()
        print()
        verlauf.append({"role": "assistant", "content": antwort})


if __name__ == "__main__":
    main()
