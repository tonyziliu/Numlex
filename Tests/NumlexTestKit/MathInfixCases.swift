import Foundation
import NumlexCore

// Infix `x` multiplication and the calculator result request (a bare
// trailing `=`), evaluated through the same sheet API the app uses.

private func mathLines(_ content: String) -> [LineResult] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: Rates(), decimalPlaces: 7).map(\.result)
}

private func mathLast(_ content: String) -> LineResult? {
    mathLines(content).last
}

private func expectNumber(_ r: LineResult?, _ value: Double, _ what: String,
                          _ kind: NumericKind = .plain) throws {
    guard case .number(let n, nil, let k, _)? = r, n == value, k == kind else {
        throw CaseFailure(message: "\(what): expected \(value) \(kind), got \(String(describing: r))",
                          location: "MathInfixCases")
    }
}

public let mathInfixCases: [EngineCase] = [
    EngineCase("math.infix-x-multiplies") {
        try expectNumber(mathLast("1000 x 10000"), 10_000_000, "1000 x 10000")
    },
    EngineCase("math.infix-x-chains-with-star-precedence") {
        try expectNumber(mathLast("2 x 3 x 4"), 24, "2 x 3 x 4")
        try expectNumber(mathLast("2 + 3 x 4"), 14, "2 + 3 x 4")
        try expectNumber(mathLast("2 x (3 + 1)"), 8, "2 x (3 + 1)")
    },
    EngineCase("math.trailing-equals-requests-result") {
        try expectNumber(mathLast("1000 x 10000 ="), 10_000_000, "1000 x 10000 =")
        try expectNumber(mathLast("1000 * 10000=  "), 10_000_000, "1000 * 10000=")
        try expectNumber(mathLast("2 x 3 x 4 ="), 24, "2 x 3 x 4 =")
        try expectNumber(mathLast("a = 5\na + 1 ="), 6, "a + 1 =")
    },
    EngineCase("math.declared-x-keeps-identifier-reading") {
        try expectEqual(mathLast("x = 3\n2 x 4"), .error(message: "Invalid expression"),
                        "declared x is not an operator")
        try expectNumber(mathLast("x = 3\nx * 4"), 12, "declared x is a variable")
    },
    EngineCase("math.multiplier-suffix-unchanged") {
        try expectNumber(mathLast("1.5x"), 1.5, "1.5x", .multiplier)
        try expectNumber(mathLast("1.5x of 20"), 30, "1.5x of 20")
        try expectNumber(mathLast("1.5x - 3"), -1.5, "1.5x - 3")
    },
    EngineCase("math.hex-literal-unchanged") {
        try expectEqual(mathLast("0x1F"), .integer(value: 31, radix: 16), "0x1F")
    },
    EngineCase("math.bare-name-equals-stays-assignment-error") {
        try expectEqual(mathLast("a ="), .error(message: "Missing expression"), "a =")
        try expectEqual(mathLast("monthly rent ="), .error(message: "Invalid assignment"),
                        "monthly rent =")
        try expectEqual(mathLast("2 == 2"), .boolean(value: true), "== is a comparison")
    },
    EngineCase("math.real-assignment-still-assigns") {
        let lines = mathLines("a = 5\na x 2")
        try expectEqual(lines.first, .variable(name: "a", value: 5, kind: .plain, fraction: nil),
                        "a = 5")
        try expectNumber(lines.last, 10, "a x 2")
    },
]
