import Foundation

/// An everyday thing with a known water footprint, used to put the LLM
/// estimate "in perspective".
///
/// Comparisons are made on BLUE water — freshwater withdrawn or consumed from
/// surface/groundwater — because that is the kind data centres use. The famous
/// headline figures for food (140 L per coffee, 2,400 L per burger) are total
/// virtual-water footprints dominated by GREEN water (rain falling on crops
/// and pasture), which would overstate the comparison in AI's favour by ~30×
/// for a burger. Where the two differ, `litersTotal` keeps the headline figure
/// so both can be shown. Splits from Mekonnen & Hoekstra (2012) and
/// Chapagain & Hoekstra (2007).
struct Comparison: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    /// Blue-water figure — the like-for-like basis for the bars and phrases.
    let litersBlue: Double
    /// Total virtual water (green + blue + grey) when meaningfully different.
    let litersTotal: Double?
    let note: String
}

enum Comparisons {
    /// Ordered smallest → largest blue-water footprint.
    static let all: [Comparison] = [
        Comparison(emoji: "💧", name: "bottle of water", litersBlue: 0.5, litersTotal: nil,
                   note: "A standard 500 mL bottle of drinking water."),
        Comparison(emoji: "☕️", name: "cup of coffee", litersBlue: 1.0, litersTotal: 140,
                   note: "About 1 L of pumped freshwater per cup. The famous 140 L is nearly all rain falling on the coffee crop."),
        Comparison(emoji: "🚿", name: "8-min shower", litersBlue: 65, litersTotal: nil,
                   note: "8 minutes at about 8 L per minute. Shower water mostly drains back for treatment; cooling water evaporates."),
        Comparison(emoji: "🍔", name: "hamburger", litersBlue: 82, litersTotal: 2400,
                   note: "About 82 L of pumped freshwater per burger. The famous 2,400 L is nearly all rain falling on feed crops."),
    ]

    /// The most dramatic reference (largest blue footprint) — used for share headlines.
    static var hero: Comparison { all.max { $0.litersBlue < $1.litersBlue }! }

    /// A single punchy line for the share card, e.g. "🍔 ≈ 3% of a hamburger".
    static func headline(ml: Double) -> String {
        "\(hero.emoji) \(describe(ml: ml, hero))"
    }

    /// How many of item `c` the given `ml` of water equals (can be < 1 or > 1).
    /// Blue-water basis.
    static func count(ml: Double, _ c: Comparison) -> Double {
        (ml / 1000.0) / c.litersBlue
    }

    /// Fraction of a single item, clamped to 0...1 for bar fills.
    static func fraction(ml: Double, _ c: Comparison) -> Double {
        min(max(count(ml: ml, c), 0), 1)
    }

    /// The item's blue-water figure for row labels, e.g. "0.5 L", "82 L".
    static func litersText(_ c: Comparison) -> String {
        c.litersBlue < 1
            ? String(format: "%.1f L", c.litersBlue)
            : String(format: "%.0f L", c.litersBlue)
    }

    /// A compact value for the meter rows, e.g. "5%", "3.2×", "<0.01%".
    static func compactValue(ml: Double, _ c: Comparison) -> String {
        let count = self.count(ml: ml, c)
        if count >= 10 { return String(format: "%.0f×", count) }
        if count >= 1 { return String(format: "%.1f×", count) }
        let pct = count * 100
        if pct >= 1 { return String(format: "%.0f%%", pct) }
        if pct >= 0.1 { return String(format: "%.1f%%", pct) }
        if pct >= 0.01 { return String(format: "%.2f%%", pct) }
        return "<0.01%"
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
