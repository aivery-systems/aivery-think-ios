import Foundation

// Models sprinkle LaTeX math into prose ("12V $\rightarrow$ the pad"). There's no math
// renderer here, so math spans are rewritten to their closest Unicode: arrows, operators,
// Greek letters, simple super/subscripts, \frac → a/b. Mirrors think web's lib/math.ts
// delimiter rules: \(..\), \[..\], $$..$$, and $..$ only when the body reads as LaTeX —
// so "$5 and $10" stays text. Inline code spans are left untouched.

enum LatexText {
    static func render(_ text: String) -> String {
        guard text.contains("$") || text.contains("\\") else { return text }
        // Odd-indexed parts are inline code spans.
        return splitInlineCode(text).enumerated()
            .map { $0.offset % 2 == 1 ? $0.element : renderProse($0.element) }
            .joined()
    }

    // MARK: - Delimiters

    private static let spanPatterns: [NSRegularExpression] = [
        #"\\\[([\s\S]+?)\\\]"#,
        #"\\\(([\s\S]+?)\\\)"#,
        #"\$\$([^$]+?)\$\$"#,
        #"(?<!\$)\$(?![\s$])([^$\n]+?)(?<!\s)\$(?!\$)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let latexHint = try! NSRegularExpression(pattern: #"\\[a-zA-Z]+|[\^_{]"#)

    private static func renderProse(_ s: String) -> String {
        var out = s
        for (i, re) in spanPatterns.enumerated() {
            out = replace(re, in: out) { g in
                // Single-dollar spans only count as math when they look like LaTeX.
                if i == spanPatterns.count - 1, !matches(latexHint, g[1]) { return g[0] }
                return convert(g[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return out
    }

    private static func splitInlineCode(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inCode = false
        for ch in s {
            if ch == "`" {
                if inCode { current.append(ch); parts.append(current); current = "" }
                else { parts.append(current); current = String(ch) }
                inCode.toggle()
            } else {
                current.append(ch)
            }
        }
        // An unclosed backtick isn't code — fold it back into prose.
        if inCode, let prose = parts.popLast() { parts.append(prose + current) } else { parts.append(current) }
        return parts
    }

    // MARK: - LaTeX → Unicode

    private static let symbols: [String: String] = [
        "rightarrow": "→", "to": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔",
        "Rightarrow": "⇒", "implies": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "iff": "⇔",
        "longrightarrow": "⟶", "longleftarrow": "⟵", "uparrow": "↑", "downarrow": "↓", "mapsto": "↦",
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "ast": "∗",
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "neq": "≠", "ne": "≠", "approx": "≈",
        "sim": "∼", "equiv": "≡", "propto": "∝", "ll": "≪", "gg": "≫",
        "infty": "∞", "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏", "int": "∫",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "cup": "∪", "cap": "∩",
        "forall": "∀", "exists": "∃", "neg": "¬", "land": "∧", "lor": "∨", "emptyset": "∅",
        "circ": "∘", "degree": "°", "checkmark": "✓", "dots": "…", "ldots": "…", "cdots": "⋯",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
        "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "phi": "φ", "varphi": "φ", "chi": "χ",
        "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ",
        "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "quad": "  ", "qquad": "    ", "%": "%", "$": "$", "&": "&", "#": "#", "_": "_",
    ]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸",
        "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ",
    ]
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈",
        "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
    ]

    private static let unwrap = try! NSRegularExpression(pattern: #"\\(?:text|textbf|textit|mathrm|mathbf|mathit|operatorname|mathbb|mathcal)\{([^{}]*)\}"#)
    private static let frac = try! NSRegularExpression(pattern: #"\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}"#)
    private static let sqrt = try! NSRegularExpression(pattern: #"\\sqrt\{([^{}]*)\}"#)
    private static let degree = try! NSRegularExpression(pattern: #"\^\{?\\circ\}?"#)
    private static let command = try! NSRegularExpression(pattern: #"\\([a-zA-Z]+|[%$&#_])"#)
    private static let scripted = try! NSRegularExpression(pattern: #"([\^_])(?:\{([^{}]*)\}|(\S))"#)
    private static let spacing = try! NSRegularExpression(pattern: #"\\[,;:! ]"#)

    private static func convert(_ body: String) -> String {
        var s = body
        s = replace(spacing, in: s) { _ in " " }
        s = replace(degree, in: s) { _ in "°" }
        s = replace(unwrap, in: s) { g in g[1] }
        s = replace(frac, in: s) { g in "\(wrap(g[1]))/\(wrap(g[2]))" }
        s = replace(sqrt, in: s) { g in "√\(wrap(g[1]))" }
        s = replace(command, in: s) { g in symbols[g[1]] ?? g[1] }
        s = replace(scripted, in: s) { g in
            let marker = g[1], arg = g[2].isEmpty ? g[3] : g[2]
            let table = marker == "^" ? superscripts : subscripts
            // Only rewrite when every character has a Unicode script form.
            if arg.allSatisfy({ table[$0] != nil }) { return String(arg.compactMap { table[$0] }) }
            return marker + (arg.count > 1 ? "(\(arg))" : arg)
        }
        return s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
    }

    private static func wrap(_ s: String) -> String {
        s.count > 1 && s.contains(where: { "+-*/ ".contains($0) }) ? "(\(s))" : s
    }

    // MARK: - Regex helpers

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Replaces each match; the closure gets [whole match, group 1, …, group n] (unmatched groups are "").
    private static func replace(_ re: NSRegularExpression, in s: String, _ transform: ([String]) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += transform((0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            })
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
}
