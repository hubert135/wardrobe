"""
Extracts outfit recipes and shop links from a style e-book PDF into backend/data/stylebook.raw.json.

The e-book is paid content owned by the user, so everything it produces stays local:
backend/data/ is git-ignored and never pushed. Run:

    python tools/stylebook/import_ebook.py "<path to the e-book>.pdf"

Requires PyMuPDF (pip install pymupdf). Affiliate short links are resolved over HTTP
to find the real shop.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import fitz  # PyMuPDF

OUT_DIR = Path(__file__).resolve().parents[2] / "backend" / "data"

BUDGETS = {
    "WERSJA STANDARD": "standard",
    "WERSJA W NIŻSZEJ CENIE": "budget",
    "WERSJA PREMIUM": "premium",
}

# Hosts that redirect to the real shop.
REDIRECTORS = ("stylink.it", "mpic.link", "go.", "click.", "tradedoubler", "awin", "convertiser")

SHOP_NAMES = {
    "vistula.pl": "Vistula", "bytom.com.pl": "Bytom", "massimodutti.com": "Massimo Dutti", "cos.com": "COS",
    "herse.com": "Herse", "loakepolska.pl": "Loake", "zara.com": "Zara", "tommy.com": "Tommy Hilfiger",
    "kazar.com": "Kazar", "lancerto.com": "Lancerto", "balamonte.com": "Balamonte", "suitsupply.com": "Suitsupply",
    "hugoboss.com": "BOSS", "pewienpan.pl": "Pewien Pan", "martinandmoore.com": "Martin&Moore",
    "klasycznebuty.pl": "Klasyczne Buty", "zalando.pl": "Zalando", "hm.com": "H&M", "wolczanka.pl": "Wólczanka",
    "reserved.com": "Reserved", "rylko.com": "Ryłko", "poszetka.com": "Poszetka", "ochnik.com": "Ochnik",
    "macaronitomato.com": "Macaroni Tomato", "gomez.pl": "Gomez", "oscarjacobson.com": "Oscar Jacobson",
    "johnhenric.com": "John Henric", "vangraaf.com": "Van Graaf", "reiss.com": "Reiss", "prm.com": "PRM",
    "pakolorente.com": "Pako Lorente", "marc-o-polo.com": "Marc O'Polo", "prochnik.pl": "Próchnik",
    "brooksbrothers.eu": "Brooks Brothers", "giacomo.pl": "Giacomo", "strellson.com": "Strellson",
    "puccini.pl": "Puccini", "mango.com": "Mango", "answear.com": "Answear", "levi.com": "Levi's",
    "finshleyandharding.com": "Finshley&Harding", "calvinklein.pl": "Calvin Klein", "gant.pl": "Gant",
    "lee.com": "Lee", "falke.com": "Falke", "apc.fr": "A.P.C.", "polo-ralphlauren.com": "Polo Ralph Lauren",
    "ralphlauren.pl": "Polo Ralph Lauren", "barbour.com": "Barbour", "wittchen.com": "Wittchen",
    "christianberg.com": "Christian Berg", "marksandspencer.com": "M&S", "jackjones.com": "Jack&Jones",
    "unitedcolors.com": "United Colors of Benetton", "benetton.com": "United Colors of Benetton",
}
MPIC_SHOPS = {"mango-pl": "Mango", "answear-pl": "Answear", "levis-pl": "Levi's"}

_resolve_cache: dict[str, str] = {}


def resolve(url: str) -> str:
    """Follows redirects of affiliate short links to the final shop URL (best effort)."""
    host = urllib.parse.urlparse(url).netloc
    if not any(r in host for r in REDIRECTORS):
        return url
    if url in _resolve_cache:
        return _resolve_cache[url]
    final = url
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (stylebook import)"})
        with urllib.request.urlopen(request, timeout=15) as response:
            final = response.geturl()
    except urllib.error.HTTPError as error:
        # Shops often refuse bots on the final page; the address we were redirected to is what we need.
        if urllib.parse.urlparse(error.url).netloc != host:
            final = error.url
    except Exception as error:  # noqa: BLE001 - keep the short link if resolution fails
        print(f"  could not resolve {url}: {error}", file=sys.stderr)
    _resolve_cache[url] = final
    return final


def shop_name(url: str, final_url: str) -> str:
    host = urllib.parse.urlparse(url).netloc
    for prefix, name in MPIC_SHOPS.items():
        if host.startswith(prefix):
            return name
    final_host = urllib.parse.urlparse(final_url).netloc.lower()
    for domain, name in SHOP_NAMES.items():
        if final_host.endswith(domain):
            return name
    parts = [p for p in final_host.split(".") if p not in ("www", "www2", "pl", "sklep", "com", "eu", "shop")]
    return parts[0].capitalize() if parts else final_host


def clean_url(url: str) -> str:
    """Drops tracking parameters; keeps the product path."""
    parsed = urllib.parse.urlparse(url)
    keep = [(k, v) for k, v in urllib.parse.parse_qsl(parsed.query) if not re.match(r"(utm_|gad_|gclid|gbraid|wbraid|ref$|pelement)", k)]
    return urllib.parse.urlunparse(parsed._replace(query=urllib.parse.urlencode(keep), fragment=""))


def lines_with_boxes(page: fitz.Page) -> list[tuple[str, fitz.Rect]]:
    result = []
    for block in page.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            text = "".join(span["text"] for span in line["spans"]).strip()
            if text:
                result.append((text, fitz.Rect(line["bbox"])))
    return result


LABEL = re.compile(r"^[A-ZĄĆĘŁŃÓŚŹŻ’'&\-\. ]{2,40}$")
PRICE = re.compile(r"^(\d{2,5})$")


def labelled_items(lines: list[tuple[str, fitz.Rect]]) -> list[dict]:
    """Pairs an uppercase label line with the price line directly below it."""
    items = []
    for index, (text, box) in enumerate(lines):
        if not LABEL.match(text) or text.startswith("WERSJA") or "RAZEM" in text:
            continue
        for next_text, next_box in lines[index + 1:index + 3]:
            match = PRICE.match(next_text.replace(" ", ""))
            if match and abs(next_box.x0 - box.x0) < 40 and -6 <= next_box.y0 - box.y1 < 25:
                items.append({"label": text.strip(), "price": int(match.group(1)), "box": box | next_box})
                break
        else:
            # "SPODNIE 500" on one line
            inline = re.match(r"^([A-ZĄĆĘŁŃÓŚŹŻ’'&\-\. ]{2,40}?)\s+(\d{2,5})$", text)
            if inline and not text.startswith("WERSJA"):
                items.append({"label": inline.group(1).strip(), "price": int(inline.group(2)), "box": box})
    return items


def match_links(items: list[dict], links: list[dict]) -> None:
    """Assigns each item the nearest product link (one-to-one, closest pairs first)."""
    def distance(box: fitz.Rect, rect: fitz.Rect) -> float:
        cx, cy = (box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2
        dx = max(rect.x0 - cx, 0, cx - rect.x1)
        dy = max(rect.y0 - cy, 0, cy - rect.y1)
        return (dx * dx + dy * dy) ** 0.5

    pairs = sorted(
        ((distance(item["box"], fitz.Rect(link["from"])), i, j) for i, item in enumerate(items) for j, link in enumerate(links)),
        key=lambda p: p[0],
    )
    used_items, used_links = set(), set()
    for dist, i, j in pairs:
        if i in used_items or j in used_links:
            continue
        used_items.add(i)
        used_links.add(j)
        items[i]["url"] = links[j]["uri"]
        items[i]["matchDistance"] = round(dist, 1)


def product(item: dict) -> dict:
    url = item.get("url")
    entry = {"label": item["label"], "price": item["price"], "currency": "PLN"}
    if url:
        final = resolve(url)
        entry.update({"shop": shop_name(url, final), "url": clean_url(final)})
        if item.get("matchDistance", 0) > 60:
            entry["uncertainLink"] = True
    return entry


def main(pdf_path: str) -> None:
    doc = fitz.open(pdf_path)
    recipes: dict[str, dict] = {}
    alternatives: list[dict] = []

    for page_index, page in enumerate(doc):
        lines = lines_with_boxes(page)
        texts = [t for t, _ in lines]
        links = [l for l in page.get_links() if l.get("uri")]
        budget = next((value for key, value in BUDGETS.items() if any(t.startswith(key) and "RAZEM" not in t for t in texts)), None)
        number = next((m.group(1) for t in texts if (m := re.match(r"^(\d{2})\.$", t.strip()))), None)

        if budget and number:
            top = sorted((box.y0, t) for t, box in lines if 55 <= box.y0 <= 100 and not t.startswith(("WERSJA", number)))
            title = " ".join(t for _, t in top).replace("  ", " ").strip()
            recipe = recipes.setdefault(number, {"id": number, "title": title, "description": "", "pages": [], "budgets": {}})
            recipe["pages"].append(page_index + 1)
            description = " ".join(t for t, box in lines if t.startswith("Wykorzystaj") or (130 <= box.y0 <= 270 and box.x0 < 100))
            if budget == "standard" and description:
                recipe["description"] = description.replace("Wykorzystaj:", "").strip()
            total = next((int(m.group(1)) for t in texts if (m := re.search(r"RAZEM:\s*(\d+)", t))), None)
            items = labelled_items(lines)
            match_links(items, links)
            recipe["budgets"][budget] = {"total": total, "items": [product(i) for i in items]}
        elif any("INNE OPCJE" in t for t in texts) and links:
            heading = next((t for t, box in lines if box.y0 < 120 and LABEL.match(t) and "INNE OPCJE" not in t), "")
            items = labelled_items(lines)
            match_links(items, links)
            alternatives.append({"page": page_index + 1, "title": heading, "options": [product(i) | {"brand": i["label"]} for i in items]})
        print(f"page {page_index + 1}: {'recipe ' + number + ' ' + budget if budget and number else ('alternatives' if alternatives and alternatives[-1]['page'] == page_index + 1 else '-')}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / "stylebook.raw.json"
    data = {"source": Path(pdf_path).name, "recipes": sorted(recipes.values(), key=lambda r: r["id"]), "alternatives": alternatives}
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n{len(recipes)} recipes, {len(alternatives)} alternative pages -> {out}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: import_ebook.py <ebook.pdf>")
    main(sys.argv[1])
