import argparse
import html
import json
import re
from pathlib import Path

from pypdf import PdfReader
import pypdfium2 as pdfium
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


def register_cjk_font():
    candidates = [
        Path('/System/Library/Fonts/STHeiti Light.ttc'),
        Path('/System/Library/Fonts/Hiragino Sans GB.ttc'),
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\simsun.ttc"),
    ]
    for path in candidates:
        if not path.exists():
            continue
        try:
            pdfmetrics.registerFont(TTFont("ReportCJK", str(path)))
            return "ReportCJK", str(path)
        except Exception:
            continue
    raise RuntimeError("No compatible Chinese font was found in C:\\Windows\\Fonts")


def inline_markup(value):
    value = value.strip()
    parts = []
    position = 0
    for match in re.finditer(r"\[([^\]]+)\]\((https?://[^)]+)\)", value):
        parts.append(html.escape(value[position : match.start()]))
        label = html.escape(match.group(1))
        url = html.escape(match.group(2), quote=True)
        parts.append(f'<link href="{url}" color="#1d4ed8">{label}</link>')
        position = match.end()
    parts.append(html.escape(value[position:]))
    text = "".join(parts)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`([^`]+)`", r"<font name=\"Courier\">\1</font>", text)
    return text


def table_column_widths(headers, available_width):
    weights = []
    for header in headers:
        normalized = header.lower()
        if any(token in normalized for token in ["商品", "标题", "title", "观察", "说明"]):
            weights.append(3.0)
        elif any(token in normalized for token in ["asin", "链接", "url", "类目", "榜单"]):
            weights.append(1.35)
        else:
            weights.append(0.85)
    total = sum(weights)
    return [available_width * weight / total for weight in weights]


def split_markdown_table_row(line):
    """Split a Markdown table row while preserving escaped pipe characters."""
    value = line.strip()
    if value.startswith("|"):
        value = value[1:]
    if value.endswith("|") and not value.endswith(r"\|"):
        value = value[:-1]

    cells = []
    current = []
    escaped = False
    for character in value:
        if escaped:
            current.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(character)
    if escaped:
        current.append("\\")
    cells.append("".join(current).strip())
    return cells


def parse_table(lines, start, styles, available_width):
    raw_rows = []
    index = start
    while index < len(lines) and lines[index].strip().startswith("|"):
        cells = split_markdown_table_row(lines[index])
        raw_rows.append(cells)
        index += 1
    if len(raw_rows) < 2:
        return None, start + 1
    separator = raw_rows[1]
    if not all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in separator):
        return None, start + 1
    rows = [raw_rows[0]] + raw_rows[2:]
    column_count = len(rows[0])
    rows = [row[:column_count] + [""] * max(0, column_count - len(row)) for row in rows]
    rendered = []
    for row_index, row in enumerate(rows):
        style = styles["table_header"] if row_index == 0 else styles["table_cell"]
        rendered.append([Paragraph(inline_markup(cell), style) for cell in row])
    widths = table_column_widths(rows[0], available_width)
    table = Table(rendered, colWidths=widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#0f172a")),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#94a3b8")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f8fafc")]),
                ("LEFTPADDING", (0, 0), (-1, -1), 3),
                ("RIGHTPADDING", (0, 0), (-1, -1), 3),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table, index


def build_styles(font_name):
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle("TitleCJK", parent=base["Title"], fontName=font_name, fontSize=20, leading=26, textColor=colors.HexColor("#0f172a"), alignment=TA_CENTER, spaceAfter=10),
        "h2": ParagraphStyle("H2CJK", parent=base["Heading2"], fontName=font_name, fontSize=15, leading=20, textColor=colors.HexColor("#0f3b63"), spaceBefore=10, spaceAfter=6, keepWithNext=0),
        "h2_keep": ParagraphStyle("H2KeepCJK", parent=base["Heading2"], fontName=font_name, fontSize=15, leading=20, textColor=colors.HexColor("#0f3b63"), spaceBefore=10, spaceAfter=6, keepWithNext=1),
        "h3": ParagraphStyle("H3CJK", parent=base["Heading3"], fontName=font_name, fontSize=12.5, leading=17, textColor=colors.HexColor("#334155"), spaceBefore=8, spaceAfter=4, keepWithNext=0),
        "h3_keep": ParagraphStyle("H3KeepCJK", parent=base["Heading3"], fontName=font_name, fontSize=12.5, leading=17, textColor=colors.HexColor("#334155"), spaceBefore=8, spaceAfter=4, keepWithNext=1),
        "body": ParagraphStyle("BodyCJK", parent=base["BodyText"], fontName=font_name, fontSize=9.2, leading=14, textColor=colors.HexColor("#1f2937"), alignment=TA_LEFT, spaceAfter=4),
        "bullet": ParagraphStyle("BulletCJK", parent=base["BodyText"], fontName=font_name, fontSize=9.2, leading=14, leftIndent=12, firstLineIndent=-7, spaceAfter=3),
        "quote": ParagraphStyle("QuoteCJK", parent=base["BodyText"], fontName=font_name, fontSize=8.8, leading=13, leftIndent=10, borderColor=colors.HexColor("#f59e0b"), borderWidth=2, borderPadding=6, backColor=colors.HexColor("#fff7ed"), spaceAfter=6),
        "table_header": ParagraphStyle("TableHeaderCJK", fontName=font_name, fontSize=7.2, leading=9, textColor=colors.HexColor("#0f172a")),
        "table_cell": ParagraphStyle("TableCellCJK", fontName=font_name, fontSize=6.8, leading=9, textColor=colors.HexColor("#1f2937")),
        "meta": ParagraphStyle("MetaCJK", fontName=font_name, fontSize=8.5, leading=12, textColor=colors.HexColor("#475569"), alignment=TA_CENTER),
    }


def should_add_blank_spacer(lines, index):
    previous = index - 1
    while previous >= 0 and not lines[previous].strip():
        previous -= 1
    return not (previous >= 0 and lines[previous].strip().startswith(("## ", "### ")))


def should_keep_heading_with_next(lines, index):
    following = index + 1
    while following < len(lines) and not lines[following].strip():
        following += 1
    return following < len(lines) and not lines[following].strip().startswith("|")


def make_page_callback(font_name, title, generated_at):
    def draw(canvas, document):
        canvas.saveState()
        width, height = landscape(A4)
        canvas.setStrokeColor(colors.HexColor("#cbd5e1"))
        canvas.line(14 * mm, height - 12 * mm, width - 14 * mm, height - 12 * mm)
        canvas.setFont(font_name, 7.5)
        canvas.setFillColor(colors.HexColor("#475569"))
        canvas.drawString(14 * mm, height - 9 * mm, title[:90])
        canvas.drawRightString(width - 14 * mm, 8 * mm, f"{generated_at}  |  {document.page}")
        canvas.restoreState()

    return draw


def render(markdown_path, pdf_path, title, generated_at):
    font_name, font_path = register_cjk_font()
    styles = build_styles(font_name)
    lines = markdown_path.read_text(encoding="utf-8").splitlines()
    page_width, _ = landscape(A4)
    available_width = page_width - 28 * mm
    story = [Paragraph(inline_markup(title), styles["title"]), Paragraph(f"Pacific Time: {html.escape(generated_at)}", styles["meta"]), Spacer(1, 5 * mm)]
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if not line:
            if should_add_blank_spacer(lines, index):
                story.append(Spacer(1, 2.5 * mm))
            index += 1
            continue
        if line.startswith("|"):
            table, next_index = parse_table(lines, index, styles, available_width)
            if table is not None:
                story.extend([table, Spacer(1, 4 * mm)])
                index = next_index
                continue
        if line.startswith("### "):
            style = styles["h3_keep"] if should_keep_heading_with_next(lines, index) else styles["h3"]
            story.append(Paragraph(inline_markup(line[4:]), style))
        elif line.startswith("## "):
            style = styles["h2_keep"] if should_keep_heading_with_next(lines, index) else styles["h2"]
            story.append(Paragraph(inline_markup(line[3:]), style))
        elif line.startswith("# "):
            pass
        elif line.startswith("- "):
            story.append(Paragraph(inline_markup(line[2:]), styles["bullet"], bulletText="•"))
        elif line.startswith("> "):
            story.append(Paragraph(inline_markup(line[2:]), styles["quote"]))
        else:
            story.append(Paragraph(inline_markup(line), styles["body"]))
        index += 1

    pdf_path.parent.mkdir(parents=True, exist_ok=True)
    document = SimpleDocTemplate(
        str(pdf_path),
        pagesize=landscape(A4),
        leftMargin=14 * mm,
        rightMargin=14 * mm,
        topMargin=16 * mm,
        bottomMargin=14 * mm,
        title=title,
        author="Amazon US Home Equipment Intelligence Platform",
    )
    callback = make_page_callback(font_name, title, generated_at)
    document.build(story, onFirstPage=callback, onLaterPages=callback)
    reader = PdfReader(str(pdf_path))
    if len(reader.pages) == 0:
        raise RuntimeError("Generated PDF has no pages")
    if pdf_path.stat().st_size < 1000:
        raise RuntimeError("Generated PDF is unexpectedly small")
    return {"status": "GENERATED", "pdf_path": str(pdf_path.resolve()), "page_count": len(reader.pages), "font_path": font_path, "size_bytes": pdf_path.stat().st_size}


def verify_pdf(pdf_path, expected_page_count, render_directory=None):
    document = pdfium.PdfDocument(str(pdf_path))
    page_count = len(document)
    if page_count != expected_page_count:
        raise RuntimeError(f"PDF rendered page count mismatch: expected {expected_page_count}, found {page_count}")

    rendered_pages = []
    if render_directory is not None:
        render_directory.mkdir(parents=True, exist_ok=True)
    for page_index in range(page_count):
        bitmap = document[page_index].render(scale=110 / 72)
        image = bitmap.to_pil()
        if image.width < 1 or image.height < 1:
            raise RuntimeError(f"Rendered PDF page {page_index + 1} has no pixels")
        if render_directory is not None:
            rendered_path = render_directory / f"page-{page_index + 1}.png"
            image.save(rendered_path, format="PNG")
            if rendered_path.stat().st_size < 1000:
                raise RuntimeError(f"Rendered PDF page {page_index + 1} is unexpectedly small")
            rendered_pages.append(str(rendered_path.resolve()))
    return {"rendered_pages": rendered_pages}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--markdown", required=True)
    parser.add_argument("--pdf", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--generated-at-beijing", required=True)
    parser.add_argument("--verify-pdf", action="store_true")
    parser.add_argument("--render-directory")
    args = parser.parse_args()
    result = render(Path(args.markdown), Path(args.pdf), args.title, args.generated_at_beijing)
    if args.verify_pdf:
        result.update(
            verify_pdf(
                Path(args.pdf),
                result["page_count"],
                Path(args.render_directory) if args.render_directory else None,
            )
        )
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
