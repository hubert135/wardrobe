import OutfitEngine
import SwiftUI

/// Form sections for editing every garment field. Embed inside a `Form`.
struct GarmentFormSections: View {
    @Binding var draft: GarmentDraft
    var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"
    var showsPurchaseFields = true

    var body: some View {
        Section("Basics") {
            TextField("Name", text: $draft.name)
                .accessibilityIdentifier("garment.name")
            Picker("Category", selection: $draft.category) {
                ForEach(GarmentCategory.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("garment.category")
            TextField("Type (e.g. oxford shirt)", text: $draft.subcategory)
        }

        Section("Look") {
            ColorPickerRow(title: "Main color", color: $draft.primaryColor)
            ColorPickerRow(title: "Second color", optionalColor: $draft.secondaryColor)
            Picker("Pattern", selection: $draft.pattern) {
                ForEach(Pattern.allCases) { Text($0.displayName).tag($0) }
            }
            TextField("Material", text: $draft.material)
            Stepper(value: $draft.formality, in: Formality.range) {
                HStack {
                    Text("Formality")
                    Spacer()
                    Text("\(draft.formality) · \(Formality.label(draft.formality))").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Seasons").font(.subheadline)
                ChipSelector(options: Season.allCases, selection: $draft.seasons, title: \.displayName)
                Text(draft.seasons.isEmpty ? "No season selected means all year." : " ")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }

        if showsPurchaseFields {
            Section("Purchase") {
                TextField("Brand", text: $draft.brand)
                TextField("Size", text: $draft.size)
                TextField("Price", value: $draft.price, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .overlay(alignment: .trailing) { Text(currencyCode).foregroundStyle(.secondary) }
                DatePicker(
                    "Purchase date",
                    selection: Binding(get: { draft.purchaseDate ?? Date() }, set: { draft.purchaseDate = $0 }),
                    in: ...Date(),
                    displayedComponents: .date
                )
            }
        }
    }
}
