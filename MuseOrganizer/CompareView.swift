import SwiftUI

/// Side-by-side table of the current options; the best value in each row is highlighted.
struct CompareView: View {
    let options: [CarOption]
    let tally: [String: Int]

    private struct Row {
        let label: String
        let value: (CarOption) -> Int
        var format: (Int) -> String = { "\($0)" }
        var higherIsBetter = true
    }

    private var rows: [Row] {
        [
            Row(label: "Match", value: \.score, format: { "\($0)%" }),
            Row(label: "Finance / mo", value: { $0.finance.finance.monthly }, format: dollars, higherIsBetter: false),
            Row(label: "Lease / mo", value: { $0.finance.lease.monthly }, format: dollars, higherIsBetter: false),
            Row(label: "Lowest real cost",
                value: { $0.finance[$0.finance.best].netCost }, format: dollars, higherIsBetter: false),
            Row(label: "Seats", value: \.seats),
            Row(label: "MPG", value: \.mpg),
            Row(label: "Cargo (cu ft)", value: \.cargo),
            Row(label: "Votes", value: { tally[$0.name] ?? 0 }),
        ]
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(options) { Text($0.name).font(.subheadline.bold()).lineLimit(2) }
                }
                Divider()
                ForEach(rows.indices, id: \.self) { i in
                    let row = rows[i]
                    let values = options.map(row.value)
                    let best = row.higherIsBetter ? values.max() : values.min()
                    GridRow {
                        Text(row.label).foregroundStyle(.secondary)
                        ForEach(values.indices, id: \.self) { j in
                            Text(row.format(values[j]))
                                .monospacedDigit()
                                .fontWeight(values[j] == best && Set(values).count > 1 ? .bold : .regular)
                                .foregroundStyle(values[j] == best && Set(values).count > 1 ? Color.green : .primary)
                        }
                    }
                }
            }
            .font(.subheadline)
            .padding()
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }
}
