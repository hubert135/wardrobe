"""
Merges backend/data/stylebook.raw.json (from import_ebook.py) with backend/data/stylebook.annotations.json
(engine-readable recipe formulas) into backend/data/stylebook.json, which the backend serves to the app.
Everything in backend/data/ is private and git-ignored.

    python tools/stylebook/build_stylebook.py
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[2] / "backend" / "data"


def main() -> None:
    raw = json.loads((DATA / "stylebook.raw.json").read_text(encoding="utf-8"))
    notes = json.loads((DATA / "stylebook.annotations.json").read_text(encoding="utf-8"))
    recipes = []
    problems = []

    for recipe in raw["recipes"]:
        note = notes["recipes"].get(recipe["id"])
        if not note:
            problems.append(f"recipe {recipe['id']}: no annotation, skipped")
            continue
        pieces = note["pieces"]
        budgets = {}
        for budget, data in recipe["budgets"].items():
            items = []
            for item in data["items"]:
                index = next((i for i, piece in enumerate(pieces) if item["label"] in piece.get("labels", [])), None)
                if index is None:
                    problems.append(f"recipe {recipe['id']} {budget}: product label {item['label']} not mapped to a piece")
                items.append({**item, "pieceIndex": index})
            budgets[budget] = {"total": data.get("total"), "items": items}
        recipes.append({
            "id": recipe["id"],
            "title": recipe["title"],
            "summary": note["summary"],
            "description": recipe["description"],
            "occasions": note["occasions"],
            "styles": note["styles"],
            "seasons": note.get("seasons", notes.get("seasons", [])),
            "pieces": [{"optional": False, "patterns": [], **piece} for piece in pieces],
            "budgets": budgets,
        })

    payload = {"source": raw["source"], "recipes": recipes, "alternatives": raw.get("alternatives", [])}
    body = json.dumps(payload, ensure_ascii=False, sort_keys=True)
    payload["version"] = hashlib.sha256(body.encode("utf-8")).hexdigest()[:12]
    (DATA / "stylebook.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    for problem in problems:
        print("warning:", problem, file=sys.stderr)
    print(f"{len(recipes)} recipes -> {DATA / 'stylebook.json'} (version {payload['version']})")


if __name__ == "__main__":
    main()
