import Foundation

/// Converts token counts into an estimated volume of water, per model.
///
/// There is no exact public figure for this — published estimates of data-centre
/// water use per token span a couple of orders of magnitude, because they depend
/// on the model, the data centre's cooling design (WUE) and the local grid's
/// water intensity. So each rate is a single, editable coefficient.
///
/// Bigger models do more compute per token, so the built-in defaults scale with
/// model size (Opus > Sonnet > Haiku). They are rough — tune them in the menu.
/// Per-model overrides are stored in UserDefaults under "rate.<model-id>".
///
/// For reference, headline journalism (Washington Post / UC Riverside, 2024) put
/// a single 100-word GPT-4 email at up to ~500 mL in a water-stressed region —
/// far higher than these defaults, because that's a worst-case grid.
@MainActor
final class WaterModel {
    /// Fallback when a model matches none of the prefixes below.
    static let fallbackMlPer1k = 0.5

    /// Default mL / 1k tokens, matched by model-id prefix (first match wins).
    static let defaultsByPrefix: [(prefix: String, rate: Double)] = [
        ("claude-opus", 0.80),
        ("claude-sonnet", 0.40),
        ("claude-haiku", 0.15),
    ]

    private func key(_ model: String) -> String { "rate.\(model)" }

    /// The built-in default for a model, ignoring any user override.
    func defaultRate(for model: String) -> Double {
        for entry in Self.defaultsByPrefix where model.hasPrefix(entry.prefix) {
            return entry.rate
        }
        return Self.fallbackMlPer1k
    }

    /// The effective rate: user override if set, otherwise the default.
    func rate(for model: String) -> Double {
        let v = UserDefaults.standard.double(forKey: key(model))
        return v > 0 ? v : defaultRate(for: model)
    }

    func setRate(_ value: Double, for model: String) {
        UserDefaults.standard.set(value, forKey: key(model))
    }

    /// Remove the override so the model falls back to its default.
    func resetRate(for model: String) {
        UserDefaults.standard.removeObject(forKey: key(model))
    }

    func water(forModel model: String, tokens: Int) -> Double {
        Double(tokens) / 1000.0 * rate(for: model)
    }
}
