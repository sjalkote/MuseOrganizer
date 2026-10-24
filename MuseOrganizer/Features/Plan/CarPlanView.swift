import SwiftUI

struct CarPlanView: View {
    @Bindable var plan: Plan
    var openThread: () -> Void

    @State private var showAssumptions = false
    @State private var requested = false
    private let lease = Mock.lease

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Panel { PlanHeader(plan: plan) }
                Panel { snapshot }
                Panel { options }
                recommendation
                threadPreview
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
    }

    // MARK: Lease snapshot

    private var snapshot: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            PanelHeader(title: "Your lease", subtitle: lease.vehicle, symbol: "car.fill", tint: .car) {
                Text("Simulated")
                    .font(.smallStrong)
                    .foregroundStyle(Palette.caution)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(Tint.stays.soft, in: .capsule)
                    .accessibilityLabel("Simulated data")
            }

            HStack(spacing: Space.s) {
                stat("\(lease.monthsRemaining)", "months left")
                stat("$\(lease.monthlyPayment)", "a month")
                stat("$\(lease.residualValue.formatted())", "buyout price")
            }

            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("Miles").font(.small).foregroundStyle(Palette.inkSecondary)
                    Spacer()
                    Text("\(lease.milesUsed.formatted()) of \(lease.milesAllowed.formatted())")
                        .font(.smallStrong).figure().foregroundStyle(Palette.ink)
                }
                GeometryReader { geo in
                    let allowed = Double(lease.milesAllowed) / Double(lease.milesUsed)
                    HStack(spacing: 2) {
                        Capsule().fill(Palette.ink).frame(width: geo.size.width * allowed)
                        Capsule().fill(Palette.critical)
                    }
                }
                .frame(height: 6)
                Label("\((lease.milesUsed - lease.milesAllowed).formatted()) miles over, about 4,560 by turn-in",
                      systemImage: "exclamationmark.triangle")
                    .font(.small)
                    .foregroundStyle(Palette.critical)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.heading).figure().foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.small).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Options

    private var options: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PanelHeader(title: "Options", subtitle: "Monthly payment and total cost", symbol: "arrow.left.arrow.right", tint: .money)
            VStack(spacing: 0) {
                ForEach(Array(plan.leaseOptions.enumerated()), id: \.element.id) { index, option in
                    optionRow(option)
                    if index < plan.leaseOptions.count - 1 {
                        Hairline()
                    }
                }
            }

            DisclosureGroup(isExpanded: $showAssumptions.animation(Motion.smooth)) {
                VStack(spacing: 0) {
                    ForEach(Mock.assumptions) { a in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.label).font(.small).foregroundStyle(Palette.ink)
                                Text(a.source).font(.small).foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                            Text(a.value).font(.smallStrong).figure().foregroundStyle(Palette.ink)
                        }
                        .padding(.vertical, Space.s)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, Space.s)
            } label: {
                Text("How we got these numbers")
                    .font(.bodyRegular)
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: 44)
            }
            .tint(Palette.inkSecondary)
            .padding(.horizontal, Space.m)
            .background(Palette.fill, in: .rect(cornerRadius: Radius.m, style: .continuous))
            .padding(.top, Space.s)
        }
    }

    private func optionRow(_ option: LeaseOption) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(option.title).font(.bodyStrong).foregroundStyle(Palette.ink)
                    if option.isRecommended {
                        Text("Recommended").font(.smallStrong).foregroundStyle(Palette.accent)
                    }
                }
                Text(option.tradeoff)
                    .font(.small)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !option.votes.isEmpty {
                    AvatarStack(members: option.votes.compactMap { plan.member($0) }, size: 20)
                        .padding(.top, Space.xs)
                }
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(option.monthly).font(.heading).figure().foregroundStyle(Palette.ink)
                Text(option.total).font(.smallStrong).figure().foregroundStyle(Palette.inkSecondary)
                Text(option.totalLabel).font(.small).foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: 120, alignment: .trailing)
        }
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: Recommendation (the peak moment)

    private var recommendation: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            PlannerLabel()
            Text("Buy out the RAV4 before July")
                .font(.heading)
                .foregroundStyle(Palette.ink)
            Text("A 30-minute dealer visit locks in the 5.9% rate and skips about $1,140 in mileage fees. Three of four of you already voted for this.")
                .font(.bodyRegular)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(Motion.snappy) { requested = true }
            } label: {
                Label(requested ? "Requested for Sat, 10:30 AM" : "Book a dealer visit",
                      systemImage: requested ? "checkmark" : "calendar")
            }
            .buttonStyle(.primary)
            .padding(.top, Space.s)

            PostToChatButton(plan: plan)

            Button("Talk to an advisor") {}
                .font(.bodyStrong)
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(Space.l)
        .background(Palette.accentFill, in: .rect(cornerRadius: Radius.l, style: .continuous))
    }

    // MARK: Thread preview

    private var threadPreview: some View {
        Button(action: openThread) {
            HStack(spacing: Space.m) {
                if let last = plan.messages.last(where: { $0.senderID != "planner" }), let who = plan.member(last.senderID) {
                    Avatar(member: who, size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Family on iMessage").font(.small).foregroundStyle(Palette.inkSecondary)
                    Text(plan.lastMessagePreview)
                        .font(.bodyRegular)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.small).foregroundStyle(Palette.inkFaint)
            }
            .padding(Space.m)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.l, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens the family thread")
    }
}
