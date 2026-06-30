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
                    .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", index), y: .value("mL", value))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
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
                        Text(c.emoji).font(.title3)
                        Text(Comparisons.describe(ml: ml, c))
                            .font(.callout).fontWeight(.medium)
                        Spacer(minLength: 0)
                    }
                    ComparisonBar(
                        fraction: Comparisons.fraction(ml: ml, c),
                        full: Comparisons.count(ml: ml, c) >= 1
                    )
                    Text(c.note)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .help(c.note)
            }
        }
    }
}

/// A thin progress bar: how much of one whole item the usage equals.
private struct ComparisonBar: View {
    let fraction: Double  // 0...1
    let full: Bool        // usage exceeds one whole item

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(full
                          ? AnyShapeStyle(LinearGradient(colors: [.teal, .green],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(.blue.gradient))
                    .frame(width: fraction > 0 ? max(3, geo.size.width * fraction) : 0)
            }
        }
        .frame(height: 6)
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
                            Capsule()
                                .fill(.blue.gradient)
                                .frame(width: max(4, geo.size.width * (maxML > 0 ? r.ml / maxML : 0)))
                        }
                        .frame(height: 5)
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
                            Text("≈ \(AppState.fmtWater(share)) · one-time")
                                .font(.callout).fontWeight(.medium)
                            Text("Your lifetime share of training water, split across ~\(state.mauText) active users · estimated")
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
                Tokens → energy → water, per model, summed. Energy = output × e_out + \
                (input + cache-creation) × e_prefill (Wh/1k); cache reads are excluded. \
                Water = energy × (on-site cooling WUE + off-site grid-electricity WUE); \
                "comprehensive" includes the off-site term. Coefficients default to \
                size-based public-proxy estimates and are editable in Settings. All \
                computed locally from ~/.claude/projects.
                """)
                .font(.caption).foregroundStyle(.secondary)

                Divider()

                SectionHeader(title: "Sources", systemImage: "book.fill")
                SourceLink(
                    title: "Google — Environmental impact of AI inference (2025)",
                    url: "https://arxiv.org/abs/2508.15734",
                    note: "Median Gemini prompt: 0.24 Wh, 0.26 mL water — anchors the energy defaults."
                )
                SourceLink(
                    title: "How Hungry is AI? Benchmarking LLM inference (2025)",
                    url: "https://arxiv.org/abs/2505.09598",
                    note: "Per-query energy/water and the WUE_onsite + WUE_source water formula."
                )
                SourceLink(
                    title: "Making AI Less Thirsty (UC Riverside, 2023)",
                    url: "https://arxiv.org/abs/2304.03271",
                    note: "Training water (GPT-3 ~5.4M L) and the worst-case per-prompt figures."
                )
                SourceLink(
                    title: "Water Footprint Network",
                    url: "https://www.waterfootprint.org/resources/interactive-tools/product-gallery/",
                    note: "Water footprints of coffee, beef, etc. used in the comparisons."
                )

                Divider()

                Text("""
                These are rough estimates, not measurements. Real data-centre water use \
                varies by orders of magnitude with cooling design (WUE) and local grid \
                water intensity. Tune the rates if you have better figures.
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
                        Text("Monthly active users").font(.callout)
                        Spacer(minLength: 4)
                        TextField("", value: Binding(
                            get: { state.mauMillions },
                            set: { state.mauMillions = $0 }
                        ), format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 64).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                        Text("M").font(.callout).foregroundStyle(.secondary)
                    }

                    Text("Training water per model (million litres):")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(state.allModels, id: \.self) { model in
                        TrainingRow(state: state, model: model)
                    }

                    Text("Estimated from public proxies (training energy × a water-use factor); Anthropic doesn't publish training water or Claude's MAU. Edit to match better figures.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "Tokens → energy → water. Output (decode) costs far more per token than prefill.",
                        "Energy = output × e_out + (input + cache-creation) × e_prefill; cache reads are free.",
                        "Water = energy × (on-site WUE + off-site grid WUE). Comprehensive adds the off-site term.",
                        "Defaults are public-proxy estimates (Google 2025, How Hungry is AI 2025) — see Sources.",
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
            Text(String(format: "default %.2f / %.2f Wh per 1k", def.out, def.prefill))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct TrainingRow: View {
    @ObservedObject var state: AppState
    let model: String

    var body: some View {
        let binding = Binding(
            get: { state.trainingLiters(for: model) / 1_000_000 },
            set: { state.setTrainingLiters($0 * 1_000_000, for: model) }
        )
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(AppState.prettyModel(model)).font(.callout)
                Text(String(format: "default %.0f", state.defaultTrainingLiters(for: model) / 1_000_000))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            TextField("", value: binding, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            Text("M L").font(.caption).foregroundStyle(.secondary)
            Button { state.resetTrainingLiters(for: model) } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Reset to default")
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

    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue, .cyan],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "drop.fill")
                    Text("My Claude Code water — \(windowTitle)")
                        .fontWeight(.semibold)
                }
                .font(.title3)
                .foregroundStyle(.white.opacity(0.95))

                Text(mlText)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("from \(tokensText) tokens")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

                Text(headline)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.95))

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                    Text("github.com/FilipCondac/watermark")
                        .fontWeight(.medium)
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.18), in: Capsule())
            }
            .padding(.vertical, 34)
            .padding(.horizontal, 40)
        }
        .frame(width: 600, height: 340)
    }
}
