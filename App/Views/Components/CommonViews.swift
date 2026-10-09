import OutfitEngine
import SwiftUI

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).font(Theme.serif(.title2))
            } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.accent)
            }
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .frame(maxWidth: 260)
            }
        }
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .font(.subheadline.bold())
            }
        }
        .padding()
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Pulsing placeholder used while content loads.
struct SkeletonBlock: View {
    var height: CGFloat
    @State private var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(dimmed ? 0.08 : 0.18))
            .frame(height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
            }
            .accessibilityHidden(true)
    }
}

struct OutfitCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonBlock(height: 320)
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(height: 12).frame(width: 70)
                SkeletonBlock(height: 24).frame(width: 220)
                SkeletonBlock(height: 14)
                SkeletonBlock(height: 50)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .card()
        .accessibilityLabel("Loading outfits")
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

struct Chip: View {
    var title: String
    var isSelected: Bool
    var swatch: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle().fill(swatch).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                }
                Text(title).font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? Theme.ink : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.ink.opacity(0.12), lineWidth: 1))
            .foregroundStyle(isSelected ? Theme.paper : Theme.ink)
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Horizontally scrolling single-select chips (occasion, style, category).
struct ChipRow<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var title: (Value) -> String
    /// How far the row extends past its container's horizontal padding (edge-to-edge scrolling).
    var bleed: CGFloat = Theme.pagePadding

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Chip(title: title(option), isSelected: selection == option, swatch: nil) {
                        selection = option
                    }
                }
            }
            .padding(.horizontal, bleed)
        }
        .padding(.horizontal, -bleed)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Multi-select chips for a list of values.
struct ChipSelector<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Set<Value>
    var title: (Value) -> String
    var swatch: ((Value) -> Color)?

    var body: some View {
        FlowLayout {
            ForEach(options, id: \.self) { option in
                Chip(title: title(option), isSelected: selection.contains(option), swatch: swatch?(option)) {
                    if selection.contains(option) { selection.remove(option) } else { selection.insert(option) }
                }
            }
        }
    }
}

/// Single-select palette color picker.
struct ColorPickerRow: View {
    var title: String
    @Binding var color: String
    var allowsNone = false
    @Binding var optionalColor: String?

    init(title: String, color: Binding<String>) {
        self.title = title
        self._color = color
        self._optionalColor = .constant(nil)
    }

    init(title: String, optionalColor: Binding<String?>) {
        self.title = title
        self.allowsNone = true
        self._optionalColor = optionalColor
        self._color = .constant("")
    }

    private var current: String? { allowsNone ? optionalColor : color }

    var body: some View {
        Picker(title, selection: Binding<String>(
            get: { current ?? "" },
            set: { newValue in
                if allowsNone { optionalColor = newValue.isEmpty ? nil : newValue } else { color = newValue }
            }
        )) {
            if allowsNone { Text("None").tag("") }
            ForEach(ColorPalette.all) { named in
                Label {
                    Text(named.displayName)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(Color.garment(named.name))
                }
                .tag(named.name)
            }
            if let current, !current.isEmpty, ColorPalette.color(named: current) == nil {
                Text(current.capitalized).tag(current)
            }
        }
    }
}
