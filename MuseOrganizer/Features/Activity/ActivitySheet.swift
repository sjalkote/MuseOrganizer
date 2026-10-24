import SwiftUI

/// Every step the Planner took, what it used, and what it cost.
struct ActivitySheet: View {
    var plan: Plan

    private var totalSeconds: Double { plan.steps.reduce(0) { $0 + $1.duration } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    usage
                    steps
                    sources
                }
                .padding(Space.m)
                .padding(.bottom, Space.xl)
            }
            .background(Palette.background)
            .navigationTitle("Planner activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(plan.creditsUsed)")
                    .font(.hero).figure()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("of \(plan.creditBudget) credits this week")
                    .font(.bodyRegular)
                    .foregroundStyle(Palette.inkSecondary)
            }
            ProgressView(value: Double(plan.creditsUsed), total: Double(plan.creditBudget))
                .tint(Palette.accent)
            Text("\(plan.steps.count) steps · \(totalSeconds.formatted(.number.precision(.fractionLength(1)))) seconds · about $0.04")
                .font(.small)
                .foregroundStyle(Palette.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionTitle(title: "Steps")
            VStack(spacing: 0) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: Space.m) {
                        Text("\(index + 1)")
                            .font(.smallStrong).figure()
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 24, height: 24)
                            .background(Palette.fill, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.tool).font(.bodyRegular).foregroundStyle(Palette.ink)
                            Text(step.detail).font(.small).foregroundStyle(Palette.inkSecondary)
                            Text(step.engine)
                                .font(.smallStrong)
                                .foregroundStyle(step.engine.hasPrefix("SerpApi") || step.engine.hasPrefix("Muse") ? Palette.accent : Palette.inkSecondary)
                                .padding(.top, 2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(step.duration.formatted(.number.precision(.fractionLength(1))))s")
                                .font(.small).figure().foregroundStyle(Palette.ink)
                            if step.credits > 0 {
                                Text("\(step.credits) cr").font(.small).figure().foregroundStyle(Palette.inkSecondary)
                            }
                        }
                    }
                    .padding(.vertical, Space.m)
                    .accessibilityElement(children: .combine)
                    if index < plan.steps.count - 1 {
                        Hairline(inset: 40)
                    }
                }
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionTitle(title: "Sources")
            ForEach(plan.sources) { s in
                HStack {
                    Text(s.name).font(.bodyRegular).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(s.detail).font(.small).foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: 44)
            }
            Text("Reasoning by Muse Spark. Live prices and places by SerpApi.")
                .font(.small)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, Space.s)
        }
    }
}
