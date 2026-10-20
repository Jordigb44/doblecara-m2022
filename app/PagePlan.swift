// PagePlan.swift — lógica pura de selección y orden de páginas
// (sin SwiftUI ni @MainActor: se puede testear directamente con swift test)

import Foundation

enum PageMode: String { case all, range, custom }

/// Cálculos de páginas: qué páginas se eligen, en qué hoja y cara sale cada una
/// y el orden de las dos pasadas (cara A / cara B).
enum PagePlan {
    /// Hoja y cara en la que sale cada página (solo la primera copia)
    struct Slot { let sheet: Int; let sideB: Bool }

    /// Páginas elegidas (índices desde 0)
    static func selection(mode: PageMode, pageCount: Int, from: Int, to: Int, custom: String) -> [Int] {
        guard pageCount > 0 else { return [] }
        switch mode {
        case .all:
            return Array(0..<pageCount)
        case .range:
            let a = max(1, min(from, pageCount)), b = max(a, min(to, pageCount))
            return Array((a - 1)...(b - 1))
        case .custom:
            return parse(custom, pageCount: pageCount)
        }
    }

    /// "1-3, 5, 8-" → [0, 1, 2, 4, 7, 8, …]
    static func parse(_ text: String, pageCount n: Int) -> [Int] {
        var set = Set<Int>()
        for part in text.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let bits = part.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if bits.count == 1, let v = Int(bits[0]), (1...n).contains(v) {
                set.insert(v - 1)
            } else if bits.count == 2 {
                let a = Int(bits[0]) ?? 1, b = Int(bits[1]) ?? n
                let lo = max(1, min(a, b)), hi = min(n, max(a, b))
                if lo <= hi { for v in lo...hi { set.insert(v - 1) } }
            }
        }
        return set.sorted()
    }

    /// [0, 1, 2, 4] → "1-3, 5"
    static func format(_ indices: [Int]) -> String {
        var parts: [String] = []
        var i = 0
        let s = indices.sorted()
        while i < s.count {
            var j = i
            while j + 1 < s.count && s[j + 1] == s[j] + 1 { j += 1 }
            parts.append(i == j ? "\(s[i] + 1)" : "\(s[i] + 1)-\(s[j] + 1)")
            i = j + 1
        }
        return parts.joined(separator: ", ")
    }

    /// Hoja y cara de cada página según la selección y si es dúplex
    static func sheetPlan(selection: [Int], duplex: Bool) -> [Int: Slot] {
        var plan: [Int: Slot] = [:]
        for (k, p) in selection.enumerated() {
            plan[p] = duplex ? Slot(sheet: k / 2 + 1, sideB: k % 2 == 1) : Slot(sheet: k + 1, sideB: false)
        }
        return plan
    }

    /// Secuencia completa (con copias); nil = página en blanco
    static func sequence(selection: [Int], copies: Int, padBlank: Bool) -> [Int?] {
        let sel = selection
        var seq: [Int?] = []
        for c in 0..<max(1, copies) {
            seq += sel.map { Optional($0) }
            // Cada copia empieza en hoja nueva
            if sel.count % 2 == 1 && (c < copies - 1 || padBlank) { seq.append(nil) }
        }
        return seq
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}
