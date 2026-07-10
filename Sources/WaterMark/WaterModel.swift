import Foundation

/// Estimates the water footprint of token usage with a physically-grounded,
/// two-step model: tokens → energy (Wh) → water (mL).
///
/// Step 1 — energy. Generating tokens (decode) costs far more per token than
/// reading the prompt (prefill): measurement studies find roughly 11× at equal
/// counts ("From Prompts to Power", 2025), so output and prefill carry separate
/// Wh/1k-token coefficients, defaulting by model family. Cache *reads* are
/// charged a fraction of the prefill rate (default 10%, mirroring how they are
/// priced): retrieval is cheap, but not free, and in coding-agent usage cache
/// reads are often >90% of all tokens. Sanity anchors: a GPT-4o-class short
/// query ≈ 0.42 Wh ("How Hungry is AI?", 2025). Google's median Gemini prompt
/// (0.24 Wh) publishes no token counts, so it is an order-of-magnitude
/// cross-check, not a calibration point. Defaults sit above published
/// per-token estimates to leave headroom for long contexts, where flat
/// per-token rates undercount (attention cost grows with context; Epoch AI).
///
/// Step 2 — water. water = energy × (WUE_onsite + WUE_source), where:
///   • WUE_onsite ≈ 0.30 L/kWh — data-centre cooling. Anthropic serves mostly
///     from AWS (reported 0.15–0.18) and Google Cloud (~1.0–1.1); 0.30 is a
///     fair traffic-weighted middle. (LBNL 2024 implies a US direct average
///     of ~0.4–0.5.)
///   • WUE_source ≈ 4.35 L/kWh — water consumed generating the electricity
///     (US grid, implied by LBNL 2024; consumption basis, and it includes
///     hydro-reservoir evaporation, so it is deliberately high — "How Hungry
///     is AI?" uses 3.14).
/// "Comprehensive" scope includes the off-site source term (the honest,
/// harder-to-dismiss figure); turning it off gives the cooling-only number
/// headlines usually quote.
///
/// Every coefficient is editable; all are estimates, since Anthropic publishes
/// none of this for Claude.
@MainActor
final class WaterModel {
    // MARK: - Energy coefficients (Wh per 1k tokens)

    struct EnergyRate { let out: Double; let prefill: Double }

    /// Matched by substring so both id styles work ("claude-opus-4-8" and
    /// "claude-3-5-sonnet-20241022"). Unknown families fall back to the
    /// mid-size rate and are flagged as such in Settings.
    static let energyDefaultsByFamily: [(family: String, rate: EnergyRate)] = [
        ("opus",   EnergyRate(out: 2.0, prefill: 0.15)),
        ("sonnet", EnergyRate(out: 1.2, prefill: 0.10)),
        ("haiku",  EnergyRate(out: 0.4, prefill: 0.04)),
    ]
    static let fallbackEnergy = EnergyRate(out: 1.2, prefill: 0.10)

    /// The recognised size family for a model id, or nil if we're guessing.
    func family(for model: String) -> String? {
        for e in Self.energyDefaultsByFamily where model.contains(e.family) { return e.family }
        return nil
    }

    func defaultEnergy(for model: String) -> EnergyRate {
        for e in Self.energyDefaultsByFamily where model.contains(e.family) { return e.rate }
        return Self.fallbackEnergy
    }

    /// A stored override, or nil if the key was never set. Checks for key
    /// presence rather than `> 0` so a coefficient can be set to exactly 0.
    private func stored(_ key: String) -> Double? {
        UserDefaults.standard.object(forKey: key) == nil
            ? nil
            : UserDefaults.standard.double(forKey: key)
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

    // MARK: - Cache reads
    //
    // Cache reads skip prefill recompute but still cost retrieval and memory
    // bandwidth. Anthropic prices them at 10% of base input, which is the best
    // public proxy for their relative cost, so they default to 10% of the
    // prefill energy rate. With coding agents this term matters: cache reads
    // are routinely >90% of all tokens.

    static let defaultCacheReadFactor = 0.10

    /// Fraction of the prefill rate charged per cache-read token (0...1).
    var cacheReadFactor: Double {
        get { stored("cache_read_factor") ?? Self.defaultCacheReadFactor }
        set { UserDefaults.standard.set(min(max(0, newValue), 1), forKey: "cache_read_factor") }
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
    func energyWh(forModel model: String, output: Int, prefill: Int, cacheRead: Int) -> Double {
        Double(output) / 1000.0 * outWhPer1k(for: model)
            + Double(prefill) / 1000.0 * prefillWhPer1k(for: model)
            + Double(cacheRead) / 1000.0 * prefillWhPer1k(for: model) * cacheReadFactor
    }

    /// Water (mL) for a token breakdown, at the current scope.
    func waterML(forModel model: String, output: Int, prefill: Int, cacheRead: Int) -> Double {
        let kWh = energyWh(forModel: model, output: output, prefill: prefill, cacheRead: cacheRead) / 1000.0
        return kWh * waterIntensity * 1000.0  // L → mL
    }

    // MARK: - Training (amortised share of your usage)
    //
    // One-time training water, amortised in proportion to usage rather than
    // split equally per user: credible lifecycle analyses (Epoch AI; Luccioni
    // et al., FAccT 2024; Mistral's 2025 LCA disclosure) all amortise training
    // over lifetime inference volume, never per head. Fleet-wide, 80–90% of AI
    // compute is inference, which puts amortised training at roughly a 10–25%
    // overhead on top of inference — so the share is modelled as
    // training ≈ inference water × uplift, defaulting to the middle of that
    // band. Editable, and clearly labelled an estimate: Anthropic publishes
    // neither training water nor inference volume for Claude.

    static let defaultTrainingUplift = 0.15  // middle of the 10–25% band

    var includeTraining: Bool {
        get {
            if UserDefaults.standard.object(forKey: "includeTraining") == nil { return true }
            return UserDefaults.standard.bool(forKey: "includeTraining")
        }
        set { UserDefaults.standard.set(newValue, forKey: "includeTraining") }
    }

    /// Training share as a fraction of inference water (0.15 = 15%).
    var trainingUplift: Double {
        get { stored("training_uplift") ?? Self.defaultTrainingUplift }
        set { UserDefaults.standard.set(max(0, newValue), forKey: "training_uplift") }
    }
}
