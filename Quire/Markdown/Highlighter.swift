import SwiftUI

/// A small, language-agnostic code highlighter: comments, strings, numbers and a shared keyword set
/// that covers the languages models write most (Swift, Python, JS/TS, Go, Rust, C-family, shell, SQL).
/// It colours four token kinds in muted tones, which is what makes code scannable; it doesn't try to
/// be a parser. Results are cached by source text.
enum Highlighter {
    private static let slashComment = try! NSRegularExpression(
        pattern: "//[^\\n]*|/\\*[\\s\\S]*?\\*/", options: [])
    private static let hashComment = try! NSRegularExpression(
        pattern: "(?<![\\w\"'$])#(?![!\\[{])[^\\n]*", options: [])
    private static let dashComment = try! NSRegularExpression(pattern: "--[^\\n]*", options: [])

    private static let cLike: Set<String> = ["c", "h", "cpp", "c++", "objc", "swift", "js", "javascript", "jsx", "ts", "tsx", "typescript",
                                              "go", "rust", "rs", "java", "kotlin", "kt", "scala", "css", "scss", "json", "jsonc", "dart",
                                              "csharp", "cs", "php"]
    private static let hashLangs: Set<String> = ["python", "py", "ruby", "rb", "sh", "bash", "zsh", "shell", "fish", "yaml", "yml", "toml",
                                                  "r", "perl", "pl", "dockerfile", "makefile", "make", "ini", "conf", "nix", "elixir", "ex"]
    private static let dashLangs: Set<String> = ["sql", "lua", "haskell", "hs", "ada"]
    private static let string = try! NSRegularExpression(
        pattern: "\"(?:\\\\.|[^\"\\\\\\n])*\"|'(?:\\\\.|[^'\\\\\\n])*'|`(?:\\\\.|[^`\\\\])*`", options: [])
    private static let number = try! NSRegularExpression(
        pattern: "\\b(?:0x[0-9a-fA-F_]+|\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b", options: [])
    private static let word = try! NSRegularExpression(pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\b", options: [])

    private static let keywords: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "in",
        "where", "try", "catch", "throw", "throws", "finally", "async", "await", "yield", "import", "from", "as",
        "is", "not", "and", "or", "class", "struct", "enum", "protocol", "extension", "interface", "type", "trait",
        "impl", "fn", "func", "function", "def", "lambda", "let", "var", "val", "const", "static", "public",
        "private", "protected", "internal", "fileprivate", "open", "final", "override", "mut", "pub", "mod", "use", "package",
        "module", "export", "new", "delete", "this", "self", "Self", "super", "init", "deinit", "guard", "defer",
        "some", "any", "nil", "null", "undefined", "None", "true", "false", "True", "False", "with", "match",
        "go", "chan", "select", "union", "typedef", "void", "int", "float", "double", "bool", "char", "string",
        "String", "Int", "Double", "Bool", "echo", "then", "fi", "elif", "esac", "done", "SELECT", "FROM",
        "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "ON", "GROUP", "BY", "ORDER", "INSERT", "INTO", "VALUES",
        "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "AND", "OR", "NOT", "NULL", "AS", "LIMIT",
    ]

    private static var cache: [String: AttributedString] = [:]

    static func highlight(_ code: String, lang: String) -> AttributedString {
        let key = lang + "\u{1}" + code
        if let hit = cache[key] { return hit }
        let result = compute(code, lang: lang.lowercased())
        if cache.count > 120 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }

    private enum Kind { case comment, string, number, keyword }

    private static func compute(_ code: String, lang: String) -> AttributedString {
        // Plain text, prose-like languages and very large blocks are left alone.
        let plain: Set<String> = ["", "text", "txt", "plain", "plaintext", "markdown", "md", "output", "console", "log"]
        if plain.contains(lang) || code.utf16.count > 20_000 { return AttributedString(code) }

        let ns = code as NSString
        let full = NSRange(location: 0, length: ns.length)
        var claimed = IndexSet()
        var spans: [(NSRange, Kind)] = []

        func claim(_ re: NSRegularExpression, _ kind: Kind, filter: ((String) -> Bool)? = nil) {
            for m in re.matches(in: code, range: full) {
                let r = m.range
                guard r.length > 0, !claimed.intersects(integersIn: r.location..<(r.location + r.length)) else { continue }
                if let filter, !filter(ns.substring(with: r)) { continue }
                claimed.insert(integersIn: r.location..<(r.location + r.length))
                spans.append((r, kind))
            }
        }

        // Strings and comments first so keywords inside them stay uncoloured.
        claim(string, .string)
        if !hashLangs.contains(lang) { claim(slashComment, .comment) }
        if !cLike.contains(lang) && !dashLangs.contains(lang) { claim(hashComment, .comment) }
        if dashLangs.contains(lang) { claim(dashComment, .comment) }
        claim(number, .number)
        claim(word, .keyword, filter: { keywords.contains($0) })

        var out = AttributedString(code)
        for (range, kind) in spans {
            guard let r = Range(range, in: code),
                  let lower = AttributedString.Index(r.lowerBound, within: out),
                  let upper = AttributedString.Index(r.upperBound, within: out) else { continue }
            let color: Color
            switch kind {
            case .comment: color = .qCodeComment
            case .string: color = .qCodeString
            case .number: color = .qCodeNumber
            case .keyword: color = .qCodeKeyword
            }
            out[lower..<upper][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color
        }
        return out
    }
}
