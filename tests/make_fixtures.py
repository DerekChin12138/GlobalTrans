"""Render synthetic OCR fixtures with Pillow. No personal documents."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures"
SIZE = (1100, 1400)
WHITE = (255, 255, 255)
INK = (22, 24, 28)
MUTED = (90, 96, 104)
LINE = (210, 214, 220)
ACCENT = (24, 92, 180)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    names = (
        "PingFang.ttc",
        "Songti.ttc",
        "Hiragino Sans GB.ttc",
        "STHeiti Light.ttc",
        "Arial Unicode.ttf",
        "Helvetica.ttc",
    )
    search = [
        Path("/System/Library/Fonts") / n
        for n in names
    ] + [
        Path("/System/Library/Fonts/Supplemental") / n
        for n in (
            "Arial Unicode.ttf",
            "Songti.ttc",
            "Times New Roman.ttf",
            "Arial.ttf",
        )
    ]
    for path in search:
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size, index=0)
            except OSError:
                continue
    return ImageFont.load_default()


def new_page() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", SIZE, WHITE)
    return image, ImageDraw.Draw(image)


def invoice() -> None:
    image, draw = new_page()
    title = font(36, bold=True)
    body = font(22)
    small = font(18)
    draw.text((72, 48), "NORTHWIND SUPPLY CO.", fill=ACCENT, font=title)
    draw.text((72, 96), "INVOICE  INV-2026-0918", fill=INK, font=body)
    draw.text((72, 132), "Date: 2026-09-08    Terms: Net 15", fill=MUTED, font=small)
    draw.text((72, 176), "Bill To: Cedar Labs LLC", fill=INK, font=body)
    draw.text((72, 208), "48 Market Street, Suite 12, Portland, OR 97201", fill=MUTED, font=small)

    headers = ["Item", "Qty", "Unit", "Amount"]
    rows = [
        ("Widget A", "2", "12.00", "24.00"),
        ("Cable harness 2m", "4", "8.50", "34.00"),
        ("Mounting kit", "1", "19.90", "19.90"),
    ]
    y = 280
    x_cols = [72, 520, 680, 860]
    for i, h in enumerate(headers):
        draw.text((x_cols[i], y), h, fill=MUTED, font=small)
    draw.line((72, y + 36, 1028, y + 36), fill=LINE, width=2)
    y += 52
    for row in rows:
        for i, cell in enumerate(row):
            draw.text((x_cols[i], y), cell, fill=INK, font=body)
        y += 44
    draw.line((72, y + 8, 1028, y + 36), fill=LINE, width=2)
    draw.text((680, y + 28), "Subtotal", fill=MUTED, font=small)
    draw.text((860, y + 24), "77.90", fill=INK, font=body)
    draw.text((680, y + 68), "Tax 8%", fill=MUTED, font=small)
    draw.text((860, y + 64), "6.23", fill=INK, font=body)
    draw.text((680, y + 112), "TOTAL USD", fill=INK, font=body)
    draw.text((860, y + 108), "84.13", fill=ACCENT, font=title)
    draw.text((72, 1180), "PO-4417   Tracking 1Z999AA10123456784", fill=MUTED, font=small)
    image.save(FIXTURES / "invoice_en.png")


def chinese_form() -> None:
    image, draw = new_page()
    title = font(34)
    body = font(24)
    small = font(20)
    draw.rectangle((48, 40, 1052, 1360), outline=LINE, width=2)
    draw.text((72, 64), "研究生入学材料核对表", fill=INK, font=title)
    draw.text((72, 118), "编号：GT-2026-0041    日期：2026年9月8日", fill=MUTED, font=small)
    lines = [
        "姓名：陈晓    学号：2024310123    专业：统计学",
        "学院：统计与数据科学学院",
        "材料清单：",
        "1. 成绩单原件（盖章）",
        "2. 推荐信两封",
        "3. 研究计划 3000 字",
        "4. 英语成绩：TOEFL 104（阅读 29 / 听力 27 / 口语 24 / 写作 24）",
        "",
        "审核意见：材料齐全，准予提交。",
        "经办人：李敏    复核：王强",
        "",
        "备注：请于 2026-09-15 前补交学位证明复印件。公式示例：$E = mc^2$。",
    ]
    y = 180
    for line in lines:
        draw.text((72, y), line, fill=INK, font=body)
        y += 46
    image.save(FIXTURES / "chinese_form.png")


def ui_screenshot() -> None:
    image = Image.new("RGB", (1280, 800), (246, 247, 249))
    draw = ImageDraw.Draw(image)
    title = font(28)
    body = font(20)
    small = font(16)
    draw.rectangle((0, 0, 1280, 56), fill=(255, 255, 255))
    draw.text((24, 16), "Settings  /  Language & Region", fill=INK, font=title)
    draw.rectangle((24, 88, 1256, 760), fill=WHITE, outline=LINE, width=1)
    draw.text((48, 112), "Preferred language", fill=MUTED, font=small)
    draw.text((48, 144), "English (US)", fill=INK, font=body)
    draw.text((48, 200), "Translation", fill=MUTED, font=small)
    draw.text((48, 232), "On-device translation is available for Chinese, English, Japanese.", fill=INK, font=body)
    draw.rectangle((48, 300, 280, 348), fill=ACCENT)
    draw.text((72, 312), "Download", fill=WHITE, font=body)
    draw.text((48, 392), "Last updated  Sep 8, 2026", fill=MUTED, font=small)
    draw.text((48, 440), "Status: Ready", fill=(32, 140, 72), font=body)
    image.save(FIXTURES / "ui_settings.png")


def table_page() -> None:
    image, draw = new_page()
    title = font(32)
    body = font(20)
    small = font(18)
    draw.text((72, 48), "Motor Controller Datasheet  MC-440", fill=INK, font=title)
    draw.text((72, 100), "Absolute maximum ratings (Ta = 25°C)", fill=MUTED, font=small)
    headers = ["Parameter", "Symbol", "Min", "Typ", "Max", "Unit"]
    rows = [
        ("Supply voltage", "VCC", "4.5", "5.0", "5.5", "V"),
        ("Output current", "IOUT", "—", "2.0", "3.2", "A"),
        ("Switching freq.", "fSW", "20", "25", "30", "kHz"),
        ("Junction temp.", "TJ", "-40", "—", "150", "°C"),
        ("Rds(on)", "RDS", "—", "18", "24", "mΩ"),
    ]
    x_cols = [72, 340, 520, 680, 840, 980]
    y = 160
    for i, h in enumerate(headers):
        draw.text((x_cols[i], y), h, fill=MUTED, font=small)
    draw.line((72, y + 32, 1040, y + 32), fill=LINE, width=2)
    y += 48
    for row in rows:
        for i, cell in enumerate(row):
            draw.text((x_cols[i], y), cell, fill=INK, font=body)
        y += 44
    draw.text((72, y + 40), "Note: Values in this table are for fixture evaluation only.", fill=MUTED, font=small)
    image.save(FIXTURES / "table_datasheet.png")


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    invoice()
    chinese_form()
    ui_screenshot()
    table_page()
    print(f"wrote fixtures to {FIXTURES}")


if __name__ == "__main__":
    main()
