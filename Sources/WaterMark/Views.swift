import SwiftUI
import Charts

enum PopoverRoute: Equatable { case main, settings, sources }

/// Root popover content: header + the active screen.
struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var route: PopoverRoute = .main

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(route: $route)
            Divider()
            switch route {
            case .main:     MainView(state: state, route: $route)
            case .settings: SettingsView(state: state)
            case .sources:  SourcesView()
            }
        }
        .frame(width: 360)
    }
}

private struct HeaderBar: View {
    @Binding var route: PopoverRoute

    private var title: String {
        switch route {
        case .main: return "WaterMark"
        case .settings: return "Settings"
        case .sources: return "Sources"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill").foregroundStyle(.blue)
            Text(title).font(.headline)
            Spacer()
            if route == .main {
                Button { withAnimation(.easeInOut(duration: 0.15)) { route = .settings } } label: {
                    Image(systemName: "gearshape.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Settings")
            } else {
                Button { withAnimation(.easeInOut(duration: 0.15)) { route = .main } } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Back")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct MainView: View {
    @ObservedObject var state: AppState
    @Binding var route: PopoverRoute

    var body: some View {
        let w = state.barWindow
        let ml = state.waterML(for: w)

        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $state.barWindow) {
                        ForEach(BarWindow.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HeroCard(ml: ml, tokens: state.effectiveTokens(for: w))
                    TrendCard(series: state.dailySeries(30))
                    PerspectiveSection(ml: ml)
                    ByModelSection(state: state)
                    TrainingCard(state: state)
                }
                .padding(14)
            }
            .frame(height: 430)

            Divider()
            FooterBar(state: state, route: $route)
        }
    }
}

private struct HeroCard: View {
    let ml: Double
    let tokens: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "drop.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.95))
            Text(AppState.fmtWater(ml))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("\(AppState.fmtTokens(tokens)) tokens")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            LinearGradient(colors: [.blue, .cyan],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct TrendCard: View {
    let series: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Last 30 days", systemImage: "chart.xyaxis.line")
            Chart(Array(series.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("Day", index), y: .value("mL", value))
                    .foregroundStyle(.blue.opacity(0.10))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", index), y: .value("mL", value))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 46)
        }
    }
}

private struct PerspectiveSection: View {
    let ml: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "In perspective", systemImage: "scalemass.fill")
            ForEach(Comparisons.all) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(c.emoji).font(.body)
                        Text(c.name.prefix(1).uppercased() + c.name.dropFirst())
                            .font(.callout).fontWeight(.medium)
                        Text("– \(Comparisons.litersText(c))")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(Comparisons.compactValue(ml: ml, c))
                            .font(.callout).fontWeight(.semibold).monospacedDigit()
                    }
                    ComparisonBar(fraction: Comparisons.fraction(ml: ml, c))
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .help(c.note)
            }
            Text("Blue water (freshwater) — the kind data centres use. Details in Sources.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// A meter: how much of one whole item the usage equals. Solid fill with a
/// hard cutoff at the value; the unfilled track is a lighter step of the same
/// hue so the whole bar reads as one meter.
private struct ComparisonBar: View {
    let fraction: Double  // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.blue.opacity(0.16))
                Rectangle().fill(.blue)
                    .frame(width: fraction > 0 ? max(2, geo.size.width * fraction) : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 8)
    }
}

private struct ByModelSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        let rows = state.perModel(for: state.barWindow)
        if !rows.isEmpty {
            let maxML = rows.map(\.ml).max() ?? 1
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "By model", systemImage: "cpu.fill")
                ForEach(rows, id: \.model) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(AppState.prettyModel(r.model)).font(.callout)
                            Spacer()
                            Text(AppState.fmtWater(r.ml))
                                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.blue.opacity(0.16))
                                Rectangle().fill(.blue)
                                    .frame(width: max(2, geo.size.width * (maxML > 0 ? r.ml / maxML : 0)))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }
}

private struct TrainingCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        let share = state.lifetimeTrainingShareML
        if state.includeTraining && share > 0 {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Model training (your share)", systemImage: "gearshape.2.fill")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("🏭").font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("≈ \(AppState.fmtWater(share)) · amortised")
                                .font(.callout).fontWeight(.medium)
                            Text("Your share of one-time model training, in proportion to your usage (\(Int(state.trainingUpliftPercent))% of inference water) · estimated")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        }
                        Spacer(minLength: 0)
                    }
                    Divider()
                    HStack {
                        Text("Lifetime total (inference + training)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(AppState.fmtWater(state.lifetimeTotalML))
                            .font(.callout).fontWeight(.semibold).monospacedDigit()
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct FooterBar: View {
    @ObservedObject var state: AppState
    @Binding var route: PopoverRoute
    @State private var copied = false

    var body: some View {
        HStack(spacing: 16) {
            Button { state.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain).help("Refresh now")

            Button {
                if copyShareImage(state) {
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "square.and.arrow.up")
                    .foregroundStyle(copied ? .green : .primary)
            }
            .buttonStyle(.plain).help("Copy a shareable image to the clipboard")

            Button { withAnimation(.easeInOut(duration: 0.15)) { route = .sources } } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain).help("Sources & methodology")

            Spacer()

            Button { NSApp.terminate(nil) } label: {
                Text("Quit").font(.callout)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Sources

private struct SourcesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "How the estimate works", systemImage: "function")
                Text("""
                Tokens → energy → water, per model, summed. \
                Energy = output × e_out + (input + cache-creation) × e_prefill + \
                cache-reads × e_prefill × 10% (Wh/1k). \
                Water = energy × (on-site cooling WUE + off-site grid-electricity WUE); \
                "comprehensive" includes the off-site term. An optional training share \
                adds a usage-proportional uplift on top. Every coefficient is editable \
                in Settings. All computed locally from ~/.claude/projects.
                """)
                .font(.caption).foregroundStyle(.secondary)

                Divider()

                SectionHeader(title: "Where the numbers come from", systemImage: "number.square.fill")
                Text("""
                Energy per token. Measurement studies find generating a token (decode) \
                costs roughly 11× more energy than reading one (prefill), hence separate \
                coefficients. The defaults (e.g. 2.0 Wh/1k output for an Opus-class \
                model) deliberately sit above published GPT-4o-class estimates \
                (~0.6–1.4 Wh/1k output) to leave headroom for long coding contexts, \
                where flat per-token rates undercount: attention cost grows with context \
                length, and Epoch AI puts a 100k-token prompt at ~40 Wh. Google's \
                widely-quoted 0.24 Wh median Gemini prompt publishes no token counts, \
                so it serves as an order-of-magnitude cross-check, not a calibration \
                point — and its 0.26 mL water figure is on-site cooling only.

                Cache reads. Coding agents read the prompt cache constantly — often \
                over 90% of all tokens. Cache reads skip prefill recompute but are not \
                free; they default to 10% of the prefill rate, mirroring how they are \
                priced (10% of base input).

                Water per kWh. On-site cooling defaults to 0.30 L/kWh: Anthropic serves \
                mostly from AWS (reported 0.15–0.18) and Google Cloud (~1.0–1.1), so \
                0.30 is a fair middle. The off-site term defaults to 4.35 L/kWh, the US \
                grid's water consumption per kWh implied by the LBNL 2024 report — a \
                deliberately high figure, since it includes hydro-reservoir evaporation \
                ("How Hungry is AI?" uses 3.14). Both are consumption-basis, the right \
                basis for comparing against everyday water use.

                Training share. Credible lifecycle analyses (Epoch AI, Luccioni et al. \
                2024, Mistral's 2025 LCA) amortise one-time training over lifetime \
                inference volume — never equally per user. Fleet-wide, 80–90% of AI \
                compute is inference, making amortised training a ~10–25% overhead on \
                inference; the default uplift is 15%.
                """)
                .font(.caption).foregroundStyle(.secondary)

                Divider()

                SectionHeader(title: "Rainwater vs freshwater", systemImage: "cloud.rain.fill")
                Text("""
                Food water footprints split into green water (rain falling on crops and \
                pasture), blue water (freshwater drawn from rivers, lakes and aquifers) \
                and grey water (dilution). Data centres use blue water, so the \
                comparisons here use blue-water figures: ~82 L for a 150 g hamburger \
                and ~1 L for a cup of coffee (Mekonnen & Hoekstra 2012; Chapagain & \
                Hoekstra 2007). The headline figures — 2,400 L per burger, 140 L per \
                coffee — are green-dominated totals, and using them against AI's blue \
                water would flatter AI by ~30×. One nuance cuts the other way: shower \
                water is withdrawn but almost all returns to treatment, while \
                evaporative cooling water is consumed.
                """)
                .font(.caption).foregroundStyle(.secondary)

                Divider()

                SectionHeader(title: "Sources", systemImage: "book.fill")
                SourceLink(
                    title: "Google — Environmental impact of AI inference (2025)",
                    url: "https://arxiv.org/abs/2508.15734",
                    note: "Median Gemini prompt: 0.24 Wh, 0.26 mL (on-site only). No token counts — an order-of-magnitude cross-check."
                )
                SourceLink(
                    title: "How Hungry is AI? Benchmarking LLM inference (2025)",
                    url: "https://arxiv.org/abs/2505.09598",
                    note: "GPT-4o short query ≈ 0.42 Wh; the WUE_onsite + WUE_source formula (it uses 3.14 L/kWh off-site)."
                )
                SourceLink(
                    title: "From Prompts to Power (2025)",
                    url: "https://arxiv.org/abs/2511.05597",
                    note: "155-model measurement study; output tokens ≈ 11× input-token energy — grounds the decode/prefill split."
                )
                SourceLink(
                    title: "Epoch AI — How much energy does ChatGPT use?",
                    url: "https://epoch.ai/gradient-updates/how-much-energy-does-chatgpt-use",
                    note: "Per-query estimates incl. long contexts (100k-token prompt ≈ 40 Wh); amortises training over query volume."
                )
                SourceLink(
                    title: "LBNL — US Data Center Energy Usage Report (2024)",
                    url: "https://eta-publications.lbl.gov/sites/default/files/2024-12/lbnl-2024-united-states-data-center-energy-usage-report_1.pdf",
                    note: "Source of the 4.35 L/kWh US grid water-consumption intensity and US data-centre water totals."
                )
                SourceLink(
                    title: "Making AI Less Thirsty (UC Riverside, 2023)",
                    url: "https://arxiv.org/abs/2304.03271",
                    note: "GPT-3 training ≈ 5.4M L total / 0.7M L on-site; US grid EWIF 3.1 L/kWh consumption."
                )
                SourceLink(
                    title: "Mekonnen & Hoekstra — Farm animal products (2012)",
                    url: "https://www.waterfootprint.org/resources/Mekonnen-Hoekstra-2012-WaterFootprintFarmAnimalProducts_1.pdf",
                    note: "Beef: 15,415 L/kg total, of which 550 L/kg blue — the burger green/blue split."
                )
                SourceLink(
                    title: "Water Footprint Network",
                    url: "https://www.waterfootprint.org/resources/interactive-tools/product-gallery/",
                    note: "Virtual-water totals for coffee, beef, etc. (green + blue + grey)."
                )

                Divider()

                Text("""
                These are rough estimates, not measurements. Real data-centre water use \
                varies by orders of magnitude with cooling design (WUE) and local grid \
                water intensity, and Anthropic publishes no per-token energy, water, or \
                training figures for Claude. Tune the rates if you have better figures.
                """)
                .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(height: 480)
    }
}

private struct SourceLink: View {
    let title: String
    let url: String
    let note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(destination: URL(string: url)!) {
                HStack(spacing: 4) {
                    Text(title).font(.callout).fontWeight(.medium)
                    Image(systemName: "arrow.up.right.square").font(.caption2)
                }
            }
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Water intensity (L / kWh)", systemImage: "drop.triangle.fill")

                Toggle("Comprehensive (include grid-electricity water)", isOn: Binding(
                    get: { state.comprehensive },
                    set: { state.comprehensive = $0 }
                ))
                .toggleStyle(.switch)
                .font(.callout)

                HStack {
                    Text("On-site (cooling)").font(.callout)
                    Spacer(minLength: 4)
                    NumberField(value: Binding(get: { state.wueOnsite }, set: { state.wueOnsite = $0 }))
                }
                HStack {
                    Text("Off-site (electricity)").font(.callout)
                        .foregroundStyle(state.comprehensive ? .primary : .secondary)
                    Spacer(minLength: 4)
                    NumberField(value: Binding(get: { state.wueSource }, set: { state.wueSource = $0 }),
                                enabled: state.comprehensive)
                }

                Divider()

                SectionHeader(title: "Energy per model (Wh / 1k tokens)", systemImage: "bolt.fill")

                if state.allModels.isEmpty {
                    Text("No usage recorded yet.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(state.allModels, id: \.self) { model in
                        EnergyRow(state: state, model: model)
                    }
                }

                HStack {
                    Text("Cache reads (% of prefill)").font(.callout)
                    Spacer(minLength: 4)
                    NumberField(value: Binding(
                        get: { state.cacheReadPercent },
                        set: { state.cacheReadPercent = $0 }
                    ))
                    Text("%").font(.callout).foregroundStyle(.secondary)
                }
                Text("Cache reads often dominate coding-agent usage (>90% of tokens). They skip recompute but aren't free; default mirrors their 10%-of-input pricing.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()

                SectionHeader(title: "Training (amortised · estimated)", systemImage: "gearshape.2.fill")

                Toggle("Include training share", isOn: Binding(
                    get: { state.includeTraining },
                    set: { state.includeTraining = $0 }
                ))
                .toggleStyle(.switch)
                .font(.callout)

                if state.includeTraining {
                    HStack {
                        Text("Uplift on inference water").font(.callout)
                        Spacer(minLength: 4)
                        NumberField(value: Binding(
                            get: { state.trainingUpliftPercent },
                            set: { state.trainingUpliftPercent = $0 }
                        ))
                        Text("%").font(.callout).foregroundStyle(.secondary)
                    }

                    Text("One-time training water, amortised in proportion to your usage — the way lifecycle analyses do it (never per user). Fleet-wide, inference is 80–90% of AI compute, putting training at a ~10–25% overhead; default 15%.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "Tokens → energy → water. Output (decode) costs ~11× more per token than prefill.",
                        "Energy = output × e_out + (input + cache-creation) × e_prefill + cache-reads × e_prefill × 10%.",
                        "Water = energy × (on-site WUE + off-site grid WUE). Comprehensive adds the off-site term.",
                        "Training adds a usage-proportional uplift (default 15% of inference water).",
                        "Defaults are public-proxy estimates, deliberately on the generous side — see Sources.",
                        "Everything stays on your machine.",
                    ], id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                            Text(line)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)

                Divider()

                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .font(.callout)
            }
            .padding(14)
        }
        .frame(height: 480)
    }
}

/// A compact right-aligned numeric field used across settings.
private struct NumberField: View {
    @Binding var value: Double
    var enabled: Bool = true
    var width: CGFloat = 60

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
            .frame(width: width)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .disabled(!enabled)
    }
}

private struct EnergyRow: View {
    @ObservedObject var state: AppState
    let model: String

    var body: some View {
        let def = state.defaultEnergy(for: model)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(AppState.prettyModel(model)).font(.callout)
                Spacer()
                Button { state.resetEnergy(for: model) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Reset to defaults")
            }
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("output").font(.caption2).foregroundStyle(.secondary)
                    NumberField(value: Binding(
                        get: { state.outWhPer1k(for: model) },
                        set: { state.setOutWhPer1k($0, for: model) }
                    ), width: 54)
                }
                HStack(spacing: 4) {
                    Text("prefill").font(.caption2).foregroundStyle(.secondary)
                    NumberField(value: Binding(
                        get: { state.prefillWhPer1k(for: model) },
                        set: { state.setPrefillWhPer1k($0, for: model) }
                    ), width: 54)
                }
                Spacer(minLength: 0)
            }
            Text(state.isRecognizedFamily(model)
                 ? String(format: "default %.2f / %.2f Wh per 1k", def.out, def.prefill)
                 : String(format: "default %.2f / %.2f Wh per 1k · unrecognised family, generic mid-size defaults", def.out, def.prefill))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Share card

/// Renders the current footprint to a PNG on the clipboard. Returns success.
@MainActor
private func copyShareImage(_ state: AppState) -> Bool {
    let w = state.barWindow
    let ml = state.waterML(for: w)
    let card = ShareCardView(
        windowTitle: w.title,
        mlText: AppState.fmtWater(ml),
        tokensText: AppState.fmtTokensCompact(state.effectiveTokens(for: w)),
        headline: Comparisons.headline(ml: ml)
    )
    let renderer = ImageRenderer(content: card)
    renderer.scale = 2
    guard let image = renderer.nsImage else { return false }
    let pb = NSPasteboard.general
    pb.clearContents()
    return pb.writeObjects([image])
}

private struct ShareCardView: View {
    let windowTitle: String
    let mlText: String
    let tokensText: String
    let headline: String

    private let ink = Color(red: 0.05, green: 0.07, blue: 0.12)
    private let accent = Color(red: 0.25, green: 0.56, blue: 1.0)

    private func label(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.55))
    }

    var body: some View {
        ZStack {
            ink
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 9) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(accent, in: RoundedRectangle(cornerRadius: 8))
                        Text("WaterMark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("github.com/FilipCondac/watermark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                label("CLAUDE CODE WATER FOOTPRINT · \(windowTitle.uppercased())")
                Text(mlText)
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 2)

                Spacer()

                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

                HStack(alignment: .bottom, spacing: 36) {
                    VStack(alignment: .leading, spacing: 4) {
                        label("TOKENS")
                        Text(tokensText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        label("IN PERSPECTIVE")
                        Text(headline)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
            }
            .padding(30)
        }
        .frame(width: 600, height: 340)
    }
}
