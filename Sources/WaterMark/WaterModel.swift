import Foundation

/// Converts token counts into an estimated volume of water.
///
/// There is no exact public figure for this — published estimates of data-centre
/// water use per token span a couple of orders of magnitude, because they depend
/// on the model, the data centre's cooling design (WUE) and the local grid's
/// water intensity. So this is deliberately a single, editable coefficient.
///
/// Default derivation (very rough):
///   • ~0.5 Wh of electricity per 1k tokens of large-model inference
///   • combined on-site + off-site water intensity ~3-9 L/kWh
///   → ~1.5-4.5 mL per 1k tokens. We default to the conservative end.
///
/// For reference, headline journalism (Washington Post / UC Riverside, 2024) put
/// a single 100-word GPT-4 email at up to ~500 mL in a water-stressed region —
/// far higher, because that's a worst-case grid. Tune the rate to taste.
@MainActor
final class WaterModel {
    static let defaultMlPer1k = 0.5
    private let key = "mlPer1kTokens"

    var mlPer1kTokens: Double {
        get {
            let v = UserDefaults.standard.double(forKey: key)
            return v > 0 ? v : Self.defaultMlPer1k
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    func water(forTokens tokens: Int) -> Double {
        Double(tokens) / 1000.0 * mlPer1kTokens
    }
}
