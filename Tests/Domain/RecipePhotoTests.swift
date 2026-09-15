import Foundation
import Testing
@testable import SupperCore

struct RecipePhotoTests {
    private let page = URL(string: "https://recipes.example/food/naan")!

    @Test func photoMetadataUsesRealStructuredAndSocialImages() {
        let html = #"""
        <script type="application/ld+json">{"@type":"Recipe","name":"Naan","image":"https://cdn.example/naan.jpg"}</script>
        <meta content='/photos/naan.jpg?w=800&amp;h=800' property='og:image'>
        <meta name="twitter:image" content="https://cdn.example/naan.jpg">
        <meta property="og:image:secure_url" content="//cdn.example/second.jpg">
        """#
        #expect(RecipePhotoMetadata.imageURLs(html: html, pageURL: page).map(\.absoluteString) == [
            "https://cdn.example/naan.jpg", "https://recipes.example/photos/naan.jpg?w=800&h=800", "https://cdn.example/second.jpg"
        ])
    }

    @Test func rejectsPrivateInsecureAndInventedPhotoLinks() {
        let html = #"""
        Text claiming a photo lives at https://invented.example/photo.jpg
        <img src="https://ads.example/banner.jpg">
        <meta property="og:image" content="http://cdn.example/insecure.jpg">
        <meta property="og:image" content="https://127.0.0.1/private.jpg">
        <meta property="og:image" content="https://localhost/private.jpg">
        <meta property="og:image" content="https://cdn.example:8000/other.jpg">
        <meta property="og:image" content="data:image/jpeg;base64,abc">
        <meta property="og:title" content="Naan &amp; pizza">
        """#
        #expect(RecipePhotoMetadata.imageURLs(html: html, pageURL: page).isEmpty)
        #expect(RecipePhotoMetadata.title(html: html, pageURL: page) == "Naan & pizza")
    }

    @Test func applyingOnlinePhotoPreservesNewRecipeEditsAndCreditsSource() throws {
        var draft = RecipeDraft(title: "Naan pizza", ingredients: [Ingredient(name: "Cheese")])
        let photo = RecipePhotoProposal(image: Data([1, 2]), previousImage: nil, kind: .online,
            source: RecipeAssistantSource(title: "Publisher", url: page), imageURL: URL(string: "https://cdn.example/naan.jpg")!)
        draft.ingredients.append(Ingredient(name: "Fresh basil")); draft.notes = "My new note"
        draft.sourceURL = URL(string: "https://recipes.example/pizza")
        let changed = try photo.applying(to: draft)
        #expect(changed.ingredients == draft.ingredients)
        #expect(changed.sourceURL == draft.sourceURL)
        #expect(changed.notes.hasPrefix("My new note\n\n"))
        #expect(changed.notes.contains(page.absoluteString))
        #expect(changed.notes.contains("https://cdn.example/naan.jpg"))
        #expect(changed.imageData == Data([1, 2]))
        #expect(try RecipeAssistantUndo(before: draft, after: changed).restoring(changed) == draft)
    }

    @Test func newerManualPhotoAndMissingProvenanceBlockApply() {
        var draft = RecipeDraft(title: "Naan")
        let generated = RecipePhotoProposal(image: Data([1]), previousImage: nil, kind: .generated)
        draft.imageData = Data([2])
        #expect(throws: (any Error).self) { try generated.applying(to: draft) }
        draft.imageData = nil
        let uncredited = RecipePhotoProposal(image: Data([1]), previousImage: nil, kind: .online)
        let noOriginal = RecipePhotoProposal(image: Data([1]), previousImage: nil, kind: .enhanced)
        #expect(throws: (any Error).self) { try uncredited.applying(to: draft) }
        #expect(throws: (any Error).self) { try noOriginal.applying(to: draft) }
        let edited = RecipePhotoProposal(image: Data([1]), previousImage: nil, originalPhoto: Data([3]), kind: .enhanced)
        #expect((try? edited.applying(to: draft).notes.contains("edited with AI")) == true)
    }
}
