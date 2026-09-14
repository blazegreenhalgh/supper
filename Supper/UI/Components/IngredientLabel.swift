import SwiftUI

struct IngredientIcon: View {
    let name: String
    @ScaledMetric(relativeTo: .callout) private var size = 19
    var body: some View {
        Text(IngredientPresentation.matching(name).icon)
            .font(.system(size: min(size, 28)))
            .frame(width: min(size, 28) + 6, height: min(size, 28) + 6)
            .accessibilityHidden(true)
    }
}
struct IngredientLabel: View {
    let ingredient: Ingredient

    var body: some View {
        IngredientLineItem(name: ingredient.name, amount: ingredient.amount)
    }
}

/// Shared typography and spacing for recipe ingredients and the grocery list.
struct IngredientLineItem: View {
    let name: String
    let amount: String
    var detail: String = ""
    var isChecked = false

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            IngredientIcon(name: name)
                .opacity(isChecked ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 4) {
                ingredientText
                    .font(.callout)
                    .foregroundStyle(isChecked ? .secondary : .primary)
                    .strikethrough(isChecked)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
    private var ingredientText: Text {
        if amount.isEmpty { return Text(name) }
        // One text flow keeps amounts attached to names at every Dynamic Type size.
        return Text("\(Text(amount).bold()) \(name)")
    }
}
