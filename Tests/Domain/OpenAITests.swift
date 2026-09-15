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

    @Test func classifiesErrorsWithoutEchoingProviderData() {
        let data = Data("{\"error\":{\"code\":\"insufficient_quota\",\"message\":\"\(fakeKey) private recipe\"}}".utf8)
        #expect(OpenAIClient.apiError(status: 429, data: data).localizedDescription.contains("credits"))
        for status in [400, 401, 403, 404, 429, 500] {
            let message = OpenAIClient.apiError(status: status, data: data).localizedDescription
            #expect(!message.contains(fakeKey))
            #expect(!message.contains("private recipe"))
        }
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
            #expect(request.url?.path == "/v1/images/generations")
            return (200, Data(#"{"data":[{"b64_json":""}]}"#.utf8))
        }
        await #expect(throws: (any Error).self) { try await client.generateCover(prompt: "naan") }
    }

    @Test func foodPhotoEditUsesUploadedBytesAndHighFidelityEditingEndpoint() async throws {
        let original = Data([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9])
        let edited = Data([4, 5, 6])
        let client = try makeClient { request in
            #expect(request.url?.path == "/v1/images/edits")
            let body = try Self.body(request)
            #expect(body["model"] as? String == "gpt-image-2.5-sunburst")
            #expect(body["input_fidelity"] as? String == "high")
            #expect(body["n"] as? Int == 1)
            #expect((body["images"] as? [[String: String]]) == [["image_url": "data:image/jpeg;base64,\(original.base64EncodedString())"]])
            return (200, try JSONSerialization.data(withJSONObject: ["data": [["b64_json": edited.base64EncodedString()]]]))
        }
        #expect(try await client.enhanceFoodPhoto(jpeg: original, prompt: "Preserve the food; improve lighting.") == edited)
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
            #expect(action?["enum"] as? [String] == ["recipe", "find_photo", "generate_photo", "enhance_photo", "choose_photo"])
            return (200, Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"action\":\"find_photo\"}"}]}]}"#.utf8))
        }
        #expect(try await client.recipeChatAction(request: "Find a real photo online; don't generate one", conversation: "") == .findPhoto)
        let invalid = try makeClient { _ in
            (200, Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"action\":\"invent_recipe\"}"}]}]}"#.utf8))
        }
        await #expect(throws: (any Error).self) { try await invalid.recipeChatAction(request: "Photo please", conversation: "") }
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

    private func makeClient(_ handler: @escaping (URLRequest) throws -> (Int, Data)) throws -> OpenAIClient {
        MockOpenAIProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOpenAIProtocol.self]
        return try OpenAIClient(apiKey: fakeKey, session: URLSession(configuration: config))
    }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class MockOpenAIProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
