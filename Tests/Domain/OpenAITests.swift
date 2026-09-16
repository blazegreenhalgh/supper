import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SupperCore

@Suite(.serialized) struct OpenAITests {
    private let fakeKey = "sk-test-not-a-real-key-1234567890"

    @Test func validatesKeyWithoutLeakingIt() throws {
        #expect(try OpenAIClient.validatedKey(" \(fakeKey)\n") == fakeKey)
        for value in ["", "sk-short", "sk-this-is-not-valid\nAuthorization: bad", "password"] {
            #expect(throws: (any Error).self) { try OpenAIClient.validatedKey(value) }
        }
    }

    @Test func ignoresInventedCitationsAndUnsafeURLs() throws {
        let response = try OpenAIResponse.decode(Data("""
        {"status":"completed","output":[
          {"type":"web_search_call","status":"completed","action":{"type":"search","sources":[
            {"url":"https://recipes.example/naan?utm_source=search"},{"url":"https://recipes.example/naan"},
            {"url":"http://recipes.example/insecure"},{"url":"https://127.0.0.1/private"}]}},
          {"type":"message","content":[{"type":"output_text","text":"Found recipes","annotations":[
            {"type":"url_citation","url":"https://invented.example/naan"},
            {"type":"url_citation","url":"https://recipes.example/naan"}]}]}
        ]}
        """.utf8))
        #expect(response.didSearch)
        #expect(response.sourceURLs.map(\.absoluteString) == ["https://recipes.example/naan"])
    }

    @Test func rejectsPartialRefusedAndMalformedResponses() {
        for json in ["{}", "not json", "{\"status\":\"incomplete\",\"output\":[]}",
                     "{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"refusal\"}]}]}"] {
            #expect(throws: (any Error).self) { try OpenAIResponse.decode(Data(json.utf8)) }
        }
    }

    @Test func incompleteResponsesExplainTheOutputLimitWithoutEchoingProviderContent() throws {
        let data = Data(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#.utf8)
        do {
            _ = try OpenAIResponse.decode(data)
            Issue.record("An incomplete response must not be accepted")
        } catch {
            #expect(error.localizedDescription.contains("output limit"))
        }
    }

    @Test func classifiesErrorsWithoutEchoingProviderData() {
        let data = Data("{\"error\":{\"code\":\"insufficient_quota\",\"message\":\"\(fakeKey) private recipe\"}}".utf8)
        #expect(OpenAIClient.apiError(status: 429, data: data).localizedDescription.contains("credits"))
        for status in [400, 401, 403, 404, 429, 500] {
            let message = OpenAIClient.apiError(status: status, data: data).localizedDescription
            #expect(!message.contains(fakeKey))
            #expect(!message.contains("private recipe"))
        }
    }

    @Test func rejectedPhotoSettingIncludesSafeDiagnosticDetails() throws {
        let data = try JSONSerialization.data(withJSONObject: ["error": [
            "code": "unsupported_parameter", "type": "invalid_request_error", "param": "input_fidelity",
            "message": "Unsupported setting for \(fakeKey): private recipe and photo bytes"
        ]])
        let message = OpenAIClient.apiError(status: 400, data: data, requestID: "req_photo123").localizedDescription
        #expect(message.contains("HTTP 400"))
        #expect(message.contains("Code: unsupported_parameter"))
        #expect(message.contains("Parameter: input_fidelity"))
        #expect(message.contains("Request: req_photo123"))
        #expect(!message.contains(fakeKey))
        #expect(!message.contains("private recipe"))
        #expect(!message.contains("photo bytes"))
    }

    @Test func untrustedDiagnosticFieldsCannotExposeKeysOrContent() throws {
        let data = try JSONSerialization.data(withJSONObject: ["error": [
            "code": fakeKey, "type": "private recipe", "param": "data:image/jpeg;base64,privatephoto", "message": fakeKey
        ]])
        let message = OpenAIClient.apiError(status: 400, data: data, requestID: fakeKey).localizedDescription
        #expect(message.contains("HTTP 400"))
        for privateValue in [fakeKey, "private recipe", "privatephoto"] { #expect(!message.contains(privateValue)) }
    }

    @Test func verificationAndModerationAreExplainedEvenForHTTP400() throws {
        let verification = try JSONSerialization.data(withJSONObject: ["error": [
            "type": "invalid_request_error", "message": "Your organization must be verified to use this model. \(fakeKey)"
        ]])
        let verificationMessage = OpenAIClient.apiError(status: 400, data: verification).localizedDescription
        #expect(verificationMessage.contains("requires organization verification"))
        #expect(!verificationMessage.contains(fakeKey))
        let moderation = Data(#"{"error":{"code":"moderation_blocked","type":"image_generation_user_error"}}"#.utf8)
        #expect(OpenAIClient.apiError(status: 400, data: moderation).localizedDescription.contains("image safety check"))
        #expect(OpenAIClient.apiError(status: 415, data: Data()).localizedDescription.contains("upload format"))
    }

    @Test func structuredRequestUsesSelectedModelAndNoStorage() async throws {
        let client = try makeClient { request in
            #expect(request.url?.host == "api.openai.com")
            #expect(request.url?.path == "/v1/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(fakeKey)")
            let body = try Self.body(request)
            #expect(body["model"] as? String == "gpt-5.6-terra")
            #expect(body["store"] as? Bool == false)
            #expect(body["tools"] == nil)
            let text = body["text"] as? [String: Any]
            let format = text?["format"] as? [String: Any]
            #expect(format?["type"] as? String == "json_schema")
            #expect(format?["strict"] as? Bool == true)
            return (200, Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"ok\":true}"}]}]}"#.utf8))
        }
        struct Value: Decodable { let ok: Bool }
        let value = try await client.structured(Value.self, instructions: "test", input: "test", schema: AISchema.object(["ok": AISchema.boolean]), name: "test")
        #expect(value.ok)
    }

    @Test func searchMustUseToolEvidenceNotProse() async throws {
        let client = try makeClient { request in
            let body = try Self.body(request)
            #expect((body["tool_choice"] as? [String: String])?["type"] == "web_search")
            #expect((body["include"] as? [String]) == ["web_search_call.action.sources"])
            return (200, Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"https://invented.example/recipe"}]}]}"#.utf8))
        }
        await #expect(throws: (any Error).self) { try await client.searchRecipes("naan") }
    }

    @Test func connectionTestDoesNotGenerateOrChargeForTokens() async throws {
        let client = try makeClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/models/gpt-5.6-terra")
            #expect(request.httpBody == nil)
            return (200, Data(#"{"id":"gpt-5.6-terra"}"#.utf8))
        }
        try await client.testConnection()
    }

    @Test func invalidJSONNeverBecomesARecipe() async throws {
        let client = try makeClient { _ in
            (200, Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Here is a recipe!"}]}]}"#.utf8))
        }
        struct Value: Decodable { let ok: Bool }
        await #expect(throws: (any Error).self) {
            try await client.structured(Value.self, instructions: "test", input: "test", schema: AISchema.object(["ok": AISchema.boolean]), name: "test")
        }
    }

    @Test func coverUsesImageModelAndRejectsEmptyImages() async throws {
        let client = try makeClient { request in
            let body = try Self.body(request)
            #expect(body["model"] as? String == "gpt-image-2.5-flare")
            #expect(body["n"] as? Int == 1)
            #expect(body["output_format"] as? String == "jpeg")
            #expect(body["output_compression"] as? Int == 90)
            #expect(request.url?.path == "/v1/images/generations")
            return (200, Data(#"{"data":[{"b64_json":""}]}"#.utf8))
        }
        await #expect(throws: (any Error).self) { try await client.generateCover(prompt: "naan") }
    }

    @Test func foodPhotoEditUploadsJPEGAsMultipartWithoutFidelityOverride() async throws {
        let original = Data([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9])
        let edited = Data([4, 5, 6])
        let prompt = "Preserve the food; improve lighting.\nТёплый свет 🍲"
        let client = try makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/images/edits")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(fakeKey)")
            let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
            let body = Self.requestBody(request)
            let imageHeader = Data("Content-Disposition: form-data; name=\"image[]\"; filename=\"food-photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
            let imageStart = try #require(body.range(of: imageHeader)).upperBound
            let ending = Data("\r\n--\(boundary)--\r\n".utf8)
            #expect(body.suffix(ending.count) == ending)
            #expect(Data(body[imageStart..<(body.count - ending.count)]) == original)
            let fields = String(decoding: body[..<imageStart], as: UTF8.self)
            #expect(fields.hasPrefix("--\(boundary)\r\n"))
            for (name, value) in [
                ("model", "gpt-image-2.5-sunburst"), ("prompt", prompt), ("size", "1024x1024"),
                ("quality", "medium"), ("n", "1"), ("output_format", "jpeg"), ("output_compression", "90")
            ] {
                #expect(fields.contains("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"))
            }
            #expect(!fields.contains("input_fidelity"))
            #expect(!fields.contains("data:image/"))
            #expect(!fields.contains(fakeKey))
            return (200, try JSONSerialization.data(withJSONObject: ["data": [["b64_json": edited.base64EncodedString()]]]))
        }
        #expect(try await client.enhanceFoodPhoto(jpeg: original, prompt: prompt) == edited)
    }

    @Test(.timeLimit(.minutes(1))) func stalledPhotoResponseTimesOutAndCancelsTransport() async throws {
        let (stopped, stopSignal) = AsyncStream<Void>.makeStream()
        StalledOpenAIProtocol.onStart = nil
        StalledOpenAIProtocol.onStop = { stopSignal.yield(); stopSignal.finish() }
        let session = stalledPhotoSession()
        defer { session.invalidateAndCancel() }
        let client = try OpenAIClient(apiKey: fakeKey, session: session, imageRequestTimeout: .milliseconds(250))
        let start = ContinuousClock.now
        do {
            _ = try await client.enhanceFoodPhoto(jpeg: Data([1]), prompt: "Polish")
            Issue.record("A stalled response must not become a photo")
        } catch {
            #expect(!(error is CancellationError))
            #expect(error.localizedDescription.contains("didn’t finish this photo in time"))
            #expect(error.localizedDescription.contains("original photo is unchanged"))
        }
        #expect(start.duration(to: .now) < .seconds(5))
        // The deadline must cancel the paid request locally, not just hide its spinner.
        for await _ in stopped { break }
    }

    @Test(.timeLimit(.minutes(1))) func stopCancelsPhotoTransportWithoutWaitingForDeadline() async throws {
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let (stopped, stopSignal) = AsyncStream<Void>.makeStream()
        StalledOpenAIProtocol.onStart = { startSignal.yield(); startSignal.finish() }
        StalledOpenAIProtocol.onStop = { stopSignal.yield(); stopSignal.finish() }
        let session = stalledPhotoSession()
        defer { session.invalidateAndCancel() }
        let client = try OpenAIClient(apiKey: fakeKey, session: session, imageRequestTimeout: .seconds(30))
        let task = Task { try await client.enhanceFoodPhoto(jpeg: Data([1]), prompt: "Polish") }
        for await _ in started { break }
        let start = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled request must not return a photo")
        } catch { #expect(error is CancellationError) }
        #expect(start.duration(to: .now) < .seconds(5))
        for await _ in stopped { break }
    }

    @Test func photoErrorsReturnActionableMessagesAndAllowAnotherRequest() async throws {
        var calls = 0
        let edited = Data([4, 5, 6])
        let client = try makeClient { _ in
            calls += 1
            if calls == 1 {
                return (400, Data("{\"error\":{\"code\":\"invalid_value\",\"param\":\"image\",\"message\":\"\(fakeKey) private photo\"}}".utf8))
            }
            return (200, try JSONSerialization.data(withJSONObject: ["data": [["b64_json": edited.base64EncodedString()]]]))
        }
        do {
            _ = try await client.enhanceFoodPhoto(jpeg: Data([1]), prompt: "Polish")
            Issue.record("A rejected request must fail")
        } catch {
            #expect(error.localizedDescription.contains("HTTP 400"))
            #expect(error.localizedDescription.contains("Parameter: image"))
            #expect(error.localizedDescription.contains("Request: req_mock_photo"))
            #expect(!error.localizedDescription.contains(fakeKey))
            #expect(!error.localizedDescription.contains("private photo"))
        }
        // No automatic paid retries; a new explicit attempt remains usable.
        #expect(calls == 1)
        #expect(try await client.enhanceFoodPhoto(jpeg: Data([1]), prompt: "Polish") == edited)
        #expect(calls == 2)
    }

    @Test func invalidPhotoInputNeverSendsAnEditRequest() async throws {
        let client = try makeClient { _ in Issue.record("Invalid photo reached transport"); return (500, Data()) }
        await #expect(throws: (any Error).self) { try await client.enhanceFoodPhoto(jpeg: Data(), prompt: "Polish") }
        await #expect(throws: (any Error).self) { try await client.enhanceFoodPhoto(jpeg: Data([1]), prompt: "") }
    }

    @Test func photoRoutingUsesAnExplicitActionAndRejectsUnknownActions() async throws {
        let client = try makeClient { request in
            #expect(request.url?.path == "/v1/responses")
            let body = try Self.body(request)
            #expect(body["tools"] == nil)
            let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
            let schema = format?["schema"] as? [String: Any]
            let properties = schema?["properties"] as? [String: Any]
            let action = properties?["action"] as? [String: Any]
            #expect(action?["enum"] as? [String] == ["recipe", "collections", "find_photo", "generate_photo", "enhance_photo", "choose_photo"])
            return (200, Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"action\":\"find_photo\",\"question\":\"\",\"searchRequest\":\"\",\"reuseSources\":false}"}]}]}"#.utf8))
        }
        #expect(try await client.planRecipeChat(request: "Find a real photo online; don't generate one", context: "").action == .findPhoto)
        let invalid = try makeClient { _ in
            (200, Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"action\":\"invent_recipe\"}"}]}]}"#.utf8))
        }
        await #expect(throws: (any Error).self) { try await invalid.planRecipeChat(request: "Photo please", context: "") }
    }

    @Test func recipeAdditionsMustMatchSourceRows() throws {
        let source = RecipeDraft(title: "Naan", ingredients: [Ingredient(name: "Flour", quantity: "300", unit: "g")], steps: [RecipeStep(text: "Mix and rest for 30 minutes.")])
        let draft = RecipeDraft(title: "Naan pizza", ingredients: [Ingredient(name: "Cheese", quantity: "100", unit: "g")])
        let valid = RecipeAssistantPatch(ingredients: [.init(operation: .add, name: "Flour", quantity: "300", unit: "g", group: "Naan")], steps: [.init(operation: .add, text: "Mix and rest for 30 minutes.", group: "Naan")])
        try RecipeAIEvidence.validate(valid, draft: draft, source: source, request: "Add naan ingredients and method")
        let invented = RecipeAssistantPatch(ingredients: [.init(operation: .add, name: "Flour", quantity: "500", unit: "g")])
        #expect(throws: (any Error).self) { try RecipeAIEvidence.validate(invented, draft: draft, source: source, request: "Add naan") }
        let inventedTime = RecipeAssistantPatch(steps: [.init(operation: .add, text: "Mix and rest for 10 minutes.")])
        #expect(throws: (any Error).self) { try RecipeAIEvidence.validate(inventedTime, draft: draft, source: source, request: "Add naan") }
        let omittedWarning = RecipeAssistantPatch(steps: [.init(operation: .add, text: "Mix and rest")])
        #expect(throws: (any Error).self) { try RecipeAIEvidence.validate(omittedWarning, draft: draft, source: source, request: "Add naan") }
    }

    @Test func explicitUserChangesAndGroupingRemainPossible() throws {
        let draft = RecipeDraft(title: "Pizza", ingredients: [Ingredient(name: "Cheese", quantity: "100", unit: "g")])
        let regroup = RecipeAssistantPatch(ingredients: [.init(operation: .update, index: 0, name: "Cheese", quantity: "100", unit: "g", group: "Toppings")])
        try RecipeAIEvidence.validate(regroup, draft: draft, source: RecipeDraft(), request: "Group the ingredients")
        let addition = RecipeAssistantPatch(ingredients: [.init(operation: .add, name: "basil", quantity: "10", unit: "g")])
        try RecipeAIEvidence.validate(addition, draft: draft, source: RecipeDraft(), request: "Add 10 g basil")
    }

    @Test func discoveryHasNoGenerationMode() { #expect(RecipeDiscoveryMode.allCases == [.online]) }

    @Test func editorPlanningAsksBeforeSearchingAndPreservesFollowupContext() async throws {
        let client = try makeClient { request in
            let body = try Self.body(request)
            #expect(body["store"] as? Bool == false)
            #expect((body["input"] as? String)?.contains("heavy cream, stock, soy sauce") == true)
            let answer = #"{"action":"recipe","question":"How many servings of sauce do you need?","searchRequest":"","reuseSources":false}"#
            return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                ["type": "message", "content": [["type": "output_text", "text": answer]]]
            ]]))
        }
        let plan = try await client.planRecipeChat(request: "Find the method", context: "We used heavy cream, stock, soy sauce")
        #expect(plan.searchRequest.isEmpty)
        #expect(plan.question.contains("servings"))
        #expect(throws: (any Error).self) { try RecipeEditPlan(question: "How many?", searchRequest: "cream sauce").validate() }
        #expect(throws: (any Error).self) { try RecipeEditPlan(question: "", searchRequest: "").validate() }
    }

    @Test func groundedEditorAcceptsClarificationWithoutSourceOrMutation() async throws {
        let client = try makeClient { request in
            let body = try Self.body(request)
            #expect((body["instructions"] as? String)?.contains("preserve its core liquid-to-flour ratios") == true)
            let answer = #"{"outcome":"clarification","sourceIndex":-1,"message":"How much beef are you cooking?","baseRationale":"","assumptions":[],"ingredientAdaptations":[],"methodAdaptations":[],"patch":{"title":null,"servings":null,"durationMinutes":null,"ingredients":[],"steps":[]}}"#
            return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                ["type": "message", "content": [["type": "output_text", "text": answer]]]
            ]]))
        }
        let draft = RecipeDraft(title: "Beef dinner")
        let edit = try await client.groundedRecipeEdit(request: "Add sauce", draft: draft, sources: [], userInput: "Add sauce", conversation: "")
        #expect(edit.outcome == .clarification)
        #expect(try edit.validatedDraft(draft, sources: [], userInput: "Add sauce") == nil)
    }

    @Test func adaptationReviewerBlocksChangedTechnique() async throws {
        let client = try makeClient { request in
            let body = try Self.body(request)
            let input = try #require(body["input"] as? String)
            #expect(input.contains("Do not boil"))
            #expect(input.contains("Boil hard"))
            let answer = #"{"baseFits":true,"coreRatiosPreserved":true,"techniquePreserved":false,"changesExplained":false,"ingredientsConsistent":true,"yieldMatches":true,"question":"","concern":"The base requires gentle heat; hard boiling changes its technique."}"#
            return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                ["type": "message", "content": [["type": "output_text", "text": answer]]]
            ]]))
        }
        let source = RecipeDraft(title: "Cream sauce", steps: [.init(text: "Do not boil.")])
        let edit = GroundedRecipeEdit(outcome: .adapted, sourceIndex: 0, message: "Adapt it.", baseRationale: "Cream sauce",
            assumptions: [], ingredientAdaptations: [], methodAdaptations: [.init(patchIndex: 0, sourceIndices: [0], reason: "Change the heat.")],
            patch: .init(steps: [.init(operation: .add, text: "Boil hard.")]))
        let review = try await client.reviewRecipeAdaptation(edit, draft: .init(), source: source, userInput: "Add cream sauce")
        #expect(!review.approved)
        #expect(!review.techniquePreserved)
    }

    @MainActor @Test func servingClarificationResumesTheSelectedRecipeWithoutSearchingAgain() async throws {
        var (draft, source, adapted) = sauceFixture()
        let initialRequest = "Find ingredients and a method for this recipe. For the sauce We used heavy cream, beef stock flour soy sauce pepper rosemary"
        draft.title = "Meatballs and rice"
        draft.servings = nil
        adapted.patch.servings = 4
        adapted.patch.ingredients[1].quantity = "100.0"
        let question = "Use the published recipe's four servings?"
        let clarification = GroundedRecipeEdit(outcome: .clarification, sourceIndex: 0, message: question,
            baseRationale: "", assumptions: [], ingredientAdaptations: [], methodAdaptations: [], patch: .init())
        let approved: [String: Any] = ["baseFits": true, "coreRatiosPreserved": true, "techniquePreserved": true,
            "changesExplained": true, "ingredientsConsistent": true, "yieldMatches": true, "question": "", "concern": ""]
        var names: [String] = []
        var plans = 0, edits = 0, searches = 0
        let client = try makeClient { request in
            let body = try Self.body(request)
            let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
            let name = format?["name"] as? String ?? "search"
            names.append(name)
            let answer: String
            switch name {
            case "recipe_chat_plan":
                plans += 1
                #expect((body["max_output_tokens"] as? Int ?? 0) >= 3000)
                if plans == 1 {
                    answer = #"{"action":"recipe","question":"How many servings?","searchRequest":"","reuseSources":false}"#
                } else if plans == 2 {
                    answer = #"{"action":"recipe","question":" \n","searchRequest":" cream stock sauce \n","reuseSources":false}"#
                } else {
                    #expect((body["input"] as? String)?.contains(source.sourceURL!.absoluteString) == true)
                    answer = #"{"action":"recipe","question":"","searchRequest":"","reuseSources":true}"#
                }
            case "search":
                return (200, try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
                    ["type": "web_search_call", "status": "completed", "action": ["type": "search", "sources": [["url": source.sourceURL!.absoluteString]]]]
                ]]))
            case "recipe_edit":
                edits += 1
                #expect((body["input"] as? String)?.contains("heavy cream") == true)
                if edits == 2 { #expect((body["input"] as? String)?.contains("Use the recipes servings") == true) }
                answer = String(decoding: try JSONEncoder().encode(edits == 1 ? clarification : adapted), as: UTF8.self)
            case "recipe_adaptation_review":
                answer = String(decoding: try JSONSerialization.data(withJSONObject: approved), as: UTF8.self)
            default:
                Issue.record("Unexpected additional request: \(name)")
                throw SupperError.invalid("Unexpected request")
            }
            return (200, try Self.response(answer))
        }
        let session = RecipeEditSession()
        var userInput = initialRequest
        var history = ""
        func send(_ request: String) async throws -> RecipeAssistantReply {
            let response = try await session.respond(to: request, draft: draft, conversation: history, userInput: userInput,
                client: client, findSources: { query, _ in
                    searches += 1
                    #expect(query == "cream stock sauce")
                    let links = try await client.searchRecipes(query)
                    #expect(links == [source.sourceURL!])
                    return [source]
                }, progress: { _ in })
            guard case .recipe(let reply) = response else { throw SupperError.invalid("Expected a recipe reply") }
            history += "\nYou: \(request)\nAssistant: \(reply.message)"
            return reply
        }

        #expect(try await send(initialRequest).draft == nil)
        userInput += "\nIt served two and a one year old for lunch and dinner"
        let clarificationReply = try await send("It served two and a one year old for lunch and dinner")
        #expect(clarificationReply.source?.url == source.sourceURL)
        #expect(clarificationReply.draft == nil)
        userInput += "\nUse the recipes servings"
        let reply = try await send("Use the recipes servings")

        #expect(reply.draft?.servings == 4)
        #expect(reply.draft?.ingredients.count == 6)
        #expect(reply.source?.url == source.sourceURL)
        #expect(draft.servings == nil)
        #expect(searches == 1)
        #expect(names == ["recipe_chat_plan", "recipe_chat_plan", "search", "recipe_edit", "recipe_chat_plan", "recipe_edit", "recipe_adaptation_review"])
    }

    @MainActor @Test func failedEditsRetainResearchAndExposeTheFailedStage() async throws {
        let (draft, source, _) = sauceFixture()
        var attempts = 0, searches = 0
        let client = try makeClient { request in
            let body = try Self.body(request)
            let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
            if format?["name"] as? String == "recipe_chat_plan" {
                attempts += 1
                let answer = attempts == 1
                    ? #"{"action":"recipe","question":"","searchRequest":"cream stock sauce","reuseSources":false}"#
                    : #"{"action":"recipe","question":"","searchRequest":"","reuseSources":true}"#
                return (200, try Self.response(answer))
            }
            return (200, Data(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#.utf8))
        }
        let session = RecipeEditSession()
        for _ in 0..<2 {
            do {
                _ = try await session.respond(to: sauceRequest, draft: draft, conversation: "", userInput: sauceRequest,
                    client: client, findSources: { _, _ in searches += 1; return [source] }, progress: { _ in })
                Issue.record("The incomplete edit must not become a proposal")
            } catch {
                #expect(error.localizedDescription.contains("preparing recipe changes"))
                #expect(error.localizedDescription.contains("output limit"))
            }
        }
        #expect(searches == 1)
    }

    @MainActor @Test func changingTheDraftInvalidatesRetainedResearch() async throws {
        let (draft, source, _) = sauceFixture()
        let client = try makeClient { request in
            let body = try Self.body(request)
            let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
            if format?["name"] as? String == "recipe_chat_plan" {
                let input = try #require(body["input"] as? String)
                #expect(!input.contains(source.sourceURL!.absoluteString))
                return (200, try Self.response(#"{"action":"recipe","question":"","searchRequest":"cream stock sauce","reuseSources":false}"#))
            }
            return (200, Data(#"{"status":"incomplete","output":[]}"#.utf8))
        }
        let session = RecipeEditSession()
        var changed = draft
        changed.title = "A different dish"
        var searches = 0
        for value in [draft, changed] {
            await #expect(throws: (any Error).self) {
                try await session.respond(to: sauceRequest, draft: value, conversation: "", userInput: sauceRequest,
                    client: client, findSources: { _, _ in searches += 1; return [source] }, progress: { _ in })
            }
        }
        #expect(searches == 2)
    }

    private static func response(_ answer: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
            ["type": "message", "content": [["type": "output_text", "text": answer]]]
        ]])
    }

    private func makeClient(_ handler: @escaping (URLRequest) throws -> (Int, Data)) throws -> OpenAIClient {
        MockOpenAIProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOpenAIProtocol.self]
        return try OpenAIClient(apiKey: fakeKey, session: URLSession(configuration: config))
    }
    private func stalledPhotoSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StalledOpenAIProtocol.self]
        return URLSession(configuration: config)
    }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])
    }
    private static func requestBody(_ request: URLRequest) -> Data {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        }
        return data
    }
}

/// Starts a successful image response, then never finishes its body. This exercises
/// the actual URLSession cancellation/deadline path rather than throwing a fake timeout.
private final class StalledOpenAIProtocol: URLProtocol, @unchecked Sendable {
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"data\":[".utf8))
        Self.onStart?()
    }
    override func stopLoading() { Self.onStop?() }
}

private final class MockOpenAIProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["x-request-id": "req_mock_photo"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
