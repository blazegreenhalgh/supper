import Foundation

public enum RecipeChatAction: String, Codable, CaseIterable, Sendable {
    case recipe, findPhoto = "find_photo", generatePhoto = "generate_photo", enhancePhoto = "enhance_photo", choosePhoto = "choose_photo"
}

public enum RecipePhotoKind: String, CaseIterable, Sendable {
    case online = "Find online", generated = "Generate", enhanced = "Polish my photo"
}

/// Photo edits never replace ingredient/method edits made while an image was loading.
public struct RecipePhotoProposal: Identifiable, Sendable {
    public let id = UUID()
    public let image: Data
    public let previousImage: Data?
    public let originalPhoto: Data?
    public let kind: RecipePhotoKind
    public let source: RecipeAssistantSource?
    public let imageURL: URL?
    public init(image: Data, previousImage: Data?, originalPhoto: Data? = nil, kind: RecipePhotoKind,
                source: RecipeAssistantSource? = nil, imageURL: URL? = nil) {
        self.image = image; self.previousImage = previousImage; self.originalPhoto = originalPhoto
        self.kind = kind; self.source = source; self.imageURL = imageURL
    }
    public var caption: String {
        switch kind {
        case .online: return "Photo from \(source?.title ?? "an online source")"
        case .generated: return "AI-generated cover"
        case .enhanced: return "AI-edited from your food photo"
        }
    }
    public func applying(to draft: RecipeDraft) throws -> RecipeDraft {
        guard draft.imageData == previousImage else { throw SupperError.invalid("The recipe photo has changed. Request another photo to keep your newer choice safe.") }
        guard !image.isEmpty, image.count <= 15_000_000 else { throw SupperError.invalid("This photo couldn’t be loaded. Choose another image.") }
        let credit: String
        switch kind {
        case .online:
            guard let source, let imageURL, RecipeSearchFeed.publicURL(source.url.absoluteString) != nil,
                  RecipeSearchFeed.publicURL(imageURL.absoluteString) != nil else { throw SupperError.invalid("This photo has no verified online source.") }
            credit = "Cover photo: \(source.title)\n\(source.url.absoluteString)\nImage: \(imageURL.absoluteString)"
        case .generated: credit = "Cover generated with AI (GPT Image 2.5 Flare)."
        case .enhanced:
            guard let originalPhoto, !originalPhoto.isEmpty else { throw SupperError.invalid("Choose the original food photo before editing it.") }
            credit = "Cover edited with AI from a supplied food photo (GPT Image 2.5 Sunburst)."
        }
        var value = draft; value.imageData = image
        if !value.notes.contains(credit) { value.notes += (value.notes.isEmpty ? "" : "\n\n") + credit }
        return value
    }
}

/// Only URLs actually present in downloaded page metadata can become photo candidates.
public enum RecipePhotoMetadata {
    public static func imageURLs(html: String, pageURL: URL) -> [URL] {
        let parser = RecipeDocumentParser()
        var values: [String] = []
        if let value = parser.imageURL(html: html) { values.append(value.absoluteString) }
        let tags = matches(#"<meta\b[^>]*>"#, in: html)
        for tag in tags {
            let attrs = attributes(tag)
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            if ["og:image", "og:image:secure_url", "twitter:image", "twitter:image:src"].contains(key), let value = attrs["content"] { values.append(value) }
        }
        var seen = Set<URL>()
        return values.compactMap { value in
            guard let resolved = URL(string: parser.cleanText(value), relativeTo: pageURL)?.absoluteURL,
                  let url = RecipeSearchFeed.publicURL(resolved.absoluteString), url.port == nil || url.port == 443,
                  seen.insert(url).inserted else { return nil }
            return url
        }
    }
    public static func title(html: String, pageURL: URL) -> String {
        let parser = RecipeDocumentParser()
        if let draft = try? parser.parse(html: html, sourceURL: pageURL), !draft.title.isEmpty { return String(draft.title.prefix(200)) }
        for tag in matches(#"<meta\b[^>]*>"#, in: html) {
            let attrs = attributes(tag)
            if (attrs["property"] ?? attrs["name"])?.lowercased() == "og:title", let value = attrs["content"] {
                return String(parser.cleanText(value).prefix(200))
            }
        }
        return pageURL.host ?? "Online photo"
    }
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    private static func attributes(_ tag: String) -> [String: String] {
        let pattern = #"([\w:-]+)\s*=\s*(["'])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [:] }
        var values: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            if let key = Range(match.range(at: 1), in: tag), let value = Range(match.range(at: 3), in: tag) {
                values[String(tag[key]).lowercased()] = String(tag[value])
            }
        }
        return values
    }
}
