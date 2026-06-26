import Foundation

/// An everyday thing with a known water footprint, used to put the LLM
/// estimate "in perspective". Litres are water-to-produce/use figures from
/// public sources (Water Footprint Network and similar) — rough but honest.
struct Comparison: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    let litersEach: Double
    let note: String
}

enum Comparisons {
    static let all: [Comparison] = [
        Comparison(emoji: "💧", name: "bottle of water", litersEach: 0.5,
                   note: "A 500 mL bottle of drinking water."),
        Comparison(emoji: "🚿", name: "8-min shower", litersEach: 65,
                   note: "~8 L/min from a standard showerhead."),
        Comparison(emoji: "☕️", name: "cup of coffee", litersEach: 140,
                   note: "~140 L to grow & process the beans (Water Footprint Network)."),
        Comparison(emoji: "🍔", name: "hamburger", litersEach: 2400,
                   note: "~2,400 L incl. feed, water & processing (Water Footprint Network)."),
    ]

    /// The most dramatic reference (largest footprint) — used for share headlines.
    static var hero: Comparison { all.max { $0.litersEach < $1.litersEach }! }

    /// A single punchy line for the share card, e.g. "🍔 ≈ 3% of a hamburger".
    static func headline(ml: Double) -> String {
        "\(hero.emoji) \(describe(ml: ml, hero))"
    }

    /// How many of item `c` the given `ml` of water equals (can be < 1 or > 1).
    static func count(ml: Double, _ c: Comparison) -> Double {
        (ml / 1000.0) / c.litersEach
    }

    /// Fraction of a single item, clamped to 0...1 for bar fills.
    static func fraction(ml: Double, _ c: Comparison) -> Double {
        min(max(count(ml: ml, c), 0), 1)
    }

    /// A human phrase comparing `ml` of water to one of the reference items.
    static func describe(ml: Double, _ c: Comparison) -> String {
        let count = self.count(ml: ml, c)
        if count >= 1 {
            return String(format: "≈ %.1f× a %@", count, c.name)
        }
        let pct = count * 100
        if pct >= 1 {
            return String(format: "≈ %.0f%% of a %@", pct, c.name)
        }
        if pct >= 0.01 {
            return String(format: "≈ %.2f%% of a %@", pct, c.name)
        }
        return String(format: "< 0.01%% of a %@", c.name)
    }
}
