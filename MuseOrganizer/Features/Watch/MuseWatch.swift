import Charts
import SwiftUI

// MARK: - Card at the top of a plan

/// Muse's latest call on the plan's prices, one tap from the full list.
struct MuseWatchCard: View {
    @Environment(AppModel.self) private var model
    var plan: Plan
    @State private var showAll = false

    private var center: PriceWatchCenter { model.priceWatch }
    private var watches: [PriceWatch] { center.watches(for: plan.id) }

    var body: some View {
        Button { showAll = true } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    MuseMark(size: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Muse price watch").font(.smallStrong).foregroundStyle(Palette.ink)
                        Text(subtitle).font(.caption2).foregroundStyle(center.isDemo ? Palette.caution : Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    if center.checking.contains(plan.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkFaint)
                    }
                }

                if let (watch, advice) = center.latestAdvice(for: plan.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(advice.verdict.title, systemImage: advice.verdict.symbol)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(advice.verdict.color)
                            .contentTransition(.symbolEffect(.replace))
                        Text(advice.headline).font(.bodyStrong).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(advice.reason).font(.small).foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                    PriceLine(watch: watch, tint: advice.verdict.color)
                } else {
                    Text(emptyText).font(.small).foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(Space.m + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel)
            .overlay(alignment: .top) {
                // A band of Muse's gradient along the top edge marks the card as Muse's.
                Palette.museGradient.frame(height: 3)
            }
            .clipShape(.rect(cornerRadius: Radius.l, style: .continuous))
            .cardShadow()
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows every price Muse is watching")
        .sheet(isPresented: $showAll) {
            WatchListSheet(plan: plan)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

extension MuseWatchCard {
    private var subtitle: String {
        let count = watches.isEmpty ? "" : "\(watches.count) \(watches.count == 1 ? "price" : "prices") · "
        return count + center.sourceNote
    }

    private var emptyText: String {
        if watches.isEmpty {
            return center.api == nil ? "Prices appear here once Muse starts watching." : "Finding prices to watch…"
        }
        return "No big moves yet. Muse will tell you when something drops."
    }
}

/// Full-width price line with the low and high marked, so "is this a good price?" is answered at a glance.
struct PriceLine: View {
    var watch: PriceWatch
    var tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Sparkline(prices: watch.prices, tint: tint)
                .frame(height: 52)
            HStack {
                if let low = watch.low { Text("Low \(Money.format(low))") }
                Spacer()
                if let current = watch.current {
                    Text("Now \(Money.format(current))").fontWeight(.semibold).foregroundStyle(Palette.ink)
                }
                Spacer()
                if let high = watch.high { Text("High \(Money.format(high))") }
            }
            .font(.caption2)
            .foregroundStyle(Palette.inkSecondary)
            .figure()
        }
    }
}

struct VerdictBadge: View {
    var verdict: PriceAdvice.Verdict

    var body: some View {
        Label(verdict.title, systemImage: verdict.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(verdict.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(verdict.color.opacity(0.12), in: .capsule)
    }
}

/// Small price-over-time line. The last point is marked so "now" is obvious.
struct Sparkline: View {
    var prices: [Double]
    var tint: Color = Palette.accent

    var body: some View {
        if prices.count < 2 {
            Color.clear
        } else {
            let low = prices.min()!, high = prices.max()!
            let pad = max((high - low) * 0.15, 1)
            Chart {
                ForEach(Array(prices.enumerated()), id: \.offset) { i, p in
                    AreaMark(x: .value("Check", i), yStart: .value("Floor", low - pad), yEnd: .value("Price", p))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Check", i), y: .value("Price", p))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                PointMark(x: .value("Check", prices.count - 1), y: .value("Price", prices.last!))
                    .foregroundStyle(tint)
                    .symbolSize(28)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (low - pad)...(high + pad))
            .accessibilityLabel("Price trend from \(Money.format(prices.first!)) to \(Money.format(prices.last!))")
        }
    }
}

/// "▼ $64" in green or "▲ $12" in amber, with words for VoiceOver.
struct PriceChange: View {
    var change: Double

    var body: some View {
        if abs(change) >= 1 {
            Text(Money.change(change))
                .font(.caption2.weight(.semibold))
                .figure()
                .foregroundStyle(change < 0 ? Palette.positive : Palette.caution)
                .accessibilityLabel("\(change < 0 ? "Down" : "Up") \(Money.format(abs(change))) since Muse started watching")
        }
    }
}

// MARK: - Every watch on a plan

struct WatchListSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var plan: Plan

    private var center: PriceWatchCenter { model.priceWatch }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    notificationsRow
                } footer: {
                    Text(footer)
                }

                Section("Watching") {
                    ForEach(center.watches(for: plan.id)) { WatchRow(watch: $0) }
                    if center.watches(for: plan.id).isEmpty {
                        Text("Nothing yet. Muse watches flights, stays and car prices as soon as the plan has them.")
                            .font(.small).foregroundStyle(Palette.inkSecondary)
                    }
                }

                if let error = center.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").font(.small).foregroundStyle(Palette.caution)
                    }
                }
            }
            .navigationTitle("Muse price watch")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await center.check(plan.id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if center.checking.contains(plan.id) {
                        ProgressView()
                    } else {
                        Button("Check now", systemImage: "arrow.clockwise") {
                            Task { await center.check(plan.id) }
                        }
                        .disabled(center.api == nil)
                    }
                }
            }
        }
    }

    private var footer: String {
        if center.api == nil {
            return "These are demo prices. Run the Huddle backend with SerpApi and Muse keys and Muse re-checks every price on a schedule, updates your Budget Tracker sheet, and notifies you when it's the right time to book."
        }
        return "Muse re-checks with SerpApi on a schedule. When a price moves, Muse Spark decides whether to book now or wait, and your Budget Tracker sheet is updated."
    }

    @ViewBuilder private var notificationsRow: some View {
        if center.notificationsAllowed {
            Label("You'll get a notification when Muse finds a drop", systemImage: "bell.badge.fill")
                .font(.small).foregroundStyle(Palette.ink)
        } else {
            Button {
                Task { await center.requestNotifications() }
            } label: {
                Label("Notify me when it's time to book", systemImage: "bell")
                    .font(.smallStrong)
            }
        }
    }
}

private struct WatchRow: View {
    var watch: PriceWatch

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(watch.label).font(.smallStrong).foregroundStyle(Palette.ink)
                    Text(watch.detail).font(.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                    if let low = watch.low, let high = watch.high, high > low {
                        Text("Seen \(Money.format(low)) – \(Money.format(high))").font(.caption2).foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let current = watch.current {
                        Text(Money.format(current)).font(.bodyStrong).figure().foregroundStyle(Palette.ink)
                    }
                    Text(watch.unit).font(.caption2).foregroundStyle(Palette.inkSecondary)
                    if let change = watch.change { PriceChange(change: change) }
                }
            }
            Sparkline(prices: watch.prices, tint: watch.advice?.verdict.color ?? Palette.accent)
                .frame(height: 36)
            if let advice = watch.advice {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    VerdictBadge(verdict: advice.verdict)
                    Text(advice.reason).font(.caption).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let checked = watch.lastChecked {
                Text("Checked \(checked, format: .relative(presentation: .named))")
                    .font(.caption2).foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
