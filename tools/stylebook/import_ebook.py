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
from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[2] / "backend" / "data"
IMAGE_DIR = OUT_DIR / "images"

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


FAMILIES = {
    "knit": ["swet", "sweater", "jumper", "knit", "golf", "turtleneck", "roll-neck", "rollneck", "kardigan", "cardigan", "pullover", "troyer"],
    "polo": ["polo", "rugby"],
    "tee": ["koszulk", "t-shirt", "tshirt", "-tee", "longsleeve", "long-sleeve"],
    "shirt": ["koszul", "shirt", "overshirt"],
    "sweat": ["bluz", "hoodie", "sweatshirt"],
    "outer": ["kurtk", "jacket", "parka", "plaszcz", "coat", "trench", "trencz", "peacoat", "kamizelk", "vest", "gilet", "bomber", "harrington", "wiatrowk"],
    "tailored": ["marynark", "blazer", "garnitur", "suit"],
    "bottom": ["spodn", "trouser", "pants", "chino", "sztruks", "cord", "jogger", "jeans", "denim"],
    "shoes": ["buty", "shoe", "sneaker", "trzewik", "boot", "sztyblet", "chelsea", "derby", "loafer", "mokasyn", "oksford", "brogs", "chukka", "polbut", "obuwie"],
    "cap": ["czapk", "beanie", "-cap"],
    "bag": ["torb", "-bag", "plecak", "backpack", "weekend"],
    "belt": ["pasek", "belt"],
    "scarf": ["szal", "scarf"],
    "gloves": ["rekawicz", "glove"],
    "tie": ["krawat", "-tie"],
    "bandana": ["bandan", "chust"],
    "hat": ["kapelusz", "fedora"],
}
LABEL_FAMILY = {
    "SWETER": "knit", "GOLF": "knit", "KARDIGAN": "knit", "POLO": "polo", "RUGBY SHIRT": "polo",
    "TSHIRT": "tee", "LONGSLEEVE": "tee", "KOSZULA": "shirt", "BLUZA": "sweat",
    "KURTKA": "outer", "PARKA": "outer", "PŁASZCZ": "outer", "TRENCZ": "outer", "PEACOAT": "outer", "WIERZCHNIA": "outer", "KAMIZELKA": "outer",
    "MARYNARKA": "tailored", "GARNITUR": "tailored",
    "SPODNIE": "bottom", "SZTRUKSY": "bottom", "CHINOSY": "bottom", "JOGGERY": "bottom", "JEANSY": "bottom",
    "SNEAKERSY": "shoes", "BUTY": "shoes", "TRZEWIKI": "shoes", "SZTYBLETY": "shoes", "DERBY": "shoes", "LOAFERSY": "shoes",
    "LOAFERS": "shoes", "MOKASYNY": "shoes", "OXFORDY": "shoes",
    "CZAPKA": "cap", "TORBA": "bag", "PLECAK": "bag", "PASEK": "belt", "SZAL": "scarf", "RĘKAWICZKI": "gloves",
    "KRAWAT": "tie", "BANDANA": "bandana", "KAPELUSZ": "hat",
}
# A knitted vest or overshirt can legitimately sit in either family.
COMPATIBLE = {
    ("outer", "knit"), ("knit", "outer"), ("shirt", "outer"), ("outer", "shirt"), ("polo", "tee"), ("tee", "polo"),
    ("polo", "knit"), ("knit", "polo"), ("polo", "sweat"), ("tee", "sweat"), ("scarf", "bandana"), ("bandana", "scarf"),
}
# Brand names that contain product words.
BRAND_NOISE = ("polo-ralph-lauren", "polo ralph lauren", "ralph-lauren-polo", "sunset-suits", "suitsupply")


def url_family(url: str) -> str | None:
    path = urllib.parse.unquote(urllib.parse.urlparse(url).path).lower()
    path = path.translate(str.maketrans("ąćęłńóśźż", "acelnoszz"))
    for brand in BRAND_NOISE:
        path = path.replace(brand, " ")
    for family in ("tee", "shoes", "sweat", "bottom", "knit", "tailored", "outer", "polo", "shirt", "cap", "bag", "belt", "scarf", "gloves", "tie", "bandana", "hat"):
        if any(keyword in path for keyword in FAMILIES[family]):
            return family
    return None


def match_links(items: list[dict], links: list[dict]) -> None:
    """Assigns each item a product link (one-to-one): close on the page and, when the shop URL says what it
    sells, of the same kind as the label."""
    def distance(box: fitz.Rect, rect: fitz.Rect) -> float:
        cx, cy = (box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2
        dx = max(rect.x0 - cx, 0, cx - rect.x1)
        dy = max(rect.y0 - cy, 0, cy - rect.y1)
        return (dx * dx + dy * dy) ** 0.5

    def cost(item: dict, link: dict) -> float:
        dist = distance(item["box"], fitz.Rect(link["from"]))
        label = LABEL_FAMILY.get(item["label"])
        family = url_family(resolve(link["uri"]))
        if label and family and label != family and (label, family) not in COMPATIBLE:
            dist += 400  # the shop URL clearly sells something else
        return dist

    if not items or not links:
        return
    costs = [[cost(item, link) for link in links] for item in items]
    no_link = 600.0  # an item may stay without a link if that is cheaper overall
    # Exact minimum-cost assignment by dynamic programming over used links (pages have at most ~12 links).
    best: dict[int, tuple[float, list[int | None]]] = {0: (0.0, [])}
    for i in range(len(items)):
        nxt: dict[int, tuple[float, list[int | None]]] = {}
        for used, (total, chosen) in best.items():
            options = [(total + no_link, used, chosen + [None])]
            options += [(total + costs[i][j], used | (1 << j), chosen + [j]) for j in range(len(links)) if not used & (1 << j)]
            for value, mask, picks in options:
                if mask not in nxt or value < nxt[mask][0]:
                    nxt[mask] = (value, picks)
        best = nxt
    _, picks = min(best.values(), key=lambda v: v[0])
    for i, j in enumerate(picks):
        if j is None:
            continue
        items[i]["url"] = links[j]["uri"]
        items[i]["rect"] = fitz.Rect(links[j]["from"])
        items[i]["matchDistance"] = round(costs[i][j], 1)


def save_product_image(doc: fitz.Document, page: fitz.Page, rect: fitz.Rect, name: str) -> str | None:
    """Saves the product photo under a link (the image that overlaps the link area most) as a JPEG on white."""
    best_xref, best_overlap = None, 0.0
    for info in page.get_image_info(xrefs=True):
        xref = info.get("xref")
        if not xref:
            continue
        overlap = fitz.Rect(info["bbox"]) & rect
        area = 0.0 if overlap.is_empty else overlap.get_area()
        if area > best_overlap:
            best_xref, best_overlap = xref, area
    if not best_xref or best_overlap < 0.3 * rect.get_area():
        return None
    pix = fitz.Pixmap(doc, best_xref)
    if pix.n - pix.alpha >= 4:  # CMYK
        pix = fitz.Pixmap(fitz.csRGB, pix)
    smask = doc.extract_image(best_xref).get("smask") or 0
    if smask and not pix.alpha:
        # Transparent product cutouts store their alpha channel separately.
        pix = fitz.Pixmap(pix, fitz.Pixmap(doc, smask))
    mode = "RGBA" if pix.alpha else "RGB"
    image = Image.frombytes(mode, (pix.width, pix.height), pix.samples)
    if mode == "RGBA":
        white = Image.new("RGB", image.size, (255, 255, 255))
        white.paste(image, mask=image.split()[3])
        image = white
    image.thumbnail((900, 900))
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    file_name = f"{name}.jpg"
    image.save(IMAGE_DIR / file_name, "JPEG", quality=85)
    return file_name


def with_images(doc: fitz.Document, page: fitz.Page, items: list[dict], prefix: str) -> list[dict]:
    result = []
    for index, item in enumerate(items):
        entry = product(item)
        if "rect" in item:
            image = save_product_image(doc, page, item["rect"], f"{prefix}-{index + 1}")
            if image:
                entry["image"] = image
        result.append(entry)
    return result


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
            recipe["budgets"][budget] = {"total": total, "items": with_images(doc, page, items, f"r{number}-{budget}")}
        elif any("INNE OPCJE" in t for t in texts) and links:
            heading = next((t for t, box in lines if box.y0 < 120 and LABEL.match(t) and "INNE OPCJE" not in t), "")
            items = labelled_items(lines)
            match_links(items, links)
            options = with_images(doc, page, items, f"alt{page_index + 1}")
            alternatives.append({"page": page_index + 1, "title": heading, "options": [o | {"brand": i["label"]} for o, i in zip(options, items)]})
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
