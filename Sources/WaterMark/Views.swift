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
                Water = tokens ÷ 1000 × the rate for each model, summed across models. \
                Tokens counted: input + output + cache-creation (cache reads are excluded \
                as cheap retrieval). Per-model rates default to size-based values and are \
                editable in Settings. All computed locally from ~/.claude/projects.
                """)
                .font(.caption).foregroundStyle(.secondary)

                Divider()

                SectionHeader(title: "Sources", systemImage: "book.fill")
                SourceLink(
                    title: "Making AI Less Thirsty (UC Riverside, 2023)",
                    url: "https://arxiv.org/abs/2304.03271",
                    note: "Estimates of data-centre water use for AI training & inference."
                )
                SourceLink(
                    title: "A bottle of water per email (Washington Post, 2024)",
                    url: "https://www.washingtonpost.com/technology/2024/09/18/energy-ai-use-electricity-water-data-centers/",
                    note: "Reporting on worst-case GPT-4 water use in water-stressed regions."
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
                SectionHeader(title: "Water rates (mL / 1k tokens)", systemImage: "slider.horizontal.3")

                if state.allModels.isEmpty {
                    Text("No usage recorded yet.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(state.allModels, id: \.self) { model in
                        RateRow(state: state, model: model)
                    }
                }

                Divider()

                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .font(.callout)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "Water = tokens ÷ 1000 × each model's rate, summed across models.",
                        "Tokens counted: input + output + cache-creation (cache reads excluded).",
                        "Rates are rough indicators — see Sources for details.",
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
            }
            .padding(14)
        }
        .frame(height: 480)
    }
}

private struct RateRow: View {
    @ObservedObject var state: AppState
    let model: String

    var body: some View {
        let binding = Binding(
            get: { state.rate(for: model) },
            set: { state.setRate($0, for: model) }
        )
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(AppState.prettyModel(model)).font(.callout)
                Text(String(format: "default %.2f", state.defaultRate(for: model)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            TextField("", value: binding, format: .number.precision(.fractionLength(0...3)))
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            Stepper("", value: binding, in: 0...10, step: 0.05).labelsHidden()
            Button { state.resetRate(for: model) } label: {
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
