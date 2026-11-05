import OutfitEngine
import SwiftUI

/// What the app knows about style: the rules it applies to every outfit and the recipes it builds from.
struct StyleKnowledgeView: View {
    var stylebook: StylebookStore

    var body: some View {
        List {
            Section {
                ForEach(StyleKnowledge.shared.principles, id: \.self) { rule in
                    Text(rule).font(.subheadline)
                }
            } header: {
                Text("Styling rules")
            } footer: {
                Text("Applied to every suggestion, together with color pairings, fabric seasons and what belongs in each style.")
            }

            ForEach(Style.allCases) { style in
                let recipes = stylebook.recipes.filter { $0.styles.first == style }
                if !recipes.isEmpty {
                    Section(style.displayName) {
                        ForEach(recipes) { recipe in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(title(recipe)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if stylebook.isFromStyleGuide(recipe) {
                                        Text("Style guide").font(.caption2.bold()).foregroundStyle(Theme.accent)
                                    }
                                }
                                if !recipe.summary.isEmpty {
                                    Text(recipe.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Style knowledge")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func title(_ recipe: StyleRecipe) -> String {
        guard recipe.title == recipe.title.uppercased() else { return recipe.title }
        let lower = recipe.title.lowercased()
        return lower.prefix(1).uppercased() + String(lower.dropFirst())
    }
}
