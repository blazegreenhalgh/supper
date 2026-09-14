import Foundation

struct RecipeImportService {
    func importRecipe(from url: URL) async throws -> RecipeDraft {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw SupperError.invalid("Enter a complete http or https recipe URL.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 Supper/0.2", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, data.count < 8_000_000,
              let html = String(data: data, encoding: .utf8) else { throw SupperError.invalid("The recipe page could not be loaded. Check the URL and try again.") }
        let parser = RecipeDocumentParser()
        var draft = try parser.parse(html: html, sourceURL: url)
        if let imageURL = parser.imageURL(html: html), ["http", "https"].contains(imageURL.scheme ?? "") {
            var imageRequest = URLRequest(url: imageURL); imageRequest.timeoutInterval = 15
            if let (image, response) = try? await URLSession.shared.data(for: imageRequest),
               (response as? HTTPURLResponse)?.statusCode == 200, image.count <= 15_000_000 {
                draft.imageData = image
            }
        }
        try Task.checkCancellation()
        return draft
    }
}
