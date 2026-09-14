import SwiftUI

struct IngredientIcon: View {
    let name: String
    @ScaledMetric(relativeTo: .body) private var size = 21
    var body: some View {
        Text(IngredientPresentation.matching(name).icon)
            .font(.system(size: min(size, 30)))
            .frame(width: min(size, 30) + 6, height: min(size, 30) + 6)
            .accessibilityHidden(true)
    }
}
struct IngredientLabel: View {
    let ingredient: Ingredient
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            IngredientIcon(name: ingredient.name)
            if typeSize.isAccessibilitySize { stacked }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(ingredient.name).foregroundStyle(.primary).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        amount
                    }
                    stacked
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ingredient.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            amount
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var amount: some View {
        if !ingredient.amount.isEmpty {
            Text(ingredient.amount).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(SupperStyle.subtle, in: .capsule)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
