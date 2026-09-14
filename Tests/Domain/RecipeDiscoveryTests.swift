import XCTest
@testable import SupperCore

final class RecipeDiscoveryTests: XCTestCase {
    func testPublisherSearchValidatesSourceAndDeduplicatesTracking() throws {
        let json = """
        [
          {"url":"https://recipes.example/chicken?utm_source=search&servings=4#recipe","subtype":"post"},
          {"url":"https://recipes.example/chicken?servings=4","subtype":"post"},
          {"url":"https://other.example/untrusted","subtype":"post"},
          {"url":"https://recipes.example/category","subtype":"category"},
          {"url":"https://user:password@recipes.example/private","subtype":"post"},
          {"url":"https://recipes.example/pasta","subtype":"post"}
        ]
        """
        XCTAssertEqual(try RecipeSearchFeed.publisherLinks(in: Data(json.utf8), host: "recipes.example").map(\.absoluteString), ["https://recipes.example/chicken?servings=4", "https://recipes.example/pasta"])
    }
    func testSearchRejectsErrorPagesAndAcceptsEmptyResults() throws {
        XCTAssertThrowsError(try RecipeSearchFeed.publisherLinks(in: Data("<html>Unavailable</html>".utf8), host: "recipes.example"))
        XCTAssertThrowsError(try RecipeSearchFeed.publisherLinks(in: Data("{\"code\":\"rest_forbidden\"}".utf8), host: "recipes.example"))
        XCTAssertTrue(try RecipeSearchFeed.publisherLinks(in: Data("[]".utf8), host: "recipes.example").isEmpty)
        XCTAssertEqual(RecipeSearchFeed.fallbackKeywords("I want chicken with rice under 30 minutes please"), "chicken rice")
    }
    func testDiscoveryNeverAcceptsInventedLocalOrNonHTTPSLinks() {
        for value in ["file:///private/recipe", "http://recipes.example/one", "https://localhost/", "https://kitchen.local/", "https://[::1]/", "https://192.168.0.2/"] {
            XCTAssertNil(RecipeSearchFeed.publicURL(value))
        }
    }
    func testEditingKeepsIdentityAndDoesNotKeepRecipe() {
        let suggestion = RecipeSuggestion(recipe: Recipe(title: "Chicken", ingredients: [Ingredient(name: "rice", quantity: "200", unit: "g")]), mode: .create)
        var review = RecipeDiscoveryReview(suggestions: [suggestion])
        var draft = RecipeDraft(recipe: suggestion.recipe)
        draft.title = "Lemon chicken"; draft.ingredients[0].quantity = "300"
        review.edit(draft.applying(to: suggestion.recipe))
        XCTAssertTrue(review.keptIDs.isEmpty)
        XCTAssertEqual(review.pending.first?.id, suggestion.id)
        XCTAssertEqual(review.pending.first?.recipe.title, "Lemon chicken")
        XCTAssertEqual(review.pending.first?.recipe.ingredients.first?.quantity, "300")
        review.didKeep(suggestion.id)
        review.didKeep(suggestion.id)
        XCTAssertEqual(review.keptIDs.count, 1)
        XCTAssertTrue(review.pending.isEmpty)
    }
    func testDiscardUndoRestoresEditsAndNeverUndoesKeep() {
        let first = RecipeSuggestion(recipe: Recipe(title: "First"), mode: .create)
        let second = RecipeSuggestion(recipe: Recipe(title: "Second"), mode: .create)
        var review = RecipeDiscoveryReview(suggestions: [first, second])
        var edited = first.recipe; edited.title = "Edited first"
        review.edit(edited); review.discard(first.id); review.didKeep(second.id)
        XCTAssertTrue(review.pending.isEmpty)
        review.undoDiscard()
        XCTAssertEqual(review.pending.map(\.recipe.title), ["Edited first"])
        XCTAssertEqual(review.keptIDs, [second.id])
        review.discard(second.id)
        XCTAssertTrue(review.discardedIDs.isEmpty)
    }
    func testDeduplicationPreservesDifferentPublishers() {
        let first = Recipe(title: "Chicken", sourceURL: URL(string: "https://recipes.example/chicken"))
        let duplicate = Recipe(title: "Chicken dinner", sourceURL: URL(string: "https://recipes.example/chicken?utm_source=bing#method"))
        let other = Recipe(title: "Chicken", sourceURL: URL(string: "https://another.example/chicken"))
        let review = RecipeDiscoveryReview(suggestions: [first, duplicate, other].map { RecipeSuggestion(recipe: $0, mode: .online) })
        XCTAssertEqual(review.pending.map(\.id), [first.id, other.id])
    }
}
