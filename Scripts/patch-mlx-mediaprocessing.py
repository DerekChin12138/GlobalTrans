#!/usr/bin/env python3
"""Force mlx-swift-lm VLM image conversion onto a CPU CIContext.

SPM checkouts are mode 444. Earlier builds looked patched in our tree but the
GPU context in MediaProcessing.swift was never writable, so every OCR still
rendered RGBAf through a process-lifetime Metal CIContext. Activity Monitor
never returns those textures — about 70–80MB per screenshot.
"""
from __future__ import annotations

import os
import stat
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

GPU_CONTEXT = "CIContext(options: [.cacheIntermediates: false])"
CPU_CONTEXT = (
    "CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])"
)

RENDER_NEEDLE = """        var data = Data(count: w * h * bytesPerPixel)
        data.withUnsafeMutableBytes { ptr in
            context.render(
                image, toBitmap: ptr.baseAddress!, rowBytes: bytesPerRow, bounds: image.extent,
                format: format, colorSpace: colorSpace)
            context.clearCaches()
        }
"""

RENDER_PATCHED = """        let renderContext = CIContext(options: [
            .useSoftwareRenderer: true, .cacheIntermediates: false,
        ])
        var data = Data(count: w * h * bytesPerPixel)
        data.withUnsafeMutableBytes { ptr in
            renderContext.render(
                image, toBitmap: ptr.baseAddress!, rowBytes: bytesPerRow, bounds: image.extent,
                format: format, colorSpace: colorSpace)
            renderContext.clearCaches()
        }
"""

QWEN_NEEDLE = """        let (resizedHeight, resizedWidth) = try QwenVL.targetSize(
            height: Int(extent.height),
            width: Int(extent.width),
            factor: config.patchSize * config.mergeSize,
            minPixels: config.size.minPixels,
            maxPixels: config.size.maxPixels)
"""

QWEN_PATCHED = """        let (resizedHeight, resizedWidth) = try QwenVL.targetSize(
            height: Int(extent.height),
            width: Int(extent.width),
            factor: config.patchSize * config.mergeSize,
            minPixels: processing?.minPixels ?? config.size.minPixels,
            maxPixels: processing?.maxPixels ?? config.size.maxPixels)
"""


def checkout_files(name: str) -> list[Path]:
    files: list[Path] = []
    seen: set[str] = set()
    patterns = [
        f"**/.build/checkouts/mlx-swift-lm/**/{name}",
        f"**/.xcodebuild/SourcePackages/checkouts/mlx-swift-lm/**/{name}",
    ]
    for pattern in patterns:
        for path in ROOT.glob(pattern):
            key = str(path.resolve())
            if key in seen:
                continue
            seen.add(key)
            files.append(path)
    return files


def make_writable(path: Path) -> None:
    mode = path.stat().st_mode
    os.chmod(path, mode | stat.S_IWUSR | stat.S_IWRITE)


def write_text(path: Path, text: str) -> None:
    make_writable(path)
    path.write_text(text)


def replace_once(text: str, needle: str, patched: str) -> tuple[str, bool]:
    if patched in text:
        return text, True
    if needle not in text:
        return text, False
    return text.replace(needle, patched, 1), True


def patch_media_processing(path: Path) -> bool:
    text = path.read_text()
    original = text
    text = text.replace(GPU_CONTEXT, CPU_CONTEXT)
    text, _ = replace_once(text, RENDER_NEEDLE, RENDER_PATCHED)
    if text == original:
        ok = CPU_CONTEXT in text and "renderContext" in text
        print(f"{'already patched' if ok else 'unchanged'} {path}")
        return ok
    write_text(path, text)
    ok = CPU_CONTEXT in text and "renderContext" in text
    print(f"patched {path}")
    return ok


def patch_qwen3(path: Path) -> None:
    text = path.read_text()
    text, found = replace_once(text, QWEN_NEEDLE, QWEN_PATCHED)
    if not found:
        if "processing?.maxPixels ?? config.size.maxPixels" in text:
            print(f"already patched {path}")
        else:
            print(f"skip {path}: unexpected Qwen3VL targetSize block")
        return
    write_text(path, text)
    print(f"patched {path}")


def main() -> int:
    media = checkout_files("MediaProcessing.swift")
    if not media:
        print(
            "patch-mlx-mediaprocessing: no MediaProcessing.swift yet (resolve packages first)",
            file=sys.stderr,
        )
        return 1

    ok = True
    for path in media:
        if not patch_media_processing(path):
            ok = False

    for path in checkout_files("Qwen3VL.swift"):
        patch_qwen3(path)

    if not ok:
        print(
            "patch-mlx-mediaprocessing: MediaProcessing.swift still uses a GPU CIContext",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
