"""
Wardrobe style knowledge base: menswear principles, an outfit-recipe library and a generic capsule closet.

Written from general menswear know-how (and lessons learned from the user's style guide, in our own
words). Brand-free on purpose: a white shirt is a white shirt. Run to regenerate the engine resources:

    python tools/knowledge/style_library.py

Outputs Packages/OutfitEngine/Sources/OutfitEngine/Resources/{knowledge,recipes,capsule}.json.
Colors are palette names (see ColorPalette.swift), categories/styles/occasions/seasons are engine raw values.
"""

from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "Packages" / "OutfitEngine" / "Sources" / "OutfitEngine" / "Resources"

# --------------------------------------------------------------------------------------------------
# 1. Principles
# --------------------------------------------------------------------------------------------------

# How well two colors work in one outfit: 2 classic, 1 good, 0 neutral, -1 avoid. Symmetric.
COLOR_PAIRS = {
    ("navy", "grey"): 2, ("navy", "white"): 2, ("navy", "light blue"): 2, ("navy", "beige"): 2, ("navy", "cream"): 2,
    ("navy", "tan"): 2, ("navy", "brown"): 2, ("navy", "burgundy"): 2, ("navy", "khaki"): 1, ("navy", "olive"): 1,
    ("navy", "charcoal"): 1, ("navy", "denim"): 1, ("navy", "pink"): 1, ("navy", "red"): 1, ("navy", "yellow"): 1,
    ("navy", "green"): 1, ("navy", "orange"): 1, ("navy", "black"): -1,
    ("grey", "white"): 2, ("grey", "light blue"): 2, ("grey", "burgundy"): 2, ("grey", "black"): 1, ("grey", "charcoal"): 1,
    ("grey", "cream"): 1, ("grey", "brown"): 1, ("grey", "tan"): 1, ("grey", "denim"): 1, ("grey", "pink"): 1,
    ("grey", "green"): 1, ("grey", "purple"): 1, ("grey", "red"): 1,
    ("charcoal", "white"): 2, ("charcoal", "light blue"): 2, ("charcoal", "burgundy"): 2, ("charcoal", "black"): 1,
    ("charcoal", "cream"): 1, ("charcoal", "pink"): 1, ("charcoal", "tan"): 1, ("charcoal", "purple"): 1,
    ("black", "white"): 2, ("black", "cream"): 1, ("black", "tan"): 1, ("black", "red"): 1, ("black", "burgundy"): 1,
    ("black", "denim"): 1, ("black", "brown"): -1, ("black", "yellow"): -1,
    ("white", "light blue"): 1, ("white", "denim"): 2, ("white", "beige"): 1, ("white", "tan"): 1, ("white", "brown"): 1,
    ("white", "khaki"): 1, ("white", "olive"): 1, ("white", "green"): 1, ("white", "blue"): 1, ("white", "burgundy"): 1,
    ("white", "red"): 1, ("white", "pink"): 1, ("white", "yellow"): 1, ("white", "orange"): 1, ("white", "purple"): 1,
    ("light blue", "beige"): 2, ("light blue", "brown"): 2, ("light blue", "tan"): 1, ("light blue", "khaki"): 1,
    ("light blue", "cream"): 1, ("light blue", "denim"): 1, ("light blue", "olive"): 1, ("light blue", "burgundy"): 1,
    ("light blue", "yellow"): 1,
    ("denim", "cream"): 2, ("denim", "olive"): 2, ("denim", "brown"): 2, ("denim", "tan"): 1, ("denim", "beige"): 1,
    ("denim", "burgundy"): 1, ("denim", "red"): 1, ("denim", "green"): 1, ("denim", "khaki"): 1, ("denim", "pink"): 1,
    ("denim", "yellow"): 1, ("denim", "orange"): 1,
    ("beige", "brown"): 1, ("beige", "olive"): 1, ("beige", "cream"): 1, ("beige", "burgundy"): 1, ("beige", "green"): 1,
    ("cream", "brown"): 2, ("cream", "olive"): 2, ("cream", "tan"): 1, ("cream", "burgundy"): 1, ("cream", "green"): 1,
    ("tan", "brown"): 1, ("tan", "olive"): 1, ("tan", "burgundy"): 1,
    ("brown", "olive"): 1, ("brown", "burgundy"): 1, ("brown", "green"): 1, ("brown", "khaki"): 1, ("brown", "orange"): 1,
    ("olive", "burgundy"): 1, ("olive", "khaki"): 0,
    ("burgundy", "red"): -1, ("burgundy", "pink"): -1, ("red", "pink"): -1, ("red", "orange"): -1,
}

# Surface character by keywords found in a garment's type or material.
TEXTURES = {
    "textured": ["corduroy", "cord ", "tweed", "flannel", "cable", "chunky", "waffle", "boucle", "bouclé", "suede", "nubuck",
                 "oxford", "chambray", "denim", "linen", "herringbone", "shetland", "lambswool", "fleece", "quilted",
                 "waxed", "shearling", "seersucker", "knit"],
    "sheen": ["leather", "satin", "silk", "patent", "velvet", "nylon"],
}
# Heavy textures that look clumsy on both top and bottom (unless it is a suit).
HEAVY_TEXTURES = ["corduroy", "tweed", "cable", "chunky", "shearling", "fleece"]

# Fabrics that only make sense in some seasons (used when a garment has no seasons set).
SEASONAL_MATERIALS = {
    "spring,summer": ["linen", "seersucker", "espadrille", "sandal", "short sleeve", "short-sleeve"],
    "autumn,winter": ["flannel", "tweed", "corduroy", "cashmere", "shearling", "puffer", "down jacket", "cable",
                      "lambswool", "peacoat", "overcoat", "fleece-lined", "chunky"],
}

# Typical formality (1 sporty ... 5 formal) by garment type keyword, most specific first.
FORMALITY_KEYWORDS = [
    ["tuxedo", 5], ["dress shirt", 5], [" suit", 5], ["oxford shoe", 5], ["patent", 5], ["overcoat", 5],
    ["monk", 4], ["derby", 4], ["brogue", 4], ["chelsea", 4], ["peacoat", 4], ["trench", 4], ["blazer", 4],
    ["turtleneck", 4], ["flannel trousers", 4], ["wool trousers", 4], ["tweed", 4],
    ["loafer", 3], ["chukka", 3], ["desert", 3], ["oxford shirt", 3], ["oxford", 3], ["knit polo", 3], ["cardigan", 3],
    ["merino", 3], ["chino", 3], ["corduroy", 3], ["leather sneaker", 3], ["suede jacket", 3], ["leather jacket", 3],
    ["linen", 3], ["quarter-zip", 3],
    ["flannel shirt", 2], ["chambray", 2], ["denim jacket", 2], ["field jacket", 2], ["chore", 2], ["bomber", 2],
    ["puffer", 2], ["pique", 2], ["t-shirt", 2], ["tee", 2], ["sneaker", 2], ["canvas", 2], ["shorts", 2], ["cargo", 2],
    ["boot", 2],
    ["hoodie", 1], ["sweatshirt", 1], ["jogger", 1], ["track", 1], ["running", 1], ["trail", 1], ["windbreaker", 1],
    ["fleece", 1], ["sandal", 1], ["flip-flop", 1],
]

# What never belongs in a style, by category and by type keyword (matched in "material subcategory";
# " suit" has a leading space so tracksuits are not suits).
STYLE_EXCLUSIONS = {
    "formal": {"categories": ["hoodie", "t-shirt", "shorts", "jeans"],
               "keywords": ["sneaker", "trainer", "running", "canvas", "jogger", "sweatshirt", "sweatpant", "cotton sweat", "fleece", "cargo", "track",
                            "puffer", "down jacket", "windbreaker", "bomber", "sandal", "espadrille", "flip-flop",
                            "graphic", "field jacket", "denim jacket", "chore"]},
    "smart_casual": {"categories": ["hoodie"],
                     "keywords": ["jogger", "sweatshirt", "sweatpant", "cotton sweat", "fleece", "track", "running", "trail", "cargo", "sandal",
                                  "flip-flop", "graphic", "windbreaker", "gym"]},
    "casual": {"categories": [],
               "keywords": ["tuxedo", "patent", " suit", "dress shirt"]},
    "sporty": {"categories": ["blazer"],
               "keywords": ["tuxedo", "patent", " suit", "dress shirt", "oxford shoe", "velvet", "tweed", "overcoat",
                            "loafer", "derby", "brogue", "monk", "trench", "peacoat", "flannel trousers", "wool trousers"]},
}

# Styling tips shown with outfits (short, our own words).
PRINCIPLES = [
    "Fit beats price: no pulling at buttons, sleeves ending at the wrist, trousers without a concertina above the shoe.",
    "Balance volume: a chunky top wants straight or wider trousers; very slim trousers exaggerate a big knit.",
    "Layer from thin to thick, and make sure the outfit still works when the coat comes off.",
    "Mix one strong texture with calm, smooth pieces: a cable knit with plain trousers, corduroy with a plain top.",
    "Build around two or three base colours (navy, grey, brown, beige, olive, black) and add at most one accent.",
    "Burgundy is the easiest accent: it sits with navy, grey, brown and black.",
    "Pure white contrasts crisply with navy, black and grey; ecru and cream are softer next to brown, olive, beige and denim.",
    "Shoes set the level of the outfit; match their shape and weight to the trouser width.",
    "In smart outfits keep belt and shoes in the same colour family: black with black, brown with brown.",
    "A coordinated jacket and trousers should contrast on purpose (navy with grey, brown with cream, olive with beige).",
    "Avoid denim on denim in the same wash, and leave logos and statement details for experienced hands.",
    "Linen and seersucker are for warm months; flannel, tweed, corduroy and cashmere for cold ones.",
]


# --------------------------------------------------------------------------------------------------
# 2. Recipe library
# --------------------------------------------------------------------------------------------------

def P(slot, categories, colors=(), materials=(), avoid=(), patterns=(), optional=False, requires=()):
    """materials: preferred keywords (bonus); requires: at least one must appear (defines the piece);
    avoid: the garment may not contain any of these."""
    return {"slot": slot, "categories": list(categories), "colors": list(colors), "materials": list(materials),
            "requires": list(requires), "avoid": list(avoid), "patterns": list(patterns), "optional": optional}


def R(id, title, summary, occasions, styles, seasons, pieces):
    return {"id": id, "title": title, "summary": summary, "occasions": occasions, "styles": styles,
            "seasons": seasons, "pieces": pieces}


ALL = []
SPRING_SUMMER = ["spring", "summer"]
AUTUMN_WINTER = ["autumn", "winter"]
NOT_SUMMER = ["spring", "autumn", "winter"]
NOT_WINTER = ["spring", "summer", "autumn"]

DRESS_SHIRT_AVOID = ["flannel", "linen", "denim", "chambray", "overshirt", "short sleeve"]
SMART_SHOES_AVOID = ["sneaker", "trainer", "running", "canvas", "trail"]
FORMAL_SHOES_AVOID = SMART_SHOES_AVOID + ["suede", "chukka", "desert"]
TAILORED_AVOID = ["jogger", "sweat", "cargo", "track", "corduroy"]

belt = lambda colors=("brown", "black"): P("accessory", ["accessory"], colors, ["belt"], optional=True)
tie = lambda colors: P("accessory", ["accessory"], colors, ["tie"], optional=True)

RECIPES = [
    # ---- Formal / business ----
    R("L01", "Navy suit, white shirt, black dress shoes",
      "The most useful business outfit: a navy suit, a crisp white shirt and black oxfords. Add a navy or burgundy tie, a black belt and navy socks.",
      ["business_meeting", "event", "work"], ["formal"], [],
      [P("outerwear", ["blazer"], ["navy"], ["suit"], TAILORED_AVOID, requires=["suit"]),
       P("bottom", ["trousers"], ["navy"], ["suit"], TAILORED_AVOID, requires=["suit"]),
       P("top", ["shirt"], ["white"], ["dress shirt", "poplin"], DRESS_SHIRT_AVOID),
       P("shoes", ["shoes"], ["black"], ["oxford", "derby"], FORMAL_SHOES_AVOID),
       tie(["navy", "burgundy"])]),
    R("L02", "Charcoal suit, light blue shirt, black dress shoes",
      "Charcoal is the most formal everyday suit colour; a light blue shirt softens it and a burgundy tie is the single accent. Black shoes and belt.",
      ["business_meeting", "event"], ["formal"], [],
      [P("outerwear", ["blazer"], ["charcoal", "grey"], ["suit"], TAILORED_AVOID, requires=["suit"]),
       P("bottom", ["trousers"], ["charcoal", "grey"], ["suit"], TAILORED_AVOID, requires=["suit"]),
       P("top", ["shirt"], ["light blue"], ["dress shirt", "poplin"], DRESS_SHIRT_AVOID),
       P("shoes", ["shoes"], ["black"], ["oxford", "derby"], FORMAL_SHOES_AVOID),
       tie(["burgundy", "navy"])]),
    R("L03", "Suit without a tie, brown shoes",
      "A suit worn with an open collar reads modern rather than stiff. Brown derbies or loafers warm it up; keep the belt brown to match.",
      ["work", "dinner", "business_meeting"], ["formal", "smart_casual"], [],
      [P("outerwear", ["blazer"], ["grey", "navy", "charcoal"], ["suit"], TAILORED_AVOID, requires=["suit"]),
       P("bottom", ["trousers"], ["grey", "navy", "charcoal"], ["suit"], TAILORED_AVOID, requires=["suit"]),
       P("top", ["shirt"], ["white", "light blue"], ["oxford", "poplin"], ["flannel", "denim", "chambray"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["derby", "loafer"], SMART_SHOES_AVOID),
       belt(["brown"])]),
    R("L04", "Navy blazer, grey trousers, shirt",
      "Odd jacket and trousers should contrast on purpose: navy over mid-grey is the classic pairing. Add a tie for meetings, drop it for dinner.",
      ["business_meeting", "work", "event", "dinner"], ["formal", "smart_casual"], [],
      [P("outerwear", ["blazer"], ["navy"], ["blazer", "wool"], ["suit"]),
       P("bottom", ["trousers"], ["grey", "charcoal"], ["wool", "flannel"], TAILORED_AVOID),
       P("top", ["shirt"], ["white", "light blue"], ["oxford", "poplin"], ["flannel", "denim", "chambray"]),
       P("shoes", ["shoes"], ["black", "brown"], ["derby", "oxford", "loafer"], SMART_SHOES_AVOID),
       tie(["burgundy", "navy"])]),
    R("L05", "Tweed jacket, flannel trousers, oxford shirt",
      "Textured tweed needs equally wintry partners: flannel trousers and an oxford shirt. Brown brogues or derbies and a knitted tie finish it.",
      ["work", "dinner", "event"], ["smart_casual", "formal"], AUTUMN_WINTER,
      [P("outerwear", ["blazer"], ["brown", "grey", "olive"], ["tweed"], requires=["tweed", "herringbone"]),
       P("bottom", ["trousers"], ["grey", "charcoal"], ["flannel", "wool"], TAILORED_AVOID),
       P("top", ["shirt"], ["light blue", "white"], ["oxford"], ["denim", "chambray"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["brogue", "derby"], SMART_SHOES_AVOID),
       tie(["burgundy", "green"])]),
    R("L06", "Dark suit for the evening",
      "For evening events go dark and simple: a navy or charcoal suit, a white shirt and polished black shoes. Lose the tie at a relaxed party.",
      ["event", "dinner"], ["formal"], [],
      [P("outerwear", ["blazer"], ["navy", "charcoal", "black"], ["suit", "velvet"], TAILORED_AVOID, requires=["suit", "velvet", "tuxedo"]),
       P("bottom", ["trousers"], ["navy", "charcoal", "black"], ["suit", "wool"], TAILORED_AVOID, requires=["suit", "wool", "tuxedo"]),
       P("top", ["shirt"], ["white"], ["dress shirt", "poplin"], DRESS_SHIRT_AVOID),
       P("shoes", ["shoes"], ["black"], ["oxford", "derby", "loafer"], FORMAL_SHOES_AVOID)]),
    R("L07", "Light summer jacket, open collar",
      "In warm weather a stone or light grey suit in linen or cotton looks fresh. A light blue shirt and brown suede loafers; ties optional.",
      ["event", "dinner", "business_meeting"], ["formal", "smart_casual"], SPRING_SUMMER,
      [P("outerwear", ["blazer"], ["beige", "grey", "cream"], ["linen", "cotton"], ["tweed", "flannel", "corduroy", "velvet"]),
       P("bottom", ["trousers", "chinos"], ["beige", "grey", "cream"], ["linen", "cotton"], TAILORED_AVOID),
       P("top", ["shirt"], ["light blue", "white"], ["linen", "poplin", "oxford"], ["flannel", "denim"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede"], SMART_SHOES_AVOID)]),
    R("L08", "Blazer with a fine turtleneck",
      "A fine merino turtleneck under a blazer is the polished alternative to shirt and tie. Keep the trousers dark and the shoes sleek.",
      ["dinner", "event"], ["smart_casual", "formal"], AUTUMN_WINTER,
      [P("outerwear", ["blazer"], ["navy", "charcoal", "brown"], ["blazer", "wool", "tweed"]),
       P("top", ["sweater"], ["black", "navy", "cream"], ["merino"], requires=["turtleneck", "roll neck", "rollneck"]),
       P("bottom", ["trousers"], ["grey", "charcoal", "black"], ["wool", "flannel"], TAILORED_AVOID),
       P("shoes", ["shoes"], ["black", "brown"], ["chelsea", "loafer", "derby"], SMART_SHOES_AVOID)]),

    # ---- Smart casual ----
    R("L10", "Navy blazer, white oxford, beige chinos",
      "The everyday smart-casual uniform: navy jacket, white oxford, beige chinos. Brown suede loafers keep it relaxed; a brown belt ties it together.",
      ["work", "dinner", "event"], ["smart_casual"], [],
      [P("outerwear", ["blazer"], ["navy"], ["unstructured", "blazer"], ["suit"]),
       P("top", ["shirt"], ["white"], ["oxford"], ["flannel"]),
       P("bottom", ["chinos"], ["beige", "khaki", "tan"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede", "derby"], SMART_SHOES_AVOID),
       belt(["brown"])]),
    R("L11", "Blazer with dark jeans",
      "Dark, clean jeans dress up easily: add an oxford shirt and a soft-shouldered blazer. Loafers or Chelsea boots finish it better than trainers.",
      ["dinner", "work", "casual_outing"], ["smart_casual"], [],
      [P("outerwear", ["blazer"], ["navy", "grey", "brown"], ["unstructured", "tweed", "blazer"], ["suit"]),
       P("top", ["shirt"], ["light blue", "white"], ["oxford"], ["flannel"]),
       P("bottom", ["jeans"], ["denim"], ["dark"], ["light wash", "distressed", "ripped"]),
       P("shoes", ["shoes"], ["brown"], ["loafer", "chelsea", "derby"], SMART_SHOES_AVOID)]),
    R("L12", "Crewneck over a shirt, dark jeans, brown boots",
      "A crewneck over a button-down is warm and neat; let the collar sit outside the knit. Dark jeans and brown Chelsea boots keep it grown-up.",
      ["work", "dinner", "casual_outing"], ["smart_casual"], NOT_SUMMER,
      [P("top", ["sweater"], ["grey", "navy"], ["merino", "crewneck"], ["cable", "zip"]),
       P("bottom", ["jeans"], ["denim"], ["dark"], ["light wash", "distressed"]),
       P("shoes", ["shoes"], ["brown"], ["chelsea"], SMART_SHOES_AVOID, requires=["boot"]),
       P("top", ["shirt"], ["white", "light blue"], ["oxford"], optional=True)]),
    R("L13", "Navy knit, grey trousers, brown shoes",
      "Navy and grey is the safest smart combination there is. A fine crewneck over wool trousers works in most offices; add a collar for meetings.",
      ["work", "business_meeting", "dinner"], ["smart_casual"], NOT_SUMMER,
      [P("top", ["sweater"], ["navy"], ["merino", "crewneck"], ["cable", "hoodie"]),
       P("bottom", ["trousers"], ["grey", "charcoal"], ["wool", "flannel"], TAILORED_AVOID),
       P("shoes", ["shoes"], ["brown"], ["derby", "loafer"], SMART_SHOES_AVOID),
       P("top", ["shirt"], ["white", "light blue"], [], optional=True)]),
    R("L14", "Camel coat, dark turtleneck, grey trousers",
      "A camel coat lifts dark winter outfits instantly. Keep everything underneath dark and smooth so the coat stays the focus.",
      ["dinner", "work", "event"], ["smart_casual", "formal"], AUTUMN_WINTER,
      [P("outerwear", ["coat"], ["tan", "beige"], ["overcoat", "wool"], ["trench", "mac", "puffer", "down"], requires=["overcoat", "wool", "camel"]),
       P("top", ["sweater"], ["navy", "black", "charcoal"], ["merino"], requires=["turtleneck", "roll neck", "rollneck"]),
       P("bottom", ["trousers"], ["charcoal", "grey"], ["wool", "flannel"], TAILORED_AVOID),
       P("shoes", ["shoes"], ["black", "brown"], ["chelsea", "derby", "loafer"], SMART_SHOES_AVOID)]),
    R("L15", "Trench coat, navy knit, grey trousers",
      "A trench is the transitional-season essential. A navy knit and grey trousers underneath still work once the coat comes off.",
      ["work", "dinner"], ["smart_casual"], ["spring", "autumn"],
      [P("outerwear", ["coat"], ["beige", "tan", "khaki"], ["trench", "mac"], requires=["trench", "mac", "gabardine"]),
       P("top", ["sweater"], ["navy"], ["merino", "crewneck"]),
       P("bottom", ["trousers"], ["grey", "charcoal"], ["wool"], TAILORED_AVOID),
       P("shoes", ["shoes"], ["brown"], ["loafer", "derby"], SMART_SHOES_AVOID)]),
    R("L16", "Knit polo, chinos, suede shoes",
      "A knitted polo sits between a T-shirt and a shirt: smart enough for the office, relaxed enough for dinner. Tuck it in and show a slim belt.",
      ["work", "dinner", "casual_outing"], ["smart_casual"], NOT_WINTER,
      [P("top", ["polo"], ["navy", "brown", "cream", "white"], ["knit"], ["pique"], requires=["knit"]),
       P("bottom", ["chinos"], ["beige", "navy", "olive"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede"], SMART_SHOES_AVOID),
       belt(["brown"])]),
    R("L17", "White linen shirt, light trousers, loafers",
      "Linen is meant to look a little relaxed; keep the colours light and the fit easy. Suede loafers without socks suit a summer evening.",
      ["dinner", "casual_outing", "event", "travel"], ["smart_casual", "casual"], ["summer"],
      [P("top", ["shirt"], ["white", "light blue"], ["linen"], requires=["linen"]),
       P("bottom", ["trousers", "chinos"], ["beige", "cream", "navy"], ["linen", "cotton"], TAILORED_AVOID),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede", "espadrille"], ["running", "trail"])]),
    R("L18", "Soft blazer over a white T-shirt",
      "A soft blazer over a plain white T-shirt is the modern smart-casual shortcut. Clean white leather sneakers or loafers both work.",
      ["dinner", "casual_outing", "work"], ["smart_casual"], NOT_WINTER,
      [P("outerwear", ["blazer"], ["navy", "grey", "beige"], ["unstructured", "linen", "cotton"], ["suit"]),
       P("top", ["t-shirt"], ["white", "grey", "navy"], [], ["graphic", "breton"]),
       P("bottom", ["trousers", "chinos"], ["grey", "beige", "navy"], [], TAILORED_AVOID),
       P("shoes", ["shoes"], ["white", "brown"], ["leather sneaker", "loafer"], ["running", "trail", "canvas"])]),
    R("L19", "Chambray shirt, chinos, suede chukkas",
      "A chambray shirt has denim's texture with a shirt's polish. Earthy chinos and suede chukkas keep the palette warm.",
      ["work", "casual_outing", "weekend"], ["smart_casual", "casual"], ["spring", "autumn"],
      [P("top", ["shirt"], ["denim", "light blue"], ["chambray", "denim"], requires=["chambray", "denim"]),
       P("bottom", ["chinos"], ["beige", "khaki", "olive"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["chukka", "desert", "suede"], ["running", "trail"])]),
    R("L20", "Corduroys, oxford shirt, navy crewneck",
      "Corduroy brings texture, so keep the rest plain: a navy crewneck over a light blue oxford and brown suede shoes.",
      ["work", "weekend", "dinner"], ["smart_casual"], AUTUMN_WINTER,
      [P("bottom", ["trousers", "chinos"], ["brown", "olive", "beige", "cream"], ["corduroy"], requires=["corduroy", "cord "]),
       P("top", ["sweater"], ["navy"], ["merino", "crewneck"], ["cable"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede", "chukka"], SMART_SHOES_AVOID),
       P("top", ["shirt"], ["light blue", "white"], ["oxford"], optional=True)]),
    R("L21", "Burgundy knit with grey and navy",
      "Burgundy is the easiest accent colour: it sits naturally with grey, navy and brown. Let it be the only colour in the outfit.",
      ["work", "dinner", "casual_outing"], ["smart_casual"], AUTUMN_WINTER,
      [P("top", ["sweater"], ["burgundy", "red"], ["lambswool", "merino"]),
       P("bottom", ["trousers", "chinos", "jeans"], ["grey", "charcoal", "denim"], ["wool", "flannel"], TAILORED_AVOID),
       P("shoes", ["shoes"], ["brown", "black"], ["chelsea", "derby", "boot"], SMART_SHOES_AVOID),
       P("outerwear", ["coat"], ["navy"], ["peacoat", "overcoat"], optional=True)]),
    R("L22", "Cream cable knit, dark jeans, peacoat",
      "A chunky cream knit with dark denim is winter weekend comfort that still looks put together. Wear the knit untucked, a navy peacoat over the top.",
      ["weekend", "casual_outing", "dinner"], ["smart_casual", "casual"], AUTUMN_WINTER,
      [P("top", ["sweater"], ["cream", "white"], ["cable", "wool"], requires=["cable", "chunky", "fisherman", "aran"]),
       P("bottom", ["jeans"], ["denim"], ["dark"], ["ripped"]),
       P("outerwear", ["coat", "jacket"], ["navy"], ["peacoat", "wool"], ["puffer", "down", "nylon"], requires=["peacoat", "wool"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["boot", "chukka", "chelsea"], ["running", "trail"])]),
    R("L23", "Quarter-zip, chinos, clean sneakers",
      "A quarter-zip with a white T-shirt just visible at the neck is comfortable and tidy: great for travel days and relaxed offices.",
      ["work", "travel", "casual_outing"], ["smart_casual", "casual"], NOT_SUMMER,
      [P("top", ["sweater"], ["grey", "navy"], ["quarter-zip"], requires=["zip"]),
       P("bottom", ["chinos", "trousers"], ["navy", "beige", "grey"], [], ["jogger", "cargo"]),
       P("shoes", ["shoes"], ["white", "brown"], ["leather sneaker"], ["running", "trail"]),
       P("top", ["t-shirt"], ["white"], [], optional=True)]),
    R("L24", "Suede jacket, fine turtleneck, dark jeans",
      "Suede and soft knitwear make a warm, tactile pairing. Keep the jeans dark and the boots brown for a relaxed date-night look.",
      ["dinner", "casual_outing"], ["smart_casual"], ["spring", "autumn"],
      [P("outerwear", ["jacket"], ["brown", "tan"], ["suede"], requires=["suede"]),
       P("top", ["sweater"], ["cream", "white", "grey", "black", "navy"], ["merino"], requires=["turtleneck", "roll neck", "rollneck"]),
       P("bottom", ["jeans"], ["denim"], ["dark"], ["ripped"]),
       P("shoes", ["shoes"], ["brown"], ["chelsea", "boot", "loafer"], SMART_SHOES_AVOID)]),
    R("L25", "Black leather jacket, grey knit, black jeans",
      "A dark base with one matte grey layer keeps a leather jacket sharp rather than rock'n'roll. Black boots, no other shine.",
      ["dinner", "casual_outing", "event"], ["smart_casual", "casual"], ["spring", "autumn"],
      [P("outerwear", ["jacket"], ["black"], ["leather"], requires=["leather"]),
       P("top", ["sweater", "t-shirt"], ["grey", "charcoal", "white"], ["merino", "crewneck"]),
       P("bottom", ["jeans"], ["black", "charcoal"]),
       P("shoes", ["shoes"], ["black"], ["chelsea", "boot", "derby"], ["running", "trail", "canvas"])]),
    R("L26", "Tonal dark evening layers",
      "Tonal charcoal and black look effortlessly elegant at night. Vary the textures (fine knit, flannel, wool coat) so it does not fall flat.",
      ["dinner", "event"], ["smart_casual", "formal"], AUTUMN_WINTER,
      [P("top", ["sweater"], ["black", "charcoal"], ["turtleneck", "merino"]),
       P("bottom", ["trousers"], ["charcoal", "grey", "black"], ["wool", "flannel"], TAILORED_AVOID),
       P("outerwear", ["coat"], ["charcoal", "black", "navy"], ["overcoat", "wool"]),
       P("shoes", ["shoes"], ["black"], ["chelsea", "derby", "boot"], SMART_SHOES_AVOID)]),
    R("L27", "Grey knit, olive chinos, brown shoes",
      "Olive and grey are a quiet, grown-up pairing; brown shoes bridge the two.",
      ["work", "casual_outing", "weekend"], ["smart_casual"], NOT_SUMMER,
      [P("top", ["sweater"], ["grey"], ["merino", "crewneck"]),
       P("bottom", ["chinos"], ["olive"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["derby", "loafer", "suede", "chukka"], SMART_SHOES_AVOID),
       P("top", ["shirt"], ["white", "light blue"], optional=True)]),
    R("L28", "Pink oxford, navy chinos, brown shoes",
      "A pale pink oxford is a confident spring alternative to blue; navy chinos and brown loafers keep it grounded.",
      ["work", "dinner"], ["smart_casual"], SPRING_SUMMER,
      [P("top", ["shirt"], ["pink"], ["oxford"]),
       P("bottom", ["chinos", "trousers"], ["navy", "grey"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede"], SMART_SHOES_AVOID)]),
    R("L29", "White polo, navy trousers, brown shoes",
      "A white knitted polo with navy trousers is crisp summer evening wear. Tuck it in and add suede loafers.",
      ["dinner", "event", "work"], ["smart_casual"], SPRING_SUMMER,
      [P("top", ["polo"], ["white", "cream"], ["knit", "pique"]),
       P("bottom", ["trousers", "chinos"], ["navy"], [], TAILORED_AVOID),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede"], SMART_SHOES_AVOID)]),
    R("L30", "Navy cardigan, white T-shirt, grey trousers",
      "A cardigan is a softer blazer. Over a white T-shirt with grey trousers it works for a creative office or a weekend lunch.",
      ["work", "casual_outing", "weekend"], ["smart_casual", "casual"], NOT_SUMMER,
      [P("top", ["sweater"], ["navy", "brown", "grey"], ["cardigan"], requires=["cardigan"]),
       P("bottom", ["trousers", "chinos"], ["grey", "charcoal", "beige"], [], TAILORED_AVOID),
       P("shoes", ["shoes"], ["brown", "white"], ["loafer", "derby", "leather sneaker"], ["running", "trail"]),
       P("top", ["t-shirt"], ["white"], optional=True)]),

    # ---- Casual ----
    R("L40", "Field jacket, white T-shirt, dark jeans",
      "Military olive, white and indigo is a casual classic. Keep the jeans unripped and the sneakers clean.",
      ["weekend", "casual_outing", "travel"], ["casual"], ["spring", "autumn"],
      [P("outerwear", ["jacket"], ["olive", "khaki"], ["field", "cotton"], ["puffer", "down", "leather", "suede"], requires=["field", "utility", "m65", "m-65", "chore", "overshirt"]),
       P("top", ["t-shirt"], ["white", "grey", "cream"], [], ["graphic"]),
       P("bottom", ["jeans"], ["denim"]),
       P("shoes", ["shoes"], ["white"], ["sneaker"])]),
    R("L41", "Breton stripes, navy bottoms, white sneakers",
      "Navy-and-white stripes need nothing else patterned. Pair with navy or denim and white sneakers for an easy seaside feel.",
      ["weekend", "casual_outing", "travel"], ["casual", "smart_casual"], ["spring", "summer"],
      [P("top", ["t-shirt"], ["white", "cream", "navy"], ["breton"], patterns=["striped"]),
       P("bottom", ["chinos", "jeans"], ["navy", "denim", "beige"]),
       P("shoes", ["shoes"], ["white"], ["sneaker"]),
       P("outerwear", ["jacket", "blazer"], ["navy"], optional=True)]),
    R("L42", "White T-shirt, chino shorts, sneakers",
      "Summer basics done right: a good white T-shirt, chino shorts ending above the knee and clean white sneakers.",
      ["weekend", "casual_outing"], ["casual"], ["summer"],
      [P("top", ["t-shirt"], ["white", "grey", "navy"], [], ["graphic"]),
       P("bottom", ["shorts"], ["beige", "navy", "olive"], ["chino"]),
       P("shoes", ["shoes"], ["white"], ["sneaker", "canvas"])]),
    R("L43", "Flannel shirt over a T-shirt, jeans, boots",
      "Wear a flannel shirt open over a T-shirt as a light layer. Dark jeans and brown boots keep it rugged but neat.",
      ["weekend", "casual_outing"], ["casual"], AUTUMN_WINTER,
      [P("top", ["shirt"], [], ["flannel"], patterns=["checked"], requires=["flannel", "check", "plaid", "tartan"]),
       P("bottom", ["jeans"], ["denim"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["boot", "chukka", "chelsea"]),
       P("top", ["t-shirt"], ["white", "grey"], optional=True)]),
    R("L44", "Denim jacket, grey sweatshirt, black jeans",
      "Avoid double denim in the same wash: a denim jacket over grey with black jeans keeps the blues separate.",
      ["weekend", "casual_outing"], ["casual"], ["spring", "autumn"],
      [P("outerwear", ["jacket"], ["denim"], ["denim", "trucker"], requires=["denim", "trucker", "jean"]),
       P("top", ["hoodie", "sweater", "t-shirt"], ["grey", "white"], ["sweatshirt", "crew"]),
       P("bottom", ["jeans"], ["black", "charcoal"]),
       P("shoes", ["shoes"], ["white"], ["sneaker"])]),
    R("L45", "Down jacket, chunky knit, jeans, boots",
      "On the coldest days a down jacket over a chunky knit keeps you warm; brown boots and dark jeans stop it looking like ski gear.",
      ["weekend", "travel", "casual_outing"], ["casual"], ["winter"],
      [P("outerwear", ["jacket", "coat"], ["navy", "black", "olive"], ["puffer", "down"], requires=["puffer", "down", "quilted", "padded"]),
       P("top", ["sweater"], ["cream", "grey", "navy"], ["cable", "chunky", "wool"]),
       P("bottom", ["jeans"], ["denim"]),
       P("shoes", ["shoes"], ["brown"], ["boot", "chelsea"])]),
    R("L46", "Workwear jacket, grey T-shirt, dark jeans",
      "Workwear jackets look best with simple basics: a grey T-shirt, dark jeans and sturdy brown shoes.",
      ["weekend", "casual_outing", "work"], ["casual", "smart_casual"], ["spring", "autumn"],
      [P("outerwear", ["jacket"], ["olive", "navy", "brown", "khaki"], ["chore", "workwear"], requires=["chore", "workwear", "work jacket", "overshirt", "canvas"]),
       P("top", ["t-shirt"], ["grey", "white"], [], ["graphic"]),
       P("bottom", ["jeans"], ["denim"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["boot", "derby", "chukka"])]),
    R("L47", "Olive chinos, white T-shirt, navy cardigan",
      "Olive, navy and white is relaxed and easy to wear. Leave the cardigan open over the T-shirt.",
      ["weekend", "casual_outing"], ["casual"], ["spring", "autumn"],
      [P("bottom", ["chinos"], ["olive"]),
       P("top", ["sweater"], ["navy"], ["cardigan"], requires=["cardigan"]),
       P("shoes", ["shoes"], ["white", "brown"], ["sneaker", "suede"]),
       P("top", ["t-shirt"], ["white"], optional=True)]),
    R("L48", "Light jeans, knit polo, suede shoes",
      "Lighter denim is perfect for warm days; a navy knitted polo and suede loafers make it smart enough for dinner.",
      ["weekend", "dinner", "casual_outing"], ["casual", "smart_casual"], SPRING_SUMMER,
      [P("bottom", ["jeans"], ["light blue", "denim"], ["light"]),
       P("top", ["polo"], ["navy", "cream", "white"], ["knit"], requires=["knit"]),
       P("shoes", ["shoes"], ["brown", "tan"], ["loafer", "suede"], ["running", "trail"])]),

    # ---- Sporty ----
    R("L60", "Sweatshirt, joggers, sneakers, bomber",
      "Elevated athleisure: a plain grey sweatshirt, tapered joggers without logos and clean sneakers. A bomber makes it city-ready.",
      ["weekend", "travel", "casual_outing"], ["sporty", "casual"], [],
      [P("top", ["hoodie", "sweater"], ["grey", "navy"], ["sweatshirt"], requires=["sweatshirt", "cotton sweat", "hoodie", "fleece"]),
       P("bottom", ["trousers"], ["navy", "black", "grey"], ["jogger"], requires=["jogger", "sweat", "track"]),
       P("shoes", ["shoes"], ["white", "grey"], ["sneaker"], requires=["sneaker", "trainer", "running"]),
       P("outerwear", ["jacket"], ["olive", "navy", "black"], ["bomber"], optional=True)]),
    R("L61", "Hoodie, joggers, down jacket",
      "Comfort for cold days: hoodie and joggers in one or two quiet colours, a down jacket on top.",
      ["weekend", "travel"], ["sporty"], ["winter"],
      [P("top", ["hoodie"], ["grey", "navy", "black"]),
       P("bottom", ["trousers"], ["navy", "black", "grey"], ["jogger"], requires=["jogger", "sweat", "track"]),
       P("shoes", ["shoes"], ["white", "grey", "black"], ["sneaker", "running"], requires=["sneaker", "trainer", "running"]),
       P("outerwear", ["jacket", "coat"], ["navy", "black", "olive"], ["puffer", "down"], requires=["puffer", "down", "quilted", "padded"])]),
    R("L62", "Tech T-shirt, shorts, running shoes",
      "For an active weekend: a technical T-shirt, shorts and proper running shoes. Keep it to two colours.",
      ["weekend"], ["sporty"], ["spring", "summer"],
      [P("top", ["t-shirt"], ["white", "grey", "navy", "black"]),
       P("bottom", ["shorts"], ["navy", "black", "grey"]),
       P("shoes", ["shoes"], ["grey", "white", "black"], ["running"], requires=["running", "trainer", "sport"])]),
    R("L63", "Quarter-zip and joggers for travel",
      "Travel comfort that still looks tidy: a quarter-zip, soft trousers and white sneakers.",
      ["travel", "weekend"], ["sporty", "casual"], NOT_SUMMER,
      [P("top", ["sweater"], ["grey", "navy"], ["quarter-zip"], requires=["zip"]),
       P("bottom", ["trousers", "chinos"], ["navy", "grey", "black"], ["jogger", "chino"], ["wool", "flannel", "suit"]),
       P("shoes", ["shoes"], ["white", "grey"], ["sneaker"], requires=["sneaker", "trainer"])]),
    R("L64", "Windbreaker, T-shirt, cargo trousers, trail shoes",
      "For city walks or light hikes: a packable windbreaker, cargo trousers and trail shoes in earthy tones.",
      ["travel", "weekend"], ["sporty", "casual"], ["spring", "autumn"],
      [P("outerwear", ["jacket"], ["olive", "navy", "black", "khaki"], ["windbreaker", "technical", "nylon"], requires=["windbreaker", "technical", "shell", "anorak", "rain"]),
       P("top", ["t-shirt"], ["white", "grey", "olive"]),
       P("bottom", ["trousers"], ["olive", "khaki", "black"], ["cargo"], requires=["cargo", "utility"]),
       P("shoes", ["shoes"], ["grey", "brown", "black"], ["trail", "hiking"], requires=["trail", "hiking", "running", "sneaker"])]),
    R("L65", "Piqué polo, chino shorts, white sneakers",
      "Sporty summer smart: a piqué polo, tailored chino shorts and white sneakers.",
      ["weekend", "casual_outing"], ["sporty", "casual"], ["summer"],
      [P("top", ["polo"], ["white", "navy"], ["pique"]),
       P("bottom", ["shorts"], ["beige", "navy"]),
       P("shoes", ["shoes"], ["white"], ["sneaker"])]),
]


# --------------------------------------------------------------------------------------------------
# 3. Generic capsule closet (sample closet), brand-free
# --------------------------------------------------------------------------------------------------

def C(id, name, category, subcategory, color, material, formality, seasons=(), pattern="solid", secondary=None, description=""):
    return {"id": id, "name": name, "category": category, "subcategory": subcategory, "color": color,
            "secondaryColor": secondary, "pattern": pattern, "material": material, "formality": formality,
            "seasons": list(seasons), "description": description or name.lower()}


CAPSULE = [
    # Tops
    C("C01", "White oxford shirt", "shirt", "oxford shirt", "white", "cotton oxford", 3, description="white cotton oxford cloth button-down shirt, long sleeves"),
    C("C02", "Light blue oxford shirt", "shirt", "oxford shirt", "light blue", "cotton oxford", 3, description="light blue cotton oxford cloth button-down shirt, long sleeves"),
    C("C03", "White dress shirt", "shirt", "dress shirt", "white", "cotton poplin", 5, description="crisp white cotton poplin dress shirt with a semi-spread collar and buttoned cuffs"),
    C("C04", "Light blue dress shirt", "shirt", "dress shirt", "light blue", "cotton poplin", 4, description="light blue cotton poplin dress shirt with a semi-spread collar"),
    C("C05", "Chambray shirt", "shirt", "chambray shirt", "denim", "cotton chambray", 2, description="mid-blue cotton chambray shirt with two chest pockets"),
    C("C06", "Check flannel shirt", "shirt", "flannel shirt", "navy", "cotton flannel", 2, AUTUMN_WINTER, "checked", "green", "navy and green checked brushed cotton flannel shirt"),
    C("C07", "White linen shirt", "shirt", "linen shirt", "white", "linen", 3, SPRING_SUMMER, description="white linen shirt, relaxed fit, long sleeves"),
    C("C08", "Pink oxford shirt", "shirt", "oxford shirt", "pink", "cotton oxford", 3, NOT_WINTER, description="pale pink cotton oxford cloth button-down shirt"),
    C("C09", "White T-shirt", "t-shirt", "crew neck t-shirt", "white", "cotton jersey", 2, description="plain white heavyweight cotton crew-neck T-shirt"),
    C("C10", "Grey T-shirt", "t-shirt", "crew neck t-shirt", "grey", "cotton jersey", 2, description="plain heather grey cotton crew-neck T-shirt"),
    C("C11", "Breton striped top", "t-shirt", "breton long-sleeve top", "white", "cotton", 2, NOT_WINTER, "striped", "navy", "white and navy Breton striped long-sleeve cotton top"),
    C("C12", "Navy knit polo", "polo", "knit polo", "navy", "knitted cotton", 3, NOT_WINTER, description="navy short-sleeve knitted cotton polo shirt"),
    C("C13", "White piqué polo", "polo", "pique polo", "white", "cotton pique", 2, SPRING_SUMMER, description="white short-sleeve cotton piqué polo shirt"),
    C("C14", "Navy merino crewneck", "sweater", "merino crewneck", "navy", "merino wool", 3, NOT_SUMMER, description="navy fine-gauge merino wool crew-neck sweater"),
    C("C15", "Grey merino crewneck", "sweater", "merino crewneck", "grey", "merino wool", 3, NOT_SUMMER, description="mid-grey fine-gauge merino wool crew-neck sweater"),
    C("C16", "Cream cable-knit sweater", "sweater", "cable knit sweater", "cream", "wool cable knit", 3, AUTUMN_WINTER, description="cream chunky wool cable-knit crew-neck sweater"),
    C("C17", "Burgundy lambswool crewneck", "sweater", "lambswool crewneck", "burgundy", "lambswool", 3, AUTUMN_WINTER, description="burgundy lambswool crew-neck sweater"),
    C("C18", "Black merino turtleneck", "sweater", "merino turtleneck", "black", "merino wool", 4, NOT_SUMMER, description="black fine merino wool turtleneck sweater"),
    C("C19", "Navy cardigan", "sweater", "cardigan", "navy", "wool cardigan", 3, NOT_SUMMER, description="navy wool V-neck button cardigan"),
    C("C20", "Grey quarter-zip", "sweater", "quarter-zip sweater", "grey", "cotton knit", 3, NOT_SUMMER, description="grey cotton knit quarter-zip sweater"),
    C("C21", "Grey sweatshirt", "hoodie", "crew sweatshirt", "grey", "cotton sweat", 1, description="plain heather grey cotton crew-neck sweatshirt"),
    C("C22", "Navy hoodie", "hoodie", "hoodie", "navy", "cotton fleece", 1, description="plain navy cotton pullover hoodie"),
    # Bottoms
    C("C23", "Dark jeans", "jeans", "dark straight jeans", "denim", "dark denim", 3, description="dark indigo straight-leg jeans without distressing"),
    C("C24", "Black jeans", "jeans", "black slim jeans", "black", "denim", 2, description="black slim straight jeans"),
    C("C25", "Light wash jeans", "jeans", "light wash jeans", "light blue", "light denim", 2, SPRING_SUMMER, description="light wash straight-leg jeans"),
    C("C26", "Beige chinos", "chinos", "slim chinos", "beige", "cotton twill", 3, description="beige cotton twill slim chinos"),
    C("C27", "Navy chinos", "chinos", "slim chinos", "navy", "cotton twill", 3, description="navy cotton twill slim chinos"),
    C("C28", "Olive chinos", "chinos", "slim chinos", "olive", "cotton twill", 3, description="olive cotton twill slim chinos"),
    C("C29", "Grey wool trousers", "trousers", "wool trousers", "grey", "wool", 4, description="mid-grey wool trousers with a front crease"),
    C("C30", "Charcoal flannel trousers", "trousers", "flannel trousers", "charcoal", "wool flannel", 4, AUTUMN_WINTER, description="charcoal wool flannel trousers with a front crease"),
    C("C31", "Brown corduroy trousers", "trousers", "corduroy trousers", "brown", "corduroy", 3, AUTUMN_WINTER, description="brown medium-wale corduroy trousers"),
    C("C32", "Navy suit trousers", "trousers", "suit trousers", "navy", "wool suit", 5, description="navy wool suit trousers with a sharp crease"),
    C("C33", "Charcoal suit trousers", "trousers", "suit trousers", "charcoal", "wool suit", 5, description="charcoal wool suit trousers with a sharp crease"),
    C("C34", "Beige linen trousers", "trousers", "linen trousers", "beige", "linen", 3, ["summer"], description="beige linen drawstring-free trousers, relaxed straight leg"),
    C("C35", "Beige chino shorts", "shorts", "chino shorts", "beige", "cotton", 2, ["summer"], description="beige cotton chino shorts ending above the knee"),
    C("C36", "Navy joggers", "trousers", "joggers", "navy", "cotton jersey jogger", 1, description="navy cotton jersey tapered joggers"),
    # Shoes
    C("C37", "White leather sneakers", "shoes", "leather sneakers", "white", "leather sneaker", 3, description="minimal white leather low-top sneakers, a pair"),
    C("C38", "Brown suede loafers", "shoes", "suede loafers", "brown", "suede loafer", 3, NOT_WINTER, description="brown suede penny loafers, a pair"),
    C("C39", "Brown leather derbies", "shoes", "derby shoes", "brown", "leather derby", 4, description="brown polished leather derby shoes, a pair"),
    C("C40", "Black oxford shoes", "shoes", "oxford shoes", "black", "leather oxford", 5, description="black polished leather cap-toe oxford shoes, a pair"),
    C("C41", "Brown Chelsea boots", "shoes", "chelsea boots", "brown", "leather chelsea boot", 4, NOT_SUMMER, description="dark brown leather Chelsea boots, a pair"),
    C("C42", "Black Chelsea boots", "shoes", "chelsea boots", "black", "leather chelsea boot", 4, NOT_SUMMER, description="black leather Chelsea boots, a pair"),
    C("C43", "Tan suede chukka boots", "shoes", "chukka boots", "tan", "suede chukka", 3, ["spring", "autumn"], description="tan suede chukka boots, a pair"),
    C("C44", "Grey running sneakers", "shoes", "running sneakers", "grey", "mesh running", 1, description="grey mesh running sneakers, a pair"),
    # Outerwear
    C("C45", "Navy unstructured blazer", "blazer", "unstructured blazer", "navy", "wool blazer", 4, description="navy unstructured soft-shouldered wool blazer"),
    C("C46", "Navy suit jacket", "blazer", "suit jacket", "navy", "wool suit", 5, description="navy wool single-breasted suit jacket"),
    C("C47", "Charcoal suit jacket", "blazer", "suit jacket", "charcoal", "wool suit", 5, description="charcoal wool single-breasted suit jacket"),
    C("C48", "Brown tweed jacket", "blazer", "tweed jacket", "brown", "wool tweed", 4, AUTUMN_WINTER, description="brown wool tweed sport jacket"),
    C("C49", "Charcoal overcoat", "coat", "wool overcoat", "charcoal", "wool overcoat", 5, AUTUMN_WINTER, description="charcoal wool single-breasted overcoat, knee length"),
    C("C50", "Camel overcoat", "coat", "wool overcoat", "tan", "wool overcoat", 4, AUTUMN_WINTER, description="camel wool single-breasted overcoat, knee length"),
    C("C51", "Beige trench coat", "coat", "trench coat", "beige", "cotton gabardine trench", 4, ["spring", "autumn"], description="beige cotton gabardine trench coat"),
    C("C52", "Navy peacoat", "coat", "peacoat", "navy", "wool peacoat", 4, AUTUMN_WINTER, description="navy wool double-breasted peacoat"),
    C("C53", "Olive field jacket", "jacket", "field jacket", "olive", "cotton field jacket", 2, ["spring", "autumn"], description="olive cotton field jacket with four pockets"),
    C("C54", "Brown suede jacket", "jacket", "suede jacket", "brown", "suede", 3, ["spring", "autumn"], description="brown suede short zip jacket"),
    C("C55", "Denim jacket", "jacket", "denim jacket", "denim", "denim", 2, NOT_WINTER, description="mid-blue denim trucker jacket"),
    C("C56", "Black leather jacket", "jacket", "leather jacket", "black", "leather", 3, ["spring", "autumn"], description="black leather jacket with a simple collar and zip"),
    C("C57", "Navy down jacket", "jacket", "down puffer jacket", "navy", "down puffer", 2, ["winter"], description="navy quilted down puffer jacket"),
    C("C58", "Olive bomber jacket", "jacket", "bomber jacket", "olive", "nylon bomber", 2, ["spring", "autumn"], description="olive nylon bomber jacket"),
    C("C59", "Olive chore jacket", "jacket", "chore jacket", "olive", "cotton workwear chore", 2, ["spring", "autumn"], description="olive cotton canvas chore jacket with patch pockets"),
    C("C60", "Navy windbreaker", "jacket", "windbreaker", "navy", "nylon windbreaker technical", 1, ["spring", "autumn"], description="navy lightweight hooded nylon windbreaker"),
    C("C61", "Olive cargo trousers", "trousers", "cargo trousers", "olive", "cotton cargo", 2, description="olive cotton cargo trousers, straight leg"),
    # Accessories
    C("C62", "Brown leather belt", "accessory", "belt", "brown", "leather belt", 3, description="brown leather belt with a simple silver buckle"),
    C("C63", "Black leather belt", "accessory", "belt", "black", "leather belt", 4, description="black leather belt with a simple silver buckle"),
    C("C64", "Navy silk tie", "accessory", "tie", "navy", "silk tie", 5, description="navy silk tie"),
    C("C65", "Burgundy knit tie", "accessory", "tie", "burgundy", "knit silk tie", 4, description="burgundy knitted silk tie"),
    # Added so every library recipe can be worn from the capsule
    C("C66", "Beige linen blazer", "blazer", "unstructured linen blazer", "beige", "linen", 4, SPRING_SUMMER, description="beige unstructured linen blazer, soft shoulders"),
    C("C67", "Navy sport shorts", "shorts", "sport shorts", "navy", "technical jersey", 1, SPRING_SUMMER, description="navy lightweight technical running shorts"),
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pairs = [{"a": a, "b": b, "score": s} for (a, b), s in COLOR_PAIRS.items()]
    knowledge = {
        "colorPairs": pairs,
        "textures": TEXTURES,
        "heavyTextures": HEAVY_TEXTURES,
        "seasonalMaterials": [{"seasons": k.split(","), "keywords": v} for k, v in SEASONAL_MATERIALS.items()],
        "formalityKeywords": [{"keyword": k, "formality": f} for k, f in FORMALITY_KEYWORDS],
        "styleExclusions": [{"style": s, **v} for s, v in STYLE_EXCLUSIONS.items()],
        "principles": PRINCIPLES,
    }
    (OUT / "knowledge.json").write_text(json.dumps(knowledge, indent=1, ensure_ascii=False), encoding="utf-8")
    (OUT / "recipes.json").write_text(json.dumps(RECIPES, indent=1, ensure_ascii=False), encoding="utf-8")
    (OUT / "capsule.json").write_text(json.dumps(CAPSULE, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{len(RECIPES)} recipes, {len(CAPSULE)} capsule items, {len(pairs)} color pairs -> {OUT}")


if __name__ == "__main__":
    main()
