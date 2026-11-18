import Foundation

/// Restricted arithmetic parser. Never evaluates code: only arithmetic, grouping, percentages, and square roots.
public enum Calculator {
    public enum CalcError: Error, Equatable { case invalid, divisionByZero }

    /// Returns nil when the input is not an arithmetic expression (caller falls back to search).
    public static func evaluate(_ input: String) -> Double? {
        guard input.count <= 4096 else { return nil }
        // Width folding handles Chinese input-method digits and punctuation.
        // Smart punctuation and pasted formulas can use a dash or Unicode minus.
        let s = input.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "【", with: "[")
            .replacingOccurrences(of: "】", with: "]")
            .replacingOccurrences(of: "〔", with: "[")
            .replacingOccurrences(of: "〕", with: "]")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.contains(where: { "+-*/%^()[]{}√".contains($0) }) else { return nil }
        guard s.allSatisfy({ $0.isWhitespace || $0.isNumber || ".eE+-*/%^()[]{}√sqrt".contains($0) }) else { return nil }
        guard s.contains(where: { $0.isNumber }) else { return nil }
        var p = Parser(Array(s))
        guard let v = try? p.parseExpression() else { return nil }
        p.skipWhitespace()
        guard p.atEnd, v.isFinite else { return nil }
        // Keep signed numbers and scientific literals available to search.
        if Double(s.filter { !$0.isWhitespace }) != nil { return nil }
        return v
    }

    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 10
        f.usesGroupingSeparator = false
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    struct Parser {
        let c: [Character]
        var i = 0
        var depth = 0
        init(_ c: [Character]) { self.c = c }
        var atEnd: Bool { i == c.count }
        func peek() -> Character? { i < c.count ? c[i] : nil }
        mutating func skipWhitespace() {
            while let ch = peek(), ch.isWhitespace { i += 1 }
        }
        func closingBracket(for opening: Character) -> Character? {
            switch opening {
            case "(": ")"
            case "[": "]"
            case "{": "}"
            default: nil
            }
        }
        func startsPrimary(_ ch: Character) -> Bool {
            ch.isNumber || ch == "." || closingBracket(for: ch) != nil || ch == "√" || ch == "s"
        }

        mutating func parseExpression() throws -> Double {
            var v = try parseTerm()
            skipWhitespace()
            while let ch = peek(), ch == "+" || ch == "-" {
                i += 1
                let r = try parseTerm()
                v = ch == "+" ? v + r : v - r
                skipWhitespace()
            }
            return v
        }

        mutating func parseTerm() throws -> Double {
            var v = try parseUnary()
            while true {
                // Adjacent groups and coefficients allow 2(3+4), (2+3)4, and 2√9.
                let followsGroup = c[..<i].last(where: { !$0.isWhitespace }).map { ")]}".contains($0) } ?? false
                skipWhitespace()
                guard let ch = peek() else { break }
                if ch == "*" || ch == "/" || ch == "%" {
                    i += 1
                    let r = try parseUnary()
                    switch ch {
                    case "*": v *= r
                    case "/": guard r != 0 else { throw CalcError.divisionByZero }; v /= r
                    default: guard r != 0 else { throw CalcError.divisionByZero }; v = v.truncatingRemainder(dividingBy: r)
                    }
                } else if closingBracket(for: ch) != nil || ch == "√" || ch == "s" || (followsGroup && startsPrimary(ch)) {
                    v *= try parseUnary()
                } else {
                    break
                }
            }
            return v
        }

        mutating func parseUnary() throws -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64 else { throw CalcError.invalid }
            skipWhitespace()
            if peek() == "-" { i += 1; return -(try parseUnary()) }
            if peek() == "+" { i += 1; return try parseUnary() }
            if peek() == "√" {
                i += 1
                let value = try parseUnary()
                guard value >= 0 else { throw CalcError.invalid }
                return sqrt(value)
            }
            return try parsePower()
        }

        mutating func parsePower() throws -> Double {
            var base = try parsePrimary()
            skipWhitespace()
            // A trailing % is a percentage. Between operands, % retains remainder semantics.
            if peek() == "%" {
                var next = i + 1
                while next < c.count && c[next].isWhitespace { next += 1 }
                if next == c.count || !startsPrimary(c[next]) {
                    i += 1
                    base /= 100
                    skipWhitespace()
                }
            }
            if peek() == "^" {
                i += 1
                return pow(base, try parseUnary()) // right associative; powers precede unary minus
            }
            return base
        }

        mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            if let opening = peek(), let closing = closingBracket(for: opening) {
                i += 1
                let v = try parseExpression()
                skipWhitespace()
                guard peek() == closing else { throw CalcError.invalid }
                i += 1
                return v
            }
            if c[i...].starts(with: Array("sqrt")) {
                i += 4
                skipWhitespace()
                guard peek() == "(" else { throw CalcError.invalid }
                let value = try parsePrimary()
                guard value >= 0 else { throw CalcError.invalid }
                return sqrt(value)
            }
            let start = i
            while let ch = peek(), ch.isNumber || ch == "." { i += 1 }
            guard i > start else { throw CalcError.invalid }
            if peek() == "e" || peek() == "E" {
                i += 1
                if peek() == "+" || peek() == "-" { i += 1 }
                let exponentStart = i
                while let ch = peek(), ch.isNumber { i += 1 }
                guard i > exponentStart else { throw CalcError.invalid }
            }
            guard let v = Double(String(c[start..<i])), v.isFinite else { throw CalcError.invalid }
            return v
        }
    }
}
