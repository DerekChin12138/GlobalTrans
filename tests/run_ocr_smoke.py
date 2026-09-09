"""Load local OvisOCR2-4bit via mlx-vlm and OCR the synthetic fixtures."""

from __future__ import annotations

import json
import time
import traceback
from pathlib import Path

from mlx_vlm import generate, load
from mlx_vlm.prompt_utils import apply_chat_template

ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "OvisOCR2-4bit"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
OUTPUT = Path(__file__).resolve().parent / "output"

OCR_PROMPT = (
    "Extract all readable content from the image in natural human reading order "
    "and output the result as a single Markdown document. For charts or images, "
    'represent them using an HTML image tag: <img src="images/bbox_{left}_{top}_{right}_{bottom}.jpg" />, '
    "where left, top, right, bottom are bounding box coordinates scaled to [0, 1000). "
    "Format formulas as LaTeX. Format tables as HTML: <table>...</table>. "
    "Transcribe all other text as standard Markdown. Preserve the original text "
    "without translation or paraphrasing."
)

CASES = [
    ("invoice_en.png", 768),
    ("chinese_form.png", 1024),
    ("ui_settings.png", 512),
    ("table_datasheet.png", 768),
]


def summarize_result(result) -> dict:
    payload = {
        "type": type(result).__name__,
    }
    for key in (
        "text",
        "prompt_tokens",
        "generation_tokens",
        "prompt_tps",
        "generation_tps",
        "peak_memory",
    ):
        if hasattr(result, key):
            payload[key] = getattr(result, key)
    if isinstance(result, str):
        payload["text"] = result
    return payload


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    print(f"loading model from {MODEL_DIR}")
    t0 = time.perf_counter()
    model, processor = load(str(MODEL_DIR))
    load_s = time.perf_counter() - t0
    print(f"loaded in {load_s:.2f}s")

    formatted = apply_chat_template(
        processor,
        model.config,
        OCR_PROMPT,
        num_images=1,
        enable_thinking=False,
    )

    summary: list[dict] = []
    for name, max_tokens in CASES:
        image_path = FIXTURES / name
        print(f"\n=== {name} ===")
        t1 = time.perf_counter()
        try:
            result = generate(
                model,
                processor,
                formatted,
                image=[str(image_path)],
                max_tokens=max_tokens,
                temperature=0.0,
                verbose=True,
            )
            elapsed = time.perf_counter() - t1
            payload = summarize_result(result)
            text = payload.get("text") or ""
            out_md = OUTPUT / f"{image_path.stem}.md"
            out_md.write_text(str(text), encoding="utf-8")
            row = {
                "image": name,
                "ok": True,
                "elapsed_s": round(elapsed, 3),
                "load_s": round(load_s, 3),
                "chars": len(str(text)),
                "max_tokens": max_tokens,
                "metrics": {
                    k: payload.get(k)
                    for k in (
                        "prompt_tokens",
                        "generation_tokens",
                        "prompt_tps",
                        "generation_tps",
                        "peak_memory",
                    )
                    if k in payload
                },
                "preview": str(text)[:400],
            }
            print(f"wrote {out_md} ({row['chars']} chars, {elapsed:.2f}s)")
        except Exception as exc:  # noqa: BLE001 — smoke test must keep going
            elapsed = time.perf_counter() - t1
            row = {
                "image": name,
                "ok": False,
                "elapsed_s": round(elapsed, 3),
                "error": f"{type(exc).__name__}: {exc}",
                "traceback": traceback.format_exc(),
            }
            print(row["error"])
        summary.append(row)

    report = OUTPUT / "smoke_report.json"
    report.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nreport: {report}")


if __name__ == "__main__":
    main()
