import Foundation

/// Estimates the water footprint of token usage with a physically-grounded,
/// two-step model: tokens → energy (Wh) → water (mL).
///
/// Step 1 — energy. Generating tokens (decode) costs far more per token than
/// reading the prompt (prefill), so output and prefill have separate Wh/1k-token
/// coefficients, defaulting by model size. Calibrated against public figures:
/// a GPT-4o-class short query (100 in / 300 out) ≈ 0.42 Wh (How Hungry is AI?,
/// 2025) and a median Gemini prompt ≈ 0.24 Wh (Google, 2025).
///
/// Step 2 — water. water = energy × (WUE_onsite + WUE_source), where:
///   • WUE_onsite ≈ 0.30 L/kWh  — data-centre cooling (efficient hyperscaler;
///     industry average is ~1.9).
///   • WUE_source ≈ 4.35 L/kWh  — water used generating the electricity (US grid).
/// "Comprehensive" scope includes the off-site source term (the honest, harder-to-
/// dismiss figure); turning it off gives the cooling-only number Google headlines.
///
/// Every coefficient is editable; all are estimates, since Anthropic publishes
/// none of this for Claude.
@MainActor
final class WaterModel {
    // MARK: - Energy coefficients (Wh per 1k tokens)

    struct EnergyRate { let out: Double; let prefill: Double }

    static let energyDefaultsByPrefix: [(prefix: String, rate: EnergyRate)] = [
        ("claude-opus",   EnergyRate(out: 2.0, prefill: 0.15)),
        ("claude-sonnet", EnergyRate(out: 1.2, prefill: 0.10)),
        ("claude-haiku",  EnergyRate(out: 0.4, prefill: 0.04)),
    ]
    static let fallbackEnergy = EnergyRate(out: 1.2, prefill: 0.10)

    func defaultEnergy(for model: String) -> EnergyRate {
        for e in Self.energyDefaultsByPrefix where model.hasPrefix(e.prefix) { return e.rate }
        return Self.fallbackEnergy
    }

    private func stored(_ key: String) -> Double? {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : nil
    }

    func outWhPer1k(for model: String) -> Double {
        stored("e_out.\(model)") ?? defaultEnergy(for: model).out
    }
    func prefillWhPer1k(for model: String) -> Double {
        stored("e_prefill.\(model)") ?? defaultEnergy(for: model).prefill
    }
    func setOutWhPer1k(_ v: Double, for model: String) { UserDefaults.standard.set(max(0, v), forKey: "e_out.\(model)") }
    func setPrefillWhPer1k(_ v: Double, for model: String) { UserDefaults.standard.set(max(0, v), forKey: "e_prefill.\(model)") }
    func resetEnergy(for model: String) {
        UserDefaults.standard.removeObject(forKey: "e_out.\(model)")
        UserDefaults.standard.removeObject(forKey: "e_prefill.\(model)")
    }

    // MARK: - Water intensity (L/kWh)

    static let defaultWUEOnsite = 0.30
    static let defaultWUESource = 4.35

    var wueOnsite: Double {
        get { stored("wue_onsite") ?? Self.defaultWUEOnsite }
        set { UserDefaults.standard.set(max(0, newValue), forKey: "wue_onsite") }
    }
    var wueSource: Double {
        get { stored("wue_source") ?? Self.defaultWUESource }
        set { UserDefaults.standard.set(max(0, newValue), forKey: "wue_source") }
    }
    /// Comprehensive = include off-site grid-electricity water. Default on.
    var comprehensive: Bool {
        get {
            if UserDefaults.standard.object(forKey: "comprehensive") == nil { return true }
            return UserDefaults.standard.bool(forKey: "comprehensive")
        }
        set { UserDefaults.standard.set(newValue, forKey: "comprehensive") }
    }

    /// Total water intensity in L/kWh for the current scope.
    var waterIntensity: Double { wueOnsite + (comprehensive ? wueSource : 0) }

    // MARK: - Conversion

    /// Energy (Wh) for a token breakdown.
    func energyWh(forModel model: String, output: Int, prefill: Int) -> Double {
        Double(output) / 1000.0 * outWhPer1k(for: model)
            + Double(prefill) / 1000.0 * prefillWhPer1k(for: model)
    }

    /// Water (mL) for a token breakdown, at the current scope.
    func waterML(forModel model: String, output: Int, prefill: Int) -> Double {
        let kWh = energyWh(forModel: model, output: output, prefill: prefill) / 1000.0
        return kWh * waterIntensity * 1000.0  // L → mL
    }

    // MARK: - Training (amortised)
    //
    // A one-time model-training water cost, spread across the active user base
    // (training ÷ MAU). ALL of these figures are rough public-proxy ESTIMATES —
    // Anthropic does not publish training water/energy or Claude's MAU — so they
    // are editable and clearly labelled as estimates in the UI.
    //
    // Anchor: "Making AI Less Thirsty" (2023) puts GPT-3 training at ~5.4M L total
    // (700k L on-site). Frontier models are larger; defaults scale with model size.

    static let defaultMAU = 30_000_000.0  // estimated Claude monthly active users

    static let trainingDefaultsByPrefix: [(prefix: String, liters: Double)] = [
        ("claude-opus",   175_000_000),
        ("claude-sonnet",  60_000_000),
        ("claude-haiku",   17_000_000),
    ]
    static let fallbackTrainingLiters = 60_000_000.0

    var includeTraining: Bool {
        get {
            if UserDefaults.standard.object(forKey: "includeTraining") == nil { return true }
            return UserDefaults.standard.bool(forKey: "includeTraining")
        }
        set { UserDefaults.standard.set(newValue, forKey: "includeTraining") }
    }

    var monthlyActiveUsers: Double {
        get { stored("mau") ?? Self.defaultMAU }
        set { UserDefaults.standard.set(max(0, newValue), forKey: "mau") }
    }

    func defaultTrainingLiters(for model: String) -> Double {
        for e in Self.trainingDefaultsByPrefix where model.hasPrefix(e.prefix) { return e.liters }
        return Self.fallbackTrainingLiters
    }

    func trainingLiters(for model: String) -> Double {
        stored("training.\(model)") ?? defaultTrainingLiters(for: model)
    }

    func setTrainingLiters(_ v: Double, for model: String) {
        UserDefaults.standard.set(max(0, v), forKey: "training.\(model)")
    }

    func resetTrainingLiters(for model: String) {
        UserDefaults.standard.removeObject(forKey: "training.\(model)")
    }

    /// One user's amortised share of this model's training, in mL.
    func trainingShareML(for model: String) -> Double {
        guard monthlyActiveUsers > 0 else { return 0 }
        return trainingLiters(for: model) / monthlyActiveUsers * 1000.0
    }
}
