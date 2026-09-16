import Foundation

struct RecipeAssistantReply: Sendable {
    let message: String
    let assumptions: [String]
    let draft: RecipeDraft?
    let source: RecipeAssistantSource?
    var adaptations: [String] = []
}

enum RecipeChatReply: Sendable {
    case action(RecipeChatAction)
    case recipe(RecipeAssistantReply)
}

/// Editor-owned research, retained across questions and failures, never persisted.
/// Keeping this orchestration in the domain lets tests replay the real multi-turn flow.
@MainActor final class RecipeEditSession {
    private struct Research {
        var draft: RecipeDraft
        var sources: [RecipeDraft]
    }
    private var research: Research?

    func reset() { research = nil }

    func respond(to request: String, draft: RecipeDraft, conversation: String, userInput: String,
                 client: OpenAIClient,
                 findSources: (String, String) async throws -> [RecipeDraft],
                 progress: @MainActor @Sendable (String) -> Void) async throws -> RecipeChatReply {
        var stage = "understanding your request"
        do {
            guard !request.isEmpty, request.count <= 1200, userInput.count <= 6000, conversation.count <= 8000 else {
                throw SupperError.invalid("This conversation is too long for one edit. Start a new chat by closing and reopening the recipe editor.")
            }
            let context = RecipeAIContext.text(draft)
            guard context.count <= 40_000 else { throw SupperError.invalid("This recipe is too long for AI editing. You can still edit it manually.") }
            if research?.draft != draft { reset() }
            progress("Understanding your request…")
            let plan = try await client.planRecipeChat(request: request,
                context: "USER INPUT:\n\(userInput)\nCONVERSATION:\n\(conversation)\nCURRENT DRAFT:\n\(context)",
                retainedSources: research?.sources ?? [])
            try Task.checkCancellation()
            guard plan.action == .recipe else {
                reset()
                return .action(plan.action)
            }
            if !plan.question.isEmpty {
                // Questions about retained sources go through reuseSources and the
                // grounded editor. A new planning question starts fresh research.
                reset()
                return .recipe(RecipeAssistantReply(message: plan.question, assumptions: [], draft: nil, source: nil))
            }

            let pages: [RecipeDraft]
            if plan.reuseSources, let research {
                pages = research.sources
            } else {
                reset()
                stage = "finding and reading published recipes"
                pages = try await findSources(plan.searchRequest, request)
                try Task.checkCancellation()
            }
            // Save before generation so a failed edit can retry without another search.
            research = Research(draft: draft, sources: pages)
            stage = "preparing recipe changes"
            progress("Preparing changes from a published base recipe…")
            let result = try await client.groundedRecipeEdit(request: request, draft: draft, sources: pages,
                                                            userInput: userInput, conversation: conversation)
            try Task.checkCancellation()
            let changed = try result.validatedDraft(draft, sources: pages, userInput: userInput)
            let page = pages.indices.contains(result.sourceIndex) ? pages[result.sourceIndex] : nil
            let source = page.flatMap { page in page.sourceURL.map { RecipeAssistantSource(title: page.title, url: $0) } }
            // A question about a selected recipe must continue with that exact recipe.
            if let page { research = Research(draft: draft, sources: [page]) }
            if result.outcome == .adapted, let page {
                stage = "checking the recipe adaptation"
                progress("Checking proportions and cooking method against the source…")
                let review = try await client.reviewRecipeAdaptation(result, draft: draft, source: page, userInput: userInput)
                try Task.checkCancellation()
                guard review.approved else {
                    let message = review.question.isEmpty
                        ? "I couldn’t support this adaptation with the base recipe. " + review.concern + " Nothing has changed."
                        : review.question
                    return .recipe(RecipeAssistantReply(message: message, assumptions: [], draft: nil, source: source))
                }
            }
            if let changed { research?.draft = changed }
            if result.outcome == .unavailable { reset() }
            return .recipe(RecipeAssistantReply(message: result.message, assumptions: result.assumptions, draft: changed,
                source: source, adaptations: page.map { result.adaptationNotes(source: $0) } ?? []))
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            // Only app-authored/allowlisted errors reach the UI; no provider JSON or prompts.
            let reason = (error as? SupperError)?.localizedDescription ?? "The request could not be completed. Nothing has changed."
            throw SupperError.invalid("Failed while \(stage).\n\n\(reason)")
        }
    }
}
