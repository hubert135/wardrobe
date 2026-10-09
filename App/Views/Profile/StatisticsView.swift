import Charts
import OutfitEngine
import SwiftData
import SwiftUI

struct CategoryCount: Identifiable {
    var category: GarmentCategory
    var count: Int
    var id: GarmentCategory { category }
}

struct ClosetStatistics {
    var byCategory: [CategoryCount]
    var mostWorn: [Garment]
    var neverWorn: [Garment]
    var averageCostPerWear: Double?
    var totalValue: Double

    init(garments: [Garment]) {
        let active = garments.filter { $0.status != .archived }
        let grouped = Dictionary(grouping: active, by: \.category)
        byCategory = grouped.map { CategoryCount(category: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
        mostWorn = Array(active.filter { $0.wearCount > 0 }.sorted { $0.wearCount > $1.wearCount }.prefix(5))
        neverWorn = active.filter { $0.wearCount == 0 }
        let costs = active.compactMap { $0.wearCount > 0 ? $0.costPerWear : nil }
        averageCostPerWear = costs.isEmpty ? nil : costs.reduce(0, +) / Double(costs.count)
        totalValue = active.compactMap(\.price).reduce(0, +)
    }
}

struct StatisticsView: View {
    @Environment(AppServices.self) private var services
    @Query private var garments: [Garment]

    var body: some View {
        let stats = ClosetStatistics(garments: garments)
        let currency = services.repository.profile().currencyCode
        List {
            Section {
                LabeledContent("Garments", value: "\(garments.filter { $0.status != .archived }.count)")
                LabeledContent("Total closet value", value: stats.totalValue.currency(currency))
                if let average = stats.averageCostPerWear {
                    LabeledContent("Average cost per wear", value: average.currency(currency))
                }
            }

            if !stats.byCategory.isEmpty {
                Section("By category") {
                    Chart(stats.byCategory) { entry in
                        BarMark(x: .value("Count", entry.count), y: .value("Category", entry.category.displayName))
                            .foregroundStyle(Theme.accent)
                            .annotation(position: .trailing) { Text("\(entry.count)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(stats.byCategory.count) * 28 + 20)
                    .accessibilityLabel(stats.byCategory.map { "\($0.category.displayName): \($0.count)" }.joined(separator: ", "))
                }
            }

            if !stats.mostWorn.isEmpty {
                Section("Most worn") {
                    ForEach(stats.mostWorn) { garment in
                        row(garment, detail: "\(garment.wearCount)×", currency: currency)
                    }
                }
            }

            if !stats.neverWorn.isEmpty {
                Section("Never worn (\(stats.neverWorn.count))") {
                    ForEach(stats.neverWorn) { garment in
                        row(garment, detail: garment.price.map { $0.currency(currency) } ?? "", currency: currency)
                    }
                }
            }
        }
        .paperBackground()
        .navigationTitle("Statistics")
    }

    private func row(_ garment: Garment, detail: String, currency: String) -> some View {
        HStack(spacing: 12) {
            GarmentImageView(garment: garment, maxPixels: 120)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading) {
                Text(garment.displayName)
                if let costPerWear = garment.costPerWear, garment.wearCount > 0 {
                    Text("\(costPerWear.currency(currency)) per wear").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }
}
