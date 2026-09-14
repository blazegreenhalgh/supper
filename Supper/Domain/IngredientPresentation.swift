import Foundation

public enum GroceryAisle: String, CaseIterable, Sendable {
    case produce = "Fresh produce"
    case meatAndSeafood = "Meat & seafood"
    case dairyAndEggs = "Dairy & eggs"
    case pantry = "Pantry"
    case other = "Other items"
}

/// Uses Apple's dimensional food emoji, available offline at every text size.
/// Match whole words/phrases so e.g. eggplant isn't classified as an egg.
public struct IngredientPresentation: Equatable, Sendable {
    public let icon: String
    public let aisle: GroceryAisle

    public static func matching(_ name: String) -> Self {
        let words = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let normalized = " " + words.joined(separator: " ") + " "
        return rules.first { rule in
            rule.names.contains { normalized.contains(" " + $0 + " ") }
        }?.presentation ?? Self(icon: "🛒", aisle: .other)
    }

    private struct Rule {
        let names: [String]
        let presentation: IngredientPresentation

        init(_ names: [String], _ icon: String, _ aisle: GroceryAisle) {
            self.names = names
            self.presentation = IngredientPresentation(icon: icon, aisle: aisle)
        }
    }

    // Prepared ingredients precede the fresh ingredients in their names.
    private static let rules: [Rule] = [
        Rule(["coconut milk", "coconut cream", "almond milk", "oat milk"], "🥥", .pantry),
        Rule(["tomato paste", "tomato puree", "tomato sauce", "crushed tomatoes", "crushed tomato", "canned tomatoes", "tinned tomatoes", "passata"], "🥫", .pantry),
        Rule(["chilli powder", "chili powder", "cayenne", "paprika", "cumin", "curry powder", "turmeric", "cinnamon", "nutmeg", "garlic powder", "onion powder", "peppercorns", "black pepper", "white pepper"], "🌶️", .pantry),
        Rule(["stock", "bouillon", "broth"], "🥣", .pantry),
        Rule(["oil", "olives", "olive"], "🫒", .pantry),
        Rule(["vinegar", "soy sauce", "fish sauce", "oyster sauce", "worcestershire", "ketchup"], "🍶", .pantry),
        Rule(["salt"], "🧂", .pantry),
        Rule(["sugar", "icing sugar"], "🥄", .pantry),
        Rule(["honey", "syrup"], "🍯", .pantry),
        Rule(["flour", "cornflour", "cornstarch", "oats", "breadcrumbs", "baking powder", "baking soda", "yeast"], "🌾", .pantry),
        Rule(["green beans", "snow peas", "snap peas", "peas"], "🫛", .produce),
        Rule(["beans", "lentils", "chickpeas"], "🫘", .pantry),
        Rule(["rice", "quinoa", "couscous"], "🍚", .pantry),
        Rule(["pasta", "spaghetti", "fettuccine", "penne", "macaroni", "lasagne", "lasagna"], "🍝", .pantry),
        Rule(["noodles"], "🍜", .pantry),
        Rule(["bread", "sourdough", "baguette", "toast"], "🍞", .pantry),
        Rule(["tortilla", "tortillas", "wraps", "flatbread"], "🫓", .pantry),
        Rule(["peanut", "peanuts", "peanut butter", "almonds", "cashews", "nuts"], "🥜", .pantry),
        Rule(["chocolate", "cocoa"], "🍫", .pantry),
        Rule(["water"], "💧", .pantry),
        Rule(["garlic"], "🧄", .produce),
        Rule(["onion", "onions", "shallot", "shallots", "spring onions", "scallions", "leek", "leeks"], "🧅", .produce),
        Rule(["capsicum", "capsicums", "bell pepper", "bell peppers"], "🫑", .produce),
        Rule(["chilli", "chili", "chillies", "chilies", "jalapeno"], "🌶️", .produce),
        Rule(["tomato", "tomatoes"], "🍅", .produce),
        Rule(["aubergine", "eggplant"], "🍆", .produce),
        Rule(["sweet potato", "sweet potatoes"], "🍠", .produce),
        Rule(["potato", "potatoes"], "🥔", .produce),
        Rule(["carrot", "carrots"], "🥕", .produce),
        Rule(["broccoli", "cauliflower"], "🥦", .produce),
        Rule(["mushroom", "mushrooms"], "🍄‍🟫", .produce),
        Rule(["corn", "sweetcorn"], "🌽", .produce),
        Rule(["cucumber", "zucchini", "courgette"], "🥒", .produce),
        Rule(["lettuce", "spinach", "cabbage", "kale", "celery", "bok choy"], "🥬", .produce),
        Rule(["basil", "parsley", "coriander", "cilantro", "oregano", "thyme", "rosemary", "mint", "dill", "herbs", "bay leaf", "bay leaves"], "🌿", .produce),
        Rule(["avocado", "avocados"], "🥑", .produce),
        Rule(["lemon", "lemons"], "🍋", .produce),
        Rule(["lime", "limes"], "🍋‍🟩", .produce),
        Rule(["orange", "oranges", "mandarin"], "🍊", .produce),
        Rule(["apple", "apples"], "🍎", .produce),
        Rule(["banana", "bananas"], "🍌", .produce),
        Rule(["strawberry", "strawberries"], "🍓", .produce),
        Rule(["blueberries", "blueberry", "berries"], "🫐", .produce),
        Rule(["ginger"], "🫚", .produce),
        Rule(["chicken", "turkey", "duck"], "🍗", .meatAndSeafood),
        Rule(["beef", "steak", "lamb", "pork", "mince", "veal"], "🥩", .meatAndSeafood),
        Rule(["bacon", "ham", "pancetta"], "🥓", .meatAndSeafood),
        Rule(["prawns", "prawn", "shrimp"], "🦐", .meatAndSeafood),
        Rule(["fish", "salmon", "tuna", "cod", "barramundi"], "🐟", .meatAndSeafood),
        Rule(["egg", "eggs"], "🥚", .dairyAndEggs),
        Rule(["butter"], "🧈", .dairyAndEggs),
        Rule(["cheese", "parmesan", "cheddar", "mozzarella", "feta", "ricotta"], "🧀", .dairyAndEggs),
        Rule(["milk", "cream", "yogurt", "yoghurt", "buttermilk"], "🥛", .dairyAndEggs)
    ]
}
