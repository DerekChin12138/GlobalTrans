"""Long-lived mlx-vlm worker. One JSON object per stdin line, one JSON response per stdout line."""

from __future__ import annotations

import json
import sys
import time
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL = ROOT / "OvisOCR2-4bit"

OCR_PROMPT = (
    "Extract all readable content from the image in natural human reading order "
    "and output the result as a single Markdown document. For charts or images, "
    'represent them using an HTML image tag: <img src="images/bbox_{left}_{top}_{right}_{bottom}.jpg" />, '
    "where left, top, right, bottom are bounding box coordinates scaled to [0, 1000). "
    "Format formulas as LaTeX. Format tables as HTML: <table>...</table>. "
    "Transcribe all other text as standard Markdown. Preserve the original text "
    "without translation or paraphrasing."
)

_model = None
_processor = None
_formatted = None


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def reply(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def ensure_loaded(model_dir: str | None) -> None:
    global _model, _processor, _formatted
    if _model is not None:
        return
    from mlx_vlm import load
    from mlx_vlm.prompt_utils import apply_chat_template

    path = Path(model_dir) if model_dir else DEFAULT_MODEL
    log(f"loading {path}")
    t0 = time.perf_counter()
    _model, _processor = load(str(path))
    _formatted = apply_chat_template(
        _processor,
        _model.config,
        OCR_PROMPT,
        num_images=1,
        enable_thinking=False,
    )
    log(f"loaded in {time.perf_counter() - t0:.2f}s")


def unload() -> None:
    global _model, _processor, _formatted
    _model = None
    _processor = None
    _formatted = None
    try:
        import mlx.core as mx

        mx.clear_cache()
    except Exception:
        pass


def transcribe(image: str, max_tokens: int) -> dict:
    from mlx_vlm import generate

    ensure_loaded(None)
    t0 = time.perf_counter()
    result = generate(
        _model,
        _processor,
        _formatted,
        image=[image],
        max_tokens=max_tokens,
        temperature=0.0,
        verbose=False,
    )
    elapsed = time.perf_counter() - t0
    text = result.text if hasattr(result, "text") else str(result)
    return {
        "ok": True,
        "text": str(text).strip(),
        "elapsed_s": round(elapsed, 3),
        "peak_memory": getattr(result, "peak_memory", None),
        "generation_tps": getattr(result, "generation_tps", None),
    }


def main() -> None:
    log("ocr worker ready")
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
            op = msg.get("op")
            if op == "ping":
                reply({"ok": True, "loaded": _model is not None})
            elif op == "load":
                ensure_loaded(msg.get("model_dir"))
                reply({"ok": True, "loaded": True})
            elif op == "transcribe":
                ensure_loaded(msg.get("model_dir"))
                reply(transcribe(msg["image"], int(msg.get("max_tokens", 2048))))
            elif op == "unload":
                unload()
                reply({"ok": True, "loaded": False})
            elif op in {"quit", "exit"}:
                unload()
                reply({"ok": True, "bye": True})
                return
            else:
                reply({"ok": False, "error": f"unknown op {op}"})
        except Exception as exc:  # noqa: BLE001
            reply(
                {
                    "ok": False,
                    "error": f"{type(exc).__name__}: {exc}",
                    "traceback": traceback.format_exc(),
                }
            )


if __name__ == "__main__":
    main()
