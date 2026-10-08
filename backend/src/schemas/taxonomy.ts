// Closed vocabularies shared with the iOS app.
// Keep in sync with Packages/OutfitEngine/Sources/OutfitEngine/{Taxonomy,ColorPalette}.swift.

export const CATEGORIES = [
  "shirt",
  "t-shirt",
  "polo",
  "sweater",
  "hoodie",
  "blazer",
  "jacket",
  "coat",
  "trousers",
  "jeans",
  "chinos",
  "shorts",
  "shoes",
  "accessory",
  "other",
] as const;

export const COLORS = [
  "black",
  "white",
  "grey",
  "charcoal",
  "navy",
  "light blue",
  "denim",
  "beige",
  "cream",
  "tan",
  "brown",
  "khaki",
  "olive",
  "green",
  "blue",
  "burgundy",
  "red",
  "pink",
  "yellow",
  "orange",
  "purple",
  "multicolor",
] as const;

export const PATTERNS = ["solid", "striped", "checked", "patterned"] as const;
export const SEASONS = ["spring", "summer", "autumn", "winter"] as const;
export const OCCASIONS = ["work", "business_meeting", "dinner", "casual_outing", "weekend", "event", "travel"] as const;
export const STYLES = ["formal", "smart_casual", "casual", "sporty"] as const;

export type Category = (typeof CATEGORIES)[number];
export type ColorName = (typeof COLORS)[number];
