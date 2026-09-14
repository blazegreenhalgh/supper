import Foundation

public enum RecipeTextParser {
    /// Fallback for unsupported devices. Only explicit sections are interpreted.
    public static func parse(_ text: String) -> RecipeDraft {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var draft = RecipeDraft(title: lines.first ?? "")
        var mode = ""; var group = ""; var unstructured: [String] = []
        for line in lines.dropFirst() {
            let heading = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            if heading == "ingredients" { mode = "ingredients"; group = ""; continue }
            if ["method", "instructions", "directions"].contains(heading) { mode = "method"; continue }
            if ["notes", "tips"].contains(heading) { mode = "notes"; continue }
            if mode.isEmpty, let metadata = metadata(line) {
                if metadata.kind == "servings" { draft.servings = metadata.value }
                else { draft.durationMinutes = metadata.value }
                continue
            }
            if mode == "ingredients" {
                if line.hasSuffix(":") { group = String(line.dropLast()); continue }
                let value = line.replacingOccurrences(of: #"^[•*\-]\s*"#, with: "", options: .regularExpression)
                draft.ingredients.append(IngredientLineParser.parse(value, order: draft.ingredients.count, group: group))
            } else if mode == "method" {
                let value = line.replacingOccurrences(of: #"^\d+[.)]\s*"#, with: "", options: .regularExpression)
                draft.steps.append(RecipeStep(text: value, order: draft.steps.count))
            } else { unstructured.append(line) }
        }
        draft.notes = unstructured.joined(separator: "\n")
        return draft
    }
    private static func metadata(_ text: String) -> (kind: String, value: Int)? {
        for (kind, pattern) in [("servings", #"^(?:serves|servings|yield)\s*:?\s*(\d+)\s*(?:people|servings)?$"#),
                                ("duration", #"^(?:total time|duration|time)\s*:?\s*(\d+)\s*(?:minutes?|mins?)$"#)] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text), let value = Int(text[range]), value > 0 else { continue }
            return (kind, value)
        }
        return nil
    }

}
