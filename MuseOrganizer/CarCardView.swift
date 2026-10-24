import SwiftUI

/// Result card for one car, with a lease / finance / cash toggle over the computed comparison.
struct CarCardView: View {
    let option: CarOption
    let rank: Int
    var voting: Voting? = nil
    let onExplain: ((CarOption) -> Void)?

    @State private var plan = "finance"

    private static let planNames = ["lease": "Lease", "finance": "Finance", "cash": "Cash"]

    var body: some View {
        let f = option.finance
        let p = f[plan]
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(rank)").font(.headline).foregroundStyle(.secondary)
                Text("Toyota \(option.name)").font(.title3.bold())
                Spacer()
                Text("\(option.score)% match").font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.purple.opacity(0.15), in: .capsule)
                    .foregroundStyle(.purple)
            }
            if !option.fitsAll {
                Label("Closest option: misses a group limit", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 16) {
                stat("\(option.seats)", "seats", "person.3.fill")
                stat("\(option.mpg)", "mpg", "fuelpump.fill")
                stat("\(option.cargo)", "cu ft", "shippingbox.fill")
                if option.awd { stat("AWD", "available", "snowflake") }
            }
            Text("MSRP \(dollars(option.msrp))").font(.subheadline).foregroundStyle(.secondary)

            Picker("Plan", selection: $plan) {
                ForEach(["lease", "finance", "cash"], id: \.self) { Text(Self.planNames[$0]!).tag($0) }
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, verticalSpacing: 4) {
                if plan != "cash" { row("Monthly", dollars(p.monthly)) }
                row("Up front", dollars(p.upfront))
                row("Paid over \(f.months) mo", dollars(p.totalPaid))
                if p.interest > 0 { row(plan == "lease" ? "Rent charge" : "Interest", dollars(p.interest)) }
                row("You own at the end", dollars(p.equity))
                row("Real cost", dollars(p.netCost)).bold()
            }
            .font(.subheadline)
            if f.best == plan {
                Label("Cheapest over \(f.months) months", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.green)
            }

            if let voting {
                voteRow(voting)
            }

            HStack {
                if let link = option.listings?.first?.link, let url = URL(string: link) {
                    Link(destination: url) { Label("Listings", systemImage: "link") }
                }
                Spacer()
                if let onExplain {
                    Button("Explain to me", systemImage: "lock.fill") { onExplain(option) }
                        .buttonStyle(.bordered)
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
        .overlay {
            if voting?.state.winner == option.name {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.orange, lineWidth: 2)
            }
        }
    }

    @ViewBuilder
    private func voteRow(_ v: Voting) -> some View {
        let mine = v.state.myVote == option.name
        if v.state.winner == option.name {
            Label("Group's pick", systemImage: "trophy.fill")
                .font(.headline).foregroundStyle(.orange)
        } else if v.state.winner == nil, let count = v.state.tally[option.name] {
            HStack {
                Button(mine ? "Your vote" : "Vote", systemImage: mine ? "checkmark.circle.fill" : "hand.thumbsup") {
                    v.onVote(option.name)
                }
                .buttonStyle(.borderedProminent)
                .tint(mine ? .green : .accentColor)
                .disabled(mine)
                Spacer()
                Text(count == 1 ? "1 vote" : "\(count) votes")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func stat(_ value: String, _ unit: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(value).font(.headline)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

}

func dollars(_ n: Int) -> String {
    n.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}
