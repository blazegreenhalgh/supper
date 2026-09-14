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
        HStack(alignment: .center, spacing: 20) {
            IngredientIcon(name: ingredient.name)
            ingredientText
                .font(.callout)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
    private var ingredientText: Text {
        if ingredient.amount.isEmpty { return Text(ingredient.name) }
        // One text flow keeps amounts attached to names at every Dynamic Type size.
        return Text("\(Text(ingredient.amount).bold()) \(ingredient.name)")
    }
}
