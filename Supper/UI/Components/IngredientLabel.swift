import SwiftUI

struct IngredientIcon: View {
    let name: String
    @ScaledMetric(relativeTo: .title2) private var size = 30

    var body: some View {
        Text(IngredientPresentation.matching(name).icon)
            .font(.system(size: size))
            .frame(width: size + 12, height: size + 12)
            .accessibilityHidden(true)
    }
}

struct IngredientLabel: View {
    let ingredient: Ingredient

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IngredientIcon(name: ingredient.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                let amount = [ingredient.quantity, ingredient.unit].filter { !$0.isEmpty }.joined(separator: " ")
                if !amount.isEmpty {
                    Text(amount)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
