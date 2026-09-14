import Foundation

/// Pure, original-quantity arithmetic. Unknown text never participates in arithmetic.
public struct RecipeQuantity: Equatable, Sendable {
    public var lower: Double
    public var upper: Double?

    public static func parse(_ text: String) -> Self? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fractions = ["½":"1/2", "⅓":"1/3", "⅔":"2/3", "¼":"1/4", "¾":"3/4", "⅛":"1/8", "⅜":"3/8", "⅝":"5/8", "⅞":"7/8", "⅕":"1/5", "⅖":"2/5", "⅗":"3/5", "⅘":"4/5", "⅙":"1/6", "⅚":"5/6"]
        for (symbol, value) in fractions { text = text.replacingOccurrences(of: symbol, with: " " + value) }
        text = text.replacingOccurrences(of: "⁄", with: "/").trimmingCharacters(in: .whitespaces)
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "-–—"))
        if parts.count == 2, let a = scalar(parts[0]), let b = scalar(parts[1]), b >= a {
            return Self(lower: a, upper: b)
        }
        if parts.count == 1, let a = scalar(text) { return Self(lower: a, upper: nil) }
        let words = text.components(separatedBy: " to ")
        if words.count == 2, let a = scalar(words[0]), let b = scalar(words[1]), b >= a { return Self(lower: a, upper: b) }
        return nil
    }

    private static func scalar(_ text: String) -> Double? {
        let pieces = text.split(whereSeparator: \.isWhitespace)
        guard (1...2).contains(pieces.count) else { return nil }
        func number(_ s: Substring) -> Double? {
            guard s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "/" }) else { return nil }
            let f = s.split(separator: "/", omittingEmptySubsequences: false)
            if f.count == 2, let n = Double(f[0]), let d = Double(f[1]), d > 0 { return n / d }
            if f.count == 1, let n = Double(s), n.isFinite, n >= 0 { return n }
            return nil
        }
        if pieces.count == 2 {
            guard !pieces[0].contains("/"), pieces[1].contains("/"), let whole = number(pieces[0]), let fraction = number(pieces[1]), fraction < 1 else { return nil }
            return whole + fraction
        }
        return number(pieces[0])
    }

    public func scaled(by factor: Double) -> Self { Self(lower: lower * factor, upper: upper.map { $0 * factor }) }
    public var formatted: String { Self.format(lower) + (upper.map { "–" + Self.format($0) } ?? "") }
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let whole = floor(value)
        for (fraction, glyph) in [(0.125,"⅛"),(0.25,"¼"),(1.0/3,"⅓"),(0.375,"⅜"),(0.5,"½"),(0.625,"⅝"),(2.0/3,"⅔"),(0.75,"¾"),(0.875,"⅞")] {
            if abs(value - whole - fraction) < 0.000_01 { return (whole > 0 ? String(Int(whole)) + " " : "") + glyph }
        }
        return decimal(value)
    }
    public static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = value > 0 && value < 0.01 ? 4 : 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}

extension Ingredient {
    public func scaled(from base: Int?, to selected: Int?) -> Ingredient {
        guard let base, let selected, base > 0, selected > 0, base != selected,
              let parsed = RecipeQuantity.parse(quantity) else { return self }
        var result = self
        result.quantity = parsed.scaled(by: Double(selected) / Double(base)).formatted
        return result
    }
}

public enum IngredientLineParser {
    public static func parse(_ raw: String, id: UUID = UUID(), order: Int = 0, group: String = "") -> Ingredient {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: " ")
        // Quantity prefix only: never strip preparation text, alternate measures, or package size.
        let pattern = #"^((?:\d+(?:\.\d+)?(?:\s+\d+[/⁄]\d+)?|\d*\s*[½⅓⅔¼¾⅛⅜⅝⅞⅕⅖⅗⅘⅙⅚]|\d+[/⁄]\d+)(?:\s*(?:[-–—]|to)\s*(?:\d+(?:\.\d+)?(?:\s+\d+/\d+)?|[½⅓⅔¼¾⅛⅜⅝⅞]))?)(?:\s+|(?=[a-zA-Z]))(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let q = Range(match.range(at: 1), in: line), let rest = Range(match.range(at: 2), in: line),
              RecipeQuantity.parse(String(line[q])) != nil else { return Ingredient(id: id, name: line, order: order, group: group) }
        var name = String(line[rest]); var unit = ""
        let tokens = name.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        if let first = tokens.first, tokens.count == 2, GroceryUnit.recognizes(String(first)) {
            unit = String(first); name = String(tokens[1])
        }
        // Do not misinterpret "2 x 400 g tins" or "1 lb / 500 g" as simple quantities.
        if name.hasPrefix("x ") || name.hasPrefix("× ") || name.hasPrefix("/ ") { return Ingredient(id: id, name: line, order: order, group: group) }
        return Ingredient(id: id, name: name, quantity: String(line[q]), unit: unit, order: order, group: group)
    }
}
